import InfrastructureOptimizationModels as IOM

test_lo_sys = PSB.build_system(PSB.PSITestSystems, "c_sys5_bat")
test_lo_other_sys = PSB.build_system(PSB.PSITestSystems, "c_sys5_all_components")

"A minimal `IOM.OptimizationProblemOutputs` for `sys`, with no variable/parameter data."
function _make_test_outputs(sys::PSY.System)
    timestamps = [Dates.DateTime(2024, 1, 1) + Dates.Hour(i) for i in 0:3]
    return IOM.OptimizationProblemOutputs(
        100.0,
        timestamps,
        nothing,
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

@testset "load_outputs two-argument form attaches a system" begin
    dir = mktempdir(; cleanup = true)
    IOM.serialize_outputs(_make_test_outputs(test_lo_sys), dir)
    out = load_outputs(dir, test_lo_sys)
    @test IS.get_source_data(out) === test_lo_sys
end

@testset "load_outputs two-argument form propagates a UUID mismatch" begin
    dir = mktempdir(; cleanup = true)
    IOM.serialize_outputs(_make_test_outputs(test_lo_sys), dir)
    @test_throws IS.InvalidValue load_outputs(dir, test_lo_other_sys)
end

@testset "load_outputs one-argument form errors without a system bundle" begin
    dir = mktempdir(; cleanup = true)
    IOM.serialize_outputs(_make_test_outputs(test_lo_sys), dir)
    @test_throws ErrorException load_outputs(dir)
end

@testset "load_outputs one-argument form round-trips" begin
    dir = mktempdir(; cleanup = true)
    IOM.serialize_outputs(_make_test_outputs(test_lo_sys), dir)
    system_dir = joinpath(dir, IOM.make_system_dirname(PSY.get_system_uuid(test_lo_sys)))
    PSY.to_file(test_lo_sys, system_dir; unit_system = :device_base)
    out = load_outputs(dir)
    loaded = IS.get_source_data(out)
    # Not a UUID comparison: an OpenAPI bundle is rebuilt with fresh UUIDs, so identity is
    # established by the bundle's location and checked here on content instead.
    @test PSY.get_name(loaded) == PSY.get_name(test_lo_sys)
    @test PSY.get_base_power(loaded) == PSY.get_base_power(test_lo_sys)
    @test length(collect(PSY.get_components(PSY.Component, loaded))) ==
          length(collect(PSY.get_components(PSY.Component, test_lo_sys)))
end
