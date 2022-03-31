using Pkg
Pkg.instantiate()

using PackageCompiler

create_sysimage(:PowerModelsParallelRoutine;
    sysimage_path="PowerModelsParallelRoutine.so",
    precompile_execution_file="deploy/precompile.jl")
