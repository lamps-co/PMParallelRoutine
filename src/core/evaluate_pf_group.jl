"""
    evaluate_scenarios(data, scenarios::Dict, filter::Dict, 
                       set_initial_values!::Function, pm_model, 
                       build_model::Function, optimizer)

Run power flow model for all operation points. Return the operation points
results filtered by specific elements of the system

Inputs:

Ouputs:
                   
"""
function evaluate_pf_group(network, operating_points, model_hierarchy, 
                           parameters, connection_points; logs = true)

     outputs = Dict(
        "scenarios" => Dict(),
        "time" => 0
    )

    # store the original converged network 
    original_network = deepcopy(network)

    filter_ref = PowerFlowModule.handle_filter_ref(parameters)

    total_time = 0.0
    scenarios_ids = PowerFlowModule.get_sorted_scenarios_ids(operating_points)
    for s in scenarios_ids
        outputs["scenarios"][s] = Dict(
            "timestamps" => Dict()
            )  
        scenario = operating_points["scenarios"][s]
        timestamps = PowerFlowModule.get_sorted_timestamps(scenario)
        for (t, date) in enumerate(timestamps)
            if logs
                @info("Evaluating Scenario ($s of $(length(scenarios_ids))) at Timestamps $date ($t of $(length(timestamps)))")
            end
            outputs_iter = outputs["scenarios"][s]["timestamps"]

            # structure that contains the operation point for this iteration
            # gen and load scenario and system modifications
            oper_point = scenario["timestamps"][date]

            # apply operation point (gen, load and system modifications) into network
            PowerFlowModule.apply_operation_point!(network, oper_point)
            
            # run powermodels power flow algorithm
            (network, outputs_iter[t]), flowtime = @timed PowerFlowModule.run_model(network, model_hierarchy; filter_ref = filter_ref);
            total_time += flowtime

            # verify convergence and re-load original file in non-convergence case
            network = PowerFlowModule.verify_convergence!(outputs_iter[t], network, original_network)

            if outputs_iter[t]["termination_status"] == 1
                # unapply system modifications, i.e., contingencies and manouvers
                PowerFlowModule.unapply_system_modifications!(network, original_network, oper_point["system_modifications"])

                # update connection points structure, i.e, for all connection points
                # verify if the active injection of the current iteration is greater
                # then the maximum injection so far
                update_connection_points_from_result!(connection_points, network, date, parse(Int, s))
            end
            outputs_iter[t] = Dict()
            if logs
                @info("End of iteration ($s of $(length(scenarios_ids))) at Timestamps $date ($t of $(length(timestamps))): $flowtime seconds")
            end
        end
        if logs
            @info("End of scenario ($s of $(length(scenarios_ids)))")
        end
    end
    @info("End of function")
    # if logs
        # Ntimes = length(timestamps) * length(scenarios_ids)
        # @info("Time of execution for power flow group at worker $(myid()): $total_time")
        # @info("Mean execution time of $Ntimes power flows at worker $(myid()): $(total_time / Ntimes)")
    # end

    return connection_points
end
