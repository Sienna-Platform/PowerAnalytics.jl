# LOADING RESULTS
"""
Accept a directory that contains several results subdirectories (that each contain
`results`, `problems`, etc. sub-subdirectories) and construct a sorted dictionary from
`String` to [`PowerSimulations.SimulationProblemResults`](@extref) where the keys are the
subdirectory names and the values are loaded results datasets.

# Arguments
 - `results_dir::AbstractString`: the directory where results subdirectories can be found
 - `problem::String`: the name of the problem to load (e.g., `UC`, `ED`)
 - `scenarios::Union{Vector{AbstractString}, Nothing} = nothing`: a list of scenario
   subdirectories to load, or `nothing` to load all the subdirectories
 - `populate_system::Bool = false`: whether to automatically load and attach the system;
   errors if `true` and the system has not been saved with the results. **This keyword
   argument is `false` by default for backwards compatibility, but most PowerAnalytics
   functionality requires results to have an attached system, so users should typically pass
   `populate_system = true`.**
 - `kwargs...`: further keyword arguments to pass through to `get_decision_problem_results`

# Examples
Suppose we have the directory `data_root` with subdirectories `results1`, `results2`, and
`results3`, where each of these subdirectories contains `problems/UC`. Then:

```julia
# Load results for only `results1` and `results2`:
create_problem_results_dict(data_root, "UC", ["results1", "results2"]; populate_system = true)
# Load results for all three scenarios:
create_problem_results_dict(data_root, "UC"; populate_system = true)
```

# See also
`create_problem_results_dict` is a convenience function that calls public interface in
[`PowerSimulations.jl`](https://sienna-platform.github.io/PowerSimulations.jl/stable/). To read
one results set, or several of them that are not all in the same parent directory, invoke
that interface directly as needed:

```julia
# Load a single results set
PowerSimulations.get_decision_problem_results(
    PowerSimulations.SimulationResults(path_to_individual_results),
    problem_name; populate_system = true)
```
"""
function create_problem_results_dict(
    results_dir::AbstractString,
    problem::String,
    scenarios::Union{Vector{<:AbstractString}, Nothing} = nothing;
    populate_system::Bool = false,
    kwargs...,
)
    if scenarios === nothing
        scenarios = filter(x -> isdir(joinpath(results_dir, x)), readdir(results_dir))
    end
    return SortedDict(
        scenario => PSI.get_decision_problem_results(
            PSI.SimulationResults(joinpath(results_dir, scenario)),
            problem; populate_system = populate_system, kwargs...) for scenario in scenarios
    )
end

# READING KEYS FROM RESULTS
# TODO move `DATETIME_COL` to PowerSimulations to replace its hardcoding of :DateTime
"Name of the column that represents the time axis in computed DataFrames. Currently equal to `\"$DATETIME_COL\"`."
const DATETIME_COL = "DateTime"

"Name of a column that represents whole-of-`System` data. Currently equal to `\"$SYSTEM_COL\"`."
const SYSTEM_COL = "System"

"The various key entry types that can work with a System"
const SystemEntryType = Union{
    PSI.VariableType,
    PSI.ExpressionType,
}

"The various key entry types that can be used to make a PSI.OptimizationContainerKey"
const EntryType = Union{
    SystemEntryType,
    PSI.ParameterType,
    PSI.AuxVariableType,
    PSI.InitialConditionType,
}

# TODO: put make_key in PowerSimulations and refactor existing code to use it
"Create a PSI.OptimizationContainerKey from the given key entry type and component.

# Arguments
 - `entry::Type{<:EntryType}`: the key entry
 - `component` (`::Type{<:Union{Component, PSY.System}}` or `::Type{<:Component}` depending
   on the key type): the component type
"
function make_key end
make_key(entry::Type{<:PSI.VariableType}, component::Type{<:Union{Component, PSY.System}}) =
    PSI.VariableKey(entry, component)
make_key(entry::Type{<:PSI.ExpressionType}, comp::Type{<:Union{Component, PSY.System}}) =
    PSI.ExpressionKey(entry, comp)
make_key(entry::Type{<:PSI.ParameterType}, component::Type{<:Component}) =
    PSI.ParameterKey(entry, component)
make_key(entry::Type{<:PSI.AuxVariableType}, component::Type{<:Component}) =
    PSI.AuxVarKey(entry, component)
make_key(entry::Type{<:PSI.InitialConditionType}, component::Type{<:Component}) =
    PSI.ICKey(entry, component)

"Sort a vector of key tuples into variables, parameters, etc. like PSI.load_results! wants"
make_entry_kwargs(key_tuples::Vector{<:Tuple}) = [
    (key_name => filter(((this_key, _),) -> this_key <: key_type, key_tuples))
    for (key_name, key_type) in [
        (:variables, PSI.VariableType),
        (:duals, PSI.ConstraintType),
        (:parameters, PSI.ParameterType),
        (:aux_variables, PSI.AuxVariableType),
        (:expressions, PSI.ExpressionType),
    ]
]

# TIME WINDOWS
# Number of time steps a `horizon` spans in `res`. An integer horizon is already a step
# count; a period is divided by the results resolution and must be a whole multiple of it.
_horizon_len(::IS.Results, ::Nothing) = nothing
_horizon_len(::IS.Results, horizon::Integer) = Int(horizon)

function _horizon_len(res::IS.Results, horizon::Dates.FixedPeriod)
    resolution = PSI.get_resolution(res)
    steps = Dates.Millisecond(horizon) / Dates.Millisecond(resolution)
    isinteger(steps) || throw(
        ArgumentError(
            "horizon $horizon is not a whole multiple of the results resolution " *
            "$(Dates.canonicalize(resolution))",
        ),
    )
    return Int(steps)
end

# `Dates.Month` and `Dates.Year` have no fixed length
_horizon_len(::IS.Results, horizon::Dates.Period) = throw(
    ArgumentError(
        "horizon $horizon has no fixed duration; use a fixed period such as " *
        "`Dates.Hour` or `Dates.Day`, or an integer number of time steps",
    ),
)

_first_given(::Symbol, ::Nothing, ::Symbol, ::Nothing) = nothing
_first_given(::Symbol, value, ::Symbol, ::Nothing) = value
_first_given(::Symbol, ::Nothing, ::Symbol, value) = value
_first_given(name::Symbol, ::Any, other_name::Symbol, ::Any) = throw(
    ArgumentError("pass only one of `$name` and `$other_name`"),
)

"""
Resolve the time window key words of [`compute`](@ref) into the `start_time` (a
`DateTime`) and `len` (a number of time steps) that `Metric` evaluation functions receive.
`initial_time` and `horizon` are the documented spellings; `start_time` and `len` are the
already-resolved form, accepted so that nested `compute` calls inside evaluation functions
can forward their key words unchanged.
"""
function resolve_time_window(
    res::IS.Results;
    initial_time::Union{Nothing, DateTime} = nothing,
    horizon::Union{Nothing, Integer, Dates.Period} = nothing,
    start_time::Union{Nothing, DateTime} = nothing,
    len::Union{Nothing, Integer} = nothing,
)
    start_time = _first_given(:initial_time, initial_time, :start_time, start_time)
    len = _first_given(:horizon, _horizon_len(res, horizon), :len, len)
    return (start_time = start_time, len = len)
end

# Resolve the time window key words within `kwargs`, passing any other key words through.
# No window key words are added when none were given, so evaluation functions that take
# none keep working.
function _resolve_window_kwargs(res::IS.Results, kwargs)
    window_keys = (:initial_time, :horizon, :start_time, :len)
    other = Base.structdiff(values(kwargs), NamedTuple{window_keys})
    any(k -> haskey(kwargs, k), window_keys) || return other
    window = resolve_time_window(
        res;
        (k => kwargs[k] for k in window_keys if haskey(kwargs, k))...,
    )
    return merge(other, window)
end

# SimulationProblemResults has some extra features: the ability to `load_results!` and to specify which columns we want
function _read_results_with_keys_wrapper(
    res::PSI.SimulationProblemResults{PSI.DecisionModelSimulationResults},
    key_pair;
    start_time::Union{Nothing, DateTime} = nothing,
    len::Union{Int, Nothing} = nothing,
    cols::Union{Colon, Vector{String}},
)
    # Cache every stored window of the key. `load_results!` counts in windows starting
    # from a window-initial time while `start_time`/`len` are in time steps, so the
    # requested time window is applied by `read_results_with_keys` instead.
    PSI.load_results!(
        res,
        length(PSI.get_timestamps(res));
        make_entry_kwargs([key_pair])...,
    )
    return PSI.read_results_with_keys(
        res,
        [make_key(key_pair...)];
        start_time = start_time,
        len = len,
        cols = cols,
        table_format = IS.TableFormat.WIDE,
    )
end

# Otherwise here is the fallback
_read_results_with_keys_wrapper(
    res::IS.Results,
    key_pair;
    start_time::Union{Nothing, DateTime} = nothing,
    len::Union{Int, Nothing} = nothing,
    cols::Union{Colon, Vector{String}},
) =
    PSI.read_results_with_keys(
        res,
        [make_key(key_pair...)];
        start_time = start_time,
        len = len,
        table_format = IS.TableFormat.WIDE,
    )

# The keys of the same kind as `key` that are stored in `res`, or `nothing` when that kind
# of key cannot be listed
_stored_keys(res::IS.Results, ::PSI.VariableKey) = PSI.list_variable_keys(res)
_stored_keys(res::IS.Results, ::PSI.ExpressionKey) = PSI.list_expression_keys(res)
_stored_keys(res::IS.Results, ::PSI.ParameterKey) = PSI.list_parameter_keys(res)
_stored_keys(res::IS.Results, ::PSI.AuxVarKey) = PSI.list_aux_variable_keys(res)
_stored_keys(::IS.Results, ::PSI.OptimizationContainerKey) = nothing

# Throw a `NoResultError` if `key` was never stored in `res`, so that a missing key and a
# missing component surface as the same error
function _check_key_stored(res::IS.Results, key::PSI.OptimizationContainerKey)
    stored = _stored_keys(res, key)
    (isnothing(stored) || key in stored) && return
    throw(NoResultError("$(PSI.encode_key_as_string(key)) is not in the results"))
end

"Given an EntryType and a Component, fetch a single column of results"
function read_component_result(res::IS.Results, entry::Type{<:EntryType}, comp::Component;
    start_time::Union{Nothing, DateTime} = nothing,
    len::Union{Int, Nothing} = nothing,
)
    key_pair = (entry, typeof(comp))
    _check_key_stored(res, make_key(key_pair...))
    res = try
        only(
            values(
                _read_results_with_keys_wrapper(
                    res,
                    key_pair;
                    start_time = start_time,
                    len = len,
                    cols = [get_name(comp)],
                ),
            ),
        )
    catch e
        if e isa KeyError && e.key == get_name(comp)
            throw(
                NoResultError(
                    "$(get_name(comp)) not in the results for $(PSI.encode_key_as_string(make_key(key_pair...)))",
                ),
            )
        else
            rethrow(e)
        end
    end
    return res[!, [DATETIME_COL, get_name(comp)]]
end

# TODO caching here too
"Given an EntryType that applies to the System, fetch a single column of results"
function read_system_result(res::IS.Results, entry::Type{<:SystemEntryType};
    start_time::Union{Nothing, DateTime} = nothing, len::Union{Int, Nothing} = nothing)
    key = make_key(entry, PSY.System)
    _check_key_stored(res, key)
    res = only(
        values(
            PSI.read_results_with_keys(
                res,
                [key];
                start_time = start_time,
                len = len,
                table_format = IS.TableFormat.WIDE,
            ),
        ),
    )
    @assert size(res, 2) == 2 "Expected a time column and a data column in the results for $(PSI.encode_key_as_string(key)), got $(size(res, 2)) columns"
    @assert DATETIME_COL in names(res) "Expected a column named $DATETIME_COL in the results for $(PSI.encode_key_as_string(key)), got $(names(res))"
    # Whatever the non-time column is, rename it to something standard
    res = DataFrames.rename(res, findfirst(!=(DATETIME_COL), names(res)) => SYSTEM_COL)
    return res[!, [DATETIME_COL, SYSTEM_COL]]
end
