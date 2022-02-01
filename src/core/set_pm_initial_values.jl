function gen_start_value!(result_data::Dict)
    for (g, gen) in result_data["gen"]
        gen["pg_start"] = gen["pg"]
        gen["qg_start"] = gen["qg"]
    end
    return 
end

function set_acp_start_value!(result_data::Dict)
    PowerModels.set_ac_pf_start_values!(result_data)
    gen_start_value!(result_data)
    return
end

function set_acr_start_value!(result_data::Dict)
    for (b, bus) in result_data["bus"]
        va = bus["va"]
        vm = bus["vm"]
        bus["vr_start"] = vm*cos(va)
        bus["vi_start"] = vm*sin(va)
    end
    gen_start_value!(result_data)
    return
end

function set_ivr_start_value!(result_data::Dict)
    PowerModels.update_data!(result_data, PowerModels.calc_branch_flow_ac(result_data))
    for (b, bus) in result_data["bus"]
        va = bus["va"]
        vm = bus["vm"]
        bus["vr_start"] = vm*cos(va)
        bus["vi_start"] = vm*sin(va)
    end
    for (b, branch) in result_data["branch"]
        branch["pf_start"] = branch["pf"]
        branch["pt_start"] = branch["pt"]
        branch["qf_start"] = branch["qf"]
        branch["qt_start"] = branch["qt"]
    end
    gen_start_value!(result_data)
    return
end