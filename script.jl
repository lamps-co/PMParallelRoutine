include("src/PowerModelsParallelRoutine.jl")

using Dates, CSV, DataFrames, Statistics, JSON
using Distributed
using SMTPClient

# procids = addprocs([("ubuntu@ec2-174-129-50-22.compute-1.amazonaws.com:22", 1)], sshflags=`-vvv -o StrictHostKeyChecking=no -i "/Users/pedroferraz/Desktop/acmust_lamps.pem"`, tunnel=true, exename="/home/ubuntu/julia-1.6.5/bin/julia", exeflags=["--project"], dir="/home/ubuntu/PMParallelRoutine/", max_parallel=100)
# ssh -i /Users/pedroferraz/Desktop/acmust_lamps.pem ubuntu@ec2-54-227-9-195.compute-1.amazonaws.com
# scp /Users/pedroferraz/Desktop/acmust_lamps.pem ubuntu@ec2-54-227-9-195.compute-1.amazonaws.com:~/acmust_lamps.pem

# addprocs([("ubuntu@ec2-3-95-196-126.compute-1.amazonaws.com:22", 1)], sshflags=`-vvv -o StrictHostKeyChecking=no -i "/Users/pedroferraz/Desktop/acmust_lamps.pem"`, tunnel=true, exename="/home/ubuntu/julia-1.6.5/bin/julia", exeflags=["--project"], dir="/home/ubuntu/PMParallelRoutine/", max_parallel=100)

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
    (connection_points, all_flowtimes, data_movement_processing_overhead_dict), time = @timed evaluate_pf_scenarios(input_data)
    return connection_points, all_flowtimes, data_movement_processing_overhead_dict, time
end

function run_study(study_name, machine_ids, input_data)
    study_input_data = deepcopy(input_data)

    results = Dict()
    for i in 1:36
        procids = addprocs([(machine_ids[i % length(machine_ids) + 1], 1)], sshflags=`-vvv -o StrictHostKeyChecking=no -i "~/acmust_lamps.pem"`, tunnel=true, exename="/home/ubuntu/julia-1.6.5/bin/julia", exeflags=["--project"], dir="/home/ubuntu/PMParallelRoutine/", max_parallel=100)
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
            lv0_parallel_strategy = build_parallel_strategy(scen = -1) # 1 grupos
            lv1_parallel_strategy = build_parallel_strategy(doy = 1)  # (36/1) = 36 grupos
        elseif i < 36
            continue
        end

        # instance, lv0_parallel_strategy, lv1_parallel_strategy
        study_input_data["parallel_strategy"]["lv0"] = lv0_parallel_strategy
        study_input_data["parallel_strategy"]["lv1"] = lv1_parallel_strategy

        connection_points, all_flowtimes, data_movement_processing_overhead_dict, time = run_test(study_input_data)
        results["$(nworkers())_workers"] = Dict("flow_times" => all_flowtimes, "data_movement_processing_overhead" => data_movement_processing_overhead_dict, "total_time" => time, "connection_points" => connection_points)

        file_name = "$(study_name)_$i.json"
        PowerModelsParallelRoutine.write_json(file_name, results)
        # send_mail(file_name, "Atualização $(study_name): iteração $i")
    end
end

function run_sequential_study(study_name, machine_ids, input_data)
    study_input_data = deepcopy(input_data)
    results = Dict()

    procids = addprocs([(machine_ids[1], 1)], sshflags=`-vvv -i "/Users/pedroferraz/Desktop/acmust_lamps.pem"`, tunnel=true, exename="/home/ubuntu/julia-1.6.5/bin/julia", exeflags=["--project"], dir="/home/ubuntu/PMParallelRoutine/", max_parallel=100)
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

############################### Quinto teste ###############################
input_data = create_input_data("tutorial")
# run_sequential_study("Sequencial c6i.large", ["ubuntu@ec2-3-95-196-126.compute-1.amazonaws.com:22"], input_data)
# rmprocs(workers())

# input_data = create_input_data("level 4", ts_range=1:24*36, scen_range=1:4)
input_data = create_input_data("tutorial")
lv0_parallel_strategy = build_parallel_strategy(scen = 1) # 2 grupos
lv1_parallel_strategy = build_parallel_strategy(h = 1)  # (61/31) = 2 grupos
input_data["parallel_strategy"]["lv0"] = lv0_parallel_strategy
input_data["parallel_strategy"]["lv1"] = lv1_parallel_strategy

results = evaluate_pf_scenarios(input_data)

results[3]["time_matrices"][2]

try
    run_study("Parallel c6i.large", [
        "ubuntu@ec2-54-234-199-141.compute-1.amazonaws.com:22",
        "ubuntu@ec2-34-229-217-17.compute-1.amazonaws.com:22",
        "ubuntu@ec2-54-208-207-72.compute-1.amazonaws.com:22",
        "ubuntu@ec2-54-196-246-190.compute-1.amazonaws.com:22",
        "ubuntu@ec2-52-201-255-45.compute-1.amazonaws.com:22",
        "ubuntu@ec2-54-145-244-135.compute-1.amazonaws.com:22",
        "ubuntu@ec2-54-82-62-167.compute-1.amazonaws.com:22",
        "ubuntu@ec2-54-165-99-115.compute-1.amazonaws.com:22",
        "ubuntu@ec2-54-227-182-148.compute-1.amazonaws.com:22",
        "ubuntu@ec2-54-209-195-91.compute-1.amazonaws.com:22",
        "ubuntu@ec2-100-26-22-169.compute-1.amazonaws.com:22",
        "ubuntu@ec2-54-91-32-247.compute-1.amazonaws.com:22",
        "ubuntu@ec2-107-20-73-32.compute-1.amazonaws.com:22",
        "ubuntu@ec2-184-73-135-210.compute-1.amazonaws.com:22",
        "ubuntu@ec2-54-166-67-18.compute-1.amazonaws.com:22",
        "ubuntu@ec2-3-90-225-249.compute-1.amazonaws.com:22",
        "ubuntu@ec2-18-215-174-69.compute-1.amazonaws.com:22",
        "ubuntu@ec2-54-208-3-4.compute-1.amazonaws.com:22",
        "ubuntu@ec2-18-209-70-162.compute-1.amazonaws.com:22",
        "ubuntu@ec2-54-146-31-16.compute-1.amazonaws.com:22",
        "ubuntu@ec2-18-207-123-78.compute-1.amazonaws.com:22",
        "ubuntu@ec2-54-221-147-33.compute-1.amazonaws.com:22",
        "ubuntu@ec2-52-91-243-6.compute-1.amazonaws.com:22",
        "ubuntu@ec2-54-236-95-97.compute-1.amazonaws.com:22",
        "ubuntu@ec2-3-208-13-107.compute-1.amazonaws.com:22",
        "ubuntu@ec2-107-22-37-145.compute-1.amazonaws.com:22",
        "ubuntu@ec2-3-87-238-6.compute-1.amazonaws.com:22",
        "ubuntu@ec2-54-159-15-236.compute-1.amazonaws.com:22",
        "ubuntu@ec2-34-227-71-192.compute-1.amazonaws.com:22",
        "ubuntu@ec2-54-146-205-98.compute-1.amazonaws.com:22",
        "ubuntu@ec2-54-196-170-227.compute-1.amazonaws.com:22",
        "ubuntu@ec2-34-203-234-29.compute-1.amazonaws.com:22",
        "ubuntu@ec2-54-234-127-179.compute-1.amazonaws.com:22",
        "ubuntu@ec2-3-88-184-53.compute-1.amazonaws.com:22",
        "ubuntu@ec2-3-85-112-224.compute-1.amazonaws.com:22",
        "ubuntu@ec2-54-87-118-119.compute-1.amazonaws.com:22"
    ], input_data)
catch e
    if isdefined(e, :msg)
        return send_mail("Erro durante a execução do estudo Parallel c6i.large", message="Mensagem de erro: $(e.msg)")  
    else
        return send_mail("Erro durante a execução do estudo Parallel c6i.large", message="Não houve mensagem de erro.")  
    end
end
##############################################################################

using JSON, StatsBase, Plots, Plots.PlotMeasures, StatsPlots
read_json(file::String) = JSON.parse(String(read(file)))

results_4xlarge = read_json("Parallel c6i.4xlarge_36.json")
results_2xlarge = read_json("Parallel c6i.2xlarge_36.json")
results_xlarge = read_json("Parallel c6i.xlarge_36.json")
results_large = read_json("Parallel c6i.large_36.json")
results_large2 = read_json("Parallel c6i.large_36_new.json")

# seq_results_4xlarge = read_json("Sequencial c6i.4xlarge.json")
# seq_results_2xlarge = read_json("Sequencial c6i.2xlarge.json")
# seq_results_xlarge = read_json("Sequencial c6i.xlarge.json")
# seq_results_large = read_json("Sequencial c6i.large.json")

F = 24*36*4
I = [3, 4, 6, 9, 12, 18, 36]
times_4xlarge = [results_4xlarge["$(i)_workers"]["total_time"] for i in I]
flow_times_4xlarge = [mean(results_4xlarge["$(i)_workers"]["flow_times"]) for i in I]

times_2xlarge = [results_2xlarge["$(i)_workers"]["total_time"] for i in I]
flow_times_2xlarge = [mean(results_2xlarge["$(i)_workers"]["flow_times"]) for i in I]

times_xlarge = [results_xlarge["$(i)_workers"]["total_time"] for i in I]
flow_times_xlarge = [mean(results_xlarge["$(i)_workers"]["flow_times"]) for i in I]

times_large = [results_large["$(i)_workers"]["total_time"] for i in I]
flow_times_large = [mean(results_large["$(i)_workers"]["flow_times"]) for i in I]

times_large2 = [results_large2["$(i)_workers"]["total_time"] for i in I]
flow_times_large2 = [mean(results_large2["$(i)_workers"]["flow_times"]) for i in I]

dict_4xlarge = Dict("times" => times_4xlarge, "flow_times" => flow_times_4xlarge)
dict_2xlarge = Dict("times" => times_2xlarge, "flow_times" => flow_times_2xlarge)
dict_xlarge = Dict("times" => times_xlarge, "flow_times" => flow_times_xlarge)
dict_large = Dict("times" => times_large, "flow_times" => flow_times_large)
dict_large2 = Dict("times" => times_large2, "flow_times" => flow_times_large2)

# speedup_xlarge = F * mean(seq_results_xlarge["1_workers"]["flow_times"]) ./ dict_xlarge["times"]
# speedup_2xlarge = F * mean(seq_results_2xlarge["1_workers"]["flow_times"]) ./ dict_2xlarge["times"]
# speedup_4xlarge = F * mean(seq_results_4xlarge["1_workers"]["flow_times"]) ./ dict_4xlarge["times"]

# I = [3, 4, 6, 9, 12, 18, 36]
# plt = plot(I, speedup_xlarge[1:length(I)], title="Speedup", xlabel="Number of workers", label="12 x 4vCPU", linewidth=2, size=(1000, 600), legend=:topleft, legendfontsize=20, xtickfontsize = 20, ytickfontsize = 20, titlefontsize = 20, labelfontsize=20, left_margin = 5mm, bottom_margin=6mm, xticks=I)
# plot!(I, speedup_2xlarge[1:length(I)], xlabel="Number of workers", label="6 x 8vCPU", linewidth=2)
# plot!(I, speedup_4xlarge[1:length(I)], xlabel="Number of workers", label="3 x 16vCPU", linewidth=2)
# scatter!(I, speedup_xlarge[1:length(I)], label="", color=1)
# scatter!(I, speedup_2xlarge[1:length(I)], label="", color=2)
# scatter!(I, speedup_4xlarge[1:length(I)], label="", color=3)
# f(x) = x
# plot!(f, linewidth=2, color=4, label="Ideal")
# savefig(plt, "plots/speedup_36.png")

# plt = plot(I, dict_large["times"], title="Execution time (in seconds)", xlabel="Number of workers",    label="36 x 2vCPU")
plot(I, dict_xlarge["times"], title="Execution time (in seconds)", xlabel="Number of workers", label="12 x 4vCPU", linewidth=2, size=(1000, 600), legendfontsize=20, xtickfontsize = 20, ytickfontsize = 20, titlefontsize = 20, labelfontsize=20, left_margin = 5mm, bottom_margin=6mm, xticks=I)
plot!(I, dict_2xlarge["times"], xlabel="Number of workers", label="6 x 8vCPU", linewidth=2)
plot!(I, dict_4xlarge["times"], xlabel="Number of workers", label="3 x 16vCPU", linewidth=2)
plot!(I, dict_large2["times"], label="36 x 2vCPU (new)", linewidth=2)
scatter!(I, dict_xlarge["times"], label="", color=1)
scatter!(I, dict_2xlarge["times"], label="", color=2)
scatter!(I, dict_4xlarge["times"], label="", color=3)
scatter!(I, dict_large2["times"], label="", color=4)
savefig(plt, "plots/execution_time_new.png")

plt = plot(I, dict_xlarge["flow_times"], label="12 x 4vCPU",  linewidth=2, color=1, title="Mean power flow execution time (in seconds)", xlabel="Number of workers", legend=:topleft, size=(1000, 600), legendfontsize=20, xtickfontsize = 20, ytickfontsize = 20, titlefontsize = 20, labelfontsize=20, left_margin = 5mm, bottom_margin=6mm, xticks=I)
plot!(I, dict_2xlarge["flow_times"], label="6 x 8vCPU", linewidth=2, color=2)
plot!(I, dict_4xlarge["flow_times"], label="3 x 16vCPU", linewidth=2, color=3)
plot!(I, dict_large["flow_times"], label="36 x 2vCPU", linewidth=2, color=4)
plot!(I, dict_large2["flow_times"], label="36 x 2vCPU (new)", linewidth=2, color=5)
scatter!(I, dict_xlarge["flow_times"], label="", color=1)
scatter!(I, dict_4xlarge["flow_times"], label="", color=3)
scatter!(I, dict_2xlarge["flow_times"], label="", color=2)
scatter!(I, dict_large["flow_times"], label="", color=4)
scatter!(I, dict_large2["flow_times"], label="", color=5)
savefig(plt, "plots/flow_times_new.png")

# plt = plot(I,    [dict_xlarge["flow_times"][i]  / w for (i, w) in enumerate(I)], label="12 x 4vCPU", linewidth=2, color=1, title="Equivalent sequential power flow execution time (in seconds)", xlabel="Number of workers", legend=:topright, size=(1000, 600), legendfontsize=20, xtickfontsize = 20, ytickfontsize = 20, titlefontsize = 20, labelfontsize=20, left_margin = 5mm, bottom_margin=6mm, xticks=I)
# plot!(I,    [dict_2xlarge["flow_times"][i] / w for (i, w) in enumerate(I)], label="6 x 8vCPU", linewidth=2, color=2)
# plot!(I,    [dict_4xlarge["flow_times"][i] / w for (i, w) in enumerate(I)], label="3 x 16vCPU", linewidth=2, color=3)
# plot!( I,    [dict_large["flow_times"][i]   / w for (i, w) in enumerate(I)], label="36 x 2vCPU", linewidth=2, color=4)
# scatter!(I, [dict_xlarge["flow_times"][i]  / w for (i, w) in enumerate(I)], label="", color=1)
# scatter!(I, [dict_2xlarge["flow_times"][i] / w for (i, w) in enumerate(I)], label="", color=2)
# scatter!(I, [dict_4xlarge["flow_times"][i] / w for (i, w) in enumerate(I)], label="", color=3)
# scatter!(I, [dict_large["flow_times"][i]   / w for (i, w) in enumerate(I)], label="", color=4)
# savefig(plt, "plots/equivalent_sequential_time_2.png")

plt = plot(I,  (dict_xlarge["times"]) .- sum(dict_xlarge["flow_times"]), title="Data movement, processing and overhead (in seconds)", linewidth=2, xlabel="Number of workers", label="12 x 4vCPU", legend=:topright, size=(1000, 600), legendfontsize=20, xtickfontsize = 20, ytickfontsize = 20, titlefontsize = 20, labelfontsize=20, left_margin = 5mm, bottom_margin=6mm, xticks=I)
plot!(I, (dict_2xlarge["times"]) .- sum(dict_2xlarge["flow_times"]), linewidth=2, label="6 x 8vCPU", legend=:bottomright)
plot!(I, (dict_4xlarge["times"]) .- sum(dict_4xlarge["flow_times"]), linewidth=2, label="3 x 16vCPU")
plot!(I, (dict_large2["times"]) .- sum(dict_large2["flow_times"]), linewidth=2, label="36 x 2vCPU", legend=:outerright)
savefig(plt, "plots/data_movement_processing_and_overhead_time_new2.png")

plt = plot(I, [dict_xlarge["flow_times"][i]  / w for (i, w) in enumerate(I)], label="Power flow", linewidth=2, color=1, title="Time spent - 12 x 4vCPU", xlabel="Number of workers", legend=:topright, size=(1000, 600), legendfontsize=20, xtickfontsize = 20, ytickfontsize = 20, titlefontsize = 20, labelfontsize=20, left_margin = 5mm, bottom_margin=6mm, xticks=I)
plot!(I, (dict_xlarge["times"] / F) .- ([dict_xlarge["flow_times"][i]  / w for (i, w) in enumerate(I)]), linewidth=2, xlabel="Number of workers", label="Data movement", legend=:topright, size=(1000, 600), legendfontsize=20, xtickfontsize = 20, ytickfontsize = 20, titlefontsize = 20, labelfontsize=20, left_margin = 5mm, bottom_margin=6mm, xticks=I)
plot!(I, (dict_xlarge["times"] / F), linewidth=2, xlabel="Number of workers", label="Total time", legend=:topright, size=(1000, 600), legendfontsize=20, xtickfontsize = 20, ytickfontsize = 20, titlefontsize = 20, labelfontsize=20, left_margin = 5mm, bottom_margin=6mm, xticks=I)
scatter!(I, [dict_xlarge["flow_times"][i]  / w for (i, w) in enumerate(I)], label="", color=1)
scatter!(I, (dict_xlarge["times"] / F) .- ([dict_xlarge["flow_times"][i]  / w for (i, w) in enumerate(I)]), label="", color=2)
scatter!(I, (dict_xlarge["times"] / F), label="", color=3)
savefig(plt, "plots/power_flow_vs_data_movement1.png")

plt = plot(I, [dict_2xlarge["flow_times"][i]  / w for (i, w) in enumerate(I)], label="Power flow", linewidth=2, color=1, title="Time spent - 6 x 8vCPU", xlabel="Number of workers", legend=:topright, size=(1000, 600), legendfontsize=20, xtickfontsize = 20, ytickfontsize = 20, titlefontsize = 20, labelfontsize=20, left_margin = 5mm, bottom_margin=6mm, xticks=I)
plot!(I, (dict_2xlarge["times"] / F) .- ([dict_2xlarge["flow_times"][i]  / w for (i, w) in enumerate(I)]), linewidth=2, xlabel="Number of workers", label="Data movement", legend=:topright, size=(1000, 600), legendfontsize=20, xtickfontsize = 20, ytickfontsize = 20, titlefontsize = 20, labelfontsize=20, left_margin = 5mm, bottom_margin=6mm, xticks=I)
plot!(I, (dict_2xlarge["times"] / F), linewidth=2, xlabel="Number of workers", label="Total time", legend=:topright, size=(1000, 600), legendfontsize=20, xtickfontsize = 20, ytickfontsize = 20, titlefontsize = 20, labelfontsize=20, left_margin = 5mm, bottom_margin=6mm, xticks=I)
scatter!(I, [dict_2xlarge["flow_times"][i]  / w for (i, w) in enumerate(I)], label="", color=1)
scatter!(I, (dict_2xlarge["times"] / F) .- ([dict_2xlarge["flow_times"][i]  / w for (i, w) in enumerate(I)]), label="", color=2)
scatter!(I, (dict_2xlarge["times"] / F), label="", color=3)
savefig(plt, "plots/power_flow_vs_data_movement2.png")

plt = plot(I, [dict_4xlarge["flow_times"][i]  / w for (i, w) in enumerate(I)], label="Power flow", linewidth=2, color=1, title="Time spent - 3 x 16vCPU", xlabel="Number of workers", legend=:topright, size=(1000, 600), legendfontsize=20, xtickfontsize = 20, ytickfontsize = 20, titlefontsize = 20, labelfontsize=20, left_margin = 5mm, bottom_margin=6mm, xticks=I)
plot!(I, (dict_4xlarge["times"] / F) .- ([dict_4xlarge["flow_times"][i]  / w for (i, w) in enumerate(I)]), linewidth=2, xlabel="Number of workers", label="Data movement", legend=:topright, size=(1000, 600), legendfontsize=20, xtickfontsize = 20, ytickfontsize = 20, titlefontsize = 20, labelfontsize=20, left_margin = 5mm, bottom_margin=6mm, xticks=I)
plot!(I, (dict_4xlarge["times"] / F), linewidth=2, xlabel="Number of workers", label="Total time", legend=:topright, size=(1000, 600), legendfontsize=20, xtickfontsize = 20, ytickfontsize = 20, titlefontsize = 20, labelfontsize=20, left_margin = 5mm, bottom_margin=6mm, xticks=I)
scatter!(I, [dict_4xlarge["flow_times"][i]  / w for (i, w) in enumerate(I)], label="", color=1)
scatter!(I, (dict_4xlarge["times"] / F) .- ([dict_4xlarge["flow_times"][i]  / w for (i, w) in enumerate(I)]), label="", color=2)
scatter!(I, (dict_4xlarge["times"] / F), label="", color=3)
savefig(plt, "plots/power_flow_vs_data_movement3.png")

plt = plot(I, [dict_large2["flow_times"][i]  / w for (i, w) in enumerate(I)], label="Power flow", linewidth=2, color=1, title="Time spent - 36 x 2vCPU", xlabel="Number of workers", legend=:topright, size=(1000, 600), legendfontsize=20, xtickfontsize = 20, ytickfontsize = 20, titlefontsize = 20, labelfontsize=20, left_margin = 5mm, bottom_margin=6mm, xticks=I)
plot!(I, (dict_large2["times"] / F) .- ([dict_large2["flow_times"][i]  / w for (i, w) in enumerate(I)]), linewidth=2, xlabel="Number of workers", label="Data movement", legend=:topright, size=(1000, 600), legendfontsize=20, xtickfontsize = 20, ytickfontsize = 20, titlefontsize = 20, labelfontsize=20, left_margin = 5mm, bottom_margin=6mm, xticks=I)
plot!(I, (dict_large2["times"] / F), linewidth=2, xlabel="Number of workers", label="Total time", legend=:topright, size=(1000, 600), legendfontsize=20, xtickfontsize = 20, ytickfontsize = 20, titlefontsize = 20, labelfontsize=20, left_margin = 5mm, bottom_margin=6mm, xticks=I)
scatter!(I, [dict_large2["flow_times"][i]  / w for (i, w) in enumerate(I)], label="", color=1)
scatter!(I, (dict_large2["times"] / F) .- ([dict_large2["flow_times"][i]  / w for (i, w) in enumerate(I)]), label="", color=2)
scatter!(I, (dict_large2["times"] / F), label="", color=3)
savefig(plt, "plots/power_flow_vs_data_movement4.png")

p1_xlarge = ([dict_xlarge["flow_times"][i]  / w for (i, w) in enumerate(I)]) ./ (dict_xlarge["times"] / F)
p2_xlarge = 1 .- p1_xlarge
p1_2xlarge = ([dict_2xlarge["flow_times"][i]  / w for (i, w) in enumerate(I)]) ./ (dict_2xlarge["times"] / F)
p2_2xlarge = 1 .- p1_2xlarge
p1_4xlarge = ([dict_4xlarge["flow_times"][i]  / w for (i, w) in enumerate(I)]) ./ (dict_4xlarge["times"] / F)
p2_4xlarge = 1 .- p1_4xlarge
p1_large2 = ([dict_large2["flow_times"][i]  / w for (i, w) in enumerate(I)]) ./ (dict_large2["times"] / F)
p2_large2 = 1 .- p1_large2
plt = groupedbar(I, hcat(p1_xlarge, p2_xlarge), bar_position=:stack, xlabel="Number of workers", title="Proportion of execution time - 12 x 4vCPU", label=["Power flow" "Data movement"], bar_width=1, legend=:outertop, size=(1000, 600), legendfontsize=20, xtickfontsize = 20, ytickfontsize = 20, titlefontsize = 20, labelfontsize=20, left_margin = 5mm, bottom_margin=6mm, xticks=I)
savefig(plt, "plots/proportion_time_1.png")

plt = groupedbar(I, hcat(p1_2xlarge, p2_2xlarge), bar_position=:stack, xlabel="Number of workers", title="Proportion of execution time - 6 x 8vCPU", label=["Power flow" "Data movement"], bar_width=1, legend=:outertop, size=(1000, 600), legendfontsize=20, xtickfontsize = 20, ytickfontsize = 20, titlefontsize = 20, labelfontsize=20, left_margin = 5mm, bottom_margin=6mm, xticks=I)
savefig(plt, "plots/proportion_time_2.png")

plt = groupedbar(I, hcat(p1_4xlarge, p2_4xlarge), bar_position=:stack, xlabel="Number of workers", title="Proportion of execution time - 3 x 16vCPU", label=["Power flow" "Data movement"], bar_width=1, legend=:outertop, size=(1000, 600), legendfontsize=20, xtickfontsize = 20, ytickfontsize = 20, titlefontsize = 20, labelfontsize=20, left_margin = 5mm, bottom_margin=6mm, xticks=I)
savefig(plt, "plots/proportion_time_3.png")

plt = groupedbar(I, hcat(p1_large2, p2_large2), bar_position=:stack, xlabel="Number of workers", title="Proportion of execution time - 36 x 2vCPU", label=["Power flow" "Data movement"], bar_width=1, legend=:outertop, size=(1000, 600), legendfontsize=20, xtickfontsize = 20, ytickfontsize = 20, titlefontsize = 20, labelfontsize=20, left_margin = 5mm, bottom_margin=6mm, xticks=I)
savefig(plt, "plots/proportion_time_4.png")


# using GLM, DataFrames
# data = DataFrame(X=collect(1:16), Y=Float64.(dict["flow_times"]))
# ols = lm(@formula(Y ~ X), data)
# f(x) = GLM.coef(ols)[1] + GLM.coef(ols)[2] * x
# plot!(f)
