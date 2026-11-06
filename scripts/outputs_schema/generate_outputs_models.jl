import OpenAPI

const REPO = dirname(dirname(@__DIR__))
const SCHEMAS = joinpath(REPO, "schemas", "outputs")
const PKG_DIR = get(ENV, "OUTPUTS_SCHEMAS_OUT", joinpath(REPO, "PowerOutputSchemas.jl"))
const MODULE_PATH = joinpath(PKG_DIR, "src", "PowerOutputSchemas.jl")

# Generates PowerOutputSchemas.jl/src from schemas/outputs/openapi-outputs.json with
# OpenAPI.jl, then inserts the public `decode` and `encode` wrappers before the model structs.
const CODEC_DEFINITIONS = """
\"\"\"
    decode(T, value[, validate])

Build a `T` from parsed JSON data (a scalar, `Vector`, or `AbstractDict`). `validate`
defaults to true, which checks the value against the schema the generated package embeds.
\"\"\"
decode(::Type{T}, value) where {T} = _decode(T, value)
decode(::Type{T}, value, validate::Bool) where {T} = _decode(T, value, validate)

\"\"\"
    encode(value)

Reduce a generated model to JSON-ready data.
\"\"\"
encode(value) = _encode(value)
"""

const CODEC_EXPORTS = ["decode", "encode", "SchemaValidationError"]

function generate()
    mkpath(dirname(MODULE_PATH))
    OpenAPI.client(
        joinpath(SCHEMAS, "openapi-outputs.json");
        name = "PowerOutputSchemas",
        path = MODULE_PATH,
        datetime = :zoned,
    )
    lines = split(read(MODULE_PATH, String), '\n')
    first_decl = findfirst(l -> startswith(l, "@doc ") || startswith(l, "struct ") || startswith(l, "Base.@kwdef struct "), lines)
    last_end = findlast(startswith("end # module"), lines)
    open(MODULE_PATH, "w") do io
        println(io, join(lines[1:(first_decl - 1)], '\n'))
        println(io, CODEC_DEFINITIONS)
        println(io, join(lines[first_decl:(last_end - 1)], '\n'))
        for n in CODEC_EXPORTS
            println(io, "export $n")
        end
        println(io, lines[last_end])
    end
    return nothing
end

generate()
