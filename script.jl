include("src/PowerModelsParallelRoutine.jl")
using Dates, CSV, DataFrames, Statistics, JSON
using Distributed
using SMTPClient

# procids = addprocs([("ubuntu@ec2-174-129-50-22.compute-1.amazonaws.com:22", 1)], sshflags=`-vvv -o StrictHostKeyChecking=no -i "/Users/pedroferraz/Desktop/acmust_lamps.pem"`, tunnel=true, exename="/home/ubuntu/julia-1.6.5/bin/julia", exeflags=["--project"], dir="/home/ubuntu/PMParallelRoutine/", max_parallel=100)
ssh -i /Users/pedroferraz/Desktop/acmust_lamps.pem ubuntu@ec2-54-227-67-130.compute-1.amazonaws.com

# @everywhere procids begin
#     using Pkg
#     Pkg.activate(".")
#     Pkg.instantiate()
# end

function send_mail(subject::String; message::String="")
    opt = SendOptions(
    isSSL = true,
    username = "pedroferraz1029@gmail.com",
    passwd = "TestesJulia123",
    verbose=true)

    url = "smtp://smtp.gmail.com:587"
    to = ["<pedroferraz1029@gmail.com>", "<iagochavarry20@gmail.com>"]
    from = "<pedroferraz1029@gmail.com>"
    subject = subject
    message = message

    mime_msg = get_mime_msg(message)

    body = get_body(to, from, subject, mime_msg)

    resp = send(url, to, from, body, opt)
end

function send_mail(file_name::String, subject::String; message::String="")
    opt = SendOptions(
    isSSL = true,
    username = "pedroferraz1029@gmail.com",
    passwd = "TestesJulia123",
    verbose=true)

    url = "smtp://smtp.gmail.com:587"
    to = ["<pedroferraz1029@gmail.com>", "<iagochavarry20@gmail.com>"]
    from = "<pedroferraz1029@gmail.com>"
    subject = subject
    message = message
    attachments = [file_name]

    mime_msg = get_mime_msg(message)

    body = get_body(to, from, subject, mime_msg; attachments)

    resp = send(url, to, from, body, opt)
end

# Parallel Parameters
parallel        = true
procs           = 3
CHANNEL = RemoteChannel(()->Channel{Vector{Float64}}(Inf));
include("script_functions.jl")
#                Possible Instances                   #
#                                                     #
# instance = "tutorial"    # scenarios: 2,   years:1, days:1   - total number of power flow = 2*1*1*24     =        48   #
# instance = "level 1"     # scenarios: 2,   years:1, days:2   - total number of power flow = 2*1*2*24     =        96   #
# instance = "level 2"     # scenarios: 5,   years:1, days:5   - total number of power flow = 5*1*5*24     =       600   #
# instance = "level 3"     # scenarios: 10,  years:1, days:10  - total number of power flow = 10*1*10*24   =     2.400   #
# instance = "level 4"     # scenarios: 20,  years:1, days:61  - total number of power flow = 20*1*61*24   =    29.280   #
# instance = "level 5"     # scenarios: 50,  years:1, days:181 - total number of power flow = 50*1*181*24  =   210.200   #
# instance = "level 6"     # scenarios: 100, years:1, days:360 - total number of power flow = 100*1*360*24 =   864.000   #
# instance = "final boss"  # scenarios: 200, years:4, days:360 - total number of power flow = 200*4*360*24 = 6.912.000   #
#                                                     #
#######################################################
function create_input_data(instance; ts_range=nothing, scen_range=nothing)
    ###########
    pm_ivr = PowerModelsParallelRoutine.pm_ivr_parameters #
    pm_acr = PowerModelsParallelRoutine.pm_acr_parameters #
    pm_ivr_s = PowerModelsParallelRoutine.pm_ivr_parameters_silence #
    pm_acr_s = PowerModelsParallelRoutine.pm_acr_parameters_silence #
    #######################################################

    #######################################################
    #                Define ASPO, CASE                    #
                                                        #
    ASPO = "EMS"                                          #
    CASE = "FP"                                           #
    file_border = "data/$ASPO/raw_data/border.csv"        #
    println(file_border)
                                                        #
    #_--__--__--__--__--__--__--__--__--__--__--__--__--__--__--__--__--__-#
    #                           EXECUTION                                  #
    #_--__--__--__--__--__--__--__--__--__--__--__--__--__--__--__--__--__-#

    gen_scenarios, load_scenarios, trash = PowerModelsParallelRoutine.read_scenarios(ASPO, instance);
    timestamps_range = isnothing(ts_range) ? collect(1:size(gen_scenarios["values"], 1)) : ts_range
    scenarios_range = isnothing(scen_range) ? collect(1:size(gen_scenarios["values"], 3)) : scen_range
    gen_scenarios["values"] = gen_scenarios["values"][timestamps_range, :, scenarios_range]
    gen_scenarios["dates"] = gen_scenarios["dates"][timestamps_range]
    load_scenarios["values"] = load_scenarios["values"][timestamps_range, :, scenarios_range]
    load_scenarios["dates"] = load_scenarios["dates"][timestamps_range]

    (all_timestamps, all_scenarios_ids, all_years, all_days) = PowerModelsParallelRoutine.case_parameters(gen_scenarios);

    dates_dict    = build_dates_dict(all_timestamps)

    border = read_border_as_matrix(file_border)

    networks_info = create_networks_info(ASPO, all_timestamps, pm_ivr)

    network = networks_info["Fora Ponta"]["network"]

    filter_results = PowerModelsParallelRoutine.create_filter_results(ASPO, network); # 

    networks_info["Fora Ponta"]["dates"] = networks_info["Fora Ponta"]["dates"] .|> DateTime

    model_hierarchy = Dict("1" => pm_acr_s)
    model_hierarchy["1"]["build_model"] = PowerModelsParallelRoutine.NetworkSimulations.build_pf_plf_instantiate

    lv0_parallel_strategy = build_parallel_strategy()
    lv1_parallel_strategy = build_parallel_strategy()

    input_data = Dict(
        "gen_scenarios"     => gen_scenarios,
        "load_scenarios"    => load_scenarios,
        "border"            => border,
        "networks_info"     => networks_info,
        "parallel_strategy" => Dict("lv0"=>lv0_parallel_strategy, "lv1"=>lv1_parallel_strategy),
        "filter_results"    => filter_results,
        "dates"             => all_timestamps,
        "scenarios"         => all_scenarios_ids,
        "model_hierarchy"   => model_hierarchy,
        "parallelize"       => Dict(
            "command"         => parallel,
            "procs"           => procs,
            "outputs_channel" => CHANNEL
        )
    )
    return input_data
end

function run_test(input_data)
    (connection_points, all_flowtimes), time = @timed evaluate_pf_scenarios(input_data)
    return connection_points, all_flowtimes, time
end

function run_study(study_name, machine_ids, input_data)
    study_input_data = deepcopy(input_data)

    results = Dict()
    for i in 1:36
        procids = addprocs([(machine_ids[i % length(machine_ids) + 1], 1)], sshflags=`-vvv -o StrictHostKeyChecking=no -i "home/ischavarry/Dropbox/Prainha/acmust_lamps.pem"`, tunnel=true, exename="/home/ubuntu/julia-1.6.5/bin/julia", exeflags=["--project"], dir="/home/ubuntu/PMParallelRoutine/", max_parallel=100)
        procids = workers()
        @everywhere procids begin
            include("src/PowerModelsParallelRoutine.jl")
        end
        include("script_functions.jl")

        ######### Define PowerModels Parameters ###############
        @everywhere PowerModelsParallelRoutine.NetworkSimulations.PowerModels.silence() 
        
        if i == 3
            lv0_parallel_strategy = build_parallel_strategy(scen = 1) # 1 grupo
            lv1_parallel_strategy = build_parallel_strategy(doy = 12) # (36/12) = 3 grupos
        elseif i == 4
            lv0_parallel_strategy = build_parallel_strategy(scen = 1) # 1 grupo
            lv1_parallel_strategy = build_parallel_strategy(doy = 9) # (36/6) = 4 grupos
        elseif i == 6
            lv0_parallel_strategy = build_parallel_strategy(scen = 1) # 1 grupo
            lv1_parallel_strategy = build_parallel_strategy(doy = 6) # (36/6) 6 grupos
        elseif i == 8
            continue
            # lv0_parallel_strategy = build_parallel_strategy() # 1 grupos
            # lv1_parallel_strategy = build_parallel_strategy(doy = 9, scen = 2) # (36/9 * 4/2) 8 grupos
        elseif i == 9
            lv0_parallel_strategy = build_parallel_strategy(scen = 1) # 1 grupos
            lv1_parallel_strategy = build_parallel_strategy(doy = 4)  # (36/4) = 9 grupos
        elseif i == 12
            lv0_parallel_strategy = build_parallel_strategy(scen = 1) # 1 grupos
            lv1_parallel_strategy = build_parallel_strategy(doy = 3)  # (36/3) = 12 grupos
        elseif i == 16
            continue
            # lv0_parallel_strategy = build_parallel_strategy() # 1 grupos
            # lv1_parallel_strategy = build_parallel_strategy(doy = 9, scen = 1)  # (36/9 * 4/1) = 16 grupos
        elseif i == 18
            lv0_parallel_strategy = build_parallel_strategy(scen = 1) # 1 grupos
            lv1_parallel_strategy = build_parallel_strategy(doy = 2)  # (36/2) = 18 grupos
        elseif i == 24
            continue
            # lv0_parallel_strategy = build_parallel_strategy() # 1 grupos
            # lv1_parallel_strategy = build_parallel_strategy(doy = 3, scen = 2)  # (36/3 * 4/2) = 24 grupos
        elseif i == 36
            lv0_parallel_strategy = build_parallel_strategy(scen = 1) # 1 grupos
            lv1_parallel_strategy = build_parallel_strategy(doy = 1)  # (36/1) = 36 grupos
        elseif i < 36
            continue
        end

        # instance, lv0_parallel_strategy, lv1_parallel_strategy
        study_input_data["parallel_strategy"]["lv0"] = lv0_parallel_strategy
        study_input_data["parallel_strategy"]["lv1"] = lv1_parallel_strategy

        connection_points, all_flowtimes, time = run_test(study_input_data)
        results["$(nworkers())_workers"] = Dict("flow_times" => all_flowtimes, "total_time" => time, "connection_points" => connection_points)

        file_name = "$(study_name)_$i.json"
        PowerModelsParallelRoutine.write_json(file_name, results)
        send_mail(file_name, "Atualização $(study_name): iteração $i")
    end
end

function run_sequential_study(study_name, machine_ids, input_data)
    study_input_data = deepcopy(input_data)
    results = Dict()

    procids = addprocs([(machine_ids[1], 1)], sshflags=`-vvv -i "home/ischavarry/Dropbox/Prainha/acmust_lamps.pem"`, tunnel=true, exename="/home/ubuntu/julia-1.6.5/bin/julia", exeflags=["--project"], dir="/home/ubuntu/PMParallelRoutine/", max_parallel=100)
    procids = workers()
    @everywhere procids begin
        include("src/PowerModelsParallelRoutine.jl")
    end
    include("script_functions.jl")
    @everywhere PowerModelsParallelRoutine.NetworkSimulations.PowerModels.silence() 
    lv0_parallel_strategy = build_parallel_strategy()
    lv1_parallel_strategy = build_parallel_strategy()

    study_input_data["parallel_strategy"]["lv0"] = lv0_parallel_strategy
    study_input_data["parallel_strategy"]["lv1"] = lv1_parallel_strategy

    connection_points, all_flowtimes, time = run_test(study_input_data)
    results["$(nworkers())_workers"] = Dict("flow_times" => all_flowtimes, "total_time" => time, "connection_points" => connection_points)

    file_name = "$(study_name).json"
    PowerModelsParallelRoutine.write_json(file_name, results)
    send_mail(file_name, "Estudo sequencial: $(study_name)")    
end

############################### Quarto teste ###############################

 rmprocs(workers())
input_data = create_input_data("level 4", ts_range=1:24*36, scen_range=1:4)
try
    run_study("Parallel c6i.large", [
        "ubuntu@ec2-3-95-196-126.compute-1.amazonaws.com:22",
        "ubuntu@ec2-54-237-202-131.compute-1.amazonaws.com:22",
        "ubuntu@ec2-54-242-158-218.compute-1.amazonaws.com:22",
        "ubuntu@ec2-54-89-174-124.compute-1.amazonaws.com:22",
        "ubuntu@ec2-54-83-111-245.compute-1.amazonaws.com:22",
        "ubuntu@ec2-54-198-26-77.compute-1.amazonaws.com:22",
        "ubuntu@ec2-54-145-40-187.compute-1.amazonaws.com:22",
        "ubuntu@ec2-54-91-72-198.compute-1.amazonaws.com:22",
        "ubuntu@ec2-54-226-107-115.compute-1.amazonaws.com:22",
        "ubuntu@ec2-23-20-156-5.compute-1.amazonaws.com:22",
        "ubuntu@ec2-3-90-201-104.compute-1.amazonaws.com:22",
        "ubuntu@ec2-54-164-5-149.compute-1.amazonaws.com:22",
        "ubuntu@ec2-3-84-185-146.compute-1.amazonaws.com:22",
        "ubuntu@ec2-75-101-211-0.compute-1.amazonaws.com:22",
        "ubuntu@ec2-52-23-197-69.compute-1.amazonaws.com:22",
        "ubuntu@ec2-34-227-192-72.compute-1.amazonaws.com:22",
        "ubuntu@ec2-54-147-209-218.compute-1.amazonaws.com:22",
        "ubuntu@ec2-54-84-72-53.compute-1.amazonaws.com:22",
        "ubuntu@ec2-54-204-105-86.compute-1.amazonaws.com:22",
        "ubuntu@ec2-54-160-131-158.compute-1.amazonaws.com:22",
        "ubuntu@ec2-107-22-150-92.compute-1.amazonaws.com:22",
        "ubuntu@ec2-54-234-73-236.compute-1.amazonaws.com:22",
        "ubuntu@ec2-18-212-240-124.compute-1.amazonaws.com:22",
        "ubuntu@ec2-34-202-236-201.compute-1.amazonaws.com:22",
        "ubuntu@ec2-18-212-102-125.compute-1.amazonaws.com:22",
        "ubuntu@ec2-54-80-191-25.compute-1.amazonaws.com:22",
        "ubuntu@ec2-18-212-203-120.compute-1.amazonaws.com:22",
        "ubuntu@ec2-3-85-97-221.compute-1.amazonaws.com:22",
        "ubuntu@ec2-34-229-138-202.compute-1.amazonaws.com:22",
        "ubuntu@ec2-52-91-93-149.compute-1.amazonaws.com:22",
        "ubuntu@ec2-54-242-175-174.compute-1.amazonaws.com:22",
        "ubuntu@ec2-54-221-83-45.compute-1.amazonaws.com:22",
        "ubuntu@ec2-54-237-195-143.compute-1.amazonaws.com:22",
        "ubuntu@ec2-75-101-180-231.compute-1.amazonaws.com:22",
        "ubuntu@ec2-54-83-93-101.compute-1.amazonaws.com:22",
        "ubuntu@ec2-54-160-225-163.compute-1.amazonaws.com:22"
    ], input_data)
catch e
    if isdefined(e, :msg)
        return send_mail("Erro durante a execução do estudo Parallel c6i.large", message="Mensagem de erro: $(e.msg)")  
    else
        return send_mail("Erro durante a execução do estudo Parallel c6i.large", message="Não houve mensagem de erro.")  
    end
end
##############################################################################

results_4xlarge = read_json("Parallel c6i.4xlarge_36.json")
results_2xlarge = read_json("Parallel c6i.2xlarge_36.json")
results_xlarge = read_json("Parallel c6i.xlarge_36.json")

I = [3, 4, 6, 9, 12, 18, 36]
times_4xlarge = [results_4xlarge["$(i)_workers"]["total_time"] for i in I]
flow_times_4xlarge = [mean(results_4xlarge["$(i)_workers"]["flow_times"]) for i in I]

times_2xlarge = [results_2xlarge["$(i)_workers"]["total_time"] for i in I]
flow_times_2xlarge = [mean(results_2xlarge["$(i)_workers"]["flow_times"]) for i in I]

times_xlarge = [results_xlarge["$(i)_workers"]["total_time"] for i in I]
flow_times_xlarge = [mean(results_xlarge["$(i)_workers"]["flow_times"]) for i in I]

dict_4xlarge = Dict("times" => times_4xlarge, "flow_times" => flow_times_4xlarge)
dict_2xlarge = Dict("times" => times_2xlarge, "flow_times" => flow_times_2xlarge)
dict_xlarge = Dict("times" => times_xlarge, "flow_times" => flow_times_xlarge)

plot(I, dict_xlarge["times"], title="Tempo de execução (em segundos)", xlabel="Número de workers", label="12 xlarge")
plot!(I, dict_2xlarge["times"], title="Tempo de execução (em segundos)", xlabel="Número de workers", label="6 2xlarge")
plot!(I, dict_4xlarge["times"], title="Tempo de execução (em segundos)", xlabel="Número de workers", label="3 4xlarge")

plot(I, dict_xlarge["flow_times"], title="Tempo médio do fluxo de potência (em segundos)", xlabel="Número de workers", label="12 xlarge", legend=:bottomright)
plot!(I, dict_2xlarge["flow_times"], title="Tempo médio do fluxo de potência (em segundos)", xlabel="Número de workers", label="6 2xlarge")
plot!(I, dict_4xlarge["flow_times"], title="Tempo médio do fluxo de potência (em segundos)", xlabel="Número de workers", label="3 4xlarge")

# using GLM, DataFrames
# data = DataFrame(X=collect(1:16), Y=Float64.(dict["flow_times"]))
# ols = lm(@formula(Y ~ X), data)
# f(x) = GLM.coef(ols)[1] + GLM.coef(ols)[2] * x
# plot!(f)
