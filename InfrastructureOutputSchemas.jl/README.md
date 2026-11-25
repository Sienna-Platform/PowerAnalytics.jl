# InfrastructureOutputSchemas

This package defines the format of the `outputs.json` document of a Sienna outputs artifact. The format has no vocabulary of one domain. A power, gas, or water model can use it.

The `src/` directory is generated from `schemas/outputs/infrastructure/` by `scripts/outputs_schema/generate_outputs_models.jl`. Do not edit it.

## Entry points

- `decode(T, value[, validate])` builds a `T` from parsed JSON data. It checks the value against the embedded schema unless `validate` is false. A schema violation throws `SchemaValidationError`.
- `encode(value)` reduces a generated type to JSON-ready data.

```julia
import JSON
using InfrastructureOutputSchemas

document =
    decode(InfrastructureOutputSchemas.OutputsDocument, JSON.parsefile("outputs.json"))
```

## Document facts

`created_at` needs `Z` or a UTC offset. Axis `initial_timestamp` and simulation `initial_time` are naive datetimes. They have no zone.

In the document, `models` and `axes` are arrays. Each model has a `name`. A dataset lists axis names in `axes`.

A `time`, `execution`, or `horizon` axis has its kind as its name. A `component` axis has the `component_type` values joined with `__` as its name. If `subset` exists, the name ends with `__subset`. A `label` axis has its `name` field as its name.

## Unit systems

| Value | Meaning | Base | `units` |
|---|---|---|---|
| `SYSTEM_BASE` | Per unit on the system base of the model | `Model.base_power` gives the power base. A kind that needs a different base gets it from the system in the artifact bundle. | `pu` |
| `COMPONENT_BASE` | Per unit on the own base of each component of the component axis | The component record in the system bundle | `pu` |
| `NATURAL_UNITS` | A physical unit | None | The unit. Not `pu`. |

## Domain names

The fields `OutputsDocument.kind`, `Model.model_type`, and `quantity_kind` are strings. The schema checks only the form of each string. The domain convention gives the permitted names.

- `kind` and `model_type` use lower snake case.
- `quantity_kind` uses the `TypeName` pattern.
