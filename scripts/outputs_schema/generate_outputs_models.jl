import OpenAPI

const REPO = dirname(dirname(@__DIR__))
const SCHEMAS = joinpath(REPO, "schemas", "outputs")

# Generates <name>.jl/src from an index below schemas/outputs/ with
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

const CONVENTION_DEFINITIONS = """
\"\"\"
    check_power_convention(document::AbstractDict)

Check the vocabulary fields of a parsed outputs document against the power convention.
Throw `SchemaValidationError` when `kind`, a `model_type`, or a `quantity_kind` is not in
the power lists. Return `nothing` otherwise.
\"\"\"
function check_power_convention(document::AbstractDict)
    decode(PowerConvention, document)
    return nothing
end

export check_power_convention, QuantityKind

"""

function generate(index::AbstractString, name::AbstractString, definitions::AbstractString)
    module_path = joinpath(REPO, "$name.jl", "src", "$name.jl")
    mkpath(dirname(module_path))
    OpenAPI.client(
        joinpath(SCHEMAS, index);
        name = name,
        path = module_path,
        datetime = :zoned,
        models_only = true,
    )
    src = read(module_path, String)
    module_end = first(findlast("end # module", src))
    write(module_path, src[1:(module_end - 1)] * definitions * src[module_end:end])
    return nothing
end

generate(
    joinpath("infrastructure", "openapi-outputs.json"),
    "InfrastructureOutputSchemas",
    CODEC_DEFINITIONS,
)
generate(
    joinpath("power", "openapi-outputs-power.json"),
    "PowerOutputSchemas",
    CODEC_DEFINITIONS * CONVENTION_DEFINITIONS,
)
