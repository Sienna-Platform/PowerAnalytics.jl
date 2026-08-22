# [Choosing built-in metrics](@id choosing_built_in_metrics)

```@meta
CurrentModule = PowerAnalytics
```

Built-in metrics live in [`PowerAnalytics.Metrics`](@ref). Exact formulas, PowerSimulations
keys, and aggregation details are in each metric's docstring on
[Built-in Metrics](@ref Built-in-Metrics). This page compares when to reach for which one.

## Curtailment: absolute versus fraction

| Metric                                                                       | Use when                                                                                           |
|:---------------------------------------------------------------------------- |:-------------------------------------------------------------------------------------------------- |
| [`calc_curtailment`](@ref PowerAnalytics.Metrics.calc_curtailment)           | You need energy (or MW-step) of unused availability: forecast minus dispatch                       |
| [`calc_curtailment_frac`](@ref PowerAnalytics.Metrics.calc_curtailment_frac) | You need a rate relative to available power; time/component averages should weight by availability |

Both require forecast parameters and active-power variables on the selector. Prefer the
absolute metric for energy balances and totals; prefer the fraction when comparing units or
periods with different available capacity.

## Integration versus capacity factor

| Metric                                                                     | Numerator                                                                              | Denominator                            | Typical question                           |
|:-------------------------------------------------------------------------- |:-------------------------------------------------------------------------------------- |:-------------------------------------- |:------------------------------------------ |
| [`calc_integration`](@ref PowerAnalytics.Metrics.calc_integration)         | Realized [`calc_active_power`](@ref PowerAnalytics.Metrics.calc_active_power)          | System load forecast + storage-as-load | What share of demand did this fleet serve? |
| [`calc_capacity_factor`](@ref PowerAnalytics.Metrics.calc_capacity_factor) | [`calc_active_power_forecast`](@ref PowerAnalytics.Metrics.calc_active_power_forecast) | Component rating                       | Does forecast/rating look plausible?       |

Integration is a **system demand** share (and can exceed a naive “generation / load” story
when storage charging is in the denominator). Capacity factor here is **not** realized
production over rating — it deliberately uses the forecast parameter as a sanity check.
For a classical realized capacity factor, compose or define a metric that divides
[`calc_active_power`](@ref PowerAnalytics.Metrics.calc_active_power) by rating (see
[How to define a custom metric](@ref define_custom_metric)).

## Cost family

| Metric                                                                                                                                        | Meaning                                                             |
|:--------------------------------------------------------------------------------------------------------------------------------------------- |:------------------------------------------------------------------- |
| [`calc_production_cost`](@ref PowerAnalytics.Metrics.calc_production_cost)                                                                    | Production-cost expression from the solver                          |
| [`calc_startup_cost`](@ref PowerAnalytics.Metrics.calc_startup_cost) / [`calc_shutdown_cost`](@ref PowerAnalytics.Metrics.calc_shutdown_cost) | Commitment start/stop binaries times cost coefficients              |
| [`calc_total_cost`](@ref PowerAnalytics.Metrics.calc_total_cost)                                                                              | **Currently an alias of production cost** — does not add start/stop |

Sum production, startup, and shutdown yourself when you need a full commitment cost. Not
every component cost type defines start/stop coefficients.

## Weighted aggregation

Curtailment fraction, integration (in time), and capacity factor attach `agg_meta` weights so
[`aggregate_time`](@ref) and multi-component reductions are not simple unweighted means.
If a summary looks “too small” or “too large” relative to a hand-built mean, check the
metric docstring for `weighted_mean` / `unweighted_sum` behavior.

## Related

  - [Metrics and ComponentSelectors](@ref metrics_and_selectors)
  - [Built-in Metrics](@ref Built-in-Metrics)
  - [Simulation Scenarios Analysis](@ref Scenarios_PA_tutorial)
