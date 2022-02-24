include("src/PowerModelsParallelRoutine.jl")

using Dates, CSV, DataFrames, Statistics
using Distributed

function handle_processes(command, procs)
    if command
        addprocs(procs)
        @everywhere include("src/PowerModelsParallelRoutine.jl")
        return RemoteChannel(()->Channel{Dict}(32));
    end
    return 
end

# Parallel Parameters
parallel        = false
procs           = 5
outputs_channel = handle_processes(parallel, procs)
###########

include("script_functions.jl")

######### Define PowerModels Parameters ###############
@everywhere PowerModelsParallelRoutine.PowerFlowModule.PowerModels.silence() 
                                                      #
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
                                                      #
#                Possible Instances                   #
#                                                     #
# instance = "tutorial"    # scenarios: 2,   years:1, days:1   - total number of power flow = 2*1*1*24     =        48   #
# instance = "level 1"     # scenarios: 2,   years:1, days:2   - total number of power flow = 2*1*2*24     =        96   #
instance = "level 2"     # scenarios: 5,   years:1, days:5   - total number of power flow = 5*1*5*24     =       600   #
# instance = "level 3"     # scenarios: 10,  years:1, days:10  - total number of power flow = 10*1*10*24   =     2.400   #
# instance = "level 4"     # scenarios: 20,  years:1, days:61  - total number of power flow = 20*1*61*24   =    29.280   #
# instance = "level 5"     # scenarios: 50,  years:1, days:181 - total number of power flow = 50*1*181*24  =   210.200   #
# instance = "level 6"     # scenarios: 100, years:1, days:360 - total number of power flow = 100*1*360*24 =   864.000   #
# instance = "final boss"  # scenarios: 200, years:4, days:360 - total number of power flow = 200*4*360*24 = 6.912.000   #
#                                                     #
#######################################################

#_--__--__--__--__--__--__--__--__--__--__--__--__--__--__--__--__--__-#
#                           EXECUTION                                  #
#_--__--__--__--__--__--__--__--__--__--__--__--__--__--__--__--__--__-#

gen_scenarios, load_scenarios, trash = PowerModelsParallelRoutine.read_scenarios(ASPO, instance);
(all_timestamps, all_scenarios_ids, all_years, all_days) = PowerModelsParallelRoutine.case_parameters(gen_scenarios);

dates_dict    = build_dates_dict(all_timestamps)

dates_dict[DateTime("2019-01-02T07:00:00")]

parallel_strategy = build_parallel_strategy(scen = 3, d = true)

tuples          = build_execution_group_tuples(all_timestamps, all_scenarios_ids, parallel_strategy) # escolher a forma de criação dos grupos de execução

lv1_dates      = get_execution_group_dates(dates_dict, tuples[1])

lv1_scenarios  = get_execution_group_scenarios(all_scenarios_ids, tuples[1])


border = read_border_as_matrix(file_border)

networks_info = create_networks_info(ASPO, all_timestamps)

network, result = PowerModelsParallelRoutine.PowerFlowModule.run_model(networks_info["Fora Ponta"]["network"], Dict("1" => pm_ivr))

filter_results = PowerModelsParallelRoutine.create_filter_results(ASPO, network); # 

networks_info["Fora Ponta"]["dates"] = networks_info["Fora Ponta"]["dates"] .|> DateTime

lv0_parallel_strategy = build_parallel_strategy(scen = -1)
lv1_parallel_strategy = build_parallel_strategy(scen = 1)


input_data = Dict(
    "gen_scenarios"     => gen_scenarios,
    "load_scenarios"    => load_scenarios,
    "border"            => border,
    "networks_info"     => networks_info,
    "parallel_strategy" => Dict("lv0"=>lv0_parallel_strategy, "lv1"=>lv1_parallel_strategy),
    "filter_results"    => filter_results,
    "dates"             => all_timestamps,
    "scenarios"         => all_scenarios_ids,
    "model_hierarchy"   => Dict("1" => pm_acr_s, "2"=>pm_ivr_s),
    "parallelize"       => Dict(
        "command"         => parallel,
        "procs"           => 5,
        "outputs_channel" => outputs_channel
    )
)

connection_points = evaluate_pf_scenarios(input_data)

using Distributed

addprocs(5); # add worker processes

@everywhere include("src/PowerModelsParallelRoutine.jl")

@everywhere PowerModelsParallelRoutine.PowerFlowModule.PowerModels.silence() 

const outputs_channel = RemoteChannel(()->Channel{Dict}(32));



time = @elapsed begin
    @sync @distributed for i in 1:5
        @info("Worker $(myid()) receive task $i")
        @async execute_pf(execution_groups[map_egs[i]], outputs_channel)
    end

    retrive_outputs!(outputs_channel, connection_points, 5)
end

connection_points

execute_pf(inputs, outputs_channel)


addprocs(2); # add worker processes

@everywhere a(i) = i
b(i) = 2
@sync @distributed for i in b.(1:10)

    put!(ch, a(i))
end

n = 0
while n != 10
    r = take!(ch)
    @show r
    n += 1
end