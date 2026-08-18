const _RO_TIMESTAMPS = [Dates.DateTime(2024, 1, 1) + Dates.Hour(i) for i in 0:3]
const _RO_KEY = IOM.VariableKey(IOM.ActivePowerVariable, PSY.ThermalStandard)
const _RO_UUID = Base.UUID("123e4567-e89b-12d3-a456-426614174000")
const _RO_VALUES = [1.0, 2.0, 3.0, 4.0]

"A minimal populated `IOM.OptimizationProblemOutputs`, mirroring `test_load_outputs.jl`.
`variable_values` are stored long-format (`name`/`time_index`/`value`), as `IOM` expects."
function _make_realized_test_outputs()
    long_df = DataFrame(
        "name" => fill("Comp1", length(_RO_TIMESTAMPS)),
        "time_index" => 1:length(_RO_TIMESTAMPS),
        "value" => _RO_VALUES,
    )
    return IOM.OptimizationProblemOutputs(
        100.0,
        _RO_TIMESTAMPS,
        nothing,
        _RO_UUID,
        Dict{IOM.AuxVarKey, DataFrame}(),
        Dict(_RO_KEY => long_df),
        Dict{IOM.ConstraintKey, DataFrame}(),
        Dict{IOM.ParameterKey, DataFrame}(),
        Dict{IOM.ExpressionKey, DataFrame}(),
        DataFrame(),
        IOM.OptimizationContainerMetadata(),
        "TestModel",
        "",
        "",
    )
end

@testset "realized_timestamps is a pass-through for a single model" begin
    outputs = _make_realized_test_outputs()
    @test collect(realized_timestamps(outputs)) == _RO_TIMESTAMPS
end

@testset "read_realized_key_wide matches read_key_wide for a single model" begin
    outputs = _make_realized_test_outputs()
    expected = DataFrame(DATETIME_COL => _RO_TIMESTAMPS, "Comp1" => _RO_VALUES)
    @test PowerAnalytics.read_key_wide(outputs, _RO_KEY) == expected
    @test read_realized_key_wide(outputs, _RO_KEY) == expected
end

"""
A test-local `IS.Outputs` that reports a strict subset of its data as realized, to prove
`realized_timestamps` and `read_realized_key_wide` dispatch on a new outputs type without any
change to PowerAnalytics itself.
"""
struct _FakeRealizedOutputs <: IS.Outputs
    data::DataFrame
    realized::Vector{Dates.DateTime}
end

PowerAnalytics.realized_timestamps(
    outputs::_FakeRealizedOutputs;
    start_time::Union{Nothing, Dates.DateTime} = nothing,
    len::Union{Int, Nothing} = nothing,
) = outputs.realized

IOM.read_variable(outputs::_FakeRealizedOutputs, key::AbstractString; kwargs...) =
    outputs.data

@testset "read_realized_key_wide restricts rows when the seam overrides realized_timestamps" begin
    subset_timestamps = _RO_TIMESTAMPS[1:2]
    data = DataFrame(DATETIME_COL => _RO_TIMESTAMPS, "Comp1" => [10.0, 20.0, 30.0, 40.0])
    outputs = _FakeRealizedOutputs(data, subset_timestamps)

    @test realized_timestamps(outputs) == subset_timestamps

    expected = DataFrame(DATETIME_COL => subset_timestamps, "Comp1" => [10.0, 20.0])
    key = PowerAnalytics.VariableName("ActivePowerVariable__ThermalStandard")
    @test read_realized_key_wide(outputs, key) == expected
end
