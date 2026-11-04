import JSON

const SCHEMAS_DIR = joinpath(dirname(@__DIR__), "schemas", "outputs")
const UNITS_JSON =
    joinpath(dirname(dirname(@__DIR__)), "SiennaSchemas", "Core", "units.json")

const SCHEMA_DOCS = Dict{String, Any}(
    f => JSON.parsefile(joinpath(SCHEMAS_DIR, f)) for
    f in readdir(SCHEMAS_DIR) if endswith(f, ".json")
)

@testset "common.json enums match the spec" begin
    common = SCHEMA_DOCS["common.json"]
    defs = common["\$defs"]
    @test defs["Kind"]["enum"] ==
          ["single", "simulation", "power_flow", "security_analysis"]
    @test defs["Container"]["enum"] ==
          ["variables", "aux_variables", "parameters", "expressions", "duals"]
    @test defs["BaseReference"]["enum"] == ["system", "component"]
    @test defs["RunStatus"]["enum"] == ["RUNNING", "SUCCESSFULLY_FINALIZED", "FAILED"]
    @test defs["ModelType"]["enum"] ==
          ["decision", "emulation", "power_flow", "security_analysis"]
    @test defs["Dtype"]["enum"] == ["f64", "f32", "i64", "i32", "bool"]
    @test defs["ColumnDtype"]["enum"] == ["f64", "i64", "bool", "str"]
    @test defs["UnitSystem"]["enum"] == ["COMPONENT_BASE", "NATURAL_UNITS"]
    @test defs["AxisKind"]["enum"] == ["time", "execution", "horizon", "component", "label"]
    @test "ActivePower" in defs["QuantityKind"]["enum"]
    @test "Dimensionless" in defs["QuantityKind"]["enum"]
end

@testset "QuantityKind enum is in sync with units.json" begin
    units = JSON.parsefile(UNITS_JSON)
    names = [q["name"] for q in units["quantity_kinds"]]
    common = SCHEMA_DOCS["common.json"]
    @test common["\$defs"]["QuantityKind"]["enum"] == names
end

function collect_refs(node::AbstractDict)
    refs = String[]
    for (k, v) in node
        if k == "\$ref"
            push!(refs, v)
        else
            append!(refs, collect_refs(v))
        end
    end
    return refs
end
collect_refs(node::AbstractVector) = reduce(vcat, collect_refs.(node); init = String[])
collect_refs(::Any) = String[]

function ref_resolves(current_file::AbstractString, ref::AbstractString)
    file, pointer = split(ref * "#", "#"; limit = 2)
    pointer = chopsuffix(pointer, "#")
    target = current_file
    if !isempty(file)
        target = file
    end
    haskey(SCHEMA_DOCS, target) || return false
    node = SCHEMA_DOCS[target]
    for segment in filter(!isempty, split(pointer, "/"))
        haskey(node, segment) || return false
        node = node[segment]
    end
    return true
end

@testset "every schema file parses and every \$ref resolves" begin
    wrapper = SCHEMA_DOCS["openapi-outputs.json"]
    @test wrapper["openapi"] == "3.1.0"
    for (name, ref) in wrapper["components"]["schemas"]
        file = first(split(ref["\$ref"], "#"; limit = 2))
        @test isfile(joinpath(SCHEMAS_DIR, file))
    end
    for (f, doc) in SCHEMA_DOCS
        for ref in collect_refs(doc)
            @test ref_resolves(f, ref)
        end
    end
    @test Set(keys(wrapper["components"]["schemas"])) == Set([
        "OutputsDocument", "Model", "Dataset", "Table", "Column", "Axis", "TimeAxis",
        "ExecutionAxis", "HorizonAxis", "ComponentAxis", "LabelAxis", "ProducerInfo",
        "SimulationParams", "DatasetLayout",
    ])
end

@testset "Dataset.json carries the conditional rules" begin
    ds = SCHEMA_DOCS["Dataset.json"]
    @test "name" ∉ ds["required"]
    @test ds["required"] == [
        "container", "entry_type", "meta", "axes", "dtype", "fill_value",
        "quantity_kind", "unit_system", "units", "layout", "path",
    ]
    @test length(ds["allOf"]) == 3
end

@testset "quantities.json rows are well formed" begin
    reg = SCHEMA_DOCS["quantities.json"]
    @test Set(keys(reg["entries"])) == Set([
        "PowerFlowVoltageMagnitude", "PowerFlowVoltageAngle",
        "PowerFlowBranchActivePowerFromTo", "PowerFlowActivePowerInjection",
        "PowerFlowConverged",
    ])
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
    invalid = readdir(joinpath(FIXTURES, "invalid"))
    @test length(invalid) == 12
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
    @test length(doc.models.additional_properties) == 3
end
