function read_network(file::String)
    filetype = split(lowercase(file), '.')[end]
    if filetype == "json"
        network = read_json(file)
        _handle_info!(network)
    elseif filetype == "pwf"
        network = PWF.parse_file(file, add_control_data = true)
    else
        @error("Filetype $filetype not availble when reading a network file")
    end
    
    return network
end