# PowerAnalytics: psy6 port + self-contained outputs, reloaded as results

Design and plan. Written 2026-08-14, revised twice after review.

> **Status 2026-08-17: Part A implemented, Parts B and C superseded.**
> Commit `1870a0c` executed phases 1–8; the Part A gate now passes. §0 (terminology) and §3
> (the round trip) still hold and are still the reference. §5's baseline table is obsolete —
> `jd/schema_matching`, `jd/data_source_sa` and `jd/remove_pscb_code` have merged into their
> line branches. For current state and the remaining work see
> `2026-08-17-pa-part-b-self-contained-outputs.md`.

## 0. Terminology

Fixed vocabulary for this plan and the code it produces. The whole point of the split is to keep
these two apart.

| Term | Means | Lives in |
|---|---|---|
| **Outputs** | The raw, unprocessed output of a model application — variable/parameter/expression values as solved. | IOM defines them (`OptimizationProblemOutputs`); POM produces and serializes them. |
| **Results** | The processed, aggregated, summarized artifacts of analysis. | PowerAnalytics produces them. |

So PA **loads outputs** and **produces results**. Any PA identifier that says "result" when it means
raw model output is misnamed and gets renamed — see §8.6.

## 1. Goal

1. **Port PA to psy6.** Drop PowerSimulations. PA depends on **IS + IOM + PSY** — never POM.
2. **Make a serialized outputs directory self-contained.** Everything needed to interpret the
   outputs, the `PSY.System` included, sits in the directory — the approach PSI used.
3. **PA reloads those outputs and owns the analysis** that turns them into results.

```
IS ─┬─ IOM   outputs layer: OptimizationProblemOutputs, read_*, serialization  (unchanged)
    │         │
    ├─ PSY ───┼── PNM ── POM   models; solve! serializes outputs + the System JSON
    │         │
    └─────────┴── PA    loads outputs → produces results
```

PA never imports POM. POM's variable types are reached by **string key**, which works because
`deserialize_key` is a plain `Dict{String, OptimizationContainerKey}` lookup.

## 2. Decisions

| Question | Decision |
|---|---|
| Missing simulation-results layer | Single-model outputs, with a dispatch seam for a future simulation type. |
| Legacy layer (`get_data.jl`, `fuel_results.jl`) | Delete. New metrics framework only. |
| `SystemBalanceSlack*` multi-column | Slack becomes a `ComponentSelectorTimedMetric`. |
| Test fixtures | Park the simulation-dependent tests; build a new suite alongside. |
| `[sources]` | Path pins to the sibling checkouts. |
| PA's power-domain half | Keep it. PA depends on IS + IOM + PSY; only POM is dropped. |
| Where the outputs layer lives | **IOM.** Unchanged, definitions included. |
| Outputs directory | **Self-contained** — carries the System JSON, PSI-style. |
| Outputs vs results naming | Outputs = raw model output; results = PA's processed analysis. |
| Slack selector default | **No default.** Require the selector. |
| `SystemTimedMetric` / `SYSTEM_COL` | **Keep both exported** as extension points. |
| System-JSON write | **Port psy5 PSI's approach** — `system_to_file` setting, `PSY.to_json` into the model output dir. |
| Realized-output scope | **One-model case only**, with an interface a multi-model version slots into. |

## 3. The round trip

Traced step by step against the IOM source.

| Step | Where | Status |
|---|---|---|
| POM `solve!` serializes outputs | `POM/src/operation/decision_model.jl:228`, `emulation_model.jl:280` | exists |
| Write outputs to disk | `IOM/.../optimization_problem_outputs.jl:362` — `Serialization.serialize` of `_copy_for_serialization`, which nulls `source_data` but keeps `source_data_uuid` | exists |
| **Write the System JSON** | — | **missing** |
| Reload outputs from a directory | `optimization_problem_outputs.jl:374` | exists |
| Locate the System file | `make_system_filename(uuid) = "system-$(uuid).json"` at `:109` | exists |
| Read the System back | `load_system` at `:116` builds an `IS.InfrastructureSystemsContainer`, not a `PSY.System` | insufficient |
| Attach with UUID validation | `set_source_data!` at `:335` | exists |

### 3.1 The read side is orphaned

`load_system` looks for `joinpath(get_outputs_dir(res), make_system_filename(uuid))` — the filename
convention already exists. **Nothing writes that file.** Verified: no `to_json`, `serialize_system`,
or equivalent call targeting the outputs directory anywhere in IOM or POM.

So the directory is not self-contained today, and the reader that would make it so has never had
anything to read.

### 3.2 Who writes it — port the psy5 PSI implementation

psy5 PowerSimulations already solved this. `PSI 0.33.5`,
`src/operation/operation_model_serialization.jl:38-46`, inside `serialize_problem`:

```julia
sys_to_file = get_system_to_file(get_settings(model))
if sys_to_file
    sys = get_system(model)
    sys_filename = joinpath(get_output_dir(model), make_system_filename(sys))
    # Skip serialization if the system is already in the folder
    !ispath(sys_filename) && PSY.to_json(sys, sys_filename)
else
    sys_filename = nothing
end
```

Two details worth copying: the write is **gated on a `system_to_file` setting**, and it is **skipped
if the file already exists**, so re-solving into the same directory is cheap.

**The path already matches.** PSI writes to `joinpath(get_output_dir(model), make_system_filename(sys))`.
IOM's `load_system` reads `joinpath(get_outputs_dir(res), make_system_filename(uuid))`, and
`outputs_dir` is set to `get_output_dir(model)` in the `OptimizationProblemOutputs(model)`
constructor (`problem_outputs.jl`). So the psy5 write path drops in unchanged.

Beware the naming trap while implementing: on `OptimizationProblemOutputs`, **`outputs_dir` is the
model output directory** and **`output_dir` is the `outputs/` subdirectory beneath it**
(`mkpath(joinpath(get_output_dir(model), "outputs"))`). They are one character apart and mean
different things.

**Two gaps against psy5:**

1. **IOM's `Settings` has no `system_to_file` field.** Verified — `grep -rn system_to_file` across
   IOM and POM returns nothing, and the `Settings` struct (`IOM/src/core/settings.jl:2-23`) has no
   such field. Add it, defaulting to `true` as PSI did.
2. **Nothing calls `PSY.to_json`.** psy6's `serialize_optimization_model`
   (`IOM/src/operation/optimization_model_interface.jl:324`) writes only `jump_model.json`; there is
   no `ProblemSerializationWrapper` equivalent carrying the system filename.

**IOM cannot write the file itself** — no PowerSystems dependency (verified,
`grep -c PowerSystems IOM/Project.toml` → 0). **POM can**, and it is what is present at solve time.
So the setting lands in IOM and the write lands in POM.

**This is the one change outside PA.** An earlier draft claimed the work was PA-only; that is no
longer true. It adds a setting and a guarded call, and removes nothing.

### 3.3 Time series come along

`PSY.to_json` writes the time-series files beside the System JSON, so the outputs directory grows by
the size of the system's time series. psy5 accepted exactly this and made the whole write
opt-out-able via `system_to_file` rather than stripping time series. Do the same: forecast metrics
(`calc_active_power_forecast`, `calc_capacity_factor`, `calc_curtailment`) need the time series, so a
stripped system would silently break them.

### 3.4 PA's loader

With the directory self-contained, PA's entry point takes a path and nothing else:

```julia
"""
Load a serialized outputs directory. The directory is self-contained: the `PSY.System` that
produced the outputs is stored alongside them, so no system argument is needed.

Returns raw model outputs. Analysis of them produces results — see [`compute`](@ref).
"""
function load_outputs(directory::AbstractString)
    out = IOM.OptimizationProblemOutputs(directory)
    file = joinpath(
        IOM.get_outputs_dir(out),
        IOM.make_system_filename(IOM.get_source_data_uuid(out)),
    )
    isfile(file) || error(
        "No system file at $file. The outputs directory is not self-contained; it was " *
        "probably written before POM began serializing the System.",
    )
    IOM.set_source_data!(out, PSY.System(file; time_series_read_only = true))
    return out
end

"Load a serialized outputs directory, attaching a `PSY.System` you already hold."
function load_outputs(directory::AbstractString, sys::PSY.System)
    out = IOM.OptimizationProblemOutputs(directory)
    IOM.set_source_data!(out, sys)
    return out
end
```

The UUID check inside `set_source_data!` makes the two-argument form safe.

## 4. What PA owns on top

Additive. IOM keeps its own `read_*` family for its use and POM's; PA builds the analysis above it.

- **Realized-output computation.** `IOM.get_realized_timestamps` handles one model's timestamp
  arithmetic. The analysis meaning — stitching non-overlapping windows across several models into
  one series — has no home today and belongs in PA. **Scope: build the one-model case only**, and
  shape the interface so a multi-model version slots in without changing callers. With no simulation
  layer in psy6 every timestamp of a single model is realized, so the computation is currently a
  pass-through; the value now is fixing the API shape, not the arithmetic.
- **The DataFrame shaping the metrics framework needs**: WIDE pivoting at the read boundary, the
  column-metadata conventions in `output_utils.jl`, `aggregate_time`, `compose_metrics`, and the
  `component_agg_fn` / `time_agg_fn` machinery.
- **The `Metric` hierarchy and all `calc_*` built-ins**, which are PSY-flavoured.

## 5. Baseline: what builds today

| Repo | Branch | Dirty |
|---|---|---|
| InfrastructureSystems.jl | `jd/data_source_sa` | 0 |
| PowerSystems.jl | `jd/schema_matching` | 3 |
| PowerNetworkMatrices.jl | `psy6` | 11 |
| InfrastructureOptimizationModels.jl | `jd/network-sources` | 0 |
| PowerOperationsModels.jl | `jd/network_matrix_consolidation` | 8 |
| PowerSystemCaseBuilder.jl | `jd/remove_pscb_code` | 16 |

POM does not precompile in any all-git or all-path configuration:

- **All git pins**: `UndefVarError: sparse_variable_key_type` at `POM/src/core/variables.jl:537` —
  the pinned IOM rev `jd/network-sources` lags the local checkout
  (`src/core/optimization_container.jl:742`).
- **All five siblings dev-linked**: `UndefVarError: ReserveNonSpinning` at
  `POM/src/core/problem_template.jl:286` — PSY `jd/schema_matching` retired it for
  `AbstractReserve` / `OnlineReserve` / `OfflineReserve` (`2e1cf2b5a`, `c9bc8e473`).

**Verified green**: local IOM + POM + PNM by path, PSY at git `psy6`, IS at git `IS4`.

Dropping POM loosens this for PA: PA builds and tests against IS + IOM + PSY alone. Only the POM
write-side change (§3.2) and the solved-model fixture need POM to build.

## 6. Load-time note

Cold load, fresh process each: IS 2.13 s, **IOM 3.16 s**, PSY 1.83 s, POM 3.27 s.

Dropping POM buys roughly 0.1 s — IOM alone already costs more than PSY, and the weight is JuMP,
HDF5 and MathOptInterface. If "lightweight" means load time, this does not deliver it. What it does
deliver: a clean dependency graph, PA testable without POM, and PA reusable against any IOM producer.

## 7. PA after the change

### 7.1 Dependencies

Drop `PowerSimulations`. Add `InfrastructureOptimizationModels`. Keep `PSY`, `IS`, `DataFrames`,
`DataStructures`, `Dates`, `TimeSeries`, `YAML`, `Statistics`. No POM.

`[sources]` entries must appear in `[deps]` or `[extras]` — Pkg errors otherwise, verified. PNM is
transitive only, so it goes in `[extras]`:

```toml
[sources]
InfrastructureOptimizationModels = {path = "../InfrastructureOptimizationModels.jl"}
InfrastructureSystems = {path = "../InfrastructureSystems.jl"}
PowerSystems = {path = "../PowerSystems.jl"}
```

Interim: path-pinning PSY breaks POM (§5), so use `PowerSystems = {rev = "psy6", ...}` until POM is
ported to the new reserve hierarchy. No version or compat bumps — `version = "1.5.0"` stays.

### 7.2 File layout

```
src/
  PowerAnalytics.jl            module: exports, IOM/PSY aliases, include order
  load_outputs.jl              NEW — load a self-contained outputs directory
  realized_outputs.jl          NEW — realized-output computation
  input_utils.jl               key construction, the read seam, component/system readers
  output_utils.jl              column-metadata helpers                    (unchanged)
  metrics.jl                   Metric hierarchy, compute, aggregation     (IS.Outputs rename)
  builtin_component_selectors.jl                                          (unchanged)
  builtin_metrics.jl           calc_* metrics                             (units + slack + keys)
```

Deleted: `get_data.jl`, `fuel_results.jl`, `definitions.jl`.

### 7.3 Reaching POM types without depending on POM

Replace type references with the encoded string form:

```julia
const SYSTEM_SLACK_UP_KEY = "SystemBalanceSlackUp__System"
```

`read_variable(out, "SystemBalanceSlackUp__System")` resolves through
`deserialize_key(metadata, name)`. PA needs no POM dep at any point. Reloading in a fresh session
does require POM *loadable* — the serialized keys carry POM type parameters — but that is the user's
session, not PA's dependency graph. A missing key already errors with `"$name is not stored"`.

## 8. The psy6 port

### 8.1 Symbol migration

| PSI symbol | Becomes |
|---|---|
| `VariableKey` `ParameterKey` `ExpressionKey` `AuxVarKey` | `IOM.` same name |
| `ICKey` | `IOM.InitialConditionKey` |
| `VariableType` … `InitialConditionType` | `IOM.` same name; all share `IS.Optimization.OptimizationKeyType` |
| `OptimizationProblemResults` | `IOM.OptimizationProblemOutputs` |
| `read_results_with_keys` | `IOM.read_outputs_with_keys` — no `cols` kwarg, defaults `TableFormat.LONG` |
| `read_optimizer_stats` | `IOM.read_optimizer_stats` |
| `IS.Results` | `IS.Outputs` — 51 signatures |
| `SimulationResults`, `SimulationProblemResults`, `get_decision_problem_results`, `load_results!` | no replacement |
| `SystemBalanceSlack*`, `FlowActivePower*`, `PowerFlowBranchActivePower*`, `EnergyVariable`, `PowerOutput` | string keys per §7.3 |

`EntryType`'s five-member `Union` is replaced by dispatch on
`IS.Optimization.OptimizationKeyType` (`IS/src/Optimization/optimization_container_types.jl:3`).
`SystemEntryType` stays a two-member `Union{VariableType, ExpressionType}`.

### 8.2 Delete the legacy layer

`src/get_data.jl`, `src/fuel_results.jl`, `src/definitions.jl`. Verified clean by reference scan:
every `definitions.jl` constant is referenced only from `get_data.jl`, except
`GENERATOR_MAPPING_FILE` and `UNMAPPED_GENERATOR_CATEGORY` (only from `fuel_results.jl`);
`SUPPORTED_OVERGENERATION_VARIABLE` and `SUPPORTED_UNSERVEDENERGY_VARIABLES` have no references;
`builtin_component_selectors.jl` declares its own `FUEL_TYPES_DATA_FILE` and never calls into
`fuel_results.jl`.

`deps/generator_mapping.yaml` stays. Exports removed: `make_fuel_dictionary`,
`get_generation_data`, `get_load_data`, `get_service_data`, `get_branch_data`, `categorize_data`,
`no_datetime`.

### 8.3 The read seam

```julia
function read_key_wide end

function read_key_wide(
    out::IOM.OptimizationProblemOutputs,
    key::IOM.OptimizationContainerKey;
    start_time::Union{Nothing, DateTime} = nothing,
    len::Union{Int, Nothing} = nothing,
)
    return only(
        values(
            IOM.read_outputs_with_keys(
                out, [key];
                start_time = start_time, len = len,
                table_format = IS.TableFormat.WIDE,
            ),
        ),
    )
end
```

Replaces both `_read_results_with_keys_wrapper` methods and is the documented extension point for a
future simulation-outputs type. `make_entry_kwargs` and the `load_results!` / `cols` fast path are
deleted — they existed only for `SimulationProblemResults`.

### 8.4 Slack becomes a selector metric

POM adds slack as
`add_variable_container!(container, T, PSY.System, reference_buses, time_steps)`
(`POM/src/network_models/network_slack_variables.jl:20`) — one column per reference bus, and per
`PSY.Area` under `AreaBalanceNetworkModel` (`:44`). The existing `@assert size(res, 2) == 2` is dead.

```julia
make_system_indexed_metric(name::String, key::String) =
    ComponentTimedMetric(; name = name,
        eval_fn = (out::IS.Outputs, comp::Component; kwargs...) ->
            read_system_indexed_output(out, key, comp; kwargs...))

const calc_system_slack_up = make_system_indexed_metric("SystemSlackUp", SYSTEM_SLACK_UP_KEY)
```

`compute(calc_system_slack_up, outputs, make_selector(PSY.ACBus))` gives per-bus slack; the default
`component_agg_fn = sum` collapses it to the total. `make_selector(PSY.Area)` covers area balance.
**No default selector** — a default of `ACBus` would silently return the wrong answer under
`AreaBalanceNetworkModel`. `make_calc_is_slack_up` becomes a `CustomTimedMetric` thresholding every
data column rather than `first(get_data_cols(val))`.

**Breaking**: both slack metrics now take a selector.

### 8.5 Units

POM sets `convert_output_to_natural_units = true` for the power variables
(`POM/src/core/variables.jl:854–861`), so outputs arrive in MW. Component quantities must be read in
`PSY.NU`, not `PSY.SU`.

| `builtin_metrics.jl` | Current | Becomes |
|---|---|---|
| `:264` | `PSY.get_rating(comp)` | `PSY.get_rating(comp, PSY.NU)` |
| `:319` | `PSY.get_storage_capacity(comp)` | `PSY.get_storage_capacity(comp, PSY.NU)` |
| `:317` | `PSY.get_storage_level_limits(comp)` | unchanged — dimensionless, no units arg |
| `:278`, `:291` | `get_start_up` / `get_shut_down` | unchanged — dollars, no units arg |

Verified across `ThermalGenerationCost`, `StorageCost`, `MarketBidCost`,
`MarketBidTimeSeriesCost`. Pre-existing and separate: `ThermalGenerationCost.start_up` is
`Union{StartUpStages, Float64}`, so `calc_startup_cost`'s scalar multiply only handles the
`Float64` case.

### 8.6 Naming sweep

Per §0, PA identifiers that say "result" but mean raw model output get renamed. All exported, all
breaking, which is fine under no-shims:

| Current | Becomes | Why |
|---|---|---|
| `read_component_result` | `read_component_output` | reads a raw output column |
| `read_system_result` | `read_system_indexed_output` | same, and the semantics change anyway (§8.4) |
| `NoResultError` | `NoOutputError` | raised when an output key or column is absent |
| `ResultsTimelessMetric` | `OutputsTimelessMetric` | computes over the outputs container |
| `RESULTS_COL` | `OUTPUTS_COL` | for consistency |

`compute`, `compute_all`, and the DataFrames they return keep "result" language — those *are*
results.

`SystemTimedMetric` and `SYSTEM_COL` stay exported as extension points for user-defined
whole-system metrics, even though no built-in produces one after §8.4.

## 9. Tests

Parked, kept on disk, added to `DISABLED_TEST_FILES` with a header explaining why:
`test/test_data/results_data.jl`, `test_result_sorting.jl`, `test_input.jl`,
`test_builtin_metrics.jl`, `test_metrics.jl`. `test_builtin_component_selectors.jl` uses a plain
`System` and needs no fixture change. `test_input.jl`'s `read_component_result` coverage is still
valid and must be re-homed under its new name, not lost.

**Two tiers:**

- **Tier 1, no POM, no solver.** Build an `IOM.OptimizationProblemOutputs` from hand-made
  `DenseAxisArray`s, serialize it with a PSB system's JSON alongside, reload through
  `load_outputs(dir)`, and assert on the metrics. Covers the self-contained round trip, WIDE
  shaping, units, slack column selection, and realized outputs. **Runs today** against the green
  IS + IOM + PSY environment.
- **Tier 2, POM integration.** Solve a real `DecisionModel` through POM as
  `POM/test/test_model_decision.jl:45` does, confirm the System JSON is written, reload in PA.
  Disabled until POM builds.

Tier 1 is why this is testable now. Neither IOM nor POM needs a dependency on PA.

### 9.1 The new PA fixture is a port

`results_data.jl:227`'s `run_test_prob()` already builds a single `DecisionModel`, solves it, and
returns `OptimizationProblemResults(prob)`. Lift it with these substitutions:

| PSI | psy6 |
|---|---|
| `OptimizationProblemResults(prob)` | `IOM.OptimizationProblemOutputs(prob)` |
| `ProblemTemplate` | `POM.PowerOperationsProblemTemplate` |
| `template_unit_commitment()` | **no equivalent** — build the template explicitly |
| `CopperPlatePowerModel` / `PTDFPowerModel` | `CopperPlateNetworkModel` / `PTDFNetworkModel` |
| `FixedOutput` | `IOM.FixedOutput` |

PSB psy6 has `c_sys5_uc`, `c_sys5_bat`, `c_sys5_re`, `c_sys5_ed`, `c_sys5_all_components`,
`5_bus_hydro_uc_sys`, `RTS_GMLC_DA_sys`. Slack coverage needs
`NetworkModel(CopperPlateNetworkModel; use_slacks = true)`.

Test deps drop `PowerSimulations`, `HydroPowerSimulations`, `StorageSystemsSimulations`.

## 10. Phased plan

Every phase ends with a compile check and the formatter
(`julia --project=scripts/formatter -e 'include("scripts/formatter/formatter_code.jl")'`).

**Part A — PA on psy6.** PA only. Can start today.

1. **Environment.** Drop PSI, add IOM, path pins, PSY interim override. Gate: `Pkg.resolve()`.
2. **Legacy deletion.**
3. **Module surface.** IOM alias, the `PSI.` retarget, `IS.Results` → `IS.Outputs`.
4. **String keys** (§7.3).
5. **Read seam** (§8.3).
6. **Naming sweep** (§8.6).
7. **Slack redesign** (§8.4) and **units** (§8.5).
8. **Part A gate**: `using PowerAnalytics` succeeds with **no POM in the environment at all**.

**Part B — self-contained outputs.** Two changes outside PA, both ports of psy5 PSI.

9. **IOM gains a `system_to_file` setting** (§3.2), defaulting to `true`, mirroring PSI's
   `get_system_to_file(get_settings(model))`. Additive; nothing else in IOM changes.
10. **POM writes the System JSON** (§3.2) — the guarded `PSY.to_json` call in each of the two solve
    paths, skipping when the file already exists. Gate: a solved model's output directory contains
    `system-$(uuid).json`. Blocked on POM building.
11. **`load_outputs`** (§3.4), both the self-contained and bring-your-own-system forms.
12. **Realized outputs** (§4) — one-model case, extensible interface.
13. **Tier 1 tests** (§9) — the full round trip, no POM, no solver.

**Part C — finish.**

14. **Docs.** InterLinks retarget, park the simulation tutorials, fix `missing_docs` by registering
    docstrings — never `warnonly`. Gate: `julia --project=docs docs/make.jl` clean.
15. **Tier 2 tests.**

Phases 1–6 are mechanical. Phases 7, 11, and 12 carry the design work. Phases 10 and 15 wait on POM
building. Note phase 11 can be written and unit-tested against a hand-written outputs directory
before phases 9–10 land, so the POM blocker gates very little.

## 11. Open items

1. **Should PA re-export IOM's `read_*` family** so users have one import, or keep them qualified as
   `IOM.read_variable`? Re-exporting is friendlier; qualifying keeps the outputs/results layering
   visible, which §0 argues for.
2. **Does `system_to_file` belong in IOM's `Settings` or POM's?** PSI put it in `Settings`, which in
   psy6 is IOM-owned — but the thing it gates (`PSY.to_json`) can only run in POM. A POM-side
   setting would keep the PSY-shaped concern out of the domain-neutral package. Recommendation:
   follow PSI and put it in IOM's `Settings`, since it is a plain `Bool` and matching psy5 keeps the
   port mechanical.

## 12. Out of scope

- Reconciling POM to PSY `jd/schema_matching`'s `AbstractReserve` hierarchy.
- Bumping IOM's pinned rev so POM's own env resolves `sparse_variable_key_type`.
- An IOM sequential-simulation layer.
- Changing how IOM persists outputs. Noted preference if it is ever revisited: **HDF5** over the
  current `Serialization.serialize`. (psy5 PSI used HDF5 for its *simulation* store —
  `hdf_simulation_store.jl:727` `serialize_system!` — while single-problem serialization went to
  JSON on disk. The single-model path this plan needs is the JSON one.)
- Native long-format / 3-D support in the metrics layer. `to_outputs_dataframe` has a WIDE method
  only for 2-D `DenseAxisArray{Float64, 2, Tuple{Vector{String}, IntegerAxis}}`
  (`jump_utils.jl:391`, `:401`), so POM's sparse keys — `ActivePowerReserveVariable` (3-D),
  `PiecewiseLinearBlockReserveOffer` (4-D), `HVDCPiecewiseLossVariable` — stay unreadable in WIDE.
- Reimplementing the deleted legacy API on the metrics framework.
