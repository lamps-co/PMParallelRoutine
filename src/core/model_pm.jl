get_sorted_scenarios_ids(operation_points::Dict) = string.(sort(parse.(Int, [s for (s, scen) in operation_points["scenarios"]])))
get_sorted_timestamps(scenario::Dict)        = sort([t for (t, operation_point) in scenario["timestamps"]])

function filter_results(solution, filter)
    if !(typeof(filter) <: Dict)
        return solution
    end
    d = Dict()
    for (k, v) in filter
        d[k] = filter_results(solution[k], v)
    end
    return d
end

"recursive call of _update_data"
function _update_data!(data::Dict, new_data::Dict)
    for (key, new_v) in new_data
        if haskey(data, key)
            v = data[key]
            if isa(v, Dict) && isa(new_v, Dict)
                _update_data!(v, new_v)
            else
                data[key] = new_v
            end
        else
            data[key] = new_v
        end
    end
end

function _restore_data!(modified_data::Dict, original_data, modifications::Dict)
    for (key, new_v) in modifications
        if haskey(modified_data, key)
            modified_v = modified_data[key]
            original_v = original_data[key]
            if isa(modified_v, Dict) && isa(new_v, Dict)
                _restore_data!(modified_v, original_v, new_v)
            else
                modified_data[key] = original_data[key]
            end
        else
            modified_data[key] = original_data[key]
        end
    end
end

function apply_system_modifications!(network, operation_point)
    _update_data!(network, operation_point["system_modifications"])
end

function apply_operation_point!(network::Dict, operation_point::Dict)
    _update_data!(network["gen"], operation_point["gen"])
    _update_data!(network["load"], operation_point["load"])
    apply_system_modifications!(network, operation_point)
end

function unapply_system_modifications!(network::Dict, original_network::Dict, operation_point::Dict)
    _restore_data!(network, original_network, operation_point)
end

function verify_convergence!(outputs_iter_t, network, original_network, s, t)
    if outputs_iter_t["termination_status"] != 1
        @info("Model didn't converge at scenario $s and timestamp $t," *
                            " re-loading original network")
        network = deepcopy(original_network)
    end
    return network
end

function update_results!(network, result)
    solution = result["solution"]
    _update_data!(network, solution)
    _update_data!(network, PowerModels.calc_branch_flow_ac(network))
    network["solve_time"] = result["solve_time"]
    network["termination_status"] = result["termination_status"]
    return 
end

function build_and_optimize(network::Dict, pm_parameters::PMParameters)
    @unpack pm_model, build_model, set_initial_values!, optimizer = pm_parameters

    termination = 0
    build_time  = 0
    opt_time    = 0

    set_initial_values!(network)

    build_time += @elapsed begin 
        pm = PowerModels.instantiate_model(network, pm_model, build_model);
    end
    
    set_optimizer(pm.model, optimizer)
   
    opt_time = @elapsed begin
        result = PowerModels.optimize_model!(pm; solution_processors = [PowerModels.sol_data_model!]);
    end

    result["termination_status"] != MOI.LOCALLY_SOLVED ? @warn("Model did not converged") : termination = 1

    return (termination, build_time, opt_time), result
end

function run_model_pm(network::Dict, filter::Dict, pm_parameters::PMParameters)

    (termination, build_time, opt_time), result = build_and_optimize(network::Dict, pm_parameters::PMParameters)
    
    update_results!(network, result)
    
    filtered_result = filter_results(network, filter)

    return Dict(
        "result"             => filtered_result,
        "build_time"         => build_time, 
        "opt_time"           => opt_time,
        "termination_status" => termination
    )
end

function run_model_pm(network::Dict, pm_parameters::PMParameters)
    (termination, build_time, opt_time), result = build_and_optimize(network::Dict, pm_parameters::PMParameters)
    
    update_results!(network, result)

    return Dict(
        "result"             => network,
        "build_time"         => build_time, 
        "opt_time"           => opt_time,
        "termination_status" => termination
    )
end
