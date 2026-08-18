# REALIZED OUTPUTS
"""
The single boundary between PowerAnalytics and a model's notion of "realized" timestamps.

In a sequential simulation, chained models' windows overlap, and only a non-overlapping
prefix of each window is realized. psy6 has no simulation layer yet, so for a single
`DecisionModel` every timestamp is realized and this delegates straight to
`IOM.get_realized_timestamps`. To support a future simulation-outputs type, add a method
here — nothing in the layer above changes.
"""
function realized_timestamps end

function realized_timestamps(
    outputs::IS.Outputs;
    start_time::Union{Nothing, DateTime} = nothing,
    len::Union{Int, Nothing} = nothing,
)
    return IOM.get_realized_timestamps(outputs; start_time = start_time, len = len)
end

"""
Read a key wide, then restrict the rows to [`realized_timestamps`](@ref).

`key` takes the same forms `read_key_wide` accepts: an `IOM.OptimizationContainerKey`, a
[`VariableName`](@ref), an [`AuxVariableName`](@ref), or a [`ParameterName`](@ref).

Returns the same wide shape `read_key_wide` returns: a `$DATETIME_COL` column plus one
column per component.
"""
function read_realized_key_wide(
    outputs::IS.Outputs,
    key;
    start_time::Union{Nothing, DateTime} = nothing,
    len::Union{Int, Nothing} = nothing,
)
    df = read_key_wide(outputs, key; start_time = start_time, len = len)
    realized = realized_timestamps(outputs; start_time = start_time, len = len)
    return filter(DATETIME_COL => in(realized), df)
end
