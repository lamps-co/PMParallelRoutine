"""
    evaluate_scenarios(data, scenarios::Dict, filter::Dict, 
                       set_initial_values!::Function, pm_model, 
                       build_model::Function, optimizer)

Run power flow model for all operation points. Return the operation points
results filtered by specific elements of the system

Inputs:

Ouputs:
                   
"""
function evaluate_pf_group!(network::Dict, execution_group::ExecutionGroup, 
                            pm_parameters::PMParameters; logs = true)

    @unpack  operation_points, filter_results, connection_points = execution_group

    outputs = Dict(
        "scenarios" => Dict(),
        "time" => 0
        )
    # store the original converged network 
    original_network = deepcopy(network)

    execution_time = @elapsed begin 
        scenarios_ids = get_sorted_scenarios_ids(operation_points)
        for s in scenarios_ids
            outputs["scenarios"][s] = Dict(
                "timestamps" => Dict()
                )  
            scenario = operation_points["scenarios"][s]
            timestamps = get_sorted_timestamps(scenario)
            for t in timestamps
                if logs
                    @info("Evaluating Scenario $s at Timestamps $t")
                end
                outputs_iter = outputs["scenarios"][s]["timestamps"]

                # structure that contains the operation point for this iteration
                # gen and load scenario and system modifications
                oper_point = scenario["timestamps"][t]
                
                # apply operation point (gen, load and system modifications) into network
                apply_operation_point!(network, oper_point)
                
                # run powermodels power flow algorithm
                outputs_iter[t] = run_model_pm(network, filter_results, pm_parameters);

                # verify convergence and re-load original file in non-convergence case
                network = verify_convergence!(outputs_iter[t], network, original_network, s, t)

                # unapply system modifications, i.e., contingencies and manouvers
                unapply_system_modifications!(network, original_network, oper_point["system_modifications"])

                # update connection points structure, i.e, for all connection points
                # verify if the active injection of the current iteration is greater
                # then the maximum injection so far
                update_connection_points!(connection_points, outputs_iter[t]["result"], oper_point, t, parse(Int, s))
            end
        end
    end

    outputs["time"] = execution_time

    return outputs
end
