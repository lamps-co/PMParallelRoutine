include("src/PowerModelsParallelRoutine.jl")

using Dates, CSV, DataFrames, Statistics

######### Define PowerModels Parameters ###############
PowerModelsParallelRoutine.PowerModels.silence()      #
pm_ivr = PowerModelsParallelRoutine.pm_ivr_parameters #
pm_acr = PowerModelsParallelRoutine.pm_acr_parameters #
#######################################################

#######################################################
#                Define ASPO, CASE                    #
                                                      #
ASPO = "EMS"                                          #
CASE = "FP"                                           #
                                                      #
#                Possible Instances                   #
#                                                     #
instance = "tutorial"    # scenarios: 2,   years:1, days:1     - total number of power flow = 2*1*1*24     =        48   #
# instance = "level 1"     # scenarios: 2,   years:1, days:2   - total number of power flow = 2*1*2*24     =        96   #
# instance = "level 2"     # scenarios: 5,   years:1, days:5   - total number of power flow = 5*1*5*24     =       600   #
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


network = PowerModelsParallelRoutine.read_and_converge_network(ASPO, CASE; pm_parameters = pm_ivr);

gen_scenarios, load_scenarios, trash = PowerModelsParallelRoutine.read_scenarios(ASPO, instance);

(timestamps, scenarios_ids, years, days) = PowerModelsParallelRoutine.case_parameters(gen_scenarios);

# Dictionary that stores the maximum injection for each scenario, year and day
connection_points = PowerModelsParallelRoutine.build_connection_points(ASPO, network, timestamps, scenarios_ids);

filter_results = PowerModelsParallelRoutine.create_filter_results(ASPO, network); # 


######################
# Unified execution  # - can stress in large instances
######################

# ITER PARAMETERS #
# Using all scenarios and all timestamps to create execution groups
scenarios_ids_iter  = scenarios_ids
timestamps_ids_iter = collect(1:length(timestamps))
timestamps_iter     = timestamps[timestamps_ids_iter]
years_iter          = years
days_iter           = days
####################################################################

# Create all execution groups with define iter parameters
# Each execution group stores:
# - operation_points
# - connection_points -> used to store the maximum injection for each group
# - filter_results

execution_groups = PowerModelsParallelRoutine.create_all_execution_groups(
        gen_scenarios, load_scenarios, filter_results, connection_points,
        timestamps_ids_iter, timestamps_iter, scenarios_ids_iter, years_iter, days_iter
);

# Evaluate all execution groups parallelizing
PowerModelsParallelRoutine.evaluate_execution_groups!(network, execution_groups, pm_acr)

# reassemble the connection groups evaluated
PowerModelsParallelRoutine.assemble_connection_points!(connection_points, execution_groups, scenarios_ids_iter, years_iter, days_iter)

# verify max injections
name = "SIDROLANDIA"
max_inj = PowerModelsParallelRoutine.refcpall(connection_points, name) # should not have Inf values

######################
# Separate execution #
######################

for s in scenarios_ids
    # define iter parameters
    scenarios_ids_iter  = [s]
    timestamps_ids_iter = collect(3:4)

    timestamps_iter     = timestamps[timestamps_ids_iter]
    years_iter          = unique(year.(timestamps_iter))
    days_iter           = unique(Dates.dayofyear.(timestamps_iter))

    execution_groups = PowerModelsParallelRoutine.create_all_execution_groups(
        gen_scenarios, load_scenarios, filter_results, connection_points,
        timestamps_ids_iter, timestamps_iter, scenarios_ids_iter, years_iter, days_iter
    );

    # Evaluate all execution groups parallelizing
    PowerModelsParallelRoutine.evaluate_execution_groups!(network, execution_groups, pm_acr)

    # reassemble the connection groups evaluated
    PowerModelsParallelRoutine.assemble_connection_points!(connection_points, execution_groups, scenarios_ids_iter, years_iter, days_iter)
end



#####################
# usefull functions #
#####################

# Retrive connection point for one scenario, year and day
name = "SIDROLANDIA"
s = 1
y = 2019
d = 1
cp = PowerModelsParallelRoutine.refcp(connection_points, name, s, y, d)

# Retrive injection matrix for a connection point
max_inj = PowerModelsParallelRoutine.refcpall(connection_points, name)

# Retrive execution group for one scenario, year and day
s = 1
y = 2019
d = 1
eg = PowerModelsParallelRoutine.refeg(execution_groups, s, y, d)