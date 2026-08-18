# PowerAnalytics.jl — Claude Guide

Platform-wide Sienna conventions (performance, type stability, formatter, environments, code style) live in `.claude/Sienna.md` — read it too. This file is repo-specific and does not restate them.

**This is the psy6 line.** PowerSimulations does not exist here — it was split into
InfrastructureOptimizationModels (IOM) and PowerOperationsModels (POM). Anything you read in
psy5 docs, older PRs, or the registered package must be translated before you act on it.

## Vocabulary — this distinction is load-bearing

| Term | Means | Lives in |
|---|---|---|
| **Outputs** | The raw, unprocessed output of a model run — variable/parameter/expression values as solved. | IOM defines them (`OptimizationProblemOutputs`); POM produces and serializes them. |
| **Results** | The processed, aggregated, summarized artifacts of analysis. | PowerAnalytics produces them. |

PowerAnalytics **loads outputs** and **produces results**. An identifier or docstring that says
"result" when it means raw model output is a defect. `compute` / `compute_all` and the
DataFrames they return correctly keep "result" language — those *are* results.

## Package purpose & place in the stack

PowerAnalytics post-processes optimization **outputs** into aggregated, categorized time-series
**results**: active power, production/startup/total cost, curtailment, capacity factor, stored
energy, slack, objective value, solve time.

It depends on **IS + IOM + PSY** and **never on POM**. POM's variable and parameter types are
reached *by name*, not by type — see "Reading entries defined elsewhere" below. Do not add a POM
dependency.

Downstream: PowerGraphics consumes PowerAnalytics for plotting. Preserve DataFrame column
conventions and metadata keys — breaking them breaks PowerGraphics and user code.

Current facts (verify against `Project.toml`): version **1.5.0**; compat **PowerSystems ^5.10**,
**InfrastructureSystems 3**, julia ^1.10. These read lower than the actual 6.0/4.0 lines *on
purpose* — no version or compat bumps until release. Aliases: `PSY`, `IS`, `IOM`.

## Architecture & `src/` layout

The legacy layer ("Old PowerAnalytics") is **gone** — `get_data.jl`, `fuel_results.jl` and
`definitions.jl` were deleted, along with `PowerData`, `get_generation_data`, `get_load_data`,
`get_service_data`, `categorize_data`, `make_fuel_dictionary`, `combine_categories` and
`no_datetime`. The metrics framework is the only layer. Do not reintroduce them.

- `PowerAnalytics.jl` — module entry: exports, imports, aliases, include order, submodule `using`s.
- `load_outputs.jl` — `load_outputs(dir)` reads a self-contained serialized outputs directory,
  finding the System JSON beside `problem_outputs.bin`; `load_outputs(dir, sys)` attaches a
  System you already hold.
- `input_utils.jl` — key construction, the `read_key_wide` read seam, `read_component_output`,
  `read_system_indexed_output`, `VariableName`/`AuxVariableName`/`ParameterName`, `NoOutputError`.
- `output_utils.jl` — DataFrame column-metadata helpers, time-series/data accessors.
- `realized_outputs.jl` — `realized_timestamps`, `read_realized_key_wide`.
- `metrics.jl` — `Metric` hierarchy, `compute`, `compute_all`, `aggregate_time`, `compose_metrics`.
- `builtin_component_selectors.jl` — `Selectors` submodule; fuel/category selectors.
- `builtin_metrics.jl` — `Metrics` submodule; `calc_*` metric constants.

Include order (from `src/PowerAnalytics.jl`) matters: `load_outputs.jl` → `input_utils.jl` →
`realized_outputs.jl` → `output_utils.jl` → `metrics.jl` → `builtin_component_selectors.jl` →
`builtin_metrics.jl`. `realized_outputs.jl` must follow `input_utils.jl` because it calls
`read_key_wide`.

## Public API

### ComponentSelector

A selector is a **declarative query**, not a materialized set — resolved against a `System` or an
`IS.Outputs` at `compute` time. `make_selector` builds them from a type, a filter closure, or
named subselectors. Built-ins (`Selectors` submodule): `all_loads`, `all_storage`,
`injector_categories`, `generator_categories`, `categorized_injectors`, `categorized_generators`,
plus fuel/category selectors derived from the generator-mapping YAML.

`categorized_generators` resolves to 13 categories: Biopower, CSP, Coal, Geothermal, Hydropower,
NG-CC, NG-CT, NG-Steam, Nuclear, Other, Petroleum, PV, Wind.

**`make_selector` defaults to `groupby = :each`** — one group per component. If you want a single
aggregated column, `rebuild_selector(sel; groupby = :all)`. Forgetting this yields one column per
component and then an error from single-column accessors like `get_data_vec`.

### Metric hierarchy (`metrics.jl`)

```
Metric
├── TimedMetric
│   ├── ComponentSelectorTimedMetric
│   │   ├── ComponentTimedMetric        # per-component time series over a selector
│   │   └── CustomTimedMetric
│   └── SystemTimedMetric               # system-wide time series
└── TimelessMetric
    └── OutputsTimelessMetric           # scalar stats (objective, solve time)
```

`compute(metric, outputs, selector; ...)` is the dispatch core; `compute_all` runs several at
once. Each metric carries a `component_agg_fn` (across components in a selector) and a
`time_agg_fn` (across the time dimension) — orthogonal. Aggregators exported: `mean`,
`weighted_mean`, `unweighted_sum`. Derive variants with `rebuild_metric`,
`with_component_agg_fn`, `with_time_agg_fn`; combine with `compose_metrics`.

Results are `DataFrame`s with a `DATETIME_COL` column; aggregation info lives in **column/table
metadata** (`is_col_meta`, `set_col_meta!`, `get_agg_meta`, `set_agg_meta!`, `AGG_META_KEY`), not
separate arguments. Accessors: `get_time_df`, `get_time_vec`, `get_data_cols`, `get_data_df`,
`get_data_vec`, `get_data_mat`.

Built-in `calc_*` metrics include `calc_active_power`(`_in`/`_out`), `calc_production_cost`,
`calc_startup_cost`/`calc_shutdown_cost`/`calc_total_cost`, `calc_curtailment`(`_frac`),
`calc_capacity_factor`, `calc_integration`, `calc_stored_energy`, `calc_discharge_cycles`,
`calc_*_forecast`, slack (`calc_system_slack_up`, `calc_is_slack_up`), and timeless stats
(`calc_sum_objective_value`, `calc_sum_solve_time`, `calc_sum_bytes_alloc`).

**`calc_system_slack_up` has no default selector, deliberately.** A default of `ACBus` would
silently return the wrong answer under an area-balance network model, where the slack variable is
indexed by `PSY.Area`. Callers supply the selector matching their network model. Do not add a
default.

### Reading entries defined elsewhere

PowerAnalytics reads outputs produced by packages it does not depend on. `VariableName`,
`AuxVariableName` and `ParameterName` (`input_utils.jl`) wrap an entry-type **name** as a string;
the component type is appended at read time to form the encoded key the outputs store uses.

Use a named key — not a typed one — whenever the entry type is defined in POM, **or is
duplicated between IOM and POM**. Six type names are currently duplicated across IOM and POM
(`ActivePowerTimeSeriesParameter`, `ActivePowerIn/OutTimeSeriesParameter`,
`ReactivePowerTimeSeriesParameter`, `RequirementTimeSeriesParameter`, `HVDCPowerBalance`). They
are distinct types, so keys built from IOM's version never match values stored under POM's.

### Generator categorization

Driven by `deps/generator_mapping.yaml`, parsed by `builtin_component_selectors.jl`
(`parse_generator_mapping_file`, `parse_injector_categories`, `parse_generator_categories`).

`gentype: Any` resolves to the parser's `root_type` (`PSY.StaticInjection`) — **every** injector,
loads included. Use `gentype: Generator` for generator-only categories; an `Any` catch-all will
sweep in loads whose variables the formulation never created.

## Verified commands

```bash
# Full test suite (test env contains all deps — never bare julia)
julia --project=test test/runtests.jl

# Single test file (ARG = file stem without .jl)
julia --project=test test/runtests.jl test_load_outputs

# Instantiate test env
julia --project=test -e 'using Pkg; Pkg.instantiate()'

# Build docs
julia --project=docs docs/make.jl

# Format (authoritative — do not hand-revert its output)
julia --project=scripts/formatter -e 'include("scripts/formatter/formatter_code.jl")'
```

Suite currently **37 passing**.

Active tests: `test_builtin_component_selectors.jl`, `test_load_outputs.jl`,
`test_realized_outputs.jl`, `test_compute_selectors.jl`, `test_calc_load_forecast.jl`.

Parked in `DISABLED_TEST_FILES` (`test/setuptests.jl`) — they depend on the PSI `Simulation`
fixture in `test/test_data/results_data.jl`, which psy6 has no equivalent for:
`test_builtin_metrics.jl`, `test_input.jl`, `test_metrics.jl`, `test_result_sorting.jl`. They are
kept on disk, not deleted. Several `test_result_sorting.jl` testsets have **zero** PSI dependency
and could be re-enabled without a rebuilt fixture.

## Gotchas & durable knowledge

- **Suite-wide "no Error log events" guard.** `runtests.jl:64` asserts zero `@error` events across
  the whole suite. A test that intentionally triggers one (e.g. the by-design
  `@error "No mapping defined …"`) must wrap it:
  `@test_logs (:error, r"No mapping defined") match_mode=:any`.

- **The test environment needs pins its dependencies cannot supply.** A dependency's own
  `[sources]` are ignored once it is no longer the root project, so PowerSystems' and
  PowerSystemCaseBuilder's pins do nothing here. Without explicit entries for
  `PowerCoreOpenAPIModels`, `PowerOperationsOpenAPIModels`, `PowerTableDataParser` and
  `PowerFlowFileParser`, Pkg silently resolves *registered* versions: the registered
  PowerFlowFileParser predates `OpenAPISystem` and breaks PowerSystemCaseBuilder's precompile,
  and the registered PowerAnalytics still depends on PowerSimulations. The
  `PowerTableDataParser` org really is `NLR-Sienna` — it looks like a typo and is not.

- **Path pins in `[sources]` are local-development only** and will not resolve in CI.

- **Coverage tests the layer, not the integration.** Three real defects shipped against a green
  suite and were found only by driving the package from PowerGraphics: selector resolution
  imported from the wrong package, an `eval_fn` that rejected kwargs, and the duplicated
  parameter types above. When adding a metric or a read path, test it through `compute` against
  an `IS.Outputs`, not just in isolation.

- **`metrics.jl:700`'s functor silently drops kwargs** for `OutputsTimelessMetric`. Known,
  unfixed.

- **Wide-format only.** The metrics/output layer is hard-wired to a 2-D wide DataFrame
  (`DATETIME_COL` + one column per component); wide is forced at the `read_key_wide` seam. Native
  long-format and 3-D support is a real design change, not a flag flip — do not implement before
  a design is approved. POM's sparse keys (`ActivePowerReserveVariable` 3-D,
  `PiecewiseLinearBlockReserveOffer` 4-D, `HVDCPiecewiseLossVariable`) stay unreadable in wide.

## When modifying code

- Match construction idioms in `builtin_metrics.jl` / `builtin_component_selectors.jl`; use
  multiple dispatch on the `Metric`/selector hierarchy (no `isa`/`<:` branching).
- Fail fast with actionable errors (`NoOutputError`) — never return silently-wrong aggregates,
  and never accept kwargs you then discard.
- Changes ripple to PowerGraphics: preserve DataFrame column conventions and metadata keys.
- All exports go in `src/PowerAnalytics.jl`. Respect include order when adding constants/types.
- Run the formatter and the full suite before reporting done.
