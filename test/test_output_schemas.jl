import JSON

const SCHEMAS_DIR = joinpath(dirname(@__DIR__), "schemas", "outputs")
const UNITS_JSON =
    joinpath(dirname(dirname(@__DIR__)), "SiennaSchemas", "Core", "units.json")

const SCHEMA_DOCS = Dict{String, Any}(
    f => JSON.parsefile(joinpath(SCHEMAS_DIR, f)) for
    f in readdir(SCHEMAS_DIR) if endswith(f, ".json")
)

@testset "QuantityKind enum is in sync with units.json" begin
    units = JSON.parsefile(UNITS_JSON)
    names = [q["name"] for q in units["quantity_kinds"]]
    common = SCHEMA_DOCS["common.json"]
    @test common["\$defs"]["QuantityKind"]["enum"] == names
end

@testset "quantities.json rows are well formed" begin
    reg = SCHEMA_DOCS["quantities.json"]
    for (name, row) in reg["entries"]
        @test row["unit_system"] in ("COMPONENT_BASE", "NATURAL_UNITS")
        @test (row["unit_system"] == "COMPONENT_BASE") == haskey(row, "base_reference")
        if row["unit_system"] == "COMPONENT_BASE"
            @test row["units"] == "pu"
        end
    end
end

const FIXTURES = joinpath(@__DIR__, "fixtures", "outputs")

@testset "fixture corpus is complete" begin
    valid = readdir(joinpath(FIXTURES, "valid"))
    @test Set(valid) == Set(["single", "simulation", "power_flow", "security_analysis"])
    for d in valid
        @test JSON.parsefile(joinpath(FIXTURES, "valid", d, "outputs.json"))["kind"] == d
    end
end

@testset "PowerAnalytics loads PowerOutputSchemas and the fixtures decode through it" begin
    @test isdefined(PowerAnalytics, :PowerOutputSchemas)
    raw = JSON.parsefile(joinpath(FIXTURES, "valid", "simulation", "outputs.json"))
    doc = PowerAnalytics.PowerOutputSchemas.decode(
        PowerAnalytics.PowerOutputSchemas.OutputsDocument,
        raw,
    )
    @test [m.name for m in doc.models] == ["UC", "ED", "EM"]
end

const IS_DATA = joinpath(
    dirname(dirname(@__DIR__)),
    "InfrastructureSystems.jl",
    "test",
    "data",
    "outputs",
)

same_file(copy, original) = isfile(copy) && read(copy) == read(original)

@testset "InfrastructureSystems vendored fixtures match test/fixtures/outputs" begin
    for kind in readdir(joinpath(FIXTURES, "valid"))
        @test same_file(
            joinpath(IS_DATA, kind, "outputs.json"),
            joinpath(FIXTURES, "valid", kind, "outputs.json"),
        )
    end
end
