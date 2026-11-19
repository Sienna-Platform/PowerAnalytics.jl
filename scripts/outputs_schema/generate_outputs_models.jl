import OpenAPI

const REPO = dirname(dirname(@__DIR__))
const SCHEMAS = joinpath(REPO, "schemas", "outputs")
const MODULE_PATH = joinpath(REPO, "PowerOutputSchemas.jl", "src", "PowerOutputSchemas.jl")

# Generates PowerOutputSchemas.jl/src from schemas/outputs/openapi-outputs.json with
# OpenAPI.jl, then inserts the public `decode` and `encode` wrappers before the module end.
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

export decode, encode, SchemaValidationError, DecodeError

"""

function generate()
    mkpath(dirname(MODULE_PATH))
    OpenAPI.client(
        joinpath(SCHEMAS, "openapi-outputs.json");
        name = "PowerOutputSchemas",
        path = MODULE_PATH,
        datetime = :zoned,
        models_only = true,
    )
    src = read(MODULE_PATH, String)
    module_end = first(findlast("end # module", src))
    write(MODULE_PATH, src[1:(module_end - 1)] * CODEC_DEFINITIONS * src[module_end:end])
    return nothing
end

generate()
