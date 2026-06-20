# PowerAnalytics.jl — Claude Guide

Platform-wide Sienna conventions (performance, type stability, formatter, environments, code style) live in `.claude/Sienna.md` — read it too. This file is repo-specific and does not restate them.

## Package Purpose & Place in the Stack

PowerAnalytics provides analytic routines for **post-processing power-system simulation
results** produced by PowerSimulations.jl. It consumes `PSI.SimulationResults` and
`ProblemResults`, and turns raw optimization output into aggregated, categorized
time-series metrics (active power, production/startup/total cost, curtailment, capacity
factor, stored energy, slack, objective value, solve time, etc.).

Downstream: PowerGraphics.jl consumes PowerAnalytics output for visualization; users also
use it directly for reporting. Preserve DataFrame column conventions and metadata keys —
breaking them breaks PowerGraphics and user code.

Current facts (verify against `Project.toml`): version **1.4.0**; compat
**PowerSimulations 0.36**, **PowerSystems ^5.10**, **InfrastructureSystems 3**, julia ^1.10.
Aliases in the main module: `PSY`, `IS`, `PSI`.

## Architecture & `src/` Layout

Two layers coexist — **legacy** ("Old PowerAnalytics") and the **new metrics framework**.
Prefer the new framework for new functionality. Include order (from `src/PowerAnalytics.jl`)
matters; legacy files load before new-framework files.

- `PowerAnalytics.jl` — module entry: all exports, imports, aliases, include order, submodule `using`s.
- `definitions.jl` — supported variable/parameter constants, slack/load renaming maps, `GENERATOR_MAPPING_FILE`.

Legacy:
- `get_data.jl` — `get_generation_data`, `get_load_data`, `get_service_data`, `categorize_data`.
- `fuel_results.jl` — fuel-category aggregation, `make_fuel_dictionary`, `get_generator_category`.

New framework:
- `input_utils.jl` — results loading, `create_problem_results_dict`, generator-mapping parsing, `NoResultError`.
- `output_utils.jl` — DataFrame column-metadata helpers, time-series/data accessors.
- `metrics.jl` — `Metric` type hierarchy, `compute`, `compute_all`, `aggregate_time`, `compose_metrics`, `NoResultError`.
- `builtin_component_selectors.jl` — `Selectors` submodule; fuel/category selectors.
- `builtin_metrics.jl` — `Metrics` submodule; `calc_*` metric constants.

## Public API

### ComponentSelector (defined in PowerSystems.jl, re-exported here)

A selector is a **declarative query**, not a materialized set — it is resolved against a
`System`/`Results` at `compute` time. `make_selector` builds them from a type, a filter
closure, or named subselectors. Types: `ComponentSelector`, `SingularComponentSelector`,
`PluralComponentSelector`. Built-ins (`Selectors` submodule): `all_loads`, `all_storage`,
`injector_categories`, `generator_categories`, plus fuel/category selectors derived from
the generator-mapping YAML.

### Metric hierarchy (`metrics.jl`)

```
Metric
├── TimedMetric
│   ├── ComponentSelectorTimedMetric
│   │   └── ComponentTimedMetric        # per-component time series over a selector
│   ├── SystemTimedMetric               # system-wide time series
│   └── CustomTimedMetric
└── TimelessMetric
    └── ResultsTimelessMetric           # scalar results stats (objective, solve time)
```

`compute(metric, results; ...)` is the dispatch core; `compute_all` runs several at once.
Each metric carries a `component_agg_fn` (aggregates **across components** in a selector)
and a `time_agg_fn` (aggregates **across the time dimension**) — orthogonal. Aggregators
exported: `mean`, `weighted_mean`, `unweighted_sum`. Derive variants with `rebuild_metric`,
`with_component_agg_fn`, `with_time_agg_fn`; combine with `compose_metrics`.

Results are `DataFrame`s with a `DATETIME_COL` datetime column; aggregation info lives in
**column/table metadata** (`is_col_meta`, `set_col_meta!`, `get_agg_meta`, `set_agg_meta!`,
`AGG_META_KEY`), not separate arguments. Data accessors: `get_time_df`, `get_time_vec`,
`get_data_cols`, `get_data_df`, `get_data_vec`, `get_data_mat`.

Built-in `calc_*` metrics (`Metrics` submodule) include `calc_active_power`(`_in`/`_out`),
`calc_production_cost`, `calc_startup_cost`/`calc_shutdown_cost`/`calc_total_cost`,
`calc_curtailment`(`_frac`), `calc_capacity_factor`, `calc_integration`, `calc_stored_energy`,
`calc_discharge_cycles`, `calc_*_forecast`, slack (`calc_system_slack_up`, `calc_is_slack_up`),
and timeless stats (`calc_sum_objective_value`, `calc_sum_solve_time`, `calc_sum_bytes_alloc`).

### Generator categorization

Driven by `deps/generator_mapping.yaml`. Fuel/category selectors and `make_fuel_dictionary`
derive from it. Lookup precedence in `fuel_results.jl` `get_generator_category`:
`for t in supertypes(gentype), pm in (primemover, nothing), f in (fuel, nothing), ext in (ext, nothing)`.
`Any` is the last supertype, so `{gentype: Any}` rules are the general fallback; within a
level the actual prime mover is tried before `nothing`, so fuel-only fallbacks never shadow
specific PM rules. `make_fuel_dictionary` categorizes **Generators + Storage only** (not
loads); Storage splits into "Storage In"/"Storage Out" plus a default "Curtailment".

## Verified Commands

```bash
# Run full test suite (test env contains all deps — never bare julia)
julia --project=test test/runtests.jl

# Run a single test file (ARG = file name without .jl, e.g. test_metrics)
julia --project=test test/runtests.jl test_metrics

# Instantiate test env
julia --project=test -e 'using Pkg; Pkg.instantiate()'

# Build docs
julia --project=docs docs/make.jl

# Format (authoritative — do not hand-revert its output)
julia --project=scripts/formatter -e 'include("scripts/formatter/formatter_code.jl")'
```

Tests live in `test/`; the runner (`runtests.jl`) auto-discovers `test_*.jl` via
`@includetests ARGS`. Coverage: `test_builtin_component_selectors.jl`, `test_builtin_metrics.jl`,
`test_metrics.jl`, `test_result_sorting.jl`, `test_input.jl`. Uses PowerSystemCaseBuilder.jl
cases and stored `test/test_data/`.

Docs (`docs/src/`) follow Diataxis: `tutorials/` (Literate.jl), `how_to_guides/`,
`explanation/`, `reference/` (`public.md` `@autodocs Public=true`, `internal.md`,
`developer_guidelines.md`).

## Gotchas & Durable Knowledge

- **Suite-wide "no Error log events" guard.** `runtests.jl:64` asserts zero `@error` events
  across the whole suite. Any test that intentionally triggers an unmapped-generator lookup
  (the by-design `@error "No mapping defined …"`) must wrap it:
  `@test_logs (:error, r"No mapping defined") match_mode=:any`. This includes direct
  `get_generator_category(...) === nothing` assertions, not just `make_fuel_dictionary`.

- **Stale-test discipline.** When a test asserts a bare count/`symdiff` against a category
  list and fails, suspect staleness vs. a deliberate refactor before assuming a code bug —
  `git log -L` the testset and reproduce actual values. Prefer **set-based** assertions over
  counts. (Real category count for stored cases is 9, not 8, after the Storage In/Out split.)
  Clear stale `test/test_results/results/*` if a `RunStatus.FAILED` surfaces from old data.

- **Generator-mapping fuel coverage.** `deps/generator_mapping.yaml` covers the full
  `PSY.ThermalFuels` enum via `{gentype: Any, primemover: null, fuel: X}` fallbacks. There is
  deliberately **no blanket `{null,null}` catch-all** — keeping the unmapped `@error`
  meaningful. Don't add one. Generic gas → NG-Steam; coal→Coal; petroleum fuels→Petroleum;
  municipal/landfill/biomass→Biopower; waste heat→Other. PM-specific rules win.

- **PSI 0.34+ result modernization (parked, design-worthy).** The new framework is hard-wired
  to a 2D **wide** DataFrame (`DATETIME_COL` + one column per component) across the whole
  metrics/output layer; wide format is forced at the `input_utils.jl`/`get_data.jl` read sites.
  Native long-format (and 3D results) support is a real design change, not a flag flip — do not
  implement before a design+plan is approved. A `test_input.jl` `create_problem_results_dict`
  system-comparison assertion was commented out (PSI 0.34 deserialization exposed an empty
  HDF5 time-series store on `populate_system=true`); re-enable when the PSI-side fix lands.

## When Modifying Code

- Match construction idioms in `builtin_metrics.jl` / `builtin_component_selectors.jl`; use
  multiple dispatch on the `Metric`/selector hierarchy (no `isa`/`<:` branching).
- Fail fast with actionable errors (`NoResultError`) — never return silently-wrong aggregates.
- Changes ripple to PowerGraphics.jl and user reporting: preserve DataFrame column conventions
  and metadata keys.
- All exports go in `src/PowerAnalytics.jl`. Respect include order when adding constants/types.
- Run the formatter and full suite before reporting done.
