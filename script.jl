include("src/PowerModelsParallelRoutine.jl")
using Dates, CSV, DataFrames, Statistics
using Distributed

# procids = addprocs([("ubuntu@ec2-3-95-62-135.compute-1.amazonaws.com:22", 5), ("ubuntu@ec2-54-196-149-95.compute-1.amazonaws.com:22", 5)], sshflags=`-vvv -o StrictHostKeyChecking=no -i "~/Dropbox/Prainha/acmust_lamps.pem"`, tunnel=true, exename="julia-1.6.5/bin/julia", dir="/home/ubuntu")
# procids = addprocs([("ubuntu@ec2-54-242-126-173.compute-1.amazonaws.com:22", 5), ("ubuntu@ec2-52-91-97-87.compute-1.amazonaws.com:22", 5)], sshflags=`-vvv -i /Users/pedroferraz/Desktop/acmust_lamps.pem`, tunnel=true, exename="julia-1.6.5/bin/julia", dir="/home/ubuntu")
# ssh -i /Users/pedroferraz/Desktop/acmust_lamps.pem ubuntu@ec2-23-22-156-46.compute-1.amazonaws.com
# ssh -i /Users/pedroferraz/Desktop/acmust_lamps.pem ubuntu@ec2-54-196-149-95.compute-1.amazonaws.com

# @everywhere procids begin
#     using Pkg
#     cd("PMParallelRoutine")
#     Pkg.activate(".")
#     Pkg.instantiate()
# end

# @everywhere procids begin
#     include("src/PowerModelsParallelRoutine.jl")
# end

# Parallel Parameters
parallel        = false
procs           = 3
CHANNEL = RemoteChannel(()->Channel{Vector{Float64}}(Inf));
###########

function run_test(instance, lv0_parallel_strategy, lv1_parallel_strategy)
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
    (all_timestamps, all_scenarios_ids, all_years, all_days) = PowerModelsParallelRoutine.case_parameters(gen_scenarios);

    dates_dict    = build_dates_dict(all_timestamps)

    border = read_border_as_matrix(file_border)

    networks_info = create_networks_info(ASPO, all_timestamps, pm_ivr)

    network = networks_info["Fora Ponta"]["network"]

    filter_results = PowerModelsParallelRoutine.create_filter_results(ASPO, network); # 

    networks_info["Fora Ponta"]["dates"] = networks_info["Fora Ponta"]["dates"] .|> DateTime

    model_hierarchy = Dict("1" => pm_acr_s)
    model_hierarchy["1"]["build_model"] = PowerModelsParallelRoutine.NetworkSimulations.build_pf_plf_instantiate

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

    (connection_points, all_flowtimes), time = @timed evaluate_pf_scenarios(input_data)
    return connection_points, all_flowtimes, time
end

#                Possible Instances                   #
#                                                     #
instance = "tutorial"    # scenarios: 2,   years:1, days:1   - total number of power flow = 2*1*1*24     =        48   #
# instance = "level 1"     # scenarios: 2,   years:1, days:2   - total number of power flow = 2*1*2*24     =        96   #
# instance = "level 2"     # scenarios: 5,   years:1, days:5   - total number of power flow = 5*1*5*24     =       600   #
# instance = "level 3"     # scenarios: 10,  years:1, days:10  - total number of power flow = 10*1*10*24   =     2.400   #
# instance = "level 4"     # scenarios: 20,  years:1, days:61  - total number of power flow = 20*1*61*24   =    29.280   #
# instance = "level 5"     # scenarios: 50,  years:1, days:181 - total number of power flow = 50*1*181*24  =   210.200   #
# instance = "level 6"     # scenarios: 100, years:1, days:360 - total number of power flow = 100*1*360*24 =   864.000   #
# instance = "final boss"  # scenarios: 200, years:4, days:360 - total number of power flow = 200*4*360*24 = 6.912.000   #
#                                                     #
#######################################################

include("script_functions.jl")
PowerModelsParallelRoutine.NetworkSimulations.PowerModels.silence()
lv0_parallel_strategy = build_parallel_strategy() # 1 grupo
lv1_parallel_strategy = build_parallel_strategy() # 1 grupo 
connection_points, all_flowtimes, time = run_test(instance, lv0_parallel_strategy, lv1_parallel_strategy)

# results = Dict()
# for i in 1:16
#     addprocs(1)
#     include("script_functions.jl")
#     procids = workers()
#     @everywhere procids begin
#         using Pkg
#         # cd("PMParallelRoutine")
#         Pkg.activate(".")
#         Pkg.instantiate()
#     end

#     @everywhere procids begin
#         include("src/PowerModelsParallelRoutine.jl")
#     end

#     ######### Define PowerModels Parameters ###############
#     @everywhere PowerModelsParallelRoutine.NetworkSimulations.PowerModels.silence() 
           
#     if i == 1
#         lv0_parallel_strategy = build_parallel_strategy() # 1 grupo
#         lv1_parallel_strategy = build_parallel_strategy() # 1 grupo 
#     elseif i == 2
#         lv0_parallel_strategy = build_parallel_strategy() # 1 grupo
#         lv1_parallel_strategy = build_parallel_strategy(h = 12) # (24/12) = 2 grupos
#     elseif i == 3
#         lv0_parallel_strategy = build_parallel_strategy() # 1 grupo
#         lv1_parallel_strategy = build_parallel_strategy(h = 8) # (24/8) = 3 grupos
#     elseif i == 4
#         lv0_parallel_strategy = build_parallel_strategy() # 1 grupo
#         lv1_parallel_strategy = build_parallel_strategy(h = 6) # (24/6) = 4 grupos
#     elseif i == 5
#         lv0_parallel_strategy = build_parallel_strategy() # 1 grupo
#         lv1_parallel_strategy = build_parallel_strategy(scen = 1) # (5/1) = 5 grupos
#     elseif i == 6
#         lv0_parallel_strategy = build_parallel_strategy() # 1 grupo
#         lv1_parallel_strategy = build_parallel_strategy(h = 4) # (24/4) 6 grupos
#     elseif i == 7
#         lv0_parallel_strategy = build_parallel_strategy() # 1 grupos
#         lv1_parallel_strategy = build_parallel_strategy(h = 4) # (24/4) 6 grupos
#     elseif i == 8
#         lv0_parallel_strategy = build_parallel_strategy() # 1 grupos
#         lv1_parallel_strategy = build_parallel_strategy(h = 3, doy = 3) # (24/3) 8 grupos
#     elseif i == 9
#         lv0_parallel_strategy = build_parallel_strategy() # 1 grupos
#         lv1_parallel_strategy = build_parallel_strategy(scen = 2, doy = 2)  # (5/2) * (5/2) = 3*3 = 9 grupos
#     elseif i == 10
#         lv0_parallel_strategy = build_parallel_strategy() # 1 grupos
#         lv1_parallel_strategy = build_parallel_strategy(scen = 1, h = 12) # (5/1) * (24/12) = 5*2 = 10 grupos
#     elseif i == 11
#         lv0_parallel_strategy = build_parallel_strategy() # 1 grupo
#         lv1_parallel_strategy = build_parallel_strategy(scen = 1, h = 12) # (5/1) * (24/12) = 5*2 = 10 grupos
#     elseif i == 12
#         lv0_parallel_strategy = build_parallel_strategy() # 1 grupos
#         lv1_parallel_strategy = build_parallel_strategy(scen = 3, h = 4)  # (5/3) * (24/4) = 2*6 = 12 grupos
#     elseif i == 13
#         lv0_parallel_strategy = build_parallel_strategy() # 1 grupos
#         lv1_parallel_strategy = build_parallel_strategy(scen = 3, h = 4)  # (5/3) * (24/4) = 2*6 = 12 grupos
#     elseif i == 14
#         lv0_parallel_strategy = build_parallel_strategy() # 1 grupos
#         lv1_parallel_strategy = build_parallel_strategy(scen = 3, h = 4)  # (5/3) * (24/4) = 2*6 = 12 grupos
#     elseif i == 15
#         lv0_parallel_strategy = build_parallel_strategy() # 1 grupos
#         lv1_parallel_strategy = build_parallel_strategy(scen = 1, h = 8)  # (5/1) * (24/3) = 5*3 = 15 grupos
#     elseif i == 16
#         lv0_parallel_strategy = build_parallel_strategy() # 1 grupos
#         lv1_parallel_strategy = build_parallel_strategy(scen = 3, h = 3)  # (5/3) * (24/3) = 2*8 = 16 grupos
#     end

#     connection_points, all_flowtimes, time = run_test(instance, lv0_parallel_strategy, lv1_parallel_strategy)
#     results["$(nworkers())_workers"] = Dict("flow_times" => all_flowtimes, "total_time" => time)
# end

# times = [results["$(i)_workers"]["total_time"] for i in 1:16]
# flow_times = [mean(results["$(i)_workers"]["flow_times"]) for i in 1:16]

# dict = Dict("times" => times, "flow_times" => flow_times)

# dict = read_json("results.json")

# plot(dict["times"], title="Tempo de execução (em segundos)", xlabel="Número de workers", legend=false)
# plot(dict["flow_times"], title="Tempo médio do fluxo de potência (em segundos)", xlabel="Número de workers", legend=false)

# using GLM, DataFrames
# data = DataFrame(X=collect(1:16), Y=Float64.(dict["flow_times"]))
# ols = lm(@formula(Y ~ X), data)
# f(x) = GLM.coef(ols)[1] + GLM.coef(ols)[2] * x
# plot!(f)
