# Handle case Parameters
function case_parameters(scenarios_data::Dict)
    timestamps    = scenarios_data["dates"]
    scenarios_ids = collect(1:length(scenarios_data["values"][1,1,:]))
    years         = unique(year.(timestamps))
    days          = unique(Dates.dayofyear.(timestamps))
    
    return timestamps, scenarios_ids, years, days
end

######################################
# Creating Filter Results Dictionary #
######################################

function get_branches_from_buses(data, buses)
    branch = []
    for b in buses
        brs = findall(br -> br["f_bus"] == parse(Int, b) || br["t_bus"] == parse(Int, b), data["branch"])
        push!(branch, brs)
    end
    unique(vcat(branch...))    
end

const filter_keys = Dict(
    "bus" => ["va", "vm"],
    "branch" => ["qf", "pf"],
    "gen" => ["pg", "qg"],
    "load" => ["pd", "qd"],
    "shunt" => ["bs"]
)

function create_filter(filter_vector::Dict)
    filter_dict = Dict{String, Dict}()
    for (k, v) in filter_vector
        filter_dict[k] = Dict()
        for el in v
            filter_dict[k][el] = Dict(ke => NaN  for ke in filter_keys[k])
        end
    end
    return filter_dict
end

function create_filter_results(ASPO::String, network::Dict)
    # Construct data structure that indicates
    # which results are saved in each execution_group
    # of power flow algorithm

    file_border = "data/$ASPO/raw_data/border.csv"
    # Barras as quais o resultado será salvo em cada iteração do fluxo
    buses_filter = unique(vcat(Matrix(CSV.read(file_border, DataFrame; delim = ";")[3:end, 2:3])...));
    # Linhas as quais o resultado será salvo em cada iteração do fluxo
    branches_filter = get_branches_from_buses(network, buses_filter);
    # Estrutura intermediária para criação do filtro de resultado
    filter_vector = Dict(
        "bus"    => buses_filter,
        "branch" => branches_filter
    );
    # Criação do filtro de resultado
    filter_results = create_filter(filter_vector);
    
    return filter_results
end

######################################
#    Create Group Info Dictionary    #
######################################

function create_group_info(timestamps, s, y, d)
    timestamps_ids = findall(dt -> Dates.year(dt) == y && Dates.dayofyear(dt) == d, timestamps)
    
    group_info = Dict(
        "scenarios_ids"  => [s],
        "timestamps_ids" => timestamps_ids
    )
    return group_info
end

######################################
#  Create Operation Point Dictionary #
######################################


function create_operation_points(gen_scenarios, load_scenarios, group_info)
    scenarios_ids  = group_info["scenarios_ids"]
    timestamps_ids = group_info["timestamps_ids"]
    timestamps     = gen_scenarios["dates"]
    gen  = gen_scenarios["values"]
    ac_load = load_scenarios["values"]
    re_load = load_scenarios["values"]*0.1

    operation_points = Dict("scenarios" => Dict())
    for s in scenarios_ids
        operation_points["scenarios"]["$s"] = Dict("timestamps" => Dict())
        op_scen_time = operation_points["scenarios"]["$s"]["timestamps"]
        for t in timestamps_ids
            timestamp = timestamps[t]
            op_scen_time[timestamp] = Dict(
                "gen" => Dict(),
                "load" => Dict(),
                "system_modifications" => Dict()
            )
            for (g, gen_id) in enumerate(gen_scenarios["names"])
                op_scen_time[timestamp]["gen"][gen_id] = Dict(
                    "pg" => gen[t, g, s]
                    )
            end
            for (l, load_id) in enumerate(load_scenarios["names"])
                op_scen_time[timestamp]["load"][load_id] = Dict(
                    "pd" => ac_load[t, l, s],
                    "qd" => re_load[t, l, s],
                )
            end
        end
    end
    return operation_points
end


######################################
# Create Connection Point Dictionary #
######################################


function _handle_connection_point_info_anarede(name::String, border::Matrix)
    ids = findall(names -> names == name, border[:, 1])
    info = Dict()
    n_branch = 1
    for id in ids
        from = border[id, 2]
        to = border[id, 3]
        circuit = border[id, 4]
        info["$n_branch"] = Dict(
            "id" => (from, to, circuit)
        )
        n_branch += 1
    end
    return info
end

function find_branch_from_anarede_info(network::Dict, info::Tuple)-
    (from, to, circuit) = info
    orientation = 1
    branches = findall(br -> br["f_bus"] == from && br["t_bus"] == to && br["control_data"]["circuit"] == circuit, network["branch"])
    if isempty(branches)
        orientation = -1
        branches = findall(br -> br["t_bus"] == from && br["f_bus"] == to && br["control_data"]["circuit"] == circuit, network["branch"])
    end
    if length(branches) != 1
        @error("Could find single branch from ANAREDE information ($from, $to, $circuit). Total number of branches = $(length(branches))")
    end
    return branches[1], orientation
end

function _handle_connection_point_info_powermodels(network::Dict, anarede_info::Dict)
    powermodels_info = Dict()
    for (i, info) in anarede_info
        branch, orientation = find_branch_from_anarede_info(network, info["id"])
        powermodels_info["$i"] = Dict(
            "id" => branch,
            "orientation" => orientation
        )
    end
    return powermodels_info
end

function create_connection_points(network::Dict, border::Matrix)
    names_connection_points = unique(border[:, 1])
    connection_points = Dict()
    for name in names_connection_points
        connection_points[name] = Dict(
            "info" => Dict()
        )
        connection_points[name]["info"]["ANAREDE"] = _handle_connection_point_info_anarede(name, border)
        connection_points[name]["info"]["PowerModels"] = _handle_connection_point_info_powermodels(
            network, connection_points[name]["info"]["ANAREDE"]
        )
    end 
    return connection_points
end

##########################################
# Manipulate Connection Point Dictionary #
##########################################

function create_connection_points_results!(connection_points::Dict, timestamps::Vector{DateTime}, n_scen::Int)
    years = unique(year.(timestamps))
    days = unique(Dates.dayofyear.(timestamps))
    for (name, connection_point) in connection_points
        connection_point["scenarios"] = Dict()
        max_inj = connection_point
        for s in 1:n_scen
            scenario = max_inj["scenarios"]
            scenario["$s"] = Dict(
                "year" => Dict()
                )
            for y in years
                scenario_year = scenario["$s"]["year"]
                scenario_year["$y"] = Dict(
                    "day" => Dict()
                )
                for d in days
                    scenario_year_day = scenario_year["$y"]["day"]
                    scenario_year_day["$d"] = Dict(
                        "timestamp" => DateTime(0),
                        "active_power" => Inf
                    )
                end
            end
        end
    end
    return 
end

function connection_point_active_injection(connection_point_info, result)
    active_injection = 0.0
    for (i, branch) in connection_point_info
        branch_flow = result["branch"][branch["id"]]["pf"]
        if !isnan(branch_flow)
            active_injection += branch_flow*branch["orientation"]
        end
    end
    return active_injection
end

function handle_max_injection!(current_maximum::Dict, 
                               active_injection::Float64, 
                               timestamp::DateTime)

    current_injection = current_maximum["active_power"]

    if active_injection < current_injection
        current_maximum["active_power"]    = active_injection
        current_maximum["timestamp"]       = timestamp
    end

    return 
end

function update_connection_points_from_result!(connection_points, result, timestamp, s)
    y = Dates.year(timestamp)
    d = Dates.dayofyear(timestamp)
    
    for (name, connection_point) in connection_points
        connection_point_info = connection_point["info"]["PowerModels"]
        active_injection = connection_point_active_injection(
            connection_point_info,
            result
        )
        handle_max_injection!(
            refcp(connection_points, name, s, y, d),
            active_injection,
            timestamp
        )
    end
end

refcp(con_point::Dict, name::String) = con_point[name]
refcp(con_point::Dict, name::String, s::Int) = con_point[name]["scenarios"]["$s"]
refcp(con_point::Dict, name::String, s::Int, y::Int) = con_point[name]["scenarios"]["$s"]["year"]["$y"]
refcp(con_point::Dict, name::String, s::Int, y::Int, d::Int) = con_point[name]["scenarios"]["$s"]["year"]["$y"]["day"]["$d"]
refcp(con_point::Dict, name::String, s::Int, y::Int, d::Int, str::String) = con_point[name]["scenarios"]["$s"]["year"]["$y"]["day"]["$d"][str]

get_vec_keys(dict) = [k for (k, obj) in dict]

refcpkeys(con_point::Dict, name::String) = sort(parse.(Int, get_vec_keys(con_point[name]["scenarios"])))
refcpkeys(con_point::Dict, name::String, s::Int) = sort(parse.(Int, get_vec_keys(con_point[name]["scenarios"]["$s"]["year"])))
refcpkeys(con_point::Dict, name::String, s::Int, y) = sort(parse.(Int, get_vec_keys(con_point[name]["scenarios"]["$s"]["year"]["$y"]["day"])))

function refcpnlines(con_point::Dict, name)
    s = 1
    n_lines = 0
    years = refcpkeys(con_point, name, s)
    for y in years
        days = refcpkeys(con_point, name, s, years[1])
        n_lines += length(days)
    end
    return n_lines
end

function refcpall(con_point::Dict, name)
    n_lines = refcpnlines(con_point, name)
    scenarios_ids = refcpkeys(con_point, name)
    arr = zeros(n_lines, length(scenarios_ids))
    for s in scenarios_ids
        line = 1
        for y in refcpkeys(con_point, name, s)
            for d in refcpkeys(con_point, name, s, y)
                arr[line, s] = refcp(con_point, name, s, y, d, "active_power")
                line += 1
            end
        end
    end
    return arr
end

##########################################
#      Create Execution Groups           #
##########################################


function day_in_days(date::DateTime, days::Vector)
    return Dates.dayofyear(date) ∈ days
end

function year_in_years(date::DateTime, years::Vector)
    return Dates.year(date) ∈ years
end

function handle_timestamps_from_years_and_days(timestamps, years, days)
    
    same_days = day_in_days.(timestamps, [days for d in timestamps])
    same_years = year_in_years.(timestamps, [years for d in timestamps])
    return timestamps[same_days.*same_years]
end

function create_group_operation_points(operation_points::Dict, 
                                       timestamps_iter::Vector{DateTime},
                                       scenarios_ids_iter::Vector{Int},
                                       years_iter::Vector{Int},
                                       days_iter::Vector{Int})
    group_operation_points = Dict("scenarios" => Dict())
    timestamps_group = PowerModelsParallelRoutine.handle_timestamps_from_years_and_days(
        timestamps_iter, years_iter, days_iter
    )
    for s in scenarios_ids_iter
        group_operation_points["scenarios"]["$s"] = Dict("timestamps" => Dict())
        for t in timestamps_group
            iter_oper_point = pop!(operation_points["scenarios"]["$s"]["timestamps"], t)
            group_operation_points["scenarios"]["$s"]["timestamps"][t] = iter_oper_point
        end
    end
    return group_operation_points
end

function create_group_connection_points(connection_points, scenarios_ids,
                                  years, days)
    group_connection_point = Dict()
    for (name, connection_point) in connection_points
        group_connection_point[name] = Dict()
        group_connection_point[name]["info"] = deepcopy(connection_point["info"])
        group_connection_point[name]["scenarios"] = Dict()
        for s in scenarios_ids
            group_connection_point[name]["scenarios"]["$s"] = Dict("year" => Dict())
            for y in years
                group_connection_point[name]["scenarios"]["$s"]["year"]["$y"] = Dict("day" => Dict())
                for d in days
                    con_point = deepcopy(refcp(connection_points, name, s, y, d))
                    group_connection_point[name]["scenarios"]["$s"]["year"]["$y"]["day"]["$d"] = con_point
                end
            end
        end
    end
    return group_connection_point
end

function handle_dict_execution_group(connection_points, operation_points, 
                                     filter_results, timestamps_ids_iter, 
                                     timestamps_iter, scenarios_ids_iter,
                                     years_iter, days_iter)

    execution_groups = Dict("scenarios" => Dict())
    for s in scenarios_ids_iter
        execution_groups["scenarios"]["$s"] = Dict(
            "year" => Dict()
        )
        for y in years_iter
            execution_groups["scenarios"]["$s"]["year"]["$y"] = Dict(
                "day" => Dict()
            )
            for d in days_iter
                group_operation_points =  PowerModelsParallelRoutine.create_group_operation_points(
                    operation_points, timestamps_iter,
                    [s], [y], [d]
                )
                group_connection_point = PowerModelsParallelRoutine.create_group_connection_points(connection_points, [s], [y], [d])

                execution_group   = PowerModelsParallelRoutine.ExecutionGroup(
                    group_operation_points, 
                    filter_results, group_connection_point
                )
                execution_groups["scenarios"]["$s"]["year"]["$y"]["day"]["$d"] = execution_group
            end
        end
    end
    return execution_groups
end

function clear_constant!(constant_symbol::Symbol)
    new_val = nothing
    Base.eval(Main, Expr(:(=), constant_symbol, new_val))
end

function create_all_execution_groups(gen_scenarios, load_scenarios, 
                                     filter_results, connection_points,
                                     timestamps_ids_iter, timestamps_iter, 
                                     scenarios_ids_iter, years_iter, days_iter)
                                     
    all_operation_points_info = Dict(
        "scenarios_ids" => scenarios_ids_iter,
        "timestamps_ids" => timestamps_ids_iter
    )

    operation_points = PowerModelsParallelRoutine.create_operation_points(
        gen_scenarios, load_scenarios, all_operation_points_info, timestamps_iter
    )
    
    # clear space in memory after allocating the scenarios
    # clear_constant!(:gen_scenarios)
    # clear_constant!(:load_scenarios)
    
    # GC.gc()

    return PowerModelsParallelRoutine.handle_dict_execution_group(
        connection_points, operation_points, filter_results, 
        timestamps_ids_iter, timestamps_iter, scenarios_ids_iter, years_iter, days_iter
    )
end

refeg(con_point::Dict,) = con_point[name]
refeg(con_point::Dict, s::Int) = con_point["scenarios"]["$s"]
refeg(con_point::Dict, s::Int, y::Int) = con_point["scenarios"]["$s"]["year"]["$y"]
refeg(con_point::Dict, s::Int, y::Int, d::Int) = con_point["scenarios"]["$s"]["year"]["$y"]["day"]["$d"]
refeg(con_point::Dict, s::Int, y::Int, d::Int, str::String) = con_point["scenarios"]["$s"]["year"]["$y"]["day"]["$d"][str]

##########################################
#     Assemble Connection Points         #
##########################################

function group_has_valid_connection_points(connection_points, name, s, y, d)
    active = try
        refcp(connection_points, name, s, y, d, "active_power")
    catch
        "invalid"
    end
    return active
end

function verify_every_valid_group!(connection_point, execution_groups, name, s, y, d)
    if typeof(execution_groups) == ExecutionGroup
        active = group_has_valid_connection_points(execution_groups.connection_points, name, s, y, d)
        if active != "invalid"
            if active < connection_point["active_power"] # NEGATIVE VALUE
                connection_point["active_power"] = active
            end 
        end
        return
    else
        for (k, v) in execution_groups
            verify_every_valid_group!(connection_point, v, name, s, y, d)
        end
    end
    return 
end

function assemble_connection_points!(connection_points, execution_groups,
                                     scenarios_ids_iter, years_iter, days_iter)
    names = get_vec_keys(connection_points)
    for name in names
        for s in scenarios_ids_iter
            for y in years_iter
                for d in days_iter
                    con_point = PowerModelsParallelRoutine.refcp(connection_points, name, s, y, d)
                    PowerModelsParallelRoutine.verify_every_valid_group!(con_point, execution_groups, name, s, y, d)
                end
            end
        end
    end
end



##########################################
#            Data Processing             #
##########################################


function read_and_converge_network(ASPO, CASE; pm_parameters)
    file = "data/$ASPO/$CASE/network.json"
    # Read network file
    network        = PowerModelsParallelRoutine.read_network(file)
    # Converge network file - needed!
    PowerModelsParallelRoutine.run_model_pm(network, pm_parameters)
    return network
end

function read_scenarios(ASPO, instance)
    # Read generation and load scenarios
    gen_scenarios  = PowerModelsParallelRoutine.read_scenarios_data("data/$ASPO/treated_data/$instance/gen_scenarios.json")
    load_scenarios = PowerModelsParallelRoutine.read_scenarios_data("data/$ASPO/treated_data/$instance/load_scenarios.json")
    operative_rules = Dict()
    
    return gen_scenarios, load_scenarios, operative_rules
end

function build_connection_points(border, network, timestamps, scenarios_ids)
    # Construct connection point dictionary which will store
    # the maximum injection in each connection point for every
    # scenario, year and day
    connection_points = PowerModelsParallelRoutine.create_connection_points(network, border)
    PowerModelsParallelRoutine.create_connection_points_results!(connection_points, timestamps, length(scenarios_ids))
    return connection_points
end

function get_parameters_from_execution_groups(execution_groups)
    scenarios_ids = sort(parse.(Int,PowerModelsParallelRoutine.get_vec_keys(execution_groups["scenarios"])))
    years = sort(parse.(Int,PowerModelsParallelRoutine.get_vec_keys(execution_groups["scenarios"]["$(scenarios_ids[1])"]["year"])))
    days  = sort(parse.(Int,PowerModelsParallelRoutine.get_vec_keys(execution_groups["scenarios"]["$(scenarios_ids[1])"]["year"]["$(years[1])"]["day"])))
    return scenarios_ids, years, days
end


function reduce_scenarios_data(gen_scenarios, s)
    scenarios_data = Dict(
        "names" => gen_scenarios["names"],
        "values" => deepcopy(gen_scenarios["values"][:, :, s]),
        "dates" => gen_scenarios["dates"]
    )
end

##########################################
#     Evaluate Execution Groups          #
##########################################

function evaluate_execution_groups!(network, execution_groups, pm_parameters)
    scenarios_ids, years, days = get_parameters_from_execution_groups(execution_groups)
    
    for s in scenarios_ids
        for y in years
            for d in days
                @info("Executing Group: Scenario $s - Year $y - Day $d")
                ex_group = PowerModelsParallelRoutine.refeg(execution_groups, s, y, d)
                PowerModelsParallelRoutine.evaluate_pf_group!(network, ex_group, pm_parameters)
            end
        end
    end
    return 
end

