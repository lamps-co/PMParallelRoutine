mutable struct PMParameters
    pm_model
    build_model::Function
    set_initial_values!::Function
    optimizer
end

mutable struct ExecutionGroup
    operation_points::Dict
    filter_results::Dict
    connection_points::Dict
end

