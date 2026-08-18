# PowerAnalytics: Part B — self-contained outputs, env repair, test port

Written 2026-08-17. Supersedes the Part-A sections of
`2026-08-14-pa-psy6-and-results-layer.md`; §0 (terminology) and §3 (round trip) of that
document still hold and are not repeated here.

## 0. What changed since the 08-14 plan

**Part A landed.** Commit `1870a0c` "Drop PowerSimulations; port PowerAnalytics to IOM + PSY"
executed phases 1–8. Verified against the source, not the commit message:

| 08-14 phase | State |
|---|---|
| 1 Environment — drop PSI, add IOM | done; `Project.toml` has no `PowerSimulations` |
| 2 Legacy deletion | done; `get_data.jl`, `fuel_results.jl`, `definitions.jl` gone |
| 3 Module surface — `IS.Results` → `IS.Outputs` | done |
| 4 String keys | done, and **better than planned** — `VariableName` / `AuxVariableName` wrapper structs instead of raw `const` strings, dispatching to the public `IOM.read_variable` / `read_aux_variable` rather than reaching into `deserialize_key` |
| 5 Read seam `read_key_wide` | done, `input_utils.jl:75` |
| 6 Naming sweep | done — `read_component_output`, `read_system_indexed_output`, `NoOutputError`, `OutputsTimelessMetric`, `OUTPUTS_COL` |
| 7 Slack + units | done — `make_system_indexed_metric`, `SYSTEM_SLACK_UP_KEY = VariableName("SystemBalanceSlackUp")` |
| 8 Part A gate | **now passes — verified below** |

**The serde merge.** PSY `jd/schema_matching` merged to `psy6` (PR #1746, `239dc1bff`), carrying
`99c9531ee` "Wire the OpenAPI serde into System"; IS `jd/openapi_is_attributes` merged to `IS4`
(PR #607). `PSY.to_json` / `PSY.System(file)` round-trip is the mechanism §3 of the 08-14 plan
depends on, and it is the reason Part B is startable now.

**Part B has not started.** Verified: `grep -rn system_to_file` across IOM and POM returns
nothing, and nothing anywhere writes `system-$(uuid).json`. `IOM.load_system`
(`optimization_problem_outputs.jl:116`) is still orphaned and still builds an
`IS.InfrastructureSystemsContainer` rather than a `PSY.System`.

## 1. Verified baseline — 2026-08-17

| Repo | Branch | Dirty |
|---|---|---|
| InfrastructureSystems.jl | `IS4` | 0 |
| PowerSystems.jl | `psy6` | 0 |
| PowerNetworkMatrices.jl | `psy6` | 0 |
| InfrastructureOptimizationModels.jl | `jd/network-sources` | 0 |
| PowerOperationsModels.jl | `jd/network_matrix_consolidation` | 4 (untracked `.claude`/`.lavish` only) |
| PowerSystemCaseBuilder.jl | `psy6` | 0 |
| PowerAnalytics.jl | `psy6` | 1 (see §2) |
| PowerGraphics.jl | `psy6` | 0 |

The 08-14 baseline table is obsolete: `jd/schema_matching`, `jd/data_source_sa` and
`jd/remove_pscb_code` have all merged into their line branches.

### 1.1 Part A gate: PASSES

```
=== PA OK ===
POM loaded? false
```

`using PowerAnalytics` succeeds with **no POM in the environment at all**, against local IS,
PSY, PNM, PSB, IOM. The fuel-category selectors resolve to the same 13 generator categories
the deleted `make_fuel_dictionary` produced:

```
Biopower CSP Coal Geothermal Hydropower NG-CC NG-CT NG-Steam Nuclear Other Petroleum PV Wind
```

Two things had to be fixed to get there. Both are §2.

## 2. Environment repair — do this first

### 2.1 `deps/generator_mapping.yaml` names two retired enum members  [APPLIED, unstaged]

psy6's PSY renamed two `ThermalFuels` members (`src/definitions.jl:427`). PA's YAML still used
the old spellings, so `parse_injector_categories` threw at precompile time and **PA did not
build at all**:

```
ArgumentError: enum=PowerSystems.ThermalFuelsModule.ThermalFuels
               does not have value=tirederived_fuel
  parse_fuel_category  builtin_component_selectors.jl:35
```

| YAML said | psy6 PSY has |
|---|---|
| `TIREDERIVED_FUEL` | `TIRE_DERIVED_FUEL` |
| `BLASTE_FURNACE_GAS` | `BLAST_FURNACE_GAS` (typo fixed upstream) |

Full audit of the YAML against psy6's enums: these are the **only** two mismatches. All 13
prime-mover codes (`BA CA CC CP CS CT GT HY OT PS PVe ST WT`) still exist, and every other fuel
resolves. This edit is already in the working tree, unstaged.

### 2.2 `test/Project.toml` cannot resolve  [NOT APPLIED]

`julia --project=test -e 'using Pkg; Pkg.instantiate()'` fails:

```
Unsatisfiable requirements detected for package PowerSimulations [e690365d]
```

PSI is not in `test/Project.toml`. It appears because the env cannot resolve the *local* PSY
and PSB — their unregistered OpenAPI and parser deps have no pins — so Pkg falls back to the
registered PowerAnalytics 1.4.0, which does depend on PSI. The same trap PNM's
`test/Project.toml` documents in a comment: a dependency's own `[sources]` are ignored once it
is no longer the root project.

Fix — add to `test/Project.toml`, in both `[deps]` and `[sources]`:

```toml
[deps]
PowerCoreOpenAPIModels = "b7b40286-e793-417d-a9a0-b1583e4da1cb"
PowerOperationsOpenAPIModels = "a372b6d7-45a2-44c2-8199-6a724b72e8ff"
PowerTableDataParser = "2b750c0e-0bff-11f1-9200-1befd75df6be"

[sources]
PowerCoreOpenAPIModels = {url = "https://github.com/Sienna-Platform/PowerOpenAPIModels.git", rev = "main", subdir = "PowerCoreOpenAPIModels.jl"}
PowerOperationsOpenAPIModels = {url = "https://github.com/Sienna-Platform/PowerOpenAPIModels.git", rev = "main", subdir = "PowerOperationsOpenAPIModels.jl"}
PowerTableDataParser = {url = "https://github.com/NLR-Sienna/PowerTableDataParser.jl.git", rev = "psy6"}
```

Verified: with exactly these three added, the env resolves and PA precompiles. Note the
`NLR-Sienna` org in the PTDP URL — that is what PSB and PNM both pin; it is not a typo to
"correct".

### 2.3 The main `Project.toml` INTERIM note is stale  [NOT APPLIED]

`Project.toml` git-pins IS to `IS4` and PSY to `psy6` behind a comment claiming the local IS
branch "does not precompile — it needs a `DataSource` type that its own pinned
PowerOpenAPIModels `main` rev does not carry". That is no longer true: IS `664cffbb` /
`293483d3` pin PowerCoreOpenAPIModels by git rev, and the local IS + PSY checkouts precompile
from `[sources]` paths (§1.1 was run that way). Switch both to path pins, adding the two
OpenAPI entries as §2.2 does, and delete the comment.

The 08-14 plan's reason for the PSY git pin — "path-pinning PSY breaks POM" — is also gone; POM
migrated to the psy6 reserve tree in `945bc8c`.

**Gate for §2:** `julia --project=test -e 'using Pkg; Pkg.instantiate(); using PowerAnalytics'`.

## 3. Part B — the self-contained outputs directory

Design unchanged from the 08-14 plan §3. Restated as steps with current line numbers.

### 3.1 IOM gains `system_to_file`

`IOM/src/core/settings.jl` — `Settings` currently has 23 fields and no `system_to_file`. Add
`system_to_file::Bool`, defaulting to `true`, mirroring psy5 PSI's
`get_system_to_file(get_settings(model))`. Additive; nothing else in IOM changes.

Open item from 08-14 §11.2 — IOM's `Settings` vs POM's — resolved in favour of **IOM**: it is a
plain `Bool`, and matching psy5 keeps the port mechanical. IOM cannot make the call itself
(`grep -c PowerSystems IOM/Project.toml` → 0), only gate it.

### 3.2 POM writes the System JSON

Two solve paths:

- `POM/src/operation/decision_model.jl:228` — beside the existing `serialize_outputs(outputs, IOM.get_output_dir(model))`
- `POM/src/operation/emulation_model.jl` — the matching site

Port psy5 PSI `operation_model_serialization.jl:38-46` verbatim in shape:

```julia
if get_system_to_file(get_settings(model))
    sys = get_system(model)
    sys_filename = joinpath(IOM.get_output_dir(model), IOM.make_system_filename(sys))
    !ispath(sys_filename) && PSY.to_json(sys, sys_filename)
end
```

Both psy5 details matter: gated on the setting, and skipped when the file exists so re-solving
into the same directory is cheap.

**The path already lines up.** `IOM.load_system` reads
`joinpath(get_outputs_dir(res), make_system_filename(get_source_data_uuid(res)))`, and
`outputs_dir` is set from `get_output_dir(model)` in the `OptimizationProblemOutputs(model)`
constructor.

**Naming trap:** on `OptimizationProblemOutputs`, `outputs_dir` is the model output directory
and `output_dir` is the `outputs/` subdirectory beneath it. One character apart, different
meanings.

### 3.3 `IOM.load_system` returns the wrong type

`optimization_problem_outputs.jl:120` builds an `IS.InfrastructureSystemsContainer`, not a
`PSY.System`. It cannot be fixed in IOM — no PowerSystems dependency. Leave it; PA's
`load_outputs` (§3.4) does the PSY-typed read itself. Its docstring already says "Currently
only used in the tests, not downstream in POM."

### 3.4 PA gains `load_outputs`

New `src/load_outputs.jl`, included before `input_utils.jl`. Both forms from the 08-14 plan
§3.4: the self-contained one that finds and reads the System JSON, and the
bring-your-own-`System` one. The UUID check inside `IOM.set_source_data!` makes the two-argument
form safe.

Error loudly when the file is absent — naming the directory and saying it predates POM's write
— never return a `nothing` sentinel.

### 3.5 Realized outputs

New `src/realized_outputs.jl`. One-model case only, with the interface shaped so a multi-model
version slots in without changing callers. With no simulation layer in psy6 every timestamp of
a single model is realized, so the computation is a pass-through today; the value is fixing the
API shape.

### 3.6 Open item: re-export IOM's `read_*` family?

08-14 §11.1, still open. Recommendation: **keep them qualified.** PA now has its own named-key
vocabulary (`VariableName`, `AuxVariableName`) that is the intended user surface; re-exporting
`IOM.read_variable` alongside it would give two ways to do the same thing and blur the
outputs/results split §0 exists to keep sharp.

## 4. Tests — the whole suite is still PSI-based

Part A ported `src/` and left `test/` untouched. Verified refs:

| File | State |
|---|---|
| `test/setuptests.jl` | `using PowerSimulations`, `using HydroPowerSimulations`, `const PSI = PowerSimulations` |
| `test/test_data/results_data.jl` | builds a PSI `DecisionModel`; `PowerSimulations.PFS.DCPowerFlow()` |
| `test/test_input.jl` | `PSI.VariableKey`, `PSI.read_results_with_keys`, `PSI.get_system`, `PSI.ModelBuildStatus`, `PSI.RunStatus` |
| `test/test_result_sorting.jl` | `PowerSimulations.VariableKey` / `ParameterKey` |
| `test/test_builtin_component_selectors.jl` | plain `System`; needs no fixture change |

Two tiers, as 08-14 §9:

- **Tier 1 — no POM, no solver.** Build an `IOM.OptimizationProblemOutputs` from hand-made
  `DenseAxisArray`s, serialize it with a PSB system's JSON alongside, reload through
  `load_outputs(dir)`, assert on the metrics. Covers the round trip, WIDE shaping, units, slack
  column selection, realized outputs. Runs today against the §1.1 environment.
- **Tier 2 — POM integration.** Solve a real `DecisionModel` through POM as
  `POM/test/test_model_decision.jl:45` does, confirm `system-$(uuid).json` is written, reload
  in PA.

`test_result_sorting.jl` and `test_input.jl`'s `read_component_result` coverage are still valid
and must be re-homed under the new names, not dropped. Park the rest in `DISABLED_TEST_FILES`
with a header naming the missing upstream API.

**Suite-wide guard:** `runtests.jl` asserts zero `@error` events. Any test that triggers the
by-design unmapped-generator `@error` must wrap it in
`@test_logs (:error, r"No mapping defined") match_mode=:any`.

## 5. Docs

`docs/make.jl:17` still InterLinks `PowerSimulations` and `HydroPowerSimulations`; PSI also
appears in `docs/Project.toml`, `docs/src/index.md`,
`docs/src/tutorials/PA_workflow_tutorial.jl`, `docs/src/tutorials/_run_scenarios_RTS_Tutorial.jl`,
`docs/src/PowerAnalytics/3.0_getting_started.jl`.

Retarget InterLinks to IOM/POM, park the simulation tutorials, and fix `missing_docs` by
registering docstrings in `@autodocs`/`@docs` — **never** `warnonly`.

## 6. Order

Every phase ends with a compile check and the formatter
(`julia --project=scripts/formatter -e 'include("scripts/formatter/formatter_code.jl")'`).

| # | Step | Blocked on | Gate |
|---|---|---|---|
| 1 | §2.2 test env pins | — | `Pkg.instantiate()` + `using PowerAnalytics` |
| 2 | §2.3 main `Project.toml` path pins, drop stale comment | — | `Pkg.resolve()` |
| 3 | §3.4 `load_outputs` (both forms) | — | unit test against a hand-written outputs dir |
| 4 | §3.5 realized outputs | — | unit test |
| 5 | §4 Tier-1 test suite | 1, 3, 4 | `julia --project=test test/runtests.jl` |
| 6 | §3.1 IOM `system_to_file` | — | IOM suite |
| 7 | §3.2 POM `PSY.to_json` write | 6, POM building | solved model's dir contains `system-$(uuid).json` |
| 8 | §4 Tier-2 tests | 7 | PA reloads a POM-produced directory |
| 9 | §5 docs | 5 | `julia --project=docs docs/make.jl` clean |

Steps 1–5 are PA-only and can all start today. Step 3 can be written and tested against a
hand-built directory before 6–7 land, so the POM dependency gates only step 8.

**PowerGraphics is downstream of step 5.** See
`../PowerGraphics.jl/.claude/plans/2026-08-17-pg-refactor-onto-pa-metrics.md` — PG's entire
plotting data layer was built on the legacy API deleted in `1870a0c`.

## 7. Out of scope

Unchanged from 08-14 §12: no IOM sequential-simulation layer, no change to how IOM persists
outputs (noted preference if revisited: HDF5 over `Serialization.serialize`), no native
long-format or 3-D support in the metrics layer, no reimplementation of the deleted legacy API.

Also out of scope: bumping any version or compat. PA stays at `1.5.0`, PSY compat stays
`^5.10`, IS `3`.
