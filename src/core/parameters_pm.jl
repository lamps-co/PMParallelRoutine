#####################################
# Necessary parameters to define a  #
# power flow model in PowerModels   #
# - pm_model                        #
# - build_model                     #
# - set_initial_values!             #
# - optimizer                       #
#####################################

const optimizer = PowerFlowModule.optimizer

#############
# IVR MODEL #
#############

const pm_ivr_parameters         = PowerFlowModule.pm_ivr_parameters
const pm_ivr_parameters_silence = PowerFlowModule.pm_ivr_parameters_silence
#############
# ACR MODEL #
#############

const pm_acr_parameters         = PowerFlowModule.pm_acr_parameters
const pm_acr_parameters_silence = PowerFlowModule.pm_acr_parameters_silence