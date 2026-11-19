using Test, JSON, OpenAPI, TOML, PowerOutputSchemas

const FIXTURES = joinpath(dirname(dirname(@__DIR__)), "test", "fixtures", "outputs")
const DOCUMENT = PowerOutputSchemas.OutputsDocument
const KINDS = ("single", "simulation", "power_flow", "security_analysis")

load_fixture(kind) = JSON.parsefile(joinpath(FIXTURES, "valid", kind, "outputs.json"))

function find_model(doc, name)
    return first(m for m in doc["models"] if m["name"] == name)
end

function find_axis(model, kind)
    return first(a for a in model["axes"] if a["kind"] == kind)
end

function find_label_axis(model, name)
    return first(a for a in model["axes"] if a["kind"] == "label" && a["name"] == name)
end

function find_component_axis(model, component_type)
    return first(
        a for a in model["axes"] if
        a["kind"] == "component" && a["columns"][1]["component_type"] == component_type
    )
end

function drop_axis!(model, kind)
    filter!(a -> a["kind"] != kind, model["axes"])
    return nothing
end

# Each row: testset name, base fixture kind, function that breaks exactly one rule.
const REJECTED = [
    (
        "execution axis group is not under axes",
        "single",
        doc -> find_axis(find_model(doc, "model"), "execution")["group"] = "/model/execution",
    ),
    (
        "component axis group is not under axes",
        "single",
        doc ->
            find_component_axis(find_model(doc, "model"), "ThermalStandard")["group"] = "/model/ThermalStandard",
    ),
    (
        "time axis group is not under axes",
        "power_flow",
        doc -> find_axis(find_model(doc, "model"), "time")["group"] = "/model/time",
    ),
    (
        "base_reference on a NATURAL_UNITS dataset",
        "single",
        doc -> find_model(doc, "model")["datasets"][2]["base_reference"] = "system",
    ),
    (
        "COMPONENT_BASE dataset without base_reference",
        "single",
        doc -> delete!(find_model(doc, "model")["datasets"][1], "base_reference"),
    ),
    (
        "units other than pu on a COMPONENT_BASE dataset",
        "single",
        doc -> find_model(doc, "model")["datasets"][1]["units"] = "MW",
    ),
    (
        "boolean fill_value on an f64 dataset",
        "single",
        doc -> find_model(doc, "model")["datasets"][2]["fill_value"] = true,
    ),
    (
        "float fill_value on an i64 dataset",
        "single",
        function (doc)
            dataset = find_model(doc, "model")["datasets"][2]
            dataset["dtype"] = "i64"
            dataset["fill_value"] = 1.5
        end,
    ),
    (
        "NaN fill_value on an i64 dataset",
        "single",
        doc -> find_model(doc, "model")["datasets"][2]["dtype"] = "i64",
    ),
    (
        "number fill_value on a bool dataset",
        "single",
        function (doc)
            dataset = find_model(doc, "model")["datasets"][2]
            dataset["dtype"] = "bool"
            dataset["fill_value"] = 1
        end,
    ),
    (
        "table column units without quantity_kind",
        "single",
        doc -> delete!(find_model(doc, "model")["tables"][1]["columns"][2], "quantity_kind"),
    ),
    (
        "dataset without container",
        "single",
        doc -> delete!(find_model(doc, "model")["datasets"][1], "container"),
    ),
    (
        "dataset with horizon axis and no execution axis",
        "single",
        function (doc)
            dataset = find_model(doc, "model")["datasets"][1]
            dataset["axes"] = ["ThermalStandard", "horizon"]
            dataset["layout"]["chunks"] = [76, 48]
        end,
    ),
    (
        "meta with a double underscore",
        "single",
        doc -> find_model(doc, "model")["datasets"][1]["meta"] = "a__b",
    ),
    (
        "meta with a slash",
        "single",
        doc -> find_model(doc, "model")["datasets"][1]["meta"] = "a/b",
    ),
    ("unknown kind", "single", doc -> doc["kind"] = "batch"),
    ("unknown schema_version", "single", doc -> doc["schema_version"] = "0.2.0"),
    ("simulation kind without simulation block", "single", doc -> doc["kind"] = "simulation"),
    (
        "empty system directory",
        "single",
        doc -> doc["systems"][first(keys(doc["systems"]))] = "",
    ),
    (
        "system directory is ..",
        "single",
        doc -> doc["systems"][first(keys(doc["systems"]))] = "..",
    ),
    (
        "model without supports_realized_values_post_calculation",
        "single",
        doc -> delete!(find_model(doc, "model"), "supports_realized_values_post_calculation"),
    ),
    (
        "realized flag true and no horizon axis",
        "simulation",
        doc -> drop_axis!(find_model(doc, "UC"), "horizon"),
    ),
    (
        "realized flag true and no execution axis",
        "simulation",
        doc -> drop_axis!(find_model(doc, "UC"), "execution"),
    ),
    (
        "realized flag true and a time axis",
        "simulation",
        doc -> push!(
            find_model(doc, "UC")["axes"],
            JSON.Object(
                "kind" => "time",
                "initial_timestamp" => "2024-01-01T00:00:00",
                "resolution" => "PT1H",
                "length" => 168,
                "group" => "/UC/axes/time",
            ),
        ),
    ),
    (
        "label axis with a reserved name",
        "power_flow",
        doc -> find_label_axis(find_model(doc, "model"), "winding")["name"] = "execution",
    ),
    (
        "label axis name is not lower snake case",
        "power_flow",
        doc -> find_label_axis(find_model(doc, "model"), "winding")["name"] = "Winding Axis",
    ),
    (
        "label axis without name",
        "power_flow",
        doc -> delete!(find_label_axis(find_model(doc, "model"), "winding"), "name"),
    ),
    (
        "model without name",
        "single",
        doc -> delete!(find_model(doc, "model"), "name"),
    ),
    (
        "model name with a slash",
        "single",
        doc -> find_model(doc, "model")["name"] = "a/b",
    ),
    (
        "settings value is an object",
        "single",
        doc -> find_model(doc, "model")["settings"] = JSON.Object("nested" => JSON.Object()),
    ),
]

@testset "valid fixtures decode" begin
    for kind in KINDS
        raw = load_fixture(kind)
        doc = decode(DOCUMENT, raw)
        @test string(doc.kind.value) == kind
        @test doc.schema_version == "0.1.0"
        @test encode(decode(DOCUMENT, JSON.parse(JSON.json(encode(doc))))) == encode(doc)
        @test encode(decode(DOCUMENT, raw, false)) == encode(doc)
    end
end

@testset "rejected documents" begin
    for (name, kind, mutate!) in REJECTED
        @testset "$name" begin
            doc = load_fixture(kind)
            mutate!(doc)
            @test_throws SchemaValidationError decode(DOCUMENT, doc)
        end
    end
end

@testset "axis reference to a missing axis is schema-valid (InfrastructureSystems rejects it in validate_metadata)" begin
    raw = load_fixture("single")
    find_model(raw, "model")["datasets"][1]["axes"][2] = "Nope"
    @test_nowarn decode(DOCUMENT, raw)
end

@testset "settings keep integer and boolean values" begin
    raw = load_fixture("single")
    find_model(raw, "model")["settings"] =
        JSON.Object("threads" => 4, "max_iterations" => 1, "robust" => false)
    settings = decode(DOCUMENT, raw).models[1].settings.additional_properties
    @test settings["threads"] === 4
    @test settings["max_iterations"] === 1
    @test settings["robust"] === false
end

@testset "i64 dataset with fill_value 0" begin
    raw = load_fixture("single")
    dataset = find_model(raw, "model")["datasets"][2]
    dataset["dtype"] = "i64"
    dataset["fill_value"] = 0
    @test decode(DOCUMENT, raw).models[1].datasets[2].fill_value === 0
    @test decode(DOCUMENT, raw, false).models[1].datasets[2].fill_value === 0
end

@testset "valid fixtures decode without validation" begin
    for kind in KINDS
        @test_nowarn decode(DOCUMENT, load_fixture(kind), false)
    end
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
