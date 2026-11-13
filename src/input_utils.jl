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
# Variables of a `Service` are stored per service, so their key also carries its name
make_key(entry::Type{<:PSI.VariableType}, service::Type{<:PSY.Service}, name::String) =
    PSI.VariableKey(entry, service, name)

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
Accepts either `initial_time` or `start_time`, and either `horizon` or `len`, but not both
of a pair. Throws an `ArgumentError` if a window given by `initial_time` or `horizon` does
not lie within the realized timestamps of `res`.
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
    _check_given_time_window(res, start_time, len; initial_time, horizon)
    return (start_time = start_time, len = len)
end

# Check the window only when it was given as `initial_time` or `horizon`; the
# `start_time`/`len` spelling is not checked.
function _check_given_time_window(
    res::IS.Results,
    start_time::Union{Nothing, DateTime},
    len::Union{Nothing, Integer};
    initial_time = nothing,
    horizon = nothing,
    _...,
)
    if !isnothing(initial_time) || !isnothing(horizon)
        _check_time_window(res, start_time, len)
    end
    return
end

# Throw an `ArgumentError` unless the window of `len` steps from `start_time` lies within the
# realized timestamps of `res`. `nothing` means the start or the end of the results.
_check_time_window(::IS.Results, ::Nothing, ::Nothing) = nothing

function _check_time_window(
    res::IS.Results,
    start_time::Union{Nothing, DateTime},
    len::Union{Nothing, Integer},
)
    timestamps = PSI.get_realized_timestamps(res)
    first_time, last_time = first(timestamps), last(timestamps)
    start_index = _time_index(timestamps, start_time)
    isnothing(start_index) && throw(
        ArgumentError(
            "initial_time $start_time is not one of the results timestamps " *
            "($first_time to $last_time)",
        ),
    )
    _check_horizon_steps(timestamps, start_index, len)
    return
end

_time_index(::AbstractVector{DateTime}, ::Nothing) = 1
_time_index(timestamps::AbstractVector{DateTime}, start_time::DateTime) =
    findfirst(==(start_time), timestamps)

_check_horizon_steps(::AbstractVector{DateTime}, ::Int, ::Nothing) = nothing

function _check_horizon_steps(
    timestamps::AbstractVector{DateTime},
    start_index::Int,
    len::Integer,
)
    len >= 1 || throw(ArgumentError("horizon must be at least one time step, got $len"))
    start_index + len - 1 <= length(timestamps) || throw(
        ArgumentError(
            "a horizon of $len steps from $(timestamps[start_index]) runs past the end " *
            "of the results ($(last(timestamps)))",
        ),
    )
    return
end

# Resolve the time window key words within `kwargs`, passing other key words through; adds
# none when none were given.
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
    key_tuple;
    start_time::Union{Nothing, DateTime} = nothing,
    len::Union{Int, Nothing} = nothing,
    cols::Union{Colon, Vector{String}},
)
    # Cache every stored window: `load_results!` counts windows, not time steps, so the
    # requested window is applied by `read_results_with_keys`.
    PSI.load_results!(
        res,
        length(PSI.get_timestamps(res));
        make_entry_kwargs([key_tuple])...,
    )
    return PSI.read_results_with_keys(
        res,
        [make_key(key_tuple...)];
        start_time = start_time,
        len = len,
        cols = cols,
        table_format = IS.TableFormat.WIDE,
    )
end

# Otherwise here is the fallback
_read_results_with_keys_wrapper(
    res::IS.Results,
    key_tuple;
    start_time::Union{Nothing, DateTime} = nothing,
    len::Union{Int, Nothing} = nothing,
    cols::Union{Colon, Vector{String}},
) =
    PSI.read_results_with_keys(
        res,
        [make_key(key_tuple...)];
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

# Throw a `NoResultError` if `key` was never stored in `res`
function _check_key_stored(res::IS.Results, key::PSI.OptimizationContainerKey)
    stored = _stored_keys(res, key)
    (isnothing(stored) || key in stored) && return
    throw(NoResultError("$(PSI.encode_key_as_string(key)) is not in the results"))
end

_no_column_error(name::String, key::PSI.OptimizationContainerKey) =
    NoResultError("$name not in the results for $(PSI.encode_key_as_string(key))")

# Fetch the column of `comp` from the results stored under `key_tuple`, throwing a
# `NoResultError` if the key or the column is missing
function _read_component_column(res::IS.Results, key_tuple::Tuple, comp::Component;
    start_time::Union{Nothing, DateTime} = nothing,
    len::Union{Int, Nothing} = nothing,
)
    key = make_key(key_tuple...)
    _check_key_stored(res, key)
    name = get_name(comp)
    res = try
        only(
            values(
                _read_results_with_keys_wrapper(
                    res,
                    key_tuple;
                    start_time = start_time,
                    len = len,
                    cols = [name],
                ),
            ),
        )
    catch e
        (e isa KeyError && e.key == name) && throw(_no_column_error(name, key))
        rethrow(e)
    end
    # Results types that cannot select columns return the whole table
    name in names(res) || throw(_no_column_error(name, key))
    return res[!, [DATETIME_COL, name]]
end

"Given an EntryType and a Component, fetch a single column of results"
read_component_result(res::IS.Results, entry::Type{<:EntryType}, comp::Component;
    kwargs...) = _read_component_column(res, (entry, typeof(comp)), comp; kwargs...)

"""
Given a variable type stored per `Service` (e.g.
`PowerSimulations.ActivePowerReserveVariable`), fetch the single column of results for the
contributing device `comp`
"""
read_service_component_result(
    res::IS.Results,
    entry::Type{<:PSI.VariableType},
    service::PSY.Service,
    comp::Component;
    kwargs...,
) = _read_component_column(
    res,
    (entry, typeof(service), get_name(service)),
    comp;
    kwargs...,
)

"""
Get the `Service`s of the `System` attached to `results` that have
[`PowerSimulations.ActivePowerReserveVariable`](@extref) results stored in `results`,
sorted by name.

See also: [`make_calc_reserve_provision`](@ref PowerAnalytics.Metrics.make_calc_reserve_provision)
"""
function get_reserve_services(results::IS.Results)
    sys = get_system(results)
    isnothing(sys) && throw(
        ArgumentError(
            "The results have no attached System; load them with `populate_system = true`",
        ),
    )
    stored = Set(PSI.list_variable_keys(results))
    services = [
        service for service in get_components(PSY.Service, sys) if
        make_key(PSI.ActivePowerReserveVariable, typeof(service), get_name(service)) in
        stored
    ]
    return sort!(services; by = get_name)
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
