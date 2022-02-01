read_json(file::String) = JSON.parse(String(read(file)))

function write_json(file::String, dict::Dict, ident = 4) 
    open(file, "w") do f
        JSON.print(f, dict)
    end
    return file
end

function _handle_info!(data::Dict)
    info = Dict{Any, Any}(
        "parameters" => data["info"]["parameters"],
        "actions"    => data["info"]["actions"]
    )
    data["info"] = info
    return 
end