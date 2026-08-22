"""
Load a serialized outputs directory and attach the system serialized alongside it.

`directory` must be self-contained: it holds both `problem_outputs.bin` and the
`system-\$(uuid)` bundle that PowerOperationsModels writes next to it. No system argument is
needed.
"""
function load_outputs(directory::AbstractString)
    out = IOM.OptimizationProblemOutputs(directory)
    system_dirname = IOM.make_system_dirname(IOM.get_source_data_uuid(out))
    # Resolve against the caller's `directory`, not `IOM.get_outputs_dir(out)`: that field is
    # the absolute path recorded at solve time and goes stale if the directory was moved or
    # copied, while `directory` is always where the caller is actually looking.
    system_dir = joinpath(directory, system_dirname)
    if !isdir(system_dir)
        error(
            "No system bundle found at $system_dir. $directory is not a self-contained " *
            "outputs directory -- it was likely written before PowerOperationsModels began " *
            "serializing the system alongside the outputs. Call `load_outputs(directory, sys)` " *
            "with the system used to produce these outputs instead.",
        )
    end
    sys = PSY.from_file(PSY.System, system_dir; time_series_read_only = true)
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
    # Checked here rather than in IOM: the System UUID is a PSY concept, and IOM is
    # domain-neutral. The one-argument form above cannot check it at all -- a System rebuilt
    # from a bundle carries a fresh UUID -- so it relies on the bundle's location instead.
    sys_uuid = PSY.get_system_uuid(sys)
    recorded = IOM.get_source_data_uuid(out)
    if sys_uuid != recorded
        throw(
            IS.InvalidValue(
                "System mismatch. $sys_uuid does not match the stored value of $recorded",
            ),
        )
    end
    IOM.set_source_data!(out, sys)
    return out
end
