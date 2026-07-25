# [How to group generator categories](@id group_generation_by_fuel)

```@meta
CurrentModule = PowerAnalytics
```

Use the built-in selectors from [`PowerAnalytics.Selectors`](@ref) when you want Metric API
results grouped by fuel or technology categories from
[`deps/generator_mapping.yaml`](https://github.com/Sienna-Platform/PowerAnalytics.jl/blob/main/deps/generator_mapping.yaml),
instead of by component type alone.

## Use the built-in categorized selector

```julia
using PowerAnalytics
using PowerAnalytics.Metrics
using PowerAnalytics.Selectors

# One column per category present in the results' system (PV, Wind, Coal, …)
calc_active_power(categorized_generators, results)
```

[`categorized_generators`](@ref PowerAnalytics.Selectors.categorized_generators) is a single
[`ComponentSelector`](@extref PowerSystems InfrastructureSystems.ComponentSelector) whose
groups are the generator categories in the default mapping (storage and load categories are
excluded). For injectors including storage and sources, use
[`categorized_injectors`](@ref PowerAnalytics.Selectors.categorized_injectors).

To inspect the dictionary of per-category selectors:

```julia
generator_categories  # Dict{String, ComponentSelector}
keys(generator_categories)
```

## Point at a custom mapping file

Package defaults load
[`deps/generator_mapping.yaml`](https://github.com/Sienna-Platform/PowerAnalytics.jl/blob/main/deps/generator_mapping.yaml)
shipped with PowerAnalytics. To build selectors from your own YAML:

```julia
cats = parse_generator_categories("/path/to/generator_mapping.yaml")
sel = make_selector(values(cats)...)
calc_active_power(sel, results)
```

Use [`parse_injector_categories`](@ref) when you want every top-level category in the file,
including those listed under `__META.non_generators`. See
[`parse_generator_mapping_file`](@ref) for the full parse (selectors plus metadata).

YAML entries match on `gentype`, `primemover`, and `fuel` (PowerSystems enums). Category
names should stay consistent with any downstream color palettes (for example
[`PowerGraphics.plot_fuel`](@extref)).

## Related

  - Mental model: [Metrics and ComponentSelectors](@ref metrics_and_selectors)
  - Legacy PowerData path for stacked fuel plots:
    [How to build fuel-stacked generation data for plotting](@ref fuel_stacked_generation_data)
  - Selector reference: [Built-in Selectors](@ref Built-in-Selectors)
