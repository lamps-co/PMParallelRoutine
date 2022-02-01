#####################################
# Necessary parameters to define a  #
# power flow model in PowerModels   #
# - pm_model                        #
# - build_model                     #
# - set_initial_values!             #
# - optimizer                       #
#####################################

const optimizer = optimizer_with_attributes(Ipopt.Optimizer, "max_iter" => 50, "tol"=>1e-3, "print_level"=>0)

#############
# IVR MODEL #
#############

ivr_pm_model            = PowerModelsParallelRoutine.PowerModels.IVRPowerModel
ivr_build_model         = PowerModelsParallelRoutine.PowerModels.build_pf_iv
ivr_set_initial_values! = PowerModelsParallelRoutine.set_ivr_start_value!

const pm_ivr_parameters = PowerModelsParallelRoutine.PMParameters(
    ivr_pm_model,                #
    ivr_build_model,             #
    ivr_set_initial_values!,     # 
    optimizer                # 
)

#############
# ACR MODEL #
#############

acr_pm_model            = PowerModelsParallelRoutine.PowerModels.ACRPowerModel
acr_build_model         = PowerModelsParallelRoutine.PowerModels.build_pf
acr_set_initial_values! = PowerModelsParallelRoutine.set_acr_start_value!

const pm_acr_parameters = PowerModelsParallelRoutine.PMParameters(
    acr_pm_model,                #
    acr_build_model,             #
    acr_set_initial_values!,     # 
    optimizer                # 
)