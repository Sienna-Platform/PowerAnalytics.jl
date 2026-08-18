"""
Load a serialized outputs directory and attach the system serialized alongside it.

`directory` must be self-contained: it holds both `problem_outputs.bin` and the
`system-\$(uuid).json` that PowerOperationsModels writes next to it. No system argument is
needed.
"""
function load_outputs(directory::AbstractString)
    out = IOM.OptimizationProblemOutputs(directory)
    system_filename = IOM.make_system_filename(IOM.get_source_data_uuid(out))
    # Resolve against the caller's `directory`, not `IOM.get_outputs_dir(out)`: that field is
    # the absolute path recorded at solve time and goes stale if the directory was moved or
    # copied, while `directory` is always where the caller is actually looking.
    system_file = joinpath(directory, system_filename)
    if !isfile(system_file)
        error(
            "No system file found at $system_file. $directory is not a self-contained " *
            "outputs directory -- it was likely written before PowerOperationsModels began " *
            "serializing the system alongside the outputs. Call `load_outputs(directory, sys)` " *
            "with the system used to produce these outputs instead.",
        )
    end
    sys = PSY.System(system_file; time_series_read_only = true)
    IOM.set_source_data!(out, sys)
    return out
end

"""
Load a serialized outputs directory and attach `sys` as its source data.

Use this when `directory` has no serialized system alongside it. Throws `IS.InvalidValue` if
`sys` is not the system that produced these outputs.
"""
function load_outputs(directory::AbstractString, sys::PSY.System)
    out = IOM.OptimizationProblemOutputs(directory)
    IOM.set_source_data!(out, sys)
    return out
end
