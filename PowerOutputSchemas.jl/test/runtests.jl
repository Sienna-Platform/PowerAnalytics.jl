using Test, JSON, PowerOutputSchemas

const FIXTURES = joinpath(dirname(dirname(@__DIR__)), "test", "fixtures", "outputs")
const KINDS = ("single", "simulation", "power_flow", "security_analysis")

load_fixture(kind) = JSON.parsefile(joinpath(FIXTURES, "valid", kind, "outputs.json"))
first_model(doc) = first(doc["models"])

function unit_column!(doc)
    column = first_model(doc)["tables"][1]["columns"][1]
    column["quantity_kind"] = "GasFlowRate"
    column["unit_system"] = "NATURAL_UNITS"
    column["units"] = "m3/s"
    return
end

const REJECTED = [
    ("dataset quantity_kind outside the registry",
        doc -> first_model(doc)["datasets"][1]["quantity_kind"] = "GasFlowRate"),
    ("column quantity_kind outside the registry", unit_column!),
    ("model_type outside the power list",
        doc -> first_model(doc)["model_type"] = "gas_flow"),
    ("kind outside the power list", doc -> doc["kind"] = "gas_flow"),
]

@testset "the valid fixtures follow the power convention" begin
    for kind in KINDS
        @test isnothing(PowerOutputSchemas.check_power_convention(load_fixture(kind)))
    end
end

@testset "$name" for (name, mutate!) in REJECTED
    doc = load_fixture("single")
    mutate!(doc)
    check = PowerOutputSchemas.check_power_convention
    @test_throws PowerOutputSchemas.SchemaValidationError check(doc)
end

@testset "quantity_kind outside the registry in the last dataset of the last model" begin
    doc = load_fixture("simulation")
    doc["models"][end]["datasets"][end]["quantity_kind"] = "GasFlowRate"
    @test_throws PowerOutputSchemas.SchemaValidationError PowerOutputSchemas.check_power_convention(
        doc,
    )
end
