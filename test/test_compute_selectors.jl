const _CS_TIMESTAMPS = [Dates.DateTime(2024, 1, 1) + Dates.Hour(i) for i in 0:3]

"An `IOM.OptimizationProblemOutputs` for `sys`, with `sys` attached directly as `source_data`.
Simpler than `test_load_outputs.jl`'s helper, which round-trips through serialize/reload to
test that path specifically; here we only need a system attached, so we skip the round trip."
function _make_selector_test_outputs(sys::PSY.System)
    return IOM.OptimizationProblemOutputs(
        100.0,
        _CS_TIMESTAMPS,
        sys,
        PSY.get_system_uuid(sys),
        Dict{IOM.AuxVarKey, DataFrame}(),
        Dict{IOM.VariableKey, DataFrame}(),
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

test_cs_sys = PSB.build_system(PSB.PSITestSystems, "c_sys5_all_components")

"A `ComponentTimedMetric` whose value is constant per component, so tests can exercise
selector resolution through `compute` without any solved model data."
const _test_constant_metric = ComponentTimedMetric(;
    name = "TestConstant",
    eval_fn = (res::IS.Outputs, comp::Component;
        start_time::Union{Nothing, Dates.DateTime} = nothing,
        len::Union{Int, Nothing} = nothing) ->
        DataFrame(
            DATETIME_COL => _CS_TIMESTAMPS,
            get_name(comp) => fill(1.0, length(_CS_TIMESTAMPS)),
        ),
)

@testset "get_groups/get_components/get_component still resolve against a PSY.System (regression)" begin
    name_and_type = component -> (typeof(component), get_name(component))
    expected_load_names =
        Set([(PowerLoad, "Bus2"), (PowerLoad, "Bus4"), (StandardLoad, "Bus3")])

    @test Set(name_and_type.(PowerAnalytics.get_components(all_loads, test_cs_sys))) ==
          expected_load_names
    @test Set(PowerAnalytics.get_groups(categorized_generators, test_cs_sys)) ==
          Set(values(generator_categories))

    one_load = first(PowerAnalytics.get_components(all_loads, test_cs_sys))
    load_selector = make_selector(one_load)
    @test PowerAnalytics.get_component(load_selector, test_cs_sys) === one_load
end

@testset "compute resolves a grouped selector against an IS.Outputs, one column per group" begin
    outputs = _make_selector_test_outputs(test_cs_sys)
    computed = compute(_test_constant_metric, outputs, categorized_generators)
    expected_cols = Set(vcat(DATETIME_COL, collect(keys(generator_categories))))
    @test Set(names(computed)) == expected_cols
end

@testset "get_components(selector, outputs) resolves against an IS.Outputs" begin
    outputs = _make_selector_test_outputs(test_cs_sys)
    name_and_type = component -> (typeof(component), get_name(component))
    expected_load_names =
        Set([(PowerLoad, "Bus2"), (PowerLoad, "Bus4"), (StandardLoad, "Bus3")])

    @test Set(name_and_type.(PowerAnalytics.get_components(all_loads, outputs))) ==
          expected_load_names
end
