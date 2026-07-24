# Public API Reference

## `ComponentSelector`

PowerAnalytics depends heavily on [`ComponentSelector`](@extref PowerSystems InfrastructureSystems.ComponentSelector),
an InfrastructureSystems type exported by PowerSystems.
PowerAnalytics provides some [built-in selectors](@ref Built-in-Selectors), but much of the
power of PowerAnalytics comes from the ability to operate on custom `ComponentSelector`s.

## Input Utilities

```@autodocs
Modules = [PowerAnalytics]
Pages   = ["input_utils.jl"]
Order = [:module, :type, :function, :macro]
Private = false
```

## Basic Metric Interface

The basic [`Metric`](@ref) interface consists of calling a `Metric` itself, for computing
one `Metric` at a time, and the [`compute_all`](@ref) function for bulk computation. Combined with
PowerAnalytics' [built-in metrics](@ref Built-in-Metrics), this is enough to execute many
common computations. See [Advanced Metrics Interface](@ref) for the interface to create
custom `Metric`s.

```@docs
Metric
TimedMetric
TimelessMetric
```

```@autodocs
Modules = [PowerAnalytics]
Pages   = ["metrics.jl"]
Order = [:function]
Private = false
Filter = t -> t in [compute_all]
```

## Built-in Metrics

### `Metrics` Submodule

Here is defined a "library" of built-in metrics to execute many common power systems
post-processing calculations.

```@autodocs
Modules = [PowerAnalytics.Metrics]
Private = false
```

## Built-in Selectors

### Selector Utilities

```@docs
parse_generator_categories
parse_generator_mapping_file
parse_injector_categories
```

### `Selectors` Submodule

```@autodocs
Modules = [PowerAnalytics.Selectors]
Private = false
```

## Post-Metric Utilities

Post-processing on the specially formatted `DataFrame`s that [`Metric`](@ref)s produce.

```@docs
aggregate_time
hcat_timed_dfs
```

## Post-Metric Accessors

Extract and manipulate information from the specially formatted `DataFrame`s that [`Metric`](@ref)s produce.

```@autodocs
Modules = [PowerAnalytics]
Pages   = ["output_utils.jl"]
Order = [:module, :type, :function, :macro]
Private = false
Filter = t -> !(t in [aggregate_time, hcat_timed_dfs])
```

## Advanced Metrics Interface

```@docs
ComponentSelectorTimedMetric
```

```@autodocs
Modules = [PowerAnalytics]
Pages   = ["metrics.jl"]
Order = [:type]
Private = false
Filter = t -> !(t in [Metric, TimedMetric, TimelessMetric, ComponentSelectorTimedMetric])
```

```@docs
rebuild_metric
compose_metrics
```

```@autodocs
Modules = [PowerAnalytics]
Pages   = ["metrics.jl"]
Order = [:function]
Private = false
Filter = t -> t in [compute]
```

```@autodocs
Modules = [PowerAnalytics]
Pages   = ["metrics.jl"]
Order = [:function, :macro]
Private = false
Filter = t -> !(t in [compute_all, rebuild_metric, compose_metrics, compute, unweighted_sum, weighted_mean, metric_selector_to_string])
```

## Miscellaneous

```@docs
unweighted_sum
weighted_mean
metric_selector_to_string
```

```@autodocs
Modules = [PowerAnalytics]
Order = [:constant]
Private = false
```

## Old PowerAnalytics

This interface predates the `1.0` version and will [eventually](https://github.com/Sienna-Platform/PowerAnalytics.jl/issues/28) be deprecated.

```@autodocs
Modules = [PowerAnalytics]
Pages   = ["get_data.jl", "fuel_results.jl"]
Order = [:module, :type, :function, :macro, :constant]
Private = false
```
