import JSON

function sync_quantity_kinds(units_json::AbstractString, common_json::AbstractString)
    units = JSON.parsefile(units_json)
    names = String[q["name"] for q in units["quantity_kinds"]]
    doc = JSON.parsefile(common_json)
    quantity_kind = doc["\$defs"]["QuantityKind"]
    if quantity_kind["enum"] == names
        return false
    end
    quantity_kind["enum"] = names
    open(common_json, "w") do io
        JSON.json(io, doc; pretty = 2)
        println(io)
    end
    return true
end

const REPO = dirname(dirname(@__DIR__))
const SCHEMA_DIR = ENV["SCHEMA_DIR"]
if sync_quantity_kinds(
    joinpath(SCHEMA_DIR, "Core", "units.json"),
    joinpath(REPO, "schemas", "outputs", "common.json"),
)
    println("common.json updated")
else
    println("common.json already in sync")
end
