"""
Container for time-aligned result tables used by post-processing and plotting.

Each entry in `data` is a wide `DataFrame` of component (or
category) columns for one results key. `time` holds the timestamps shared by those
tables. Constructed by [`get_generation_data`](@ref), [`get_load_data`](@ref), and
[`get_service_data`](@ref).

# Fields
$(TYPEDFIELDS)
"""
struct PowerData
    "Map from results-key symbol to a wide DataFrame of values (no required `DateTime` column)."
    data::Dict{Symbol, DataFrames.DataFrame}
    "Timestamps aligned with the rows of each DataFrame in `data`."
    time::Union{StepRange{Dates.DateTime}, Vector{Dates.DateTime}}
end

function PowerData(
    data::Dict{PSI.OptimizationContainerKey, DataFrames.DataFrame},
    time::Union{StepRange{Dates.DateTime}, Vector{Dates.DateTime}},
)
    d = Dict(zip(Symbol.(PSI.encode_keys_as_strings(keys(data))), values(data)))

    rename_load!(d)
    return PowerData(d, time)
end

function PowerData(
    data::Dict{String, DataFrames.DataFrame},
    time::Union{StepRange{Dates.DateTime}, Vector{Dates.DateTime}},
)
    d = Dict(zip(Symbol.(keys(data)), values(data)))

    rename_load!(d)
    return PowerData(d, time)
end

function PowerData(data::Dict{String, DataFrames.DataFrame})
    d = Dict(zip(Symbol.(keys(data)), no_datetime.(values(data))))
    return PowerData(d, first(values(data)).DateTime)
end

# Rename Load variables: TODO: find a better way to do this
# Using the default keys is inappropriate since there is
# no subtyping.
function rename_load!(load_values::Dict)
    for (k, v) in load_values
        if haskey(LOAD_RENAMING, k)
            @debug "renaming" k => LOAD_RENAMING[k]
            if haskey(load_values, LOAD_RENAMING[k])
                @warn "Overwriting $(LOAD_RENAMING[k]) with $k"
            end
            load_values[LOAD_RENAMING[k]] = v
            pop!(load_values, k)
        end
    end
end

#### Generation Names ####
function get_generation_variable_keys(
    results::IS.Results;
    variable_keys::Vector{T} = PSI.list_variable_keys(results),
) where {T <: PSI.OptimizationContainerKey}
    # TODO: add slacks
    filter_keys = Vector{PSI.OptimizationContainerKey}()
    for k in variable_keys
        if (
            PSI.get_component_type(k) <: PSY.Generator &&
            PSI.get_entry_type(k) == PSI.ActivePowerVariable
        ) || PSI.get_entry_type(k) ∈ keys(BALANCE_SLACKVARS)
            push!(filter_keys, k)
        end
    end

    return filter_keys
end

function get_storage_variable_keys(
    results::IS.Results;
    variable_keys::Vector{T} = PSI.list_variable_keys(results),
) where {T <: PSI.OptimizationContainerKey}
    filter_keys = Vector{PSI.OptimizationContainerKey}()
    for k in variable_keys
        if PSI.get_component_type(k) <: PSY.Storage &&
           PSI.get_entry_type(k) ∈ SUPPORTED_STORAGE_VARIABLES
            push!(filter_keys, k)
        end
    end
    return filter_keys
end

function get_source_variable_keys(
    results::IS.Results;
    variable_keys::Vector{T} = PSI.list_variable_keys(results),
) where {T <: PSI.OptimizationContainerKey}
    filter_keys = Vector{PSI.OptimizationContainerKey}()
    for k in variable_keys
        if PSI.get_component_type(k) <: PSY.Source &&
           PSI.get_entry_type(k) ∈ SUPPORTED_SOURCE_VARIABLES
            push!(filter_keys, k)
        end
    end
    return filter_keys
end

function get_source_parameter_keys(
    results::IS.Results;
    parameter_keys::Vector{T} = PSI.list_parameter_keys(results),
) where {T <: PSI.OptimizationContainerKey}
    filter_keys = Vector{PSI.OptimizationContainerKey}()
    for k in parameter_keys
        if PSI.get_component_type(k) <: PSY.Source &&
           PSI.get_entry_type(k) ∈ SUPPORTED_SOURCE_PARAMETERS
            push!(filter_keys, k)
        end
    end
    return filter_keys
end

function get_generation_parameter_keys(
    results::IS.Results;
    parameter_keys::Vector{T} = PSI.list_parameter_keys(results),
) where {T <: PSI.OptimizationContainerKey}
    filter_keys = Vector{PSI.OptimizationContainerKey}()
    for k in parameter_keys
        if PSI.get_component_type(k) <: PSY.Generator &&
           PSI.get_entry_type(k) == PSI.ActivePowerTimeSeriesParameter
            push!(filter_keys, k)
        end
    end
    return filter_keys
end

function get_generation_aux_variable_keys(
    results::IS.Results;
    aux_variable_keys::Vector{T} = PSI.list_aux_variable_keys(results),
) where {T <: PSI.OptimizationContainerKey}
    # TODO: add slacks
    filter_keys = Vector{PSI.OptimizationContainerKey}()
    for k in aux_variable_keys
        if PSI.get_component_type(k) <: PSY.Generator &&
           PSI.get_entry_type(k) == PSI.PowerOutput
            push!(filter_keys, k)
        end
    end
    return filter_keys
end

function get_load_aux_variable_keys(
    results::IS.Results;
    aux_variable_keys::Vector{T} = PSI.list_aux_variable_keys(results),
) where {T <: PSI.OptimizationContainerKey}
    # TODO: add slacks
    filter_keys = Vector{PSI.OptimizationContainerKey}()
    for k in aux_variable_keys
        if PSI.get_component_type(k) <: PSY.ElectricLoad &&
           PSI.get_entry_type(k) == PSI.PowerOutput
            push!(filter_keys, k)
        end
    end
    return filter_keys
end

#### Load Names ####
function get_load_variable_keys(
    results::IS.Results;
    variable_keys::Vector{T} = PSI.list_variable_keys(results),
) where {T <: PSI.OptimizationContainerKey}
    filter_keys = Vector{PSI.OptimizationContainerKey}()
    for k in variable_keys
        if PSI.get_component_type(k) <: PSY.ElectricLoad &&
           PSI.get_entry_type(k) ∈ SUPPORTED_LOAD_VARIABLES
            push!(filter_keys, k)
        end
    end
    return filter_keys
end

function get_load_parameter_keys(
    results::IS.Results;
    parameter_keys::Vector{T} = PSI.list_parameter_keys(results),
) where {T <: PSI.OptimizationContainerKey}
    filter_keys = Vector{PSI.OptimizationContainerKey}()
    for k in parameter_keys
        if PSI.get_component_type(k) <: PSY.ElectricLoad &&
           PSI.get_entry_type(k) == PSI.ActivePowerTimeSeriesParameter
            push!(filter_keys, k)
        end
    end

    return filter_keys
end

#### Service Names ####
function get_service_variable_keys(
    results::IS.Results;
    variable_keys::Vector{T} = PSI.list_variable_keys(results),
) where {T <: PSI.OptimizationContainerKey}
    filter_keys = Vector{PSI.OptimizationContainerKey}()
    for k in variable_keys
        if PSI.get_component_type(k) <: PSY.Service &&
           PSI.get_entry_type(k) ∈ SUPPORTED_SERVICE_VARIABLES
            push!(filter_keys, k)
        end
    end
    return filter_keys
end

function get_service_parameter_names(
    results::IS.Results;
    parameter_keys::Vector{T} = PSI.list_parameter_keys(results),
) where {T <: PSI.OptimizationContainerKey}
    filter_keys = Vector{PSI.OptimizationContainerKey}()
    for k in parameter_keys
        if PSI.get_component_type(k) <: PSY.ElectricLoad &&
           PSI.get_entry_type(k) == PSI.RequirementTimeSeriesParameter
            push!(filter_keys, k)
        end
    end

    return filter_keys
end

"""
Return a copy of `df` with the `DateTime` column removed when present.

Useful before arithmetic or aggregation on result tables that still carry timestamps.
"""
no_datetime(df::DataFrames.DataFrame) = df[:, propertynames(df) .!== :DateTime]

function add_fixed_parameters!(
    variables::Dict{V, DataFrames.DataFrame},
    parameters::Dict{P, DataFrames.DataFrame},
) where {V <: PSI.OptimizationContainerKey, P <: PSI.OptimizationContainerKey}
    # fixed output should be added to plots when there exists a parameter of the form
    # :P__max_active_power__* but there is no corresponding :P__* variable
    # Snapshot before the loop so that parameters we add during iteration (e.g. the
    # first of two Source parameters) do not falsely block subsequent parameters for
    # the same component type.
    existing_variable_component_types =
        Set(PSI.get_component_type.(keys(variables)))
    for (param_key, param) in parameters
        PSI.get_component_type(param_key) ∈ existing_variable_component_types && continue
        if !haskey(variables, param_key)
            mult =
                any(PSI.get_component_type(param_key) .<: NEGATIVE_PARAMETERS) ? -1.0 : 1.0
            variables[param_key] = param
            variables[param_key][:, propertynames(param) .!== :DateTime] .*= mult
        end
    end
end

function add_aux_variables!(
    variables::Dict{V, DataFrames.DataFrame},
    aux_variables::Dict{A, DataFrames.DataFrame},
) where {V <: PSI.OptimizationContainerKey, A <: PSI.OptimizationContainerKey}
    # fixed output should be added to plots when there exists a parameter of the form
    # :P__max_active_power__* but there is no corresponding :P__* variable
    for (param_key, param) in aux_variables
        PSI.get_component_type(param_key) ∈ PSI.get_component_type.(keys(variables)) &&
            continue
        if !haskey(variables, param_key)
            mult =
                any(PSI.get_component_type(param_key) .<: NEGATIVE_PARAMETERS) ? -1.0 : 1.0
            variables[param_key] = param
            variables[param_key][:, propertynames(param) .!== :DateTime] .*= mult
        end
    end
end

# finds the parameters corresponding to variables for curtailment calculations
function _curtailment_parameters(
    parameter_keys::Vector{PSI.OptimizationContainerKey},
    variable_keys::Vector{PSI.OptimizationContainerKey},
)
    curtailable_parameters = parameter_keys[findall(
        in(SUPPORTED_CURTAILMENT_PARAMETERS),
        PSI.get_entry_type.(parameter_keys),
    )]
    curtailable_variables = variable_keys[findall(
        in(SUPPORTED_CURTAILMENT_VARIABLES),
        PSI.get_entry_type.(variable_keys),
    )]

    curtailment_parameters = Vector{
        NamedTuple{
            (:parameter, :variable),
            Tuple{PSI.OptimizationContainerKey, PSI.OptimizationContainerKey},
        },
    }()
    for pk in curtailable_parameters
        for cv in curtailable_variables[PSI.get_component_type.(
            curtailable_variables,
        ) .== PSI.get_component_type(pk)]
            push!(curtailment_parameters, (parameter = pk, variable = cv))
        end
    end
    return unique(curtailment_parameters)
end

function _filter_curtailment!(
    variable_values::Dict,
    parameter_values::Dict,
    curtailment_parameters::Vector{
        NamedTuple{
            (:parameter, :variable),
            Tuple{PSI.OptimizationContainerKey, PSI.OptimizationContainerKey},
        },
    },
)
    for curtailment in curtailment_parameters
        curtailment_var_key = PSI.VariableKey(
            PSI.get_entry_type(curtailment.variable),
            PSI.get_component_type(curtailment.variable),
            "Curtailment",
        )

        curt =
            parameter_values[curtailment.parameter] .- variable_values[curtailment.variable]
        if haskey(variable_values, curtailment_var_key)
            variable_values[curtailment_var_key] =
                hcat(variable_values[curtailment_var_key], no_datetime(curt))
        else
            variable_values[curtailment_var_key] = curt
        end
    end
end

function _get_components_axis(
    filter_func::Function,
    component_type::Type{T},
    system::PSY.System,
) where {T <: PSY.Component}
    return PSY.get_name.(
        PSY.get_components(filter_func, component_type, system)
    )
end

function _get_components_axis(
    filter_func::Function,
    component_type::Type{<:PSY.Bus},
    system::PSY.System,
)
    buses = PSY.get_components(filter_func, component_type, system)
    # Bus numbers are arbitrary positive identifiers, not 1..N row indices, so
    # they must not be used to index a length-N vector. Return the number
    # strings in component order, matching the generic method's `get_name.`
    # idiom; the caller selects DataFrame columns by name, so order is free.
    return string.(PSY.get_number.(buses))
end

_skip_filtering(::Type{PSY.System}) = true
_skip_filtering(::Type{T}) where {T <: PSY.Component} = false

function filter_results!(
    results_dict::Dict{PSI.OptimizationContainerKey, DataFrames.DataFrame},
    filter_func::Function,
    results::R,
) where {R <: IS.Results}
    for (k, v) in results_dict
        component_type = PSI.get_component_type(k)#getfield(PSY, Symbol(last(split(String(k), "__"))))
        _skip_filtering(component_type) && continue
        component_axis =
            _get_components_axis(filter_func, component_type, PSI.get_system(results))
        DataFrames.select!(v, vcat(["DateTime"], component_axis))
    end
end

function filter_results!(
    results_dict::Dict{PSI.OptimizationContainerKey, DataFrames.DataFrame},
    filter_func::Nothing,
    results::R,
) where {R <: IS.Results} end

"""
Extract generation (and optional storage/source) time series from simulation `results`
into a [`PowerData`](@ref).

Reads active-power variables (and related parameters / aux variables) for injectors,
optionally including storage, sources, and curtailment columns.

# Arguments
 - `results`: an [`InfrastructureSystems.Results`](@extref) object (e.g. from PowerSimulations)

# Keyword Arguments
 - `filter_func::Union{Function, Nothing} = nothing`: component filter applied when
   selecting columns; `nothing` keeps all available components
 - `initial_time` / `start_time`: start of the realized window (default: results metadata)
 - `horizon` / `len`: number of time steps to read
 - `variable_keys`, `parameter_keys`, `aux_variable_keys`: override which optimization
   container keys are considered
 - `curtailment::Bool = true`: include curtailment columns when parameters allow
 - `storage::Bool = true`: include storage injection variables
 - `sources::Bool = true`: include source injection variables and parameters

# Returns
 - [`PowerData`](@ref) with generation-related tables and aligned timestamps

See also [`get_load_data`](@ref), [`get_service_data`](@ref), [`categorize_data`](@ref).
"""
function get_generation_data(
    results::R;
    # aggregation::Union{
    #     Type{PSY.StaticInjection},
    #     Type{PSY.ACBus},
    #     Type{PSY.System},
    #     Type{<:PSY.AggregationTopology},
    # } = PSY.StaticInjection,
    filter_func::Union{Function, Nothing} = nothing,
    kwargs...,
) where {R <: IS.Results}
    initial_time = get(kwargs, :initial_time, get(kwargs, :start_time, nothing))
    len = get(kwargs, :horizon, get(kwargs, :len, nothing))
    variable_keys = get(kwargs, :variable_keys, PSI.list_variable_keys(results))
    parameter_keys = get(kwargs, :parameter_keys, PSI.list_parameter_keys(results))
    aux_variable_keys = get(kwargs, :aux_variable_keys, PSI.list_aux_variable_keys(results))
    curtailment = get(kwargs, :curtailment, true)
    storage = get(kwargs, :storage, true)
    sources = get(kwargs, :sources, true)

    if curtailment && (haskey(kwargs, :variable_keys) || haskey(kwargs, :parameter_keys))
        @warn "Cannot guarantee curtailment calculations with specified keys"
    end

    injection_keys = get_generation_variable_keys(results; variable_keys = variable_keys)
    if storage
        injection_keys = vcat(
            injection_keys,
            get_storage_variable_keys(results; variable_keys = variable_keys),
        )
    end
    if sources
        injection_keys = vcat(
            injection_keys,
            get_source_variable_keys(results; variable_keys = variable_keys),
        )
    end

    parameter_keys = get_generation_parameter_keys(results; parameter_keys = parameter_keys)
    if sources
        parameter_keys = vcat(
            parameter_keys,
            get_source_parameter_keys(
                results;
                parameter_keys = get(
                    kwargs,
                    :parameter_keys,
                    PSI.list_parameter_keys(results),
                ),
            ),
        )
    end

    aux_variable_keys =
        get_generation_aux_variable_keys(results; aux_variable_keys = aux_variable_keys)

    variables = PSI.read_results_with_keys(
        results,
        injection_keys;
        start_time = initial_time,
        len = len,
        table_format = IS.TableFormat.WIDE,
    )
    filter_results!(variables, filter_func, results)

    parameters = PSI.read_results_with_keys(
        results,
        parameter_keys;
        start_time = initial_time,
        len = len,
        table_format = IS.TableFormat.WIDE,
    )
    filter_results!(parameters, filter_func, results)

    aux_variables = PSI.read_results_with_keys(
        results,
        aux_variable_keys;
        start_time = initial_time,
        len = len,
        table_format = IS.TableFormat.WIDE,
    )
    filter_results!(aux_variables, filter_func, results)

    add_fixed_parameters!(variables, parameters)
    add_aux_variables!(variables, aux_variables)

    if curtailment
        curtailment_parameters = _curtailment_parameters(parameter_keys, injection_keys)
        _filter_curtailment!(variables, parameters, curtailment_parameters)
    end

    timestamps = PSI.get_realized_timestamps(results; start_time = initial_time, len = len)
    return PowerData(variables, timestamps)
end

"""
Extract load time series from simulation `results` into a [`PowerData`](@ref).

# Arguments
 - `results`: an [`InfrastructureSystems.Results`](@extref) object

# Keyword Arguments
 - `filter_func::Union{Function, Nothing} = nothing`: component filter for columns
 - `initial_time` / `start_time`: start of the realized window
 - `horizon` / `len`: number of time steps to read
 - `variable_keys`, `parameter_keys`, `aux_variable_keys`: override optimization
   container keys considered for load

# Returns
 - [`PowerData`](@ref) with load tables and aligned timestamps

See also [`get_load_data`](@ref) for a [`PowerSystems.System`](@extref),
[`get_generation_data`](@ref).
"""
function get_load_data(
    results::R;
    filter_func::Union{Function, Nothing} = nothing,
    kwargs...,
) where {R <: IS.Results}
    initial_time = get(kwargs, :initial_time, get(kwargs, :start_time, nothing))
    len = get(kwargs, :horizon, get(kwargs, :len, nothing))
    variable_keys = get(kwargs, :variable_keys, PSI.list_variable_keys(results))
    parameter_keys = get(kwargs, :parameter_keys, PSI.list_parameter_keys(results))
    aux_variable_keys = get(kwargs, :aux_variable_keys, PSI.list_aux_variable_keys(results))

    variable_keys = get_load_variable_keys(results; variable_keys = variable_keys)
    parameter_keys = get_load_parameter_keys(results; parameter_keys = parameter_keys)
    aux_variable_keys =
        get_load_aux_variable_keys(results; aux_variable_keys = aux_variable_keys)

    variables = PSI.read_results_with_keys(
        results,
        variable_keys;
        start_time = initial_time,
        len = len,
        table_format = IS.TableFormat.WIDE,
    )
    filter_results!(variables, filter_func, results)

    parameters = PSI.read_results_with_keys(
        results,
        parameter_keys;
        start_time = initial_time,
        len = len,
        table_format = IS.TableFormat.WIDE,
    )
    filter_results!(parameters, filter_func, results)

    aux_variables = PSI.read_results_with_keys(
        results,
        aux_variable_keys;
        start_time = initial_time,
        len = len,
        table_format = IS.TableFormat.WIDE,
    )
    filter_results!(aux_variables, filter_func, results)

    add_fixed_parameters!(variables, parameters)

    timestamps = PSI.get_realized_timestamps(results; start_time = initial_time, len = len)
    return PowerData(variables, timestamps)
end

################################### INPUT DEMAND #################################

function _get_loads(system::PSY.System, bus::PSY.ACBus)
    return [
        load for load in PSY.get_components(PSY.get_available, PSY.StaticLoad, system) if
        PSY.get_bus(load) == bus
    ]
end
function _get_loads(system::PSY.System, agg::T) where {T <: PSY.AggregationTopology}
    return PSY.get_components_in_aggregation_topology(PSY.StaticLoad, system, agg)
end
function _get_loads(system::PSY.System, load::PSY.StaticLoad)
    return [load]
end
function _get_loads(system::PSY.System, sys::PSY.System)
    return PSY.get_components(PSY.get_available, PSY.StaticLoad, system)
end

get_base_power(system::PSY.System) = PSY.get_base_power(system)
get_base_power(results::IS.Results) = IS.get_base_power(results)

"""
Build load forecast [`PowerData`](@ref) from a [`PowerSystems.System`](@extref)
(no simulation results required).

Uses deterministic `max_active_power` time series on static loads, grouped by
`aggregation`.

# Arguments
 - `system`: system containing load components and forecasts

# Keyword Arguments
 - `aggregation`: grouping type — `StaticLoad` (default), `ACBus`, `System`, or an
   `AggregationTopology` subtype (e.g. `Area`)
 - `horizon`: forecast horizon (period or step count; default: system forecast horizon)
 - `initial_time`: forecast window start (default: system forecast initial timestamp)

# Returns
 - [`PowerData`](@ref) whose `data` keys are aggregation names and whose values are
   load forecast tables

See also [`get_load_data`](@ref) for [`InfrastructureSystems.Results`](@extref).
"""
function get_load_data(
    system::PSY.System;
    aggregation::Union{
        Type{<:PSY.StaticLoad},
        Type{PSY.ACBus},
        Type{PSY.System},
        Type{<:PSY.AggregationTopology},
    } = PSY.StaticLoad,
    kwargs...,
)
    aggregation_components =
        aggregation == PSY.System ? [system] : PSY.get_components(aggregation, system)
    if isempty(aggregation_components)
        throw(ArgumentError("System does not have type $aggregation."))
    end
    horizon = get(kwargs, :horizon, PSY.get_forecast_horizon(system))
    initial_time = get(kwargs, :initial_time, PSY.get_forecast_initial_timestamp(system))
    parameters = Dict{Symbol, DataFrames.DataFrame}()
    PSY.set_units_base_system!(system, "SYSTEM_BASE")
    resolution = nothing
    len = nothing
    for agg in aggregation_components
        loads = _get_loads(system, agg)
        length(loads) == 0 && continue
        colname = aggregation == PSY.System ? "System" : PSY.get_name(agg)
        load_values = DataFrames.DataFrame()
        for load in loads
            # TODO awaiting methods in PSY to make this simpler
            keys = filter(
                key ->
                    PSY.get_time_series_type(key) <: PSY.AbstractDeterministic &&
                        PSY.get_name(key) == "max_active_power",
                PSY.get_time_series_keys(load),
            )
            @assert length(keys) == 1
            my_resolution = first(keys).resolution
            if isnothing(resolution)
                resolution = my_resolution
                len = (horizon isa Dates.Period) ? Int64(horizon / resolution) : horizon
            else
                (resolution != my_resolution) &&
                    throw(error("Load time series have mismatched resolutions"))
            end

            f = PSY.get_time_series_values( # TODO: this isn't applying the scaling factors
                PSY.Deterministic,
                load,
                "max_active_power";
                start_time = initial_time,
                len = len,
            )
            load_values[:, PSY.get_name(load)] = f
        end
        parameters[Symbol(colname)] = load_values
    end
    time_range = if isnothing(len)
        Dates.DateTime[]
    else
        collect(range(initial_time; step = resolution, length = len))
    end

    return PowerData(parameters, time_range)
end

"""
Extract ancillary-service variable time series from `results` into a [`PowerData`](@ref).

# Arguments
 - `results`: an [`InfrastructureSystems.Results`](@extref) object

# Keyword Arguments
 - `filter_func::Union{Function, Nothing} = nothing`: component filter for columns
 - `initial_time` / `start_time`: start of the realized window
 - `horizon` / `len`: number of time steps to read
 - `variable_keys`: override which service variable keys are read

# Returns
 - [`PowerData`](@ref) with service tables and aligned timestamps

See also [`get_generation_data`](@ref), [`get_load_data`](@ref).
"""
function get_service_data(
    results::R;
    filter_func::Union{Function, Nothing} = nothing,
    kwargs...,
) where {R <: IS.Results}
    initial_time = get(kwargs, :initial_time, get(kwargs, :start_time, nothing))
    len = get(kwargs, :horizon, get(kwargs, :len, nothing))
    variable_keys = get(kwargs, :variable_keys, PSI.list_variable_keys(results))
    #parameter_keys = get(kwargs, :parameter_keys, PSI.list_parameter_keys(results))

    variable_keys = get_service_variable_keys(results; variable_keys = variable_keys)

    variables = PSI.read_results_with_keys(
        results,
        variable_keys;
        start_time = initial_time,
        len = len,
        table_format = IS.TableFormat.WIDE,
    )
    filter_results!(variables, filter_func, results)

    timestamps = PSI.get_realized_timestamps(results; start_time = initial_time, len = len)

    return PowerData(variables, timestamps)
end

#### result combination and aggregation ####

"""
Aggregate each category DataFrame in `data` to a single column and horizontally
combine them into one DataFrame.

# Arguments
 - `data`: dictionary of category name => wide DataFrame (as in [`PowerData`](@ref).data)

# Keyword Arguments
 - `names`: category order (default: `keys(data)`)
 - `aggregate`: row-wise aggregator applied to each matrix (default: sum over columns)

# Example

```julia
combine_categories(gen_uc.data)
```

See also [`categorize_data`](@ref).
"""
function combine_categories(
    data::Union{Dict{Symbol, DataFrames.DataFrame}, Dict{String, DataFrames.DataFrame}};
    names::Union{Vector{String}, Vector{Symbol}, Nothing} = nothing,
    aggregate::Union{Function, Nothing} = nothing,
)
    aggregate = isnothing(aggregate) ? x -> sum(x; dims = 2) : aggregate
    names = isnothing(names) ? keys(data) : names
    values = []
    keep_names = []
    for k in names
        if !isempty(data[k])
            push!(values, aggregate(Matrix(no_datetime(data[k]))))
            push!(keep_names, k)
        end
    end
    data = hcat(values...)
    keep_names = string.(keep_names)
    isempty(data) && return DataFrames.DataFrame()
    return DataFrames.DataFrame(data, keep_names)
end

"""
Re-group [`PowerData`](@ref) tables by an aggregation dictionary (e.g. fuel categories).

Makes no guarantee of complete data collection for components missing from
`aggregation`.

# Arguments
 - `data`: dictionary of variable-key symbol => wide DataFrame (typically
   `get_generation_data(...).data`)
 - `aggregation`: map from category name to generator `(type, name)` pairs, as from
   [`make_fuel_dictionary`](@ref)

# Keyword Arguments
 - `curtailment::Bool = true`: include curtailment columns when present
 - `slacks::Bool = true`: include slack variables when present

# Example

```julia
aggregation = make_fuel_dictionary(sys)
categorize_data(gen.data, aggregation)
```

See also [`combine_categories`](@ref), [`make_fuel_dictionary`](@ref).
"""
function categorize_data(
    data::Dict{Symbol, DataFrames.DataFrame},
    aggregation::Dict;
    curtailment = true,
    slacks = true,
)
    category_dataframes = Dict{String, DataFrames.DataFrame}()
    split_power_component_types = Set{String}()

    var_types = Dict{String, Symbol}()
    for k in keys(data)
        keystring = string(k)
        device_type_string = last(split(keystring, "__"))
        if occursin("ActivePowerInVariable", keystring) ||
           occursin("ActivePowerOutVariable", keystring) ||
           occursin("ActivePowerInTimeSeriesParameter", keystring) ||
           occursin("ActivePowerOutTimeSeriesParameter", keystring)
            push!(split_power_component_types, device_type_string)
            continue
        end
        var_types[device_type_string] = k
    end

    # Categories that contain a split-power component type (e.g. storage, which
    # reports separate ActivePowerIn/OutVariable) are emitted as "<category> In"
    # and "<category> Out" instead of a single combined category. Keep the
    # original key type so `aggregation[category]` works even if `aggregation`
    # is keyed by something other than `String`; we stringify only at write time.
    split_categories = Set{keytype(aggregation)}()
    for (category, list) in aggregation
        if any(
            component_type in split_power_component_types for (component_type, _) in list
        )
            push!(split_categories, category)
        end
    end

    # Non-split components: one column per component under the original category.
    # Split-power components are skipped here and handled by the In/Out pass below.
    for (category, list) in aggregation
        category_df = DataFrames.DataFrame()
        for (component_type, component_name) in list
            component_type in split_power_component_types && continue
            haskey(var_types, component_type) || continue
            category_data = data[var_types[component_type]]
            colname =
                if typeof(names(category_data)[1]) == String
                    "$component_name"
                else
                    component_name
                end
            DataFrames.insertcols!(
                category_df,
                (colname => category_data[:, colname]);
                makeunique = true,
            )
        end
        if !isempty(category_df)
            category_dataframes[string(category)] = category_df
        end
    end

    # Split pass: discharging (ActivePowerOutVariable) is generation (+),
    # charging (ActivePowerInVariable) is load (-).
    # ActivePowerInTimeSeriesParameter is already negative (its multiplier is
    # active_power_limits.min, which is negative), so no sign flip is needed for it.
    for category in split_categories
        list = aggregation[category]
        for (suffix, variable_prefix_sign_pairs) in (
            (
                "Out",
                [
                    ("ActivePowerOutVariable", 1.0),
                    ("ActivePowerOutTimeSeriesParameter", 1.0),
                ],
            ),
            (
                "In",
                [
                    ("ActivePowerInVariable", -1.0),
                    ("ActivePowerInTimeSeriesParameter", 1.0),
                ],
            ),
        )
            split_df = DataFrames.DataFrame()
            for (component_type, component_name) in list
                component_type in split_power_component_types || continue
                for (variable_prefix, sign) in variable_prefix_sign_pairs
                    key = Symbol(variable_prefix * "__" * component_type)
                    haskey(data, key) || continue
                    component_data = data[key]
                    colname =
                        if typeof(names(component_data)[1]) == String
                            "$component_name"
                        else
                            component_name
                        end
                    string(colname) in names(component_data) || continue
                    DataFrames.insertcols!(
                        split_df,
                        (colname => sign .* component_data[:, colname]);
                        makeunique = true,
                    )
                end
            end
            if !isempty(split_df)
                category_dataframes["$category $suffix"] = split_df
            end
        end
    end

    if curtailment
        dfs = []
        for (key, val) in data
            if endswith(string(key), "Curtailment")
                push!(dfs, no_datetime(val))
            end
        end
        if !isempty(dfs)
            category_dataframes["Curtailment"] = hcat(dfs...)
        end
    end
    if slacks
        data_keys = collect(keys(data))
        for (slack, slack_name) in BALANCE_SLACKVARS
            ids =
                findall(x -> occursin(string(nameof(slack)), x), string.(data_keys))
            isempty(ids) && continue
            if length(ids) == 1
                # Single match: pass the original DataFrame through unchanged.
                category_dataframes[slack_name] = data[data_keys[ids[1]]]
            else
                # Multiple matching keys: concatenate them instead of letting
                # each iteration overwrite the previous (only the first keeps
                # its DateTime column to avoid duplicates).
                first_df = data[data_keys[ids[1]]]
                rest = [no_datetime(data[data_keys[i]]) for i in ids[2:end]]
                category_dataframes[slack_name] =
                    hcat(first_df, rest...; makeunique = true)
            end
        end
    end

    return category_dataframes
end
