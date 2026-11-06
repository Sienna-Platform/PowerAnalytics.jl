using Test, JSON, OpenAPI, TOML, PowerOutputSchemas

const FIXTURES = joinpath(dirname(dirname(@__DIR__)), "test", "fixtures", "outputs")

@testset "valid fixtures decode" begin
    for kind in ("single", "simulation", "power_flow", "security_analysis")
        raw = JSON.parsefile(joinpath(FIXTURES, "valid", kind, "outputs.json"))
        doc = decode(PowerOutputSchemas.OutputsDocument, raw)
        @test string(doc.kind.value) == kind
        @test doc.schema_version == "0.1.0"
        @test decode(PowerOutputSchemas.OutputsDocument, JSON.parse(JSON.json(encode(doc)))) isa PowerOutputSchemas.OutputsDocument
    end
end

@testset "invalid fixtures are rejected by the schema" begin
    for f in readdir(joinpath(FIXTURES, "invalid"))
        f == "invalid_axis_ref.json" && continue
        raw = JSON.parsefile(joinpath(FIXTURES, "invalid", f))
        @test_throws SchemaValidationError decode(PowerOutputSchemas.OutputsDocument, raw)
    end
end

@testset "invalid_axis_ref is schema-valid (rejected at load by PowerAnalytics)" begin
    raw = JSON.parsefile(joinpath(FIXTURES, "invalid", "invalid_axis_ref.json"))
    @test decode(PowerOutputSchemas.OutputsDocument, raw) isa PowerOutputSchemas.OutputsDocument
end

@testset "no Sienna dependency" begin
    deps = keys(TOML.parsefile(joinpath(dirname(@__DIR__), "Project.toml"))["deps"])
    @test isempty(
        intersect(
            deps,
            (
                "InfrastructureSystems",
                "PowerSystems",
                "PowerAnalytics",
                "InfrastructureOptimizationModels",
            ),
        ),
    )
end
