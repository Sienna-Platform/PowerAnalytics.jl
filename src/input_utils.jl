# READING KEYS FROM OUTPUTS
"Name of the column that represents the time axis in computed DataFrames. Currently equal to `\"$DATETIME_COL\"`."
const DATETIME_COL = "DateTime"

"Name of a column that represents whole-of-`System` data. Currently equal to `\"$SYSTEM_COL\"`."
const SYSTEM_COL = "System"

"The key entry types that can be paired with a `System` rather than a `Component`"
const SystemEntryType = Union{IOM.VariableType, IOM.ExpressionType}

"""
Create an `IOM.OptimizationContainerKey` from the given key entry type and component.

The entry types all descend from `IS.Optimization.OptimizationKeyType`. There is no
`ConstraintType` method because PowerAnalytics does not read duals.

# Arguments
 - `entry`: the key entry type
 - `component` (`::Type{<:Union{Component, PSY.System}}` or `::Type{<:Component}` depending
   on the key type): the component type
"""
function make_key end
make_key(entry::Type{<:IOM.VariableType}, component::Type{<:Union{Component, PSY.System}}) =
    IOM.VariableKey(entry, component)
make_key(entry::Type{<:IOM.ExpressionType}, comp::Type{<:Union{Component, PSY.System}}) =
    IOM.ExpressionKey(entry, comp)
make_key(entry::Type{<:IOM.ParameterType}, component::Type{<:Component}) =
    IOM.ParameterKey(entry, component)
make_key(entry::Type{<:IOM.AuxVariableType}, component::Type{<:Component}) =
    IOM.AuxVarKey(entry, component)
make_key(entry::Type{<:IOM.InitialConditionType}, component::Type{<:Component}) =
    IOM.InitialConditionKey(entry, component)

"""
An output variable named by its entry-type name rather than by the type itself.

PowerAnalytics reads outputs produced by packages it does not depend on — the power
variables live in PowerOperationsModels — so those entries are named, not typed. Give the
bare entry name, e.g. `VariableName("ActivePowerVariable")`; the component type is appended
at read time to form the encoded key the outputs store uses.

See also: [`AuxVariableName`](@ref)
"""
struct VariableName
    name::String
end

"""
An output auxiliary variable named by its entry-type name rather than by the type itself.

See also: [`VariableName`](@ref)
"""
struct AuxVariableName
    name::String
end

"""
An output parameter named by its entry-type name rather than by the type itself.

See also: [`VariableName`](@ref)
"""
struct ParameterName
    name::String
end

get_name(key::VariableName) = key.name
get_name(key::AuxVariableName) = key.name
get_name(key::ParameterName) = key.name

"Compose the encoded key string the outputs store uses for a named entry."
_encode(key::Union{VariableName, AuxVariableName, ParameterName}, ::Type{T}) where {T} =
    key.name * COMPONENT_NAME_DELIMITER * string(nameof(T))

_with_name(::VariableName, encoded::String) = VariableName(encoded)
_with_name(::AuxVariableName, encoded::String) = AuxVariableName(encoded)
_with_name(::ParameterName, encoded::String) = ParameterName(encoded)

"""
The single boundary between PowerAnalytics and an optimization outputs container.

To support a new outputs type — a future simulation-outputs type, for instance — add a
method here. Nothing in the metrics layer needs to change.

Returns a wide DataFrame: a `$DATETIME_COL` column plus one column per component.
"""
function read_key_wide end

function read_key_wide(
    outputs::IOM.OptimizationProblemOutputs,
    key::IOM.OptimizationContainerKey;
    start_time::Union{Nothing, DateTime} = nothing,
    len::Union{Int, Nothing} = nothing,
)
    return only(
        values(
            IOM.read_outputs_with_keys(
                outputs,
                [key];
                start_time = start_time,
                len = len,
                table_format = IS.TableFormat.WIDE,
            ),
        ),
    )
end

"""
Fallback for any `IS.Outputs` that isn't `IOM.OptimizationProblemOutputs` (a PowerSimulations
`Simulation`'s per-problem results, for instance): reduce the typed key to its encoded name
and re-dispatch through the `VariableName`/`AuxVariableName`/`ParameterName` methods below.
This is what lets PowerAnalytics read from such a results type without PowerAnalytics
depending on it — the type only needs to implement `IOM.read_variable`/`read_aux_variable`/
`read_parameter` by name, which every `IS.Outputs` results type is expected to.

Not ambiguous with the `OptimizationProblemOutputs` method above: both take
`::IOM.OptimizationContainerKey` for the second argument, so the two differ only in the
first, where `OptimizationProblemOutputs <: IS.Outputs` totally orders them.
"""
function read_key_wide(
    outputs::IS.Outputs,
    key::IOM.OptimizationContainerKey;
    start_time::Union{Nothing, DateTime} = nothing,
    len::Union{Int, Nothing} = nothing,
)
    encoded = IOM.encode_key_as_string(key)
    named_key = _as_named_key(key, encoded)
    return read_key_wide(outputs, named_key; start_time = start_time, len = len)
end

_as_named_key(::IOM.VariableKey, encoded::String) = VariableName(encoded)
_as_named_key(::IOM.AuxVarKey, encoded::String) = AuxVariableName(encoded)
_as_named_key(::IOM.ParameterKey, encoded::String) = ParameterName(encoded)
_as_named_key(key::IOM.OptimizationContainerKey, ::String) = error(
    "No named-key equivalent for $(typeof(key)) is defined, so it cannot be read from an " *
    "outputs type other than IOM.OptimizationProblemOutputs. Add a `VariableName`-style " *
    "wrapper and a `_as_named_key` method for it if this entry type needs to be readable " *
    "from other results types.",
)

"""
Reduce a `read_variable`/`read_aux_variable`/`read_parameter` result to one flat wide
`DataFrame`, honoring `read_key_wide`'s own contract regardless of outputs type.

Most outputs types already return that shape directly. Some (a rolling-horizon
`Simulation`'s per-problem results, for instance) instead return a per-window
`SortedDict{DateTime,DataFrame}` under `TableFormat.WIDE`, because consecutive windows
overlap and only each window's non-overlapping prefix is realized — narrow, per-window data
that `read_key_wide` has historically just handed back as-is, breaking every caller that
expects the one-DataFrame contract. Stitch it down to the realized time series here instead
of pushing that reshaping onto every caller.
"""
_make_wide(raw::DataFrame, outputs::IS.Outputs, start_time, len) = raw
_make_wide(raw, outputs::IS.Outputs, start_time, len) = IOM.make_realized_dataframe(
    raw,
    IOM.get_realized_timestamps(outputs; start_time = start_time, len = len),
)

read_key_wide(
    outputs::IS.Outputs,
    key::VariableName;
    start_time::Union{Nothing, DateTime} = nothing,
    len::Union{Int, Nothing} = nothing,
) = _make_wide(
    IOM.read_variable(
        outputs,
        key.name;
        start_time = start_time,
        len = len,
        table_format = IS.TableFormat.WIDE,
    ),
    outputs,
    start_time,
    len,
)

read_key_wide(
    outputs::IS.Outputs,
    key::AuxVariableName;
    start_time::Union{Nothing, DateTime} = nothing,
    len::Union{Int, Nothing} = nothing,
) = _make_wide(
    IOM.read_aux_variable(
        outputs,
        key.name;
        start_time = start_time,
        len = len,
        table_format = IS.TableFormat.WIDE,
    ),
    outputs,
    start_time,
    len,
)

read_key_wide(
    outputs::IS.Outputs,
    key::ParameterName;
    start_time::Union{Nothing, DateTime} = nothing,
    len::Union{Int, Nothing} = nothing,
) = _make_wide(
    IOM.read_parameter(
        outputs,
        key.name;
        start_time = start_time,
        len = len,
        table_format = IS.TableFormat.WIDE,
    ),
    outputs,
    start_time,
    len,
)

"Build the key that fetches `entry` for a component of type `T`."
_component_key(entry::Type, ::Type{T}) where {T <: Component} = make_key(entry, T)
_component_key(
    entry::Union{VariableName, AuxVariableName, ParameterName},
    ::Type{T},
) where {T <: Component} =
    _with_name(entry, _encode(entry, T))

"Build the key that fetches a `System`-keyed `entry`."
_system_key(entry::Type) = make_key(entry, PSY.System)
_system_key(entry::Union{VariableName, AuxVariableName, ParameterName}) =
    _with_name(entry, _encode(entry, PSY.System))

"Human-readable form of a key or named key, for error messages."
_key_label(key::IOM.OptimizationContainerKey) = IOM.encode_key_as_string(key)
_key_label(key::Union{VariableName, AuxVariableName, ParameterName}) = key.name
_key_label(entry::Type) = string(nameof(entry))

"Pull `comp`'s column out of a wide output frame, erroring with context when it is absent."
function _select_component_column(df::DataFrame, comp::Component, entry)
    name = get_name(comp)
    if !(name in names(df))
        throw(
            NoOutputError(
                "$name is not in the outputs for $(_key_label(entry)); " *
                "available columns are $(names(df))",
            ),
        )
    end
    return df[!, [DATETIME_COL, name]]
end

"""
Fetch one `Component`'s column of raw model outputs.

`entry` is either an entry type PowerAnalytics can name directly (an `IOM` variable,
parameter, expression, or auxiliary-variable type) or a [`VariableName`](@ref) /
[`AuxVariableName`](@ref) / [`ParameterName`](@ref) for entries defined in packages
PowerAnalytics does not depend on.
"""
function read_component_output(
    outputs::IS.Outputs,
    entry,
    comp::Component;
    start_time::Union{Nothing, DateTime} = nothing,
    len::Union{Int, Nothing} = nothing,
)
    key = _component_key(entry, typeof(comp))
    df = read_key_wide(outputs, key; start_time = start_time, len = len)
    return _select_component_column(df, comp, entry)
end

"""
Fetch one component's column from a `PSY.System`-keyed entry.

The model's index set decides the columns — reference buses under the bus-balance network
models, `PSY.Area` under the area ones — so `comp` must be one of them. A `System`-keyed
entry carries one column per index member, not a single system-wide column.
"""
function read_system_indexed_output(
    outputs::IS.Outputs,
    entry,
    comp::Component;
    start_time::Union{Nothing, DateTime} = nothing,
    len::Union{Int, Nothing} = nothing,
)
    key = _system_key(entry)
    df = read_key_wide(outputs, key; start_time = start_time, len = len)
    return _select_component_column(df, comp, entry)
end
