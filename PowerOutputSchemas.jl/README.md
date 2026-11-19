The `src/` directory is generated from `schemas/outputs/` by `scripts/outputs_schema/generate_outputs_models.jl`. Do not edit it.

`created_at` requires `Z` or a UTC offset. Axis `initial_timestamp` and simulation `initial_time` are naive local datetimes with no zone.

In the document, `models` is an array and each model has a `name`. The `axes` of a model is an array of axis objects. A dataset lists axis names in `axes`.

The axis name of a `time`, `execution`, or `horizon` axis is its kind. The axis name of a `component` axis is the `component_type` values joined with `__`, plus `__` and `subset` if present. The axis name of a `label` axis is its `name` field.
