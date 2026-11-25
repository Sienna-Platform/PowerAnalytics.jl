The `src/` directory is generated from `schemas/outputs/power/` by `scripts/outputs_schema/generate_outputs_models.jl`. Do not edit it.

This package is the power convention for an outputs document. The generic structure schema is in `InfrastructureOutputSchemas`. The two packages do not depend on each other.

`check_power_convention(document)` takes the parsed JSON of an `outputs.json` file. It returns `nothing` when the vocabulary fields follow the convention. It throws `SchemaValidationError` otherwise.

The convention has three lists:

- `Kind`: `single`, `simulation`, `power_flow`, `security_analysis`.
- `ModelType`: `decision`, `emulation`, `power_flow`, `security_analysis`.
- `QuantityKind`: a copy of the quantity kinds in SiennaSchemas `Core/units.json`.
