"""
    evaluate_scenarios(data, scenarios::Dict, filter::Dict, 
                       set_initial_values!::Function, pm_model, 
                       build_model::Function, optimizer)

Run power flow model for all operation points. Return the operation points
results filtered by specific elements of the system

Inputs:

Ouputs:
                   
"""
function evaluate_pf_group(network::Dict, operating_points::Dict, model_hierarchy::Dict, parameters, connection_points; logs = true)
    operating_points = NetworkSimulations.handle_operating_points!(operating_points)
    timestamps = operating_points["dims"]["timestamps"]
    scenarios  = operating_points["dims"]["scenarios"]
    
    # store the original converged network 
    original_network = deepcopy(network)

    filter_ref = NetworkSimulations.handle_filter_ref(parameters)

    pms =  NetworkSimulations.instantiate_pm_models(network, model_hierarchy)

    flowtimes = Vector{Float64}()
    for (s, scen) in enumerate(scenarios)
        for (t, date) in enumerate(timestamps)
            if logs
                @info("Evaluating Scenario: $scen ($s of $(length(scenarios))) - Date: $date ($t of $(length(timestamps)))")
            end
            
            NetworkSimulations.save_start_values!(pms)
            NetworkSimulations.update_start_value!(pms)

            # apply operation point (gen, load and system modifications) into network
            NetworkSimulations.apply_operating_point!(pms, network, operating_points, t, s)
            
            # run powermodels power flow algorithm
            results, flowtime = @timed NetworkSimulations.run_model(pms, network, model_hierarchy; filter_ref = filter_ref);
            push!(flowtimes, flowtime)
            
            # verify convergence and re-load original file in non-convergence case
            pms = NetworkSimulations.verify_convergence(pms, original_network, model_hierarchy)

            if results["termination_status"] == 1
                # update connection points structure, i.e, for all connection points
                # verify if the active injection of the current iteration is greater
                # then the maximum injection so far
                update_connection_points_from_result!(connection_points, results["solution"], date, scen)
            end

            if logs
                @info("End of iteration ($s of $(length(scenarios))) at Timestamps $date ($t of $(length(timestamps))): $flowtime seconds")
            end
        end
        if logs
            @info("End of scenario ($s of $(length(scenarios)))")
        end
    end

    return connection_points, flowtimes
end

# 1.42 -> 200
# 1.76 -> 20
