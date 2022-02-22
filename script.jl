include("src/PowerModelsParallelRoutine.jl")

using Dates, CSV, DataFrames, Statistics

######### Define PowerModels Parameters ###############
PowerModelsParallelRoutine.PowerModels.silence() 
     #
pm_ivr = PowerModelsParallelRoutine.pm_ivr_parameters #
pm_acr = PowerModelsParallelRoutine.pm_acr_parameters #
#######################################################

#######################################################
#                Define ASPO, CASE                    #
                                                      #
ASPO = "EMS"                                          #
CASE = "FP"                                           #
file_border = "data/$ASPO/raw_data/border.csv"        #
                                                      #
#                Possible Instances                   #
#                                                     #
instance = "tutorial"    # scenarios: 2,   years:1, days:1   - total number of power flow = 2*1*1*24     =        48   #
# instance = "level 1"     # scenarios: 2,   years:1, days:2   - total number of power flow = 2*1*2*24     =        96   #
# instance = "level 2"     # scenarios: 5,   years:1, days:5   - total number of power flow = 5*1*5*24     =       600   #
# instance = "level 3"     # scenarios: 10,  years:1, days:10  - total number of power flow = 10*1*10*24   =     2.400   #
# instance = "level 4"     # scenarios: 20,  years:1, days:61  - total number of power flow = 20*1*61*24   =    29.280   #
# instance = "level 5"     # scenarios: 50,  years:1, days:181 - total number of power flow = 50*1*181*24  =   210.200   #
# instance = "level 6"     # scenarios: 100, years:1, days:360 - total number of power flow = 100*1*360*24 =   864.000   #
# instance = "final boss"  # scenarios: 200, years:4, days:360 - total number of power flow = 200*4*360*24 = 6.912.000   #
#                                                     #
#######################################################

function create_networks_info(ASPO, dates)
    high_network = PowerModelsParallelRoutine.read_json("data/$ASPO/P/EMS.json")
    low_network  = PowerModelsParallelRoutine.read_json("data/$ASPO/FP/EMS.json")
    PowerModelsParallelRoutine._handle_info!(high_network)
    PowerModelsParallelRoutine._handle_info!(low_network)

    @info("Convergindo Ponta")
    PowerModelsParallelRoutine.run_model_pm(high_network, pm_ivr)
    @info("Convergindo Fora Ponta")
    PowerModelsParallelRoutine.run_model_pm(low_network, pm_ivr)
    
    return create_networks_info(high_network, low_network, dates)
end

function create_networks_info(high_network, low_network, dates)
    high_hours = [20,20,21,22]
    low_hours  = [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,23]

    high = Dict(
        "network" => high_network,
        "dates" => dates[findall(dt->hour(dt) in high_hours,dates)],
        "id_tariff" => 2
    )
    low = Dict(
        "network" => low_network,
        "dates" => dates[findall(dt->hour(dt) in low_hours,dates)],
        "id_tariff" => 1
    )

    return Dict(
        "Ponta" => high,
        "Fora Ponta" => low,
    )
end



#_--__--__--__--__--__--__--__--__--__--__--__--__--__--__--__--__--__-#
#                           EXECUTION                                  #
#_--__--__--__--__--__--__--__--__--__--__--__--__--__--__--__--__--__-#

gen_scenarios, load_scenarios, trash = PowerModelsParallelRoutine.read_scenarios(ASPO, instance);
(all_timestamps, all_scenarios_ids, all_years, all_days) = PowerModelsParallelRoutine.case_parameters(gen_scenarios);

border = read_border_as_matrix(file_border)

networks_info = create_networks_info(ASPO, all_timestamps)

filter_results = PowerModelsParallelRoutine.create_filter_results(ASPO, network); # 

networks_info["Fora Ponta"]["dates"] = networks_info["Fora Ponta"]["dates"] .|> DateTime
networks_info["Ponta"]["dates"]      = networks_info["Ponta"]["dates"] .|> DateTime

lv0_parallel_strategy = build_parallel_strategy(scen = -1)
lv1_parallel_strategy = build_parallel_strategy(doy = true)

input_data = Dict(
    "gen_scenarios"     => gen_scenarios,
    "load_scenarios"    => load_scenarios,
    "border"            => border,
    "networks_info"     => networks_info,
    "parallel_strategy" => Dict("lv0"=>lv0_parallel_strategy, "lv1"=>lv1_parallel_strategy),
    "filter_results"    => filter_results,
    "dates"             => all_timestamps,
    "scenarios"         => all_scenarios_ids
)

function evaluate_pf_scenarios(input_data::Dict)
    gen_scenarios     = input_data["gen_scenarios"]
    load_scenarios    = input_data["load_scenarios"]
    border            = input_data["border"]
    networks_info     = input_data["networks_info"]
    parallel_strategy = input_data["parallel_strategy"]
    lv0_parallel_strategy = parallel_strategy["lv0"]
    lv1_parallel_strategy = parallel_strategy["lv1"]
    filter_results    = input_data["filter_results"]
    dates             = input_data["dates"]
    scenarios         = input_data["scenarios"]

    dates_dict    = build_dates_dict(dates)
    
    network = networks_info["Ponta"]["network"]
    connection_points = PowerModelsParallelRoutine.build_connection_points(border, network, dates, scenarios);

    for (sig, network_info) in networks_info
        network_info = networks_info["Fora Ponta"]
        @info("Running Network: $sig")
        network = network_info["network"]

        lv0_dates = network_info["dates"]
        lv0_scenarios = scenarios
        
        isempty(lv0_dates) ? continue : nothing

        # Dictionary that stores the maximum injection for each scenario, year and day
        lv0_connection_points = PowerModelsParallelRoutine.build_connection_points(border, network, lv0_dates, lv0_scenarios);
    
        lv0_dates_dict = Dict((k, v) for (k, v) in dates_dict if k in lv0_dates)
        lv0_dates_indexes = dates_index_from_dates_dict(lv0_dates_dict)
        lv0_tuples = build_execution_group_tuples(lv0_dates, lv0_scenarios, lv0_parallel_strategy) # escolher a forma de criação dos grupos de execução
    
        lv0_filters = create_filters(lv0_tuples)
    
        for lv0_tup in lv0_tuples  # outside loop
            lv0_tup = lv0_tuples[1]
            @info("Level 0 Tuple: $lv0_tup")
            lv1_dates      = get_execution_group_dates(lv0_dates_dict, lv0_tup)
            lv1_scenarios  = get_execution_group_scenarios(lv0_scenarios, lv0_tup)
        
            lv1_connection_points = PowerModelsParallelRoutine.build_connection_points(border, network, lv1_dates, lv1_scenarios);
            # create level 1 connection point
        
            lv1_dates_dict = Dict((k, v) for (k, v) in dates_dict if k in lv1_dates)
            lv1_dates_indexes = dates_index_from_dates_dict(lv1_dates_dict)
            lv1_tuples = build_execution_group_tuples(lv1_dates, lv1_scenarios, lv1_parallel_strategy) # escolher a forma de criação dos grupos de execução

            execution_groups, map_egs   = create_all_execution_groups(
                gen_scenarios, load_scenarios, filter_results, 
                lv1_connection_points, lv1_dates_dict, lv1_dates_indexes,
                lv1_scenarios, lv1_tuples
            );
    
            # Evaluate all execution groups parallelizing
            evaluate_execution_groups!(network, execution_groups, pm_ivr)

            # updating lv1_connection_points
            for (group, eg) in execution_groups
                eg_timestamps = get_execution_group_dates(lv1_dates_dict, group)
                eg_scenarios  = get_execution_group_scenarios(lv1_scenarios, group)

                eg_years, eg_days = get_connection_point_sets(eg_timestamps)
                
                update_connection_points!(lv1_connection_points, eg.connection_points, eg_scenarios, eg_years, eg_days)
            end
        
            lv1_scenarios
            lv1_years, lv1_days = get_connection_point_sets(lv1_dates)
            # update lv0_connection_points
            update_connection_points!(lv0_connection_points, lv1_connection_points, lv1_scenarios, lv1_years, lv1_days)
        end

        lv0_scenarios
        lv0_years, lv0_days = get_connection_point_sets(lv0_dates)
        #update_lv1_connection_points
        update_connection_points!(connection_points, lv0_connection_points, lv0_scenarios, lv0_years, lv0_days)
    end

    return connection_points
end

function update_connection_points!(master_cp, slave_cp, scenarios, years, days)
    for (name, slcp) in slave_cp, s in scenarios, y in years, d in days
        master_must_info = PowerModelsParallelRoutine.refcp(master_cp, name, s, y, d)
        slave_must_info  = PowerModelsParallelRoutine.refcp(slave_cp,  name, s, y, d)
        if slave_must_info["active_power"] <= master_must_info["active_power"]
            master_must_info["active_power"] = slave_must_info["active_power"]
            master_must_info["timestamp"]    = slave_must_info["timestamp"]
        end
    end
end

connection_points = evaluate_pf_scenarios(input_data)

for (sig, network_info) in networks_info
    sig = "FPU"
    network_info = networks_info[sig]

    lv0_dates = DateTime.(network_info["dates"])
    lv0_scenarios = scenarios_ids

    # Dictionary that stores the maximum injection for each scenario, year and day
    lv0_connection_points = PowerModelsParallelRoutine.build_connection_points(ASPO, network, lv0_dates, lv0_scenarios);

    lv0_dates_dict = Dict((k, v) for (k, v) in dates_dict if k in lv0_dates)
    lv0_dates_indexes = dates_index_from_dates_dict(lv0_dates_dict)
    lv0_tuples = build_execution_group_tuples(lv0_dates, lv0_scenarios, lv0_parallel_strategy) # escolher a forma de criação dos grupos de execução

    lv0_filters = create_filters(lv0_tuples)

    for lv0_tup in lv0_tuples  # outside loop
    
        lv0_tup = lv0_tuples[1]

        lv1_dates      = get_execution_group_dates(lv0_dates_dict, lv0_tup)
        lv1_scenarios  = get_execution_group_scenarios(lv0_scenarios, lv0_tup)
    
        lv1_connection_points = PowerModelsParallelRoutine.build_connection_points(ASPO, network, lv1_dates, lv1_scenarios);
        # create level 1 connection point
    
        execution_groups, map_egs   = create_all_execution_groups(
            reduce_scenarios_data(gen_scenarios, lv0_dates_indexes), 
            reduce_scenarios_data(load_scenarios, lv0_dates_indexes), 
            filter_results, lv1_connection_points, lv1_dates, 
            lv1_scenarios, lv1_parallel_strategy
        );
        
        # Evaluate all execution groups parallelizing
        evaluate_execution_groups!(network, execution_groups, pm_acr)
    
        for (group, eg) in execution_groups
            op = eg.operation_points
            eg_scenarios = scenarios_from_operation_points(op)
            eg_timestamps = timestamps_from_operation_points(op, eg_scenarios[1])
        
            eg_scenarios, eg_years, eg_days = get_connection_point_sets(eg_scenarios, eg_timestamps)
            for (name, egcp) in eg.connection_points, s in eg_scenarios, y in eg_years, d in eg_days
                lv1_must_info   = PMPR.refcp(lv1_connection_points, name, s, y, d)
                group_must_info = PMPR.refcp(eg.connection_points, name, s, y, d)
                if group_must_info["active_power"] <= lv1_must_info["active_power"]
                    lv1_must_info["active_power"] = group_must_info["active_power"]
                    lv1_must_info["timestamp"]    = group_must_info["timestamp"]
                end
            end
        end
    
        eg_scenarios, eg_years, eg_days = get_connection_point_sets(lv1_scenarios, lv1_dates)
        
        for (name, egcp) in eg.connection_points, s in eg_scenarios, y in eg_years, d in eg_days
            lv1_must_info   = PMPR.refcp(lv1_connection_points, name, s, y, d)
            group_must_info = PMPR.refcp(eg.connection_points, name, s, y, d)
            if group_must_info["active_power"] <= lv1_must_info["active_power"]
                lv1_must_info["active_power"] = group_must_info["active_power"]
                lv1_must_info["timestamp"]    = group_must_info["timestamp"]
            end
        end
    end

end
### FOR EVERY NETWORK IN SET OF NETWORKS


data = PowerModelsParallelRoutine.read_json("data/EMS/P/EMS.json")
PowerModelsParallelRoutine._handle_info!(data)

PowerModelsParallelRoutine.run_model_pm(data, pm_ivr)

op = execution_groups[map_egs[1]].operation_points["scenarios"]["1"]["timestamps"][DateTime("2019-01-01T20:00:00")]

PowerModelsParallelRoutine.apply_operation_point!(data, op)

PowerModelsParallelRoutine.run_model_pm(data, pm_acr)



networks_info["Ponta"]["network"]
data




lv0_parallel_strategy = build_parallel_strategy(h = true, scen = 1)
lv1_parallel_strategy = build_parallel_strategy(doy = true)

lv0_dates = timestamps
lv0_scenarios = scenarios_ids

# Dictionary that stores the maximum injection for each scenario, year and day
lv0_connection_points = PowerModelsParallelRoutine.build_connection_points(ASPO, network, lv0_dates, lv0_scenarios);

lv0_dates_dict = build_dates_dict(lv0_dates)

lv0_tuples = build_execution_group_tuples(lv0_dates, lv0_scenarios, lv0_parallel_strategy) # escolher a forma de criação dos grupos de execução

lv0_filters = create_filters(lv0_tuples)

for lv0_tup in lv0_tuples  # outside loop
    
    lv1_dates      = get_execution_group_dates(lv0_dates_dict, lv0_tup)
    lv1_scenarios  = get_execution_group_scenarios(lv0_scenarios, lv0_tup)

    lv1_connection_points = PowerModelsParallelRoutine.build_connection_points(ASPO, network, lv1_dates, lv1_scenarios);
    # create level 1 connection point

    execution_groups, map_egs   = create_all_execution_groups(gen_scenarios, load_scenarios, filter_results, lv1_connection_points, lv1_dates, lv1_scenarios, lv1_parallel_strategy);
    
    # Evaluate all execution groups parallelizing
    evaluate_execution_groups!(network, execution_groups, pm_acr)

    for (group, eg) in execution_groups
        op = eg.operation_points
        eg_scenarios = scenarios_from_operation_points(op)
        eg_timestamps = timestamps_from_operation_points(op, eg_scenarios[1])
    
        eg_scenarios, eg_years, eg_days = get_connection_point_sets(eg_scenarios, eg_timestamps)
        for (name, egcp) in eg.connection_points, s in eg_scenarios, y in eg_years, d in eg_days
            lv1_must_info   = PMPR.refcp(lv1_connection_points, name, s, y, d)
            group_must_info = PMPR.refcp(eg.connection_points, name, s, y, d)
            if group_must_info["active_power"] <= lv1_must_info["active_power"]
                lv1_must_info["active_power"] = group_must_info["active_power"]
                lv1_must_info["timestamp"]    = group_must_info["timestamp"]
            end
        end
    end

    # reassemble the connection groups evaluated
    PowerModelsParallelRoutine.assemble_connection_points!(connection_points, execution_groups, scenarios_ids_iter, years_iter, days_iter)

    eg_scenarios, eg_years, eg_days = get_connection_point_sets(lv1_scenarios, lv1_dates)
    
    for (name, egcp) in eg.connection_points, s in eg_scenarios, y in eg_years, d in eg_days
        lv1_must_info   = PMPR.refcp(lv1_connection_points, name, s, y, d)
        group_must_info = PMPR.refcp(eg.connection_points, name, s, y, d)
        if group_must_info["active_power"] <= lv1_must_info["active_power"]
            lv1_must_info["active_power"] = group_must_info["active_power"]
            lv1_must_info["timestamp"]    = group_must_info["timestamp"]
        end
    end
end

function read_border_as_matrix(path) 
    border = Matrix{Any}(CSV.read(file_border, delim = ";", DataFrame)[3:end, :])
    border[:, 1] = string.(border[:, 1])
    border[:, 2:end] = parse.(Int, border[:, 2:end])
    return border
end

function reduce_scenarios_data(scenarios_data, dates_index)
    return Dict(
        "names" => scenarios_data["names"],
        "values" => scenarios_data["values"][dates_index, :, :],
        "dates" => scenarios_data["dates"][dates_index]
    )
end

function assemble_connection_points!(scenarios, timestamps, slave_cp, master_cp)
    years, days = get_connection_point_sets(timestamps)
    for (name, thrash) in slave_cp.connection_points, s in scenarios, y in years, d in days
        lv1_must_info   = PMPR.refcp(lv1_connection_points, name, s, y, d)
        group_must_info = PMPR.refcp(eg.connection_points, name, s, y, d)
        if group_must_info["active_power"] <= lv1_must_info["active_power"]
            lv1_must_info["active_power"] = group_must_info["active_power"]
            lv1_must_info["timestamp"]    = group_must_info["timestamp"]
        end
    end
end

get_keys(dict) = [k for (k, v) in dict]
get_scenarios_keys(dict) = sort(parse.(Int, get_keys(dict)))
get_timestamps_keys(dict) = DateTime.(get_keys(dict))

scenarios_from_operation_points(op) = get_scenarios_keys(op["scenarios"])
timestamps_from_operation_points(op, s) = get_timestamps_keys(op["scenarios"]["$s"]["timestamps"])

function get_connection_point_sets(timestamps)

    return set_of_years(timestamps), set_of_daysofyear(timestamps)
end

# Function to be parallelized
function evaluate_execution_groups!(network, execution_groups, pm_parameters)
    for (group, ex_group) in execution_groups
        @info("Executing Group: $group")
        PowerModelsParallelRoutine.evaluate_pf_group!(network, ex_group, pm_parameters)
    end

    return 
end

function build_parallel_strategy(;y = false, s = false, q = false, m = false, w = false, d = false, doy = false, dow = false, h = false, cont = false, scen = -1) 
    return (y = y, s = s, q = q, m = m, w = w, d = d, doy = doy, dow = dow, h = h, cont = cont, scen = scen)
end

semester(dt) = Int(ceil(Dates.quarterofyear(dt) / 2))

function dates_info(dt::DateTime, id::Int) #, additional_info) # todo for contingency
    y   = year(dt)
    s   = semester(dt)
    q   = quarterofyear(dt)
    m   = month(dt)
    w   = week(dt)
    dow =  dayofweek(dt)
    d   = day(dt)
    doy = dayofyear(dt)
    h   = hour(dt)
    
    return Dict(
        "year" => y,
        "semester" => s,
        "quarterofyear" => q,
        "month" => m,
        "week" => w,
        "day" => d,
        "dayofyear" => doy,
        "dayofweek" => dow,
        "hour" => h,
        "index" => id,
        # "contingency" => [-1, 3, -1, -1, 1] # TODO contingency id at scenarios i. -1 when no contingency is applied
    )
end

function build_dates_dict(dts::Vector{DateTime}) #, additional_info) for contingency
    dates_dict = Dict()
    for (i, dt) in enumerate(dts)
        dates_dict[dt] = dates_info(dt, i) #, additional_info) for contingency
    end
    return dates_dict
end

function create_filters(tuple::Tuple)

    filters = Function[]
    if tuple[1] !== nothing
        push!(filters, (dt, y) -> dt["year"] == y)
    else
        push!(filters, (dt, y) -> true)
    end
    if tuple[2] !== nothing
        push!(filters, (dt, s) -> dt["semester"] == s)
    else
        push!(filters, (dt, s) -> true)
    end
    if tuple[3] !== nothing
        push!(filters, (dt, q) -> dt["quarterofyear"] == q)
    else
        push!(filters, (dt, q) -> true)
    end
    if tuple[4] !== nothing
        push!(filters, (dt, m) -> dt["month"] == m)
    else
        push!(filters, (dt, m) -> true)
    end
    if tuple[5] !== nothing
        push!(filters, (dt, w) -> dt["week"] == w)
    else
        push!(filters, (dt, w) -> true)
    end
    if tuple[6] !== nothing
        push!(filters, (dt, d) -> dt["day"] == d)
    else
        push!(filters, (dt, d) -> true)
    end
    if tuple[7] !== nothing
        push!(filters, (dt, doy) -> dt["dayofyear"] == doy)
    else
        push!(filters, (dt, doy) -> true)
    end
    if tuple[8] !== nothing
        push!(filters, (dt, dow) -> dt["dayofweek"] == dow)
    else
        push!(filters, (dt, dow) -> true)
    end
    if tuple[9] !== nothing
        push!(filters, (dt, h) -> dt["hour"] == h)
    else
        push!(filters, (dt, h) -> true)
    end
    # todo contingency
    # if tuple[5] !== nothing
    #     push!(filters, (dt, c) -> dt["contingency"] == h)
    # else
    #     push!(filters, (dt, c) -> true)
    # end
    return filters
end

function create_filters(tuples::Vector)
    return create_filters(tuples[1])
end


set_of_years(dates)      = unique(year.(dates))
set_of_semesters(dates)  = unique(semester.(dates))
set_of_quartersofyear(dates) = unique(quarterofyear.(dates))
set_of_months(dates)     = unique(month.(dates))
set_of_weeks(dates)      = unique(week.(dates))
set_of_days(dates)       = unique(day.(dates))
set_of_daysofyear(dates) = unique(dayofyear.(dates))
set_of_daysofweek(dates) = unique(dayofweek.(dates))
set_of_hour(dates)       = unique(hour.(dates))

function set_of_scenarios(scenarios_ids, n_scen_per_group)
    Ω_scenarios = Vector[]
    scenarios_group = []
    count = 0
    for s in scenarios_ids
        count += 1
        push!(scenarios_group, s)
        if count == n_scen_per_group
            count = 0
            push!(Ω_scenarios, scenarios_group)
            scenarios_group = []
        end
    end
    if count != 0
        push!(Ω_scenarios, scenarios_group)
    end
    return Ω_scenarios
end

function build_execution_group_tuples(network_dates::Vector{DateTime}, scenarios_ids::Vector{Int}, parallel_strategy)
    (y, s, q, m, w, d, doy, dow, h, cont, scen) = parallel_strategy
    Ω_years           = y == true   ? set_of_years(network_dates)          : [nothing]
    Ω_semesters       = s == true   ? set_of_semesters(network_dates)      : [nothing]
    Ω_quartersofyear  = q == true   ? set_of_quartersofyear(network_dates) : [nothing]
    Ω_months          = m == true   ? set_of_months(network_dates)         : [nothing]
    Ω_weeks           = w == true   ? set_of_weeks(network_dates)          : [nothing]
    Ω_days            = d == true   ? set_of_days(network_dates)           : [nothing]
    Ω_daysofyear      = doy == true   ? set_of_daysofyear(network_dates)     : [nothing]
    Ω_daysofweek      = dow == true ? set_of_daysofweek(network_dates)     : [nothing]
    Ω_hours           = h == true   ? set_of_hour(network_dates)           : [nothing]

    Ω_scenarios       = scen != -1  ? set_of_scenarios(scenarios_ids, scen) : [-1]

    exec_group_tup = []
    for year in Ω_years, semester in Ω_semesters, quarterofyear in Ω_quartersofyear, month in Ω_months, week in Ω_weeks, day in Ω_days, doy in Ω_daysofyear, dow in Ω_daysofweek, hour in Ω_hours, scen in Ω_scenarios
        push!(exec_group_tup, (year, semester, quarterofyear, month, week, day, doy, dow, hour, scen))
    end

   return exec_group_tup
end

function get_execution_group_dates(dates_dict, tup_info)
    filters = create_filters(tup_info)

    return sort(findall(
        dt -> all([func(dt, tup_info[f]) for (f, func) in enumerate(filters)]),
        dates_dict
    ))
end

function get_execution_group_scenarios(scenarios_ids::Vector{Int}, tup_info)
    filter_ids = tup_info[end]
    return filter_ids === -1 ? scenarios_ids : findall(scen -> scen in filter_ids, scenarios_ids)
end

dates_index_from_dates_dict(dates_dict) = sort([dt["index"] for (k, dt) in dates_dict])

function handle_dict_execution_group(lv1_connection_points, operation_points, filter_results,
                                     lv1_dates, lv1_scenarios, tuples)
    execution_groups = Dict()
    execution_groups_map = Dict()
    group_dates_dict = build_dates_dict(lv1_dates)
    for (t, tuple) in enumerate(tuples)

        group_timestamps = get_execution_group_dates(group_dates_dict, tuple)
        group_scenarios  = get_execution_group_scenarios(lv1_scenarios, tuple)

        group_operation_points = Dict("scenarios"=>Dict())
        for s in group_scenarios
            group_operation_points["scenarios"]["$s"] = Dict("timestamps" => Dict())
            for t in group_timestamps
                iter_oper_point = pop!(operation_points["scenarios"]["$s"]["timestamps"], t)
                group_operation_points["scenarios"]["$s"]["timestamps"][t] = iter_oper_point
            end
        end

        years = unique(year.(group_timestamps))
        days = unique(dayofyear.(group_timestamps))
        group_connection_point = PowerModelsParallelRoutine.create_group_connection_points(lv1_connection_points, group_scenarios, years, days)

        execution_group   = PowerModelsParallelRoutine.ExecutionGroup(
            group_operation_points, 
            filter_results, group_connection_point
        )
        execution_groups[tuple] = execution_group
        execution_groups_map[t] = tuple
    end
    return execution_groups, execution_groups_map
end

function create_all_execution_groups(gen_scenarios::Dict, load_scenarios::Dict, 
                                     filter_results::Dict, lv1_connection_points::Dict,
                                     lv1_dates_dict::Dict, lv1_dates_indexes::Vector, 
                                     lv1_scenarios::Vector, lv1_tuples::Vector)

    lv1_dates = sort(get_timestamps_keys(lv1_dates_dict))

    all_operation_points_info = Dict(
        "scenarios_ids" => lv1_scenarios,
        "timestamps_ids" => lv1_dates_indexes
    )

    operation_points = PowerModelsParallelRoutine.create_operation_points(
        gen_scenarios, load_scenarios, all_operation_points_info
    )

    return handle_dict_execution_group(
        lv1_connection_points, operation_points, filter_results,
        lv1_dates, lv1_scenarios, lv1_tuples
    )
end