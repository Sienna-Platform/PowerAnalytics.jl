const _LF_TIMESTAMPS = [Dates.DateTime(2024, 1, 1) + Dates.Hour(i) for i in 0:3]
const _LF_KEY = IOM.ParameterKey(IOM.ActivePowerTimeSeriesParameter, PowerLoad)
const _LF_VALUES = [10.0, 20.0, 30.0, 40.0]

"An `IOM.OptimizationProblemOutputs` for `sys` with `IOM.ActivePowerTimeSeriesParameter` data
populated for `comp_name`, mirroring `test_realized_outputs.jl`'s long-format construction.
`calc_active_power_forecast` reads parameters by name, so the metadata must map the encoded
name back to the stored key, as a real model-produced store would."
function _make_load_forecast_test_outputs(sys::PSY.System, comp_name::String)
    long_df = DataFrame(
        "name" => fill(comp_name, length(_LF_TIMESTAMPS)),
        "time_index" => 1:length(_LF_TIMESTAMPS),
        "value" => _LF_VALUES,
    )
    metadata = IOM.OptimizationContainerMetadata()
    IOM.add_container_key!(metadata, IOM.encode_key_as_string(_LF_KEY), _LF_KEY)
    return IOM.OptimizationProblemOutputs(
        100.0,
        _LF_TIMESTAMPS,
        sys,
        IS.get_uuid(sys),
        Dict{IOM.AuxVarKey, DataFrame}(),
        Dict{IOM.VariableKey, DataFrame}(),
        Dict{IOM.ConstraintKey, DataFrame}(),
        Dict(_LF_KEY => long_df),
        Dict{IOM.ExpressionKey, DataFrame}(),
        DataFrame(),
        metadata,
        "TestModel",
        "",
        "",
    )
end

test_lf_sys = PSB.build_system(PSB.PSITestSystems, "c_sys5_all_components")
test_lf_comp = PSY.get_component(PowerLoad, test_lf_sys, "Bus2")
test_lf_selector = make_selector(test_lf_comp)

"A duplicate parameter type sharing `IOM.ActivePowerTimeSeriesParameter`'s name but not its
identity, standing in for `PowerOperationsModels`'s own type of the same name -- the exact
defect `ParameterName` fixes."
module _MockPOMParameters
import InfrastructureOptimizationModels as IOM
struct ActivePowerTimeSeriesParameter <: IOM.ParameterType end
end

const _POM_LF_KEY =
    IOM.ParameterKey(_MockPOMParameters.ActivePowerTimeSeriesParameter, PowerLoad)

"An outputs object whose active-power forecast parameter is stored under a type distinct
from `IOM.ActivePowerTimeSeriesParameter` but with the same name, as `PowerOperationsModels`
would produce. Only a name-based read can find it; a type-based read against `IOM`'s type
would throw."
function _make_pom_style_load_forecast_test_outputs(sys::PSY.System, comp_name::String)
    long_df = DataFrame(
        "name" => fill(comp_name, length(_LF_TIMESTAMPS)),
        "time_index" => 1:length(_LF_TIMESTAMPS),
        "value" => _LF_VALUES,
    )
    metadata = IOM.OptimizationContainerMetadata()
    IOM.add_container_key!(metadata, IOM.encode_key_as_string(_POM_LF_KEY), _POM_LF_KEY)
    return IOM.OptimizationProblemOutputs(
        100.0,
        _LF_TIMESTAMPS,
        sys,
        IS.get_uuid(sys),
        Dict{IOM.AuxVarKey, DataFrame}(),
        Dict{IOM.VariableKey, DataFrame}(),
        Dict{IOM.ConstraintKey, DataFrame}(),
        Dict(_POM_LF_KEY => long_df),
        Dict{IOM.ExpressionKey, DataFrame}(),
        DataFrame(),
        metadata,
        "TestModel",
        "",
        "",
    )
end

@testset "calc_load_forecast accepts and honours start_time/len kwargs (regression)" begin
    outputs = _make_load_forecast_test_outputs(test_lf_sys, "Bus2")

    computed_all = compute(calc_load_forecast, outputs, test_lf_selector)
    @test size(computed_all, 1) == length(_LF_TIMESTAMPS)
    @test get_data_vec(computed_all) == -1 .* _LF_VALUES

    test_len = 2
    computed_short = compute(calc_load_forecast, outputs, test_lf_selector; len = test_len)
    @test size(computed_short, 1) == test_len
    @test get_data_vec(computed_short) == -1 .* _LF_VALUES[1:test_len]

    test_start_time = _LF_TIMESTAMPS[2]
    computed_offset = compute(calc_load_forecast, outputs, test_lf_selector;
        start_time = test_start_time, len = test_len)
    @test computed_offset[1, DATETIME_COL] == test_start_time
    @test size(computed_offset, 1) == test_len
    @test get_data_vec(computed_offset) == -1 .* _LF_VALUES[2:(1 + test_len)]
end

@testset "ParameterName round-trips a component's column" begin
    outputs = _make_pom_style_load_forecast_test_outputs(test_lf_sys, "Bus2")
    key = PowerAnalytics.ParameterName("ActivePowerTimeSeriesParameter")
    df = read_component_output(outputs, key, test_lf_comp)
    @test df[!, "Bus2"] == _LF_VALUES
end

@testset "calc_active_power_forecast reads a parameter type distinct from IOM's (regression)" begin
    outputs = _make_pom_style_load_forecast_test_outputs(test_lf_sys, "Bus2")

    computed = compute(calc_active_power_forecast, outputs, test_lf_selector)
    @test get_data_vec(computed) == _LF_VALUES

    computed_load = compute(calc_load_forecast, outputs, test_lf_selector)
    @test get_data_vec(computed_load) == -1 .* _LF_VALUES
end
