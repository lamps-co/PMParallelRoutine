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
    model_hierarchy   = input_data["model_hierarchy"]
    
    parallelize        = input_data["parallelize"]
    command = parallelize["command"]
    procs   = parallelize["procs"]
    outputs_channel = parallelize["outputs_channel"]
    dates_dict    = build_dates_dict(dates)
    
    network = networks_info["Fora Ponta"]["network"]
    connection_points = PowerModelsParallelRoutine.build_connection_points(border, network, dates, scenarios);

    for (sig, network_info) in networks_info
        @info("Running Network Info: $sig")
        network       = network_info["network"]
        lv0_dates     = network_info["dates"]
        lv0_scenarios = scenarios
        
        isempty(lv0_dates) ? continue : nothing

        # Dictionary that stores the maximum injection for each scenario, year and day
        lv0_connection_points = PowerModelsParallelRoutine.build_connection_points(border, network, lv0_dates, lv0_scenarios);
        lv0_dates_dict        = Dict((k, v) for (k, v) in dates_dict if k in lv0_dates)
        lv0_tuples            = build_execution_group_tuples(lv0_dates, lv0_scenarios, lv0_parallel_strategy) # escolher a forma de criação dos grupos de execução
    
        for lv0_tup in lv0_tuples  # outside loop
            @info("Level 0 Tuple: $lv0_tup")
            lv1_dates      = get_execution_group_dates(lv0_dates_dict, lv0_tup)
            lv1_scenarios  = get_execution_group_scenarios(lv0_scenarios, lv0_tup)
        
            lv1_connection_points = PowerModelsParallelRoutine.build_connection_points(border, network, lv1_dates, lv1_scenarios);
            # create level 1 connection point
        
            lv1_dates_dict = Dict((k, v) for (k, v) in dates_dict if k in lv1_dates)
            lv1_dates_indexes = dates_index_from_dates_dict(lv1_dates_dict)
            lv1_tuples = build_execution_group_tuples(lv1_dates, lv1_scenarios, lv1_parallel_strategy) # escolher a forma de criação dos grupos de execução

            execution_groups, map_egs   = create_all_execution_groups_new(
                gen_scenarios, load_scenarios, filter_results, 
                lv1_connection_points, lv1_dates_dict, lv1_dates_indexes,
                lv1_scenarios, lv1_tuples
            );
            if command
                tim = @time evaluate_execution_groups_parallel_optimized!(network, execution_groups, lv1_tuples, model_hierarchy, Dict(), lv1_connection_points, outputs_channel)
            else
                # Evaluate all execution groups 
                evaluate_execution_groups!(network, execution_groups, lv1_tuples, model_hierarchy, Dict(), lv1_connection_points)
            end

            @info("Updating lv0 Connection Points")
            # update lv0_connection_points
            update_connection_points!(lv0_connection_points, lv1_connection_points)
        end
        @info("Updating Final Connection Points")
        #update_lv1_connection_points
        update_connection_points!(connection_points, lv0_connection_points)
    end

    return connection_points
end

@everywhere function parallel_pf_dummy(network, operating_points, model_hierarchy, 
                                  parameters, connection_points, 
                                  outputs_channel; logs = true)  
    @info("In worker $(myid()). DUMMY")
    connection_points = Dict()
    @info("Worker $(myid()): before putting in channel")
    put!(outputs_channel, connection_points)
    @info("Worker $(myid()): put sucessful")
end

@everywhere function parallel_pf(network, operating_points, model_hierarchy, 
                                  parameters, connection_points, 
                                  outputs_channel; logs = true)  
    @info("In worker $(myid())")
    connection_points = PowerModelsParallelRoutine.evaluate_pf_group(
        network, operating_points, model_hierarchy, 
        parameters, connection_points; logs = logs
    )
    
    @info("Worker $(myid()): before putting in channel")
    put!(outputs_channel, connection_points)
    @info("Worker $(myid()): put sucessful")
end

function retrive_outputs!(outputs_channel, master_cp, n_exec_groups)
    n = 0
    while n < n_exec_groups
        slave_cp = take!(outputs_channel)
        update_connection_points!(master_cp, slave_cp)
        n += 1
        @info("Worker $(myid()): successfully took from output channel - progress: $n / $n_exec_groups")
    end
    return 
end

function evaluate_execution_groups_parallel_dummy!(network, execution_groups, ex_group_tuples, model_hierarchy, parameters, lv1_connection_points, outputs_channel)
    n_exec_groups = length(ex_group_tuples)
    @sync @distributed for i = 1:n_exec_groups
        @info("Executing Group: $(ex_group_tuples[i]) in worker $(myid()). DUMMY!")
        @async parallel_pf_dummy(
            network, 
            execution_groups[ex_group_tuples[i]]["operating_points"],
            model_hierarchy,
            parameters,
            execution_groups[ex_group_tuples[i]]["connection_points"],
            outputs_channel;
            logs = false
        )
    end
    retrive_outputs!(outputs_channel, lv1_connection_points, n_exec_groups)
    return 
end

function evaluate_execution_groups_parallel!(network, execution_groups, ex_group_tuples, model_hierarchy, parameters, lv1_connection_points, outputs_channel)
    n_exec_groups = length(ex_group_tuples)
    @sync @distributed for i = 1:n_exec_groups
        @info("Executing Group: $(ex_group_tuples[i]) in worker $(myid())")
        parallel_pf(
            network, 
            execution_groups[ex_group_tuples[i]]["operating_points"],
            model_hierarchy,
            parameters,
            execution_groups[ex_group_tuples[i]]["connection_points"],
            outputs_channel
        )
    end
    retrive_outputs!(outputs_channel, lv1_connection_points, n_exec_groups)
    return 
end

function evaluate_execution_groups_parallel_optimized!(network, execution_groups, ex_group_tuples, model_hierarchy, parameters, lv1_connection_points, outputs_channel)
    n_exec_groups = length(ex_group_tuples)
    @sync @distributed for (i, execution_group) in [(i, execution_groups[ex_group_tuples[i]]) for i = 1:n_exec_groups]
        @info("Executing Group: $(ex_group_tuples[i]) in worker $(myid()). Optimized!!!!")
        parallel_pf(
            network, 
            execution_group["operating_points"],
            model_hierarchy,
            parameters,
            execution_group["connection_points"],
            outputs_channel
        )
    end
    retrive_outputs!(outputs_channel, lv1_connection_points, n_exec_groups)
    return 
end

function create_networks_info(ASPO::String, dates)
    low_network  = PowerModelsParallelRoutine.read_json("data/$ASPO/FP/EMS.json")
    PowerModelsParallelRoutine._handle_info!(low_network)

    @info("Convergindo Fora Ponta")
    low_network, result = PowerModelsParallelRoutine.NetworkSimulations.run_model(low_network, Dict("1" => pm_ivr))
    
    return create_networks_info(low_network, dates)
end

function create_networks_info(low_network, dates)

    low = Dict(
        "network" => low_network,
        "dates" => dates,
        "id_tariff" => 1
    )

    return Dict(
        "Fora Ponta" => low,
    )
end

function update_connection_points!(master_cp, slave_cp)
    for name in keys(slave_cp)
        for s in PowerModelsParallelRoutine.refcpkeys(slave_cp, name)
            for y in PowerModelsParallelRoutine.refcpkeys(slave_cp, name, s)
                for d in PowerModelsParallelRoutine.refcpkeys(slave_cp, name, s, y)
                    master_must_info = PowerModelsParallelRoutine.refcp(master_cp, name, s, y, d)
                    slave_must_info  = PowerModelsParallelRoutine.refcp(slave_cp,  name, s, y, d)
                    if slave_must_info["active_power"] <= master_must_info["active_power"]
                        master_must_info["active_power"] = slave_must_info["active_power"]
                        master_must_info["timestamp"]    = slave_must_info["timestamp"]
                    end
                end
            end
        end
    end
    return 
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

function handle_evaluate_pf_group_inputs(network, ex_group, pm_parameters)
    inputs = Dict(
        "network"           => deepcopy(network),
        "operating_points"  => deepcopy(ex_group.operation_points),
        "model_hierarchy"   => Dict("1"=>pm_parameters),
        "parameters"        => Dict(),
        "connection_points" => deepcopy(ex_group.connection_points)
    )

    return inputs
end

# Function to be parallelized
function evaluate_execution_groups!(network, execution_groups, ex_group_tuples, model_hierarchy, parameters, lv1_connection_points)
    n_exec_groups = length(ex_group_tuples)
    output_connection_points = []
    for i = 1:n_exec_groups
        @info("Executing Group: $(ex_group_tuples[i])")
        connection_points = PowerModelsParallelRoutine.evaluate_pf_group(
            network, 
            execution_groups[ex_group_tuples[i]]["operating_points"],
            model_hierarchy,
            parameters,
            execution_groups[ex_group_tuples[i]]["connection_points"],
            )
        push!(output_connection_points, connection_points)
    end
    for out_cp in output_connection_points
        update_connection_points!(lv1_connection_points, out_cp)
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

        execution_group   = Dict(
            "operating_points" => group_operation_points, 
            "parameters" =>Dict("filter_results" => filter_results), 
            "connection_points" => group_connection_point
        )

        execution_groups[tuple] = execution_group
        execution_groups_map[t] = tuple
    end
    return execution_groups, execution_groups_map
end

function handle_dict_execution_group_new(lv1_connection_points, gen_scenarios, load_scenarios, filter_results,
                                     lv1_dates, lv1_dates_indexes, lv1_scenarios, tuples)
    execution_groups = Dict()
    execution_groups_map = Dict()
    group_dates_dict = build_dates_dict(lv1_dates)

    gen  = gen_scenarios["values"]
    ac_load = load_scenarios["values"]
    re_load = 0.1*load_scenarios["values"]

    for (t, tuple) in enumerate(tuples)
        group_timestamps = get_execution_group_dates(group_dates_dict, tuple)
        group_timestamps_indexes = [group_dates_dict[t]["index"] for t in group_timestamps]
        t_indexes = lv1_dates_indexes[group_timestamps_indexes]
        s_indexes  = get_execution_group_scenarios(lv1_scenarios, tuple)

        group_operation_points = Dict(
            "gen" => Dict(), 
            "load" => Dict(),
            "dims" => Dict(
                "timestamps" => group_timestamps,
                "scenarios" => s_indexes
            ))

        for (g, gen_id) in enumerate(gen_scenarios["names"])
            group_operation_points["gen"][gen_id] = Dict(
                "pg" => gen[t_indexes, g, s_indexes]
                )
        end

        for (l, load_id) in enumerate(load_scenarios["names"])
            group_operation_points["load"][load_id] = Dict(
                "pd" => ac_load[t_indexes, l, s_indexes],
                "qd" => re_load[t_indexes, l, s_indexes],
            )
        end


        years = unique(year.(group_timestamps))
        days = unique(dayofyear.(group_timestamps))
        group_connection_point = PowerModelsParallelRoutine.create_group_connection_points(lv1_connection_points, s_indexes, years, days)

        execution_group   = Dict(
            "operating_points" => group_operation_points, 
            "parameters" =>Dict("filter_results" => filter_results), 
            "connection_points" => group_connection_point
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

function create_all_execution_groups_new(gen_scenarios::Dict, load_scenarios::Dict, 
                                     filter_results::Dict, lv1_connection_points::Dict,
                                     lv1_dates_dict::Dict, lv1_dates_indexes::Vector, 
                                     lv1_scenarios::Vector, lv1_tuples::Vector)

    lv1_dates = sort(get_timestamps_keys(lv1_dates_dict))

    return handle_dict_execution_group_new(
        lv1_connection_points, gen_scenarios, load_scenarios, filter_results,
        lv1_dates, lv1_dates_indexes, lv1_scenarios, lv1_tuples
    )
end
