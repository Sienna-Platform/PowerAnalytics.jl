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

# SimulationProblemResults has some extra features: the ability to `load_results!` and to specify which columns we want
function _read_results_with_keys_wrapper(
    res::PSI.SimulationProblemResults{PSI.DecisionModelSimulationResults},
    key_pair;
    start_time::Union{Nothing, DateTime} = nothing,
    len::Union{Int, Nothing} = nothing,
    cols::Union{Colon, Vector{String}},
)
    cache_len = isnothing(len) ? length(PSI.get_timestamps(res)) : len
    PSI.load_results!(
        res,
        cache_len;
        initial_time = start_time,
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

"Given an EntryType and a Component, fetch a single column of results"
function read_component_result(res::IS.Results, entry::Type{<:EntryType}, comp::Component;
    start_time::Union{Nothing, DateTime} = nothing,
    len::Union{Int, Nothing} = nothing,
)
    key_pair = (entry, typeof(comp))
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

struct InvestmentOperationalResults <: IS.Results
    results::ISOPT.OptimizationProblemResults
    portfolio::PSIP.Portfolio
end

"""
    operational_results(results::InfrastructureSystems.Results)

Create a PowerAnalytics view of time-step operational variables from investment results.
The native results must have their original portfolio attached with a matching UUID.

The view supports `calc_active_power`, `calc_active_power_in`, `calc_active_power_out` and `calc_stored_energy` with portfolio technology selectors.
Native PSIN operational variable types can also be read with `read_component_result`.
Pass `meta` to a metric call when more than one formulation stores the same technology.

Investment decisions, weighted period aggregates and financial totals are outside this view.
Returned power and energy remain in their native MW and MWh units.
Time aggregation does not apply representative-period weights.
The native result object and portfolio are not modified.

See also [`compute`](@ref) and [`ComponentTimedMetric`](@ref).
"""
operational_results(results::IS.Results) =
    _operational_results(results, IS.get_source_data(results))

_operational_results(results::IS.Results, source) = throw(
    ArgumentError(
        "Operational investment results require native optimization results " *
        "with the original portfolio attached."),
)

function _operational_results(results::ISOPT.OptimizationProblemResults,
    portfolio::PSIP.Portfolio)
    IS.get_uuid(portfolio) == ISOPT.get_source_data_uuid(results) ||
        throw(ArgumentError("The attached portfolio UUID does not match the results."))
    timestamps = PSIN.get_timestamps(results)
    isempty(timestamps) && throw(ArgumentError("Operational results have no timestamps."))
    (issorted(timestamps) && allunique(timestamps)) || throw(ArgumentError(
        "Operational timestamps must be unique and increasing."))
    return InvestmentOperationalResults(results, portfolio)
end

IS.get_source_data(results::InvestmentOperationalResults) = results.portfolio
IS.get_base_power(results::InvestmentOperationalResults) =
    ISOPT.get_model_base_power(results.results)
IS.get_timestamp(results::InvestmentOperationalResults) =
    PSIN.get_timestamps(results.results)
ISOPT.get_timestamps(results::InvestmentOperationalResults) =
    PSIN.get_timestamps(results.results)

# Delegate availability to the portfolio API without changing global portfolio behavior.
IS.get_components(
    ::Type{T},
    results::InvestmentOperationalResults,
) where {T <: PSIP.Technology} =
    PSIP.get_available_technologies(T, results.portfolio)
IS.get_components(filter_func::Function, ::Type{T},
    results::InvestmentOperationalResults) where {T <: PSIP.Technology} =
    Iterators.filter(filter_func, PSIP.get_available_technologies(T, results.portfolio))
IS.get_component(::Type{T}, results::InvestmentOperationalResults,
    name::AbstractString) where {T <: PSIP.Technology} =
    PSIP.get_available_technology(T, results.portfolio, name)

function IS.get_components(
    ::Type{T},
    ::InvestmentOperationalResults,
) where {T <: IS.InfrastructureSystemsComponent}
    throw(
        ArgumentError(
            "Select a portfolio technology type such as " *
            "SupplyTechnology{ThermalStandard} for investment results.",
        ),
    )
end
function IS.get_components(filter_func::Function, ::Type{T},
    results::InvestmentOperationalResults) where {T <: IS.InfrastructureSystemsComponent}
    return IS.get_components(T, results)
end
function IS.get_component(::Type{T}, results::InvestmentOperationalResults,
    name::AbstractString) where {T <: IS.InfrastructureSystemsComponent}
    return IS.get_components(T, results)
end

# Existing metrics retain their meanings while the result entry types change.
_operational_entry(entry::Type, technology::PSIP.Technology) = throw(
    NoResultError(
        "The operational view does not support $entry for $(typeof(technology)). " *
        "Use time-step operational variables. Investment values, weighted energy " *
        "and cost reporting require their own context."),
)
_operational_entry(entry::Type{<:PSIN.OperationsVariableType}, ::PSIP.Technology) = entry
_operational_entry(::Type{PSI.ActivePowerVariable}, ::PSIP.SupplyTechnology) =
    PSIN.ActivePowerVariable
_operational_entry(::Type{PSI.ActivePowerInVariable}, ::PSIP.StorageTechnology) =
    PSIN.ActiveInPowerVariable
_operational_entry(::Type{PSI.ActivePowerOutVariable}, ::PSIP.StorageTechnology) =
    PSIN.ActiveOutPowerVariable
_operational_entry(::Type{PSI.EnergyVariable}, ::PSIP.StorageTechnology) =
    PSIN.StateOfChargeVariable

function _technology_key(results::InvestmentOperationalResults, tables, native_entry::Type,
    technology::PSIP.Technology, meta::Union{Nothing, AbstractString})
    name = PSIP.get_name(technology)
    stored = PSIP.get_technology(typeof(technology), results.portfolio, name)
    (isnothing(stored) || IS.get_uuid(stored) != IS.get_uuid(technology)) &&
        throw(ArgumentError("Technology $name does not belong to the results portfolio."))
    candidates = filter(collect(keys(tables))) do key
        ISOPT.get_entry_type(key) == native_entry &&
            ISOPT.get_component_type(key) == typeof(technology) &&
            (isnothing(meta) || key.meta == meta)
    end
    matching = filter(candidates) do key
        "name" in names(tables[key]) || throw(
            ArgumentError(
                "$(ISOPT.encode_key_as_string(key)) has no technology-name column.",
            ),
        )
        name in tables[key].name
    end
    isempty(matching) && throw(
        NoResultError(
            "No $native_entry result is stored for technology $name with meta=$(repr(meta)).",
        ),
    )
    length(matching) == 1 || throw(
        ArgumentError(
            "Multiple formulations store $native_entry for $name. " *
            "Select one with meta. Available values are $(repr(sort([key.meta for key in matching]))).",
        ),
    )
    return only(matching)
end

function _validate_operational_axis(table, key, indices)
    Set(names(table)) == Set(["time_index", "name", "value"]) ||
        throw(
            ArgumentError(
                "$(ISOPT.encode_key_as_string(key)) must have " *
                "time_index, name and value columns for operational analytics.",
            ),
        )
    for component in DataFrames.groupby(table, :name)
        sort(component.time_index) == indices || throw(
            ArgumentError(
                "$(ISOPT.encode_key_as_string(key)) does not have exactly one value " *
                "per operational index for $(first(component.name)). " *
                "Incomplete or differently indexed data cannot be read through this view.",
            ),
        )
    end
    return
end

function read_component_result(results::InvestmentOperationalResults,
    entry::Type{<:EntryType}, technology::PSIP.Technology;
    start_time::Union{Nothing, DateTime} = nothing,
    len::Union{Int, Nothing} = nothing,
    meta::Union{Nothing, AbstractString} = nothing,
)
    !isnothing(len) && len < 1 && throw(ArgumentError("len must be positive."))
    variables = PSIN.get_variable_values(results.results)
    key = _technology_key(results, variables,
        _operational_entry(entry, technology), technology, meta)
    # Check the complete axis before slicing, including when len matches a period count.
    _validate_operational_axis(variables[key], key,
        eachindex(PSIN.get_timestamps(results.results)))
    table = PSIN.read_variable(results.results, key;
        start_time = start_time, len = len, table_format = IS.TableFormat.WIDE)
    return table[!, [DATETIME_COL, PSIP.get_name(technology)]]
end

# TODO caching here too
"Given an EntryType that applies to the System, fetch a single column of results"
function read_system_result(res::IS.Results, entry::Type{<:SystemEntryType};
    start_time::Union{Nothing, DateTime} = nothing, len::Union{Int, Nothing} = nothing)
    key = make_key(entry, PSY.System)
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
