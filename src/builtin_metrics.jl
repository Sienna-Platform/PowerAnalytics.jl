"""
Make a `ComponentTimedMetric` that reads one output entry per component.

`entry` is either an entry type PowerAnalytics can name directly or a [`VariableName`](@ref)
/ [`AuxVariableName`](@ref) for entries defined in packages PowerAnalytics does not depend
on.
"""
make_component_metric_from_entry(name::String, entry) =
    ComponentTimedMetric(; name = name,
        eval_fn = (out::IS.Outputs, comp::Component; kwargs...) ->
            read_component_output(out, entry, comp; kwargs...))

"""
Make a `ComponentTimedMetric` from a `PSY.System`-keyed entry whose columns are the model's
index set — reference buses under the bus-balance network models, `PSY.Area` under the area
ones.

The metric takes a `ComponentSelector` naming those index members; there is deliberately no
default, because assuming `PSY.ACBus` would return silently wrong numbers under an
`AreaBalanceNetworkModel`. The metric's `component_agg_fn` (`sum` by default) collapses the
selected columns into the system-wide total.
"""
make_system_indexed_metric(name::String, entry) =
    ComponentTimedMetric(; name = name,
        eval_fn = (out::IS.Outputs, comp::Component; kwargs...) ->
            read_system_indexed_output(out, entry, comp; kwargs...))

"""
Compute the mean of `values` weighted by the corresponding entries of `weights`. Arguments
may be vectors or vectors of vectors. A weight of `0` cancels out a value of `NaN`.
"""
function weighted_mean(vals, weights)
    # Handle NaNs by replacing values with weight 0 with 0
    new_values = zero(vals)
    is_zeros = broadcast.(iszero, weights)
    new_values = broadcast.(ifelse, is_zeros, new_values, vals)

    weighted_values = broadcast.(*, new_values, weights)
    return sum(weighted_values) ./ sum(weights)
end

weighted_mean(empty) =
    if length(empty) == 0 || all(.!(empty .== empty))  # Zero length or all NaNs
        weighted_mean(empty, empty)
    else
        throw(
            ArgumentError(
                "weighted_mean needs two arguments unless the first argument has zero length or is all NaN",
            ),
        )
    end

"A version of [`sum`](@extref Base.sum) that ignores a second argument, for use where aggregation metadata is at play."
unweighted_sum(x) = sum(x)
unweighted_sum(x, y) = sum(x)

# METRICS MODULE
"""
PowerAnalytics built-in `Metric`s. Use `names` to list what is available.

# Examples

```julia
using PowerAnalytics
names(PowerAnalytics.Metrics)  # lists built-in Metrics
PowerAnalytics.Metrics.calc_active_power  # by default, must prefix built-in Metrics with the module name
@isdefined calc_active_power  # -> false
using PowerAnalytics.Metrics
@isdefined calc_active_power  # -> true, can now refer to built-in Metrics without the prefix
```
"""
module Metrics
import
    ..make_component_metric_from_entry,
    ..make_system_indexed_metric,
    ..compose_metrics,
    ..ComponentTimedMetric,
    ..CustomTimedMetric,
    ..SystemTimedMetric,
    ..OutputsTimelessMetric,
    ..PSY,
    ..IOM,
    ..IS,
    ..Component,
    ..compute,
    ..get_data_vec,
    ..get_data_cols,
    ..set_agg_meta!,
    ..get_time_vec,
    ..weighted_mean,
    ..unweighted_sum,
    ..mean,
    ..read_component_output,
    ..VariableName,
    ..AuxVariableName,
    ..rebuild_selector,
    ..DataFrame,
    ..DATETIME_COL,
    ...Selectors.all_loads,  # number of dots obtained by trial and error
    ...Selectors.all_storage
export calc_active_power,
    calc_production_cost,
    calc_active_power_in,
    calc_active_power_out,
    calc_stored_energy,
    calc_load_from_storage,
    calc_active_power_forecast,
    calc_load_forecast,
    calc_system_load_forecast,
    calc_system_load_from_storage,
    calc_net_load_forecast,
    calc_curtailment,
    calc_curtailment_frac,
    calc_integration,
    calc_capacity_factor,
    calc_startup_cost,
    calc_shutdown_cost,
    calc_total_cost,
    calc_discharge_cycles,
    calc_system_slack_up,
    calc_is_slack_up,
    calc_sum_objective_value,
    calc_sum_solve_time,
    calc_sum_bytes_alloc

# Entries defined in PowerOperationsModels are named, not typed: PowerAnalytics reads the
# outputs of power operations models without depending on the package that defines them.
"Encoded key for the storage state-of-charge variable, defined in PowerOperationsModels."
const ENERGY_VARIABLE_KEY = VariableName("EnergyVariable")

"Encoded key for the system balance slack up variable, defined in PowerOperationsModels."
const SYSTEM_SLACK_UP_KEY = VariableName("SystemBalanceSlackUp")

# NOTE ActivePowerVariable is in units of megawatts per simulation time period, so it's
# actually energy and it makes sense to sum it up.
"Calculate the active power of the specified `ComponentSelector`"
const calc_active_power = make_component_metric_from_entry(
    "ActivePower",
    IOM.ActivePowerVariable,
)

"Calculate the production cost expression of the specified `ComponentSelector`"
const calc_production_cost = make_component_metric_from_entry(
    "ProductionCost",
    IOM.ProductionCostExpression,
)

"Calculate the active power input to the specified (storage) `ComponentSelector`"
const calc_active_power_in = make_component_metric_from_entry(
    "ActivePowerIn",
    IOM.ActivePowerInVariable,
)

"Calculate the active power output of the specified (storage) `ComponentSelector`"
const calc_active_power_out = make_component_metric_from_entry(
    "ActivePowerOut",
    IOM.ActivePowerOutVariable,
)

"Calculate the energy stored in the specified (storage) `ComponentSelector`"
const calc_stored_energy = make_component_metric_from_entry(
    "StoredEnergy",
    ENERGY_VARIABLE_KEY,
)

"Calculate the `ActivePowerIn` minus the `ActivePowerOut` of the specified (storage) `ComponentSelector`"
const calc_load_from_storage = compose_metrics(
    "LoadFromStorage",
    (-),
    calc_active_power_in, calc_active_power_out)

"Fetch the forecast active power of the specified `ComponentSelector`"
const calc_active_power_forecast = make_component_metric_from_entry(
    "ActivePowerForecast",
    IOM.ActivePowerTimeSeriesParameter,
)

"Fetch the forecast active load of the specified `ComponentSelector`"
const calc_load_forecast = ComponentTimedMetric(;
    name = "LoadForecast",
    # Load is negative power
    # NOTE if we had our own time-indexed dataframe type we could overload multiplication with a scalar and simplify this
    eval_fn = (args...) -> let
        val = compute(calc_active_power_forecast, args...)
        get_data_vec(val) .*= -1
        return val
    end,
)

"Fetch the forecast active load of all the [`ElectricLoad`](@extref PowerSystems.ElectricLoad) [`Component`](@extref PowerSystems.Component)s in the system"
const calc_system_load_forecast = SystemTimedMetric(;
    name = "SystemLoadForecast",
    eval_fn = (res::IS.Outputs; kwargs...) ->
        compute(calc_load_forecast, res,
            rebuild_selector(all_loads; groupby = :all); kwargs...),
)

"Fetch the `LoadFromStorage` of all storage in the system"
const calc_system_load_from_storage = let
    SystemTimedMetric(;
        name = "SystemLoadFromStorage",
        eval_fn = (
            res::IS.Outputs; kwargs...
        ) ->
            compute(calc_load_from_storage, res,
                rebuild_selector(all_storage; groupby = :all); kwargs...),
    )
end

"`SystemLoadForecast` minus `ActivePowerForecast` of the given `ComponentSelector`"
const calc_net_load_forecast = compose_metrics(
    "NetLoadForecast",
    # (intentionally done with forecast to inform how storage should be used, among other reasons)
    (-),
    calc_system_load_forecast, calc_active_power_forecast)

"Calculate the `ActivePowerForecast` minus the `ActivePower` of the given `ComponentSelector`"
const calc_curtailment = compose_metrics(
    "Curtailment",
    (-),
    calc_active_power_forecast, calc_active_power,
)

"Calculate the curtailment as a fraction of the `ActivePowerForecast` of the given `ComponentSelector`"
const calc_curtailment_frac = ComponentTimedMetric(;
    name = "CurtailmentFrac",
    eval_fn = (
        (res::IS.Outputs, comp::Component; kwargs...
        ) -> let
            result = compute(calc_curtailment, res, comp; kwargs...)
            power = collect(
                get_data_vec(
                    compute(calc_active_power_forecast, res, comp; kwargs...),
                ),
            )
            get_data_vec(result) ./= power
            set_agg_meta!(result, power)
            return result
        end
    ), component_agg_fn = weighted_mean, time_agg_fn = weighted_mean,
)

# Helper function for calc_integration
_integration_denoms(res; kwargs...) =
    compute(calc_system_load_forecast, res; kwargs...),
    compute(calc_system_load_from_storage, res; kwargs...)

"Calculate the `ActivePower` of the given `ComponentSelector` over the sum of the `SystemLoadForecast` and the `SystemLoadFromStorage`"
const calc_integration = ComponentTimedMetric(;
    name = "Integration",
    eval_fn = (
        (res::IS.Outputs, comp::Component; kwargs...
        ) -> let
            result = compute(calc_active_power, res, comp; kwargs...)
            # TODO does not check date alignment, maybe use hcat_timed_dfs
            denom = (.+)(
                (_integration_denoms(res; kwargs...) .|> get_data_vec .|> collect)...,
            )
            get_data_vec(result) ./= denom
            set_agg_meta!(result, denom)
            return result
        end
    ), component_agg_fn = unweighted_sum, time_agg_fn = weighted_mean,
    component_meta_agg_fn = mean,
    # We use a custom eval_zero to put the weight in there even when there are no components
    eval_zero = (res::IS.Outputs; kwargs...) -> let
        denoms = _integration_denoms(res; kwargs...)
        # TODO does not check date alignment, maybe use hcat_timed_dfs
        time_col = get_time_vec(first(denoms))
        data_col = repeat([0.0], length(time_col))
        result = DataFrame(DATETIME_COL => time_col, "" => data_col)
        set_agg_meta!(result, (.+)((denoms .|> get_data_vec .|> collect)...))
    end,
)

"Calculate the capacity factor (actual production/rated production) of the specified `ComponentSelector`"
const calc_capacity_factor = ComponentTimedMetric(;
    name = "CapacityFactor",
    # (intentionally done with forecast to serve as sanity check -- solar capacity factor shouldn't exceed 20%, etc.)
    eval_fn = (
        (res::IS.Outputs, comp::Component; kwargs...) -> let
            result = compute(calc_active_power_forecast, res, comp; kwargs...)
            rating = PSY.get_rating(comp, PSY.NU)
            get_data_vec(result) ./= rating
            set_agg_meta!(result, repeat([rating], length(get_data_vec(result))))
            return result
        end
    ), component_agg_fn = weighted_mean, time_agg_fn = weighted_mean,
)

"Calculate the startup cost of the specified `ComponentSelector`"
const calc_startup_cost = ComponentTimedMetric(;
    name = "StartupCost",
    eval_fn = (
        (res::IS.Outputs, comp::Component; kwargs...) -> let
            val = read_component_output(res, IOM.StartVariable, comp; kwargs...)
            start_cost = PSY.get_start_up(PSY.get_operation_cost(comp))
            get_data_vec(val) .*= start_cost
            return val
        end
    ),
)

"Calculate the shutdown cost of the specified `ComponentSelector`"
const calc_shutdown_cost = ComponentTimedMetric(;
    name = "ShutdownCost",
    eval_fn = (
        (res::IS.Outputs, comp::Component; kwargs...) -> let
            val = read_component_output(res, IOM.StopVariable, comp; kwargs...)
            stop_cost = PSY.get_shut_down(PSY.get_operation_cost(comp))
            get_data_vec(val) .*= stop_cost
            return val
        end
    ),
)

_has_startup_shutdown_costs(::PSY.OperationalCost) = false
_has_startup_shutdown_costs(::PSY.ThermalGenerationCost) = true
_has_startup_shutdown_costs(::PSY.StorageCost) = true
_has_startup_shutdown_costs(::PSY.MarketBidCost) = true
_has_startup_shutdown_costs(component::PSY.Component) =
    _has_startup_shutdown_costs(PSY.get_operation_cost(component))

"Calculate the production cost of the specified `ComponentSelector`, which includes the startup and shutdown costs if they are defined"
const calc_total_cost = calc_production_cost

"Calculate the number of discharge cycles a storage device has gone through in the time period"
const calc_discharge_cycles = ComponentTimedMetric(;
    name = "DischargeCycles",
    # NOTE: here, we define one "cycle" as a discharge from the maximum state of charge to
    # the minimum state of charge. A simpler algorithm might define a cycle as a discharge
    # from the maximum state of charge to zero; the algorithm given here is more rigorous.
    eval_fn = (
        (res::IS.Outputs, comp::Component; kwargs...) -> let
            val = read_component_output(res, IOM.ActivePowerOutVariable, comp; kwargs...)
            soc_limits = PSY.get_storage_level_limits(comp)
            soc_range =
                PSY.get_storage_capacity(comp, PSY.NU) * (soc_limits.max - soc_limits.min)
            get_data_vec(val) ./= soc_range
            return val
        end
    ),
)

"""
Calculate the system balance slack up over the given `ComponentSelector`.

The optimization model indexes this entry by its reference buses, or by `PSY.Area` under an
area-balance network model, so the selector must name those index members —
`make_selector(PSY.ACBus)` or `make_selector(PSY.Area)`. There is no default: assuming
buses would silently produce wrong numbers under an area-balance model. The default
`component_agg_fn` of `sum` collapses the selection into the system-wide total.
"""
const calc_system_slack_up = make_system_indexed_metric(
    "SystemSlackUp",
    SYSTEM_SLACK_UP_KEY,
)

"""
Create a boolean `Metric` for whether the given time period has system balance slack up of
magnitude greater than the `threshold` argument.

Thresholds every data column, so it stays correct whether the composed slack metric was
aggregated to one column or left grouped per bus or area.
"""
make_calc_is_slack_up(threshold::Real) = CustomTimedMetric(;
    name = "IsSlackUp($threshold)",
    eval_fn = function (out::IS.Outputs, selector; kwargs...)
        val = compute(calc_system_slack_up, out, selector; kwargs...)
        for col in get_data_cols(val)
            val[!, col] = abs.(val[!, col]) .> threshold
        end
        return val
    end,
)

# TODO is this the appropriate place to put a default threshold (and is it the appropriate default)?
const DEFAULT_SLACK_UP_THRESHOLD = 1e-4
"Calculate whether the given time period has system balance slack up of magnitude greater than $DEFAULT_SLACK_UP_THRESHOLD"
const calc_is_slack_up = make_calc_is_slack_up(DEFAULT_SLACK_UP_THRESHOLD)

# TODO caching here too
make_results_metric_from_sum_optimizer_stat(
    name::String,
    stats_key::String) = OutputsTimelessMetric(
    name,
    (res::IS.Outputs) -> sum(IOM.read_optimizer_stats(res)[!, stats_key]),
)

"Sum the objective values achieved in the optimization problems"
const calc_sum_objective_value = make_results_metric_from_sum_optimizer_stat(
    "SumObjectiveValue",
    "objective_value")

"Sum the solve times taken by the optimization problems"
const calc_sum_solve_time = make_results_metric_from_sum_optimizer_stat(
    "SumSolveTime",
    "solve_time")

"Sum the bytes allocated to the optimization problems"
const calc_sum_bytes_alloc = make_results_metric_from_sum_optimizer_stat(
    "SumBytesAlloc",
    "solve_bytes_alloc")
end
