# [How `PowerAnalytics` thinks](@id metrics_and_selectors)

```@meta
CurrentModule = PowerAnalytics
```

PowerAnalytics post-processing is organized around two ideas: a [`Metric`](@ref) that
defines *what* to compute from simulation results, and a
[`ComponentSelector`](@extref PowerSystems InfrastructureSystems.ComponentSelector) that
defines *which* devices (or groups of devices) that quantity applies to. The
[Simulation Scenarios Analysis](@ref Scenarios_PA_tutorial) tutorial shows how to call this
API; this page explains why it is shaped that way.

## Metric plus selector

A [`Metric`](@ref) encapsulates:

  - how to read or derive a quantity from an [`InfrastructureSystems.Results`](@extref)
    object (often a [`PowerSimulations.SimulationProblemResults`](@extref))
  - default aggregation across components and across time

Many metrics also need a selector. Calling a metric is syntactic sugar for [`compute`](@ref):

```julia
using PowerAnalytics.Metrics
calc_active_power(make_selector(RenewableDispatch), results)
# same as:
compute(calc_active_power, results, make_selector(RenewableDispatch))
```

[`make_selector`](@extref PowerSystems InfrastructureSystems.make_selector) and
[`rebuild_selector`](@extref PowerSystems InfrastructureSystems.rebuild_selector-Tuple{InfrastructureSystems.ListComponentSelector})
come from InfrastructureSystems (exported by PowerSystems). They control grouping: one
column per component by default, or collapsed groups via `groupby` (for example
`groupby = :all` or a function such as `get_prime_mover_type`).

System-wide and results-wide metrics omit the selector. Examples:
[`calc_system_slack_up`](@ref PowerAnalytics.Metrics.calc_system_slack_up) and
[`calc_sum_objective_value`](@ref PowerAnalytics.Metrics.calc_sum_objective_value).

## Timed versus timeless

| Kind                     | Role                              | Typical output                       |
|:------------------------ |:--------------------------------- |:------------------------------------ |
| [`TimedMetric`](@ref)    | Values indexed by simulation time | `DataFrame` with a `DateTime` column |
| [`TimelessMetric`](@ref) | One summary per results object    | Scalar (or one-row frame)            |

Most built-ins under [`PowerAnalytics.Metrics`](@ref) are timed and component-scoped
([`ComponentTimedMetric`](@ref)). Optimizer statistics such as objective value and solve
time are timeless. [`compute_all`](@ref) and [`aggregate_time`](@ref) are the usual way to
combine timed series and then collapse time for scenario tables; see the tutorial.

## Aggregation is part of the metric

When a selector has multiple components in a group, the metric's `component_agg_fn` reduces
them (default [`sum`](@extref Base.sum)). When you call [`aggregate_time`](@ref), the
metric's `time_agg_fn` reduces the time axis (also default `sum`).

Some metrics attach **aggregation metadata** (`agg_meta`) so those reductions can be
weighted — for example curtailment fraction weights by available power. Changing defaults
without rewriting the evaluation function is the job of [`rebuild_metric`](@ref). Composing
existing metrics with an elementwise function is the job of [`compose_metrics`](@ref).

For task-oriented recipes, see [How to define a custom metric](@ref define_custom_metric)
and [How to group generation by category](@ref group_generation_by_fuel).
For formulas and caveats on specific built-ins, see
[Choosing built-in metrics](@ref choosing_built_in_metrics) and the
[Built-in Metrics](@ref Built-in-Metrics) reference.
