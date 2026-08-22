# [How to define a custom metric](@id define_custom_metric)

```@meta
CurrentModule = PowerAnalytics
```

Extend PowerAnalytics by composing existing metrics, changing aggregation defaults, or
writing a [`ComponentTimedMetric`](@ref) with a custom `eval_fn`. Prefer the smallest
extension that fits; most cases do not need a new subtype of [`Metric`](@ref).

## Compose existing metrics

[`compose_metrics`](@ref) builds a new metric that evaluates several inputs and reduces them
with a function (elementwise on timed columns):

```julia
using PowerAnalytics.Metrics

# Same pattern as the built-in calc_load_from_storage
const calc_net_storage_power = compose_metrics(
    "NetStoragePower",
    (-),
    calc_active_power_out,
    calc_active_power_in,
)

calc_net_storage_power(make_selector(EnergyReservoirStorage; groupby = :all), results)
```

You can mix [`ComponentSelectorTimedMetric`](@ref) and [`SystemTimedMetric`](@ref) inputs;
system metrics are treated as applying to the same selector context. Do not mix timed and
timeless metrics in one composition.

## Change aggregation with `rebuild_metric`

[`rebuild_metric`](@ref) copies a metric and overrides fields such as `component_agg_fn` or
`time_agg_fn`:

```julia
using PowerAnalytics.Metrics
using Statistics: mean

const calc_active_power_mean = rebuild_metric(calc_active_power; component_agg_fn = mean)
calc_active_power_mean(make_selector(ThermalStandard), results)
```

Use this when the evaluation logic is correct but defaults (usually `sum`) are not.

## Define a `ComponentTimedMetric` from scratch

When you need per-component logic that is not a simple composition, construct a
[`ComponentTimedMetric`](@ref):

```julia
using PowerAnalytics
using PowerAnalytics.Metrics

const calc_active_power_gw = ComponentTimedMetric(;
    name = "ActivePowerGW",
    eval_fn = (res, comp; kwargs...) -> begin
        val = compute(calc_active_power, res, comp; kwargs...)
        get_data_vec(val) ./= 1000
        return val
    end,
)
```

`eval_fn` receives `(results, component; start_time, len, …)` and must return a timed
`DataFrame` (with a `DateTime` column). Optional fields include `component_agg_fn`,
`time_agg_fn`, and `eval_zero` for empty groups. For selector-level evaluation without
drilling to each [`PowerSystems.Component`](@extref), use [`CustomTimedMetric`](@ref). For
system-wide quantities, use [`SystemTimedMetric`](@ref).

If you only wrap a PowerSimulations results entry type, construct a
[`ComponentTimedMetric`](@ref) whose `eval_fn` calls the package's results readers (the same
pattern as many built-ins in [`PowerAnalytics.Metrics`](@ref)).

## Related

  - [Metrics and ComponentSelectors](@ref metrics_and_selectors)
  - [Advanced Metrics Interface](@ref Advanced-Metrics-Interface) in the public API
  - [Built-in Metrics](@ref Built-in-Metrics)
