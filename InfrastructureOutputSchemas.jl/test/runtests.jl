using Test, JSON, OpenAPI, TOML, InfrastructureOutputSchemas

const FIXTURES = joinpath(dirname(dirname(@__DIR__)), "test", "fixtures", "outputs")
const DOCUMENT = InfrastructureOutputSchemas.OutputsDocument
const KINDS = ("single", "simulation", "power_flow", "security_analysis")

load_fixture(kind) = JSON.parsefile(joinpath(FIXTURES, "valid", kind, "outputs.json"))

function first_dataset(model, unit_system)
    return first(d for d in model["datasets"] if d["unit_system"] == unit_system)
end

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
        "base_reference on a dataset",
        "single",
        doc -> first_dataset(find_model(doc, "model"), "SYSTEM_BASE")["base_reference"] = "system",
    ),
    (
        "unit_system outside the three values",
        "single",
        doc -> first_dataset(find_model(doc, "model"), "SYSTEM_BASE")["unit_system"] = "PER_UNIT",
    ),
    (
        "SYSTEM_BASE dataset with a physical unit",
        "single",
        doc -> first_dataset(find_model(doc, "model"), "SYSTEM_BASE")["units"] = "MW",
    ),
    (
        "COMPONENT_BASE dataset with a physical unit",
        "power_flow",
        doc -> first_dataset(find_model(doc, "model"), "COMPONENT_BASE")["units"] = "kV",
    ),
    (
        "NATURAL_UNITS dataset with units pu",
        "single",
        doc -> first_dataset(find_model(doc, "model"), "NATURAL_UNITS")["units"] = "pu",
    ),
    (
        "quantity_kind that is not a type name",
        "single",
        doc -> first_dataset(find_model(doc, "model"), "SYSTEM_BASE")["quantity_kind"] = "active power",
    ),
    ("kind that is not lower snake case", "single", doc -> doc["kind"] = "GasFlow"),
    (
        "model_type that is not lower snake case",
        "single",
        doc -> find_model(doc, "model")["model_type"] = "Gas Flow",
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
        "base_reference on a NATURAL_UNITS table column",
        "single",
        doc ->
            find_model(doc, "model")["tables"][1]["columns"][2]["base_reference"] = "system",
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
        "component axis subset with a slash",
        "single",
        doc ->
            find_component_axis(find_model(doc, "model"), "ThermalStandard")["subset"] = "north/south",
    ),
    (
        "table column name is .",
        "single",
        doc -> find_model(doc, "model")["tables"][1]["columns"][1]["name"] = ".",
    ),
    (
        "duration part with ten digits",
        "single",
        doc ->
            find_axis(find_model(doc, "model"), "execution")["interval"] = "PT9999999999M",
    ),
    (
        "duration in seconds",
        "single",
        doc -> find_axis(find_model(doc, "model"), "execution")["interval"] = "PT30S",
    ),
    (
        "duration in months",
        "single",
        doc -> find_axis(find_model(doc, "model"), "execution")["interval"] = "P1M",
    ),
    (
        "i32 fill_value below the minimum",
        "single",
        function (doc)
            dataset = find_model(doc, "model")["datasets"][2]
            dataset["dtype"] = "i32"
            dataset["fill_value"] = -2147483649
        end,
    ),
    (
        "i32 fill_value above the maximum",
        "single",
        function (doc)
            dataset = find_model(doc, "model")["datasets"][2]
            dataset["dtype"] = "i32"
            dataset["fill_value"] = 2147483648
        end,
    ),
    (
        "i64 fill_value below the minimum",
        "single",
        function (doc)
            dataset = find_model(doc, "model")["datasets"][2]
            dataset["dtype"] = "i64"
            dataset["fill_value"] = -9223372036854775809
        end,
    ),
    (
        "i64 fill_value above the maximum",
        "single",
        function (doc)
            dataset = find_model(doc, "model")["datasets"][2]
            dataset["dtype"] = "i64"
            dataset["fill_value"] = 9223372036854775808
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
        @test doc.kind == kind
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
    @test decode(DOCUMENT, raw).models[1].datasets[1].axes[2] == "Nope"
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

@testset "integer fill_value at the dtype endpoints" begin
    for (dtype, value) in (
        ("i32", typemin(Int32)),
        ("i32", typemax(Int32)),
        ("i64", typemin(Int64)),
        ("i64", typemax(Int64)),
    )
        raw = load_fixture("single")
        dataset = find_model(raw, "model")["datasets"][2]
        dataset["dtype"] = dtype
        dataset["fill_value"] = Int64(value)
        @test decode(DOCUMENT, raw).models[1].datasets[2].fill_value == value
    end
end

@testset "component axis subset without a slash" begin
    raw = load_fixture("single")
    find_component_axis(find_model(raw, "model"), "ThermalStandard")["subset"] = "north"
    @test decode(DOCUMENT, raw).models[1].axes[3].value.subset == "north"
end

@testset "duration part with nine digits" begin
    raw = load_fixture("single")
    find_axis(find_model(raw, "model"), "horizon")["resolution"] = "PT999999999M"
    @test decode(DOCUMENT, raw).models[1].name == "model"
end

@testset "table column name with dots that is not . or .." begin
    raw = load_fixture("single")
    find_model(raw, "model")["tables"][1]["columns"][1]["name"] = "..."
    @test decode(DOCUMENT, raw).models[1].tables[1].columns[1].name == "..."
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
                "PowerOutputSchemas",
                "InfrastructureOptimizationModels",
            ),
        ),
    )
end

@testset "a document of a different domain is valid" begin
    doc = load_fixture("single")
    doc["kind"] = "gas_flow"
    model = find_model(doc, "model")
    model["model_type"] = "gas_flow"
    first_dataset(model, "NATURAL_UNITS")["quantity_kind"] = "GasFlowRate"
    decoded = InfrastructureOutputSchemas.decode(DOCUMENT, doc)
    @test decoded.kind == "gas_flow"
    @test decoded.models[1].model_type == "gas_flow"
end

@testset "table column unit fields" begin
    doc = load_fixture("single")
    column = find_model(doc, "model")["tables"][1]["columns"][1]
    @test !haskey(column, "unit_system")
    @test InfrastructureOutputSchemas.decode(DOCUMENT, doc).kind == "single"
    column["quantity_kind"] = "ActivePower"
    column["unit_system"] = "SYSTEM_BASE"
    column["units"] = "MW"
    @test_throws InfrastructureOutputSchemas.SchemaValidationError InfrastructureOutputSchemas.decode(
        DOCUMENT, doc,
    )
    column["units"] = "pu"
    @test InfrastructureOutputSchemas.decode(DOCUMENT, doc).kind == "single"
end
