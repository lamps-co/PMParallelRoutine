#####################################
# Necessary parameters to define a  #
# power flow model in PowerModels   #
# - pm_model                        #
# - build_model                     #
# - set_initial_values!             #
# - optimizer                       #
#####################################

const optimizer = NetworkSimulations.optimizer

#############
# IVR MODEL #
#############

const pm_ivr_parameters         = NetworkSimulations.pm_ivr_parameters
const pm_ivr_parameters_silence = NetworkSimulations.pm_ivr_parameters_silence
#############
# ACR MODEL #
#############

const pm_acr_parameters         = NetworkSimulations.pm_acr_parameters
const pm_acr_parameters_silence = NetworkSimulations.pm_acr_parameters_silence