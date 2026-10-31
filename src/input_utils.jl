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
"Create a result key from the given entry and component types.

# Arguments
 - `entry::Type{<:EntryType}`: the key entry
 - `component`: a PowerSystems component or system type or a portfolio technology type
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
make_key(entry::Type{<:ISOPT.VariableType}, technology::Type{<:PSIP.Technology}) =
    ISOPT.VariableKey(entry, technology)
make_key(entry::Type{<:ISOPT.ExpressionType}, technology::Type{<:PSIP.Technology}) =
    ISOPT.ExpressionKey(entry, technology)

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

abstract type AbstractInvestmentResults <: IS.Results end

struct InvestmentOperationalResults <: AbstractInvestmentResults
    results::PSIN.InvestmentProblemResults
end

_validate_investment_source(results, source) = throw(
    ArgumentError(
        "Investment results require PSIN optimization results " *
        "with the original portfolio attached.",
    ),
)

function _validate_investment_source(results, portfolio::PSIP.Portfolio)
    IS.get_uuid(portfolio) == ISOPT.get_source_data_uuid(results) ||
        throw(ArgumentError("The attached portfolio UUID does not match the results."))
    return
end

"""
Create a PowerAnalytics results object for time-step operational variables from PSIN
results.

The returned results support `calc_active_power`, `calc_active_power_in`,
`calc_active_power_out` and `calc_stored_energy` with portfolio technology selectors.
PSIN operational variable types can also be read with `read_component_result`. Pass
`meta` to a metric call when more than one formulation stores the same technology.

These operational results do not support investment decisions, weighted period
aggregates or financial totals. Returned power and energy remain in MW and MWh. Values
for a technology spanning multiple regions are summed across its regions. Time
aggregation does not apply representative-period weights. The PSIN result object and
portfolio are not modified.

# Arguments
 - `results::PowerSystemsInvestments.InvestmentProblemResults` is the PSIN results
   object with its original portfolio attached and a matching UUID.

# See also
[`compute`](@ref) and [`ComponentTimedMetric`](@ref).
"""
function operational_results(results::PSIN.InvestmentProblemResults)
    _validate_investment_source(results, IS.get_source_data(results))
    timestamps = PSIN.get_timestamps(results)
    isempty(timestamps) && throw(ArgumentError("Operational results have no timestamps."))
    (issorted(timestamps) && allunique(timestamps)) || throw(ArgumentError(
        "Operational timestamps must be unique and increasing."))
    return InvestmentOperationalResults(results)
end

IS.get_source_data(results::AbstractInvestmentResults) =
    IS.get_source_data(results.results)
IS.get_base_power(results::AbstractInvestmentResults) =
    ISOPT.get_model_base_power(results.results)
IS.get_timestamp(results::InvestmentOperationalResults) =
    ISOPT.get_timestamps(results)
ISOPT.get_timestamps(results::InvestmentOperationalResults) =
    PSIN.get_timestamps(results.results)

# Delegate availability to the portfolio API without changing global portfolio behavior.
IS.get_components(
    ::Type{T},
    results::AbstractInvestmentResults,
) where {T <: PSIP.Technology} =
    PSIP.get_available_technologies(T, IS.get_source_data(results))
IS.get_components(filter_func::Function, ::Type{T},
    results::AbstractInvestmentResults) where {T <: IS.InfrastructureSystemsComponent} =
    Iterators.filter(filter_func, IS.get_components(T, results))
IS.get_component(::Type{T}, results::AbstractInvestmentResults,
    name::AbstractString) where {T <: PSIP.Technology} =
    PSIP.get_available_technology(T, IS.get_source_data(results), name)

function IS.get_components(
    ::Type{T},
    ::AbstractInvestmentResults,
) where {T <: IS.InfrastructureSystemsComponent}
    throw(
        ArgumentError(
            "Select a portfolio technology type such as " *
            "SupplyTechnology{ThermalStandard} for investment results.",
        ),
    )
end
function IS.get_component(::Type{T}, results::AbstractInvestmentResults,
    name::AbstractString) where {T <: IS.InfrastructureSystemsComponent}
    return IS.get_components(T, results)
end

# Existing metrics retain their meanings while the result entry types change.
_operational_entry(entry::Type, technology::PSIP.Technology) = throw(
    NoResultError(
        "Operational results do not support $entry for $(typeof(technology)). " *
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

function _technology_key(results::AbstractInvestmentResults, tables, entry::Type,
    technology::PSIP.Technology, meta::Union{Nothing, AbstractString};
    candidate_keys = keys(tables))
    name = PSIP.get_name(technology)
    stored = PSIP.get_technology(typeof(technology), IS.get_source_data(results), name)
    (isnothing(stored) || IS.get_uuid(stored) != IS.get_uuid(technology)) &&
        throw(ArgumentError("Technology $name does not belong to the results portfolio."))
    candidates = filter(collect(candidate_keys)) do key
        haskey(tables, key) && ISOPT.get_entry_type(key) == entry &&
            ISOPT.get_component_type(key) == typeof(technology) &&
            (isnothing(meta) || key.meta == meta)
    end
    result_names = PSIN.get_variable_names(technology)
    matching = filter(candidates) do key
        "name" in names(tables[key]) || throw(
            ArgumentError(
                "$(ISOPT.encode_key_as_string(key)) has no technology-name column.",
            ),
        )
        all(in(tables[key].name), result_names)
    end
    isempty(matching) && throw(
        NoResultError(
            "No $entry result is stored for technology $name with meta=$(repr(meta)).",
        ),
    )
    length(matching) == 1 || throw(
        ArgumentError(
            "Multiple formulations store $entry for $name. " *
            "Select one with meta. Available values are $(repr(sort([key.meta for key in matching]))).",
        ),
    )
    return only(matching)
end

function read_component_result(results::InvestmentOperationalResults,
    entry::Type{<:EntryType}, technology::PSIP.Technology;
    start_time::Union{Nothing, DateTime} = nothing,
    len::Union{Int, Nothing} = nothing,
    meta::Union{Nothing, AbstractString} = nothing,
)
    variables = PSIN.get_variable_values(results.results)
    key = _technology_key(results, variables,
        _operational_entry(entry, technology), technology, meta)
    result_names = PSIN.get_variable_names(technology)
    table = PSIN.read_variable(results.results, key;
        start_time = start_time, len = len, cols = result_names,
        table_format = IS.TableFormat.WIDE)
    name = PSIP.get_name(technology)
    length(result_names) == 1 && return table
    return DataFrame(DATETIME_COL => table[!, DATETIME_COL],
        name => sum(eachcol(table[!, result_names])))
end

struct InvestmentCapacityResults <: AbstractInvestmentResults
    results::PSIN.InvestmentProblemResults
end

"""
Create a results object for planning-period capacity metrics from PSIN results. The
returned object uses the portfolio attached to the PSIN results.
`InvestmentProblemResults` supplies the investment-period mapping.

Computed tables use period start dates in the `DateTime` column. Capacity additions and
installed capacity come from PSIN expressions in MW for power and MWh for storage
energy. Direct `read_component_result` calls retain stored values, including unit counts
for integer builds. These results support supply, storage-power and storage-energy
investment. Values for a technology spanning multiple regions are summed across its
regions.

# Arguments

 - `results::PowerSystemsInvestments.InvestmentProblemResults` is the PSIN results
   object with its original portfolio attached and a matching UUID.

# See also

[`operational_results`](@ref) and [`get_investment_periods`](@ref).
"""
function investment_results(results::PSIN.InvestmentProblemResults)
    _validate_investment_source(results, IS.get_source_data(results))
    periods = PSIN.get_investment_time_stamps(results)
    isempty(periods) && throw(ArgumentError("Supply at least one investment period."))
    all(p -> first(p) <= last(p), periods) ||
        throw(ArgumentError("Investment periods must start on or before their end date."))
    all(i -> first(periods[i]) > last(periods[i - 1]), 2:length(periods)) ||
        throw(ArgumentError("Investment periods must be ordered and nonoverlapping."))
    all(PSIN.get_timestamps(results)) do timestamp
        any(p -> first(p) <= Dates.Date(timestamp) <= last(p), periods)
    end || throw(
        ArgumentError("Investment periods do not cover the PSIN operational timestamps."),
    )
    return InvestmentCapacityResults(results)
end

"""
Return a copy of the ordered investment-period intervals.

# Arguments
 - `results::InvestmentCapacityResults`: the results returned by [`investment_results`](@ref)
"""
get_investment_periods(results::IS.Results) =
    throw(
        ArgumentError("Investment periods require results returned by investment_results."),
    )
get_investment_periods(results::InvestmentCapacityResults) =
    PSIN.get_investment_time_stamps(results.results)
ISOPT.get_timestamps(results::InvestmentCapacityResults) =
    DateTime.(first.(get_investment_periods(results)))
IS.get_timestamp(results::InvestmentCapacityResults) = ISOPT.get_timestamps(results)

function _compute_meta_timed!(val, metric, results::InvestmentCapacityResults)
    invoke(_compute_meta_timed!, Tuple{Any, Any, Any}, val, metric, results)
    metadata!(val, "time_axis", "investment_period"; style = :note)
    periods = filter(p -> DateTime(first(p)) in val[!, DATETIME_COL],
        get_investment_periods(results))
    metadata!(val, "investment_periods", periods; style = :note)
    return
end

_investment_window(results::IS.Results; kwargs...) =
    throw(NoResultError("Capacity metrics require results returned by investment_results."))

function _investment_window(results::InvestmentCapacityResults;
    start_time::Union{Nothing, DateTime} = nothing, len::Union{Nothing, Int} = nothing)
    timestamps = ISOPT.get_timestamps(results)
    start = isnothing(start_time) ? 1 : findfirst(==(start_time), timestamps)
    isnothing(start) &&
        throw(ArgumentError("start_time must be an investment-period start."))
    count = something(len, length(timestamps) - start + 1)
    count >= 1 || throw(ArgumentError("len must be positive."))
    stop = start + count - 1
    stop <= length(timestamps) || throw(
        ArgumentError("The requested investment window exceeds the available periods."),
    )
    return timestamps[start:stop]
end

_capacity_entries(results::IS.Results, component::IS.InfrastructureSystemsComponent) =
    throw(
        NoResultError(
            "Capacity reporting requires results returned by investment_results and a supported supply or storage technology.",
        ),
    )
function _capacity_entries(results::IS.Results,
    technology::IS.InfrastructureSystemsComponent, entry::Type{<:EntryType})
    entries = _capacity_entries(results, technology)
    entry in entries || throw(
        NoResultError(
            "Investment capacity results do not support $entry for $(typeof(technology)).",
        ),
    )
    return entries
end
_capacity_entries(::InvestmentCapacityResults, ::PSIP.SupplyTechnology) =
    (PSIN.CapacityAdditions, PSIN.BuildCapacity, PSIN.CumulativeCapacity)
_capacity_entries(::InvestmentCapacityResults, ::PSIP.StorageTechnology) =
    (PSIN.PowerCapacityAdditions, PSIN.BuildPowerCapacity, PSIN.CumulativePowerCapacity)
_capacity_entries(::InvestmentCapacityResults, ::PSIP.StorageTechnology,
    ::Type{
        <:Union{PSIN.EnergyCapacityAdditions, PSIN.BuildEnergyCapacity,
            PSIN.CumulativeEnergyCapacity},
    }) =
    (PSIN.EnergyCapacityAdditions, PSIN.BuildEnergyCapacity, PSIN.CumulativeEnergyCapacity)

function _technology_key(results::InvestmentCapacityResults,
    entry::Type{<:EntryType}, technology::PSIP.Technology,
    meta::Union{Nothing, AbstractString})
    _capacity_entries(results, technology, entry)
    tables = ISOPT.get_result_values(results.results, make_key(entry, typeof(technology)))
    return _technology_key(results, tables, entry, technology, meta)
end

function _technology_key(results::InvestmentCapacityResults,
    key::Union{ISOPT.VariableKey, ISOPT.ExpressionKey},
    technology::PSIP.Technology, meta::Union{Nothing, AbstractString})
    entry = ISOPT.get_entry_type(key)
    _capacity_entries(results, technology, entry)
    isnothing(meta) ||
        throw(ArgumentError("An explicit result key already specifies meta."))
    tables = ISOPT.get_result_values(results.results, key)
    return _technology_key(results, tables, entry, technology, key.meta;
        candidate_keys = (key,))
end

function read_component_result(results::InvestmentCapacityResults,
    entry_or_key::Union{Type{<:EntryType}, ISOPT.VariableKey, ISOPT.ExpressionKey},
    technology::PSIP.Technology;
    start_time::Union{Nothing, DateTime} = nothing,
    len::Union{Nothing, Int} = nothing, meta::Union{Nothing, AbstractString} = nothing)
    key = _technology_key(results, entry_or_key, technology, meta)
    table = ISOPT.get_result_values(results.results, key)[key]
    name = PSIP.get_name(technology)
    result_names = PSIN.get_variable_names(technology)
    selected_values = table[in.(table.name, Ref(result_names)), :value]
    (any(ismissing, selected_values) || !all(isfinite, selected_values)) &&
        throw(ArgumentError("Capacity results for $name must contain finite values."))
    data = PSIN.read_results_with_keys(results.results, [key];
        start_time = start_time, len = len, cols = result_names,
        table_format = IS.TableFormat.WIDE)[key]
    length(result_names) == 1 && return data
    return DataFrame(DATETIME_COL => data[!, DATETIME_COL],
        name => sum(eachcol(data[!, result_names])))
end
