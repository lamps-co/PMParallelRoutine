function read_scenarios_data(file::String)
    @info("Reading JSON file")
    scenarios_data = PowerModelsParallelRoutine.read_json(file)    
    n_scen = length(scenarios_data["values"])
    @info("Re-organizing scenario values")
    scenarios_data["values"] = cat([hcat(scenarios_data["values"][i]...) for i = 1:n_scen]..., dims = 3)
    scenarios_data["dates"]  = DateTime.(scenarios_data["dates"])
    return scenarios_data
end



