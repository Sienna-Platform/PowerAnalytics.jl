import OpenAPI

const REPO = dirname(dirname(@__DIR__))
const SCHEMAS = joinpath(REPO, "schemas", "outputs")
const PKG_DIR = get(ENV, "OUTPUTS_SCHEMAS_OUT", joinpath(REPO, "PowerOutputSchemas.jl"))
const MODULE_PATH = joinpath(PKG_DIR, "src", "PowerOutputSchemas.jl")

const CODEC_DEFINITIONS = """
\"\"\"
    decode(T, value[, validate])

Build a `T` from parsed JSON data (a scalar, `Vector`, or `AbstractDict`), replacing
OpenAPI.jl 0.2's `OpenAPI.from_json`. `validate` defaults to true, which checks the value
against the schema the generated package embeds.

A thin public alias for the runtime's `_decode`: consumers need this entry point (to read a
store's catalog rows, or to build a strictly-typed generated struct from hand-assembled
keyword arguments), and without it every one of them reaches into an underscore-internal of
another package.
\"\"\"
decode(::Type{T}, value) where {T} = _decode(T, value)
decode(::Type{T}, value, validate::Bool) where {T} = _decode(T, value, validate)

\"\"\"
    encode(value)

Reduce a generated model to JSON-ready data, replacing OpenAPI.jl 0.2's `OpenAPI.to_json`.
The public alias for the runtime's `_encode`, for the same reason as `decode`.
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
    first_decl = findfirst(l -> startswith(l, "struct ") || startswith(l, "Base.@kwdef struct "), lines)
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
