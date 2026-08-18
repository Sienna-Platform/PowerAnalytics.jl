# Parked for the psy6 port. Needs `run_test_sim`'s `PSI.Simulation` results, which have no
# psy6 counterpart. Re-home against a rebuilt single-`DecisionModel` fixture.

# For now, for the built-in metrics, we are mostly just testing that they can all be called
# without error, though I've built out the structure to do much more than that. TODO it
# would be great if we did.

(results_uc, results_ed) = run_test_sim(TEST_RESULT_DIR, TEST_SIM_NAME)
const ResultType = AbstractDataFrame

@testset "Test make_component_metric_from_entry" begin
    entry = PSI.ActivePowerVariable
    my_calc_active_power = PA.make_component_metric_from_entry("MyActivePower", entry)
    @test get_name(my_calc_active_power) == "MyActivePower"
    comp = get_component(ThermalStandard, get_system(results_uc), "Solitude")
    my_result = my_calc_active_power(make_selector(comp), results_uc)
    existing_result = PA.read_component_result(results_uc, entry, comp)
    @test get_time_vec(my_result) == get_time_vec(existing_result)
    @test get_data_vec(my_result) == get_data_vec(existing_result)
end

@testset "Test make_system_metric_from_entry" begin
    entry = PSI.SystemBalanceSlackUp
    my_calc_system_slack_up = PA.make_system_metric_from_entry("MySystemSlackUp", entry)
    @test get_name(my_calc_system_slack_up) == "MySystemSlackUp"
    my_result = my_calc_system_slack_up(results_ed)
    existing_result = PA.read_system_result(results_ed, entry)
    @test get_time_vec(my_result) == get_time_vec(existing_result)
    @test get_data_vec(my_result) == get_data_vec(existing_result)
end

# TEST EACH BUILT-IN METRIC INDIVIDUALLY
# Future implementers of built-in metrics must add tests as shown below or this will trigger
function test_metric(::Val{metric_name}) where {metric_name}
    throw("Could not find test for $metric_name")
end

function test_metric(::Val{:calc_active_power})
    @test calc_active_power(make_selector(ThermalStandard), results_uc) isa ResultType
end

function test_metric(::Val{:calc_active_power_forecast})
    @test calc_active_power_forecast(make_selector(RenewableDispatch), results_uc) isa
          ResultType
end

function test_metric(::Val{:calc_active_power_in})
    @test calc_active_power_in(make_selector(EnergyReservoirStorage), results_uc) isa
          ResultType
end

function test_metric(::Val{:calc_active_power_out})
    @test calc_active_power_out(make_selector(EnergyReservoirStorage), results_uc) isa
          ResultType
end

function test_metric(::Val{:calc_capacity_factor})
    @test calc_capacity_factor(make_selector(RenewableDispatch), results_uc) isa ResultType
end

function test_metric(::Val{:calc_curtailment})
    # TODO broken for groupby = :each?
    @test calc_curtailment(make_selector(RenewableDispatch; groupby = :all), results_uc) isa
          ResultType
end

function test_metric(::Val{:calc_curtailment_frac})
    @test calc_curtailment_frac(make_selector(RenewableDispatch), results_uc) isa ResultType
end

function test_metric(::Val{:calc_discharge_cycles})
    @test calc_discharge_cycles(make_selector(EnergyReservoirStorage), results_uc) isa
          ResultType
end

function test_metric(::Val{:calc_integration})
    # TODO broken for groupby = :each?
    @test calc_integration(make_selector(RenewableDispatch; groupby = :all), results_uc) isa
          ResultType
end

function test_metric(::Val{:calc_is_slack_up})
    @test calc_is_slack_up(results_ed) isa ResultType
end

function test_metric(::Val{:calc_load_forecast})
    @test calc_load_forecast(make_selector(ElectricLoad), results_uc) isa ResultType
end

function test_metric(::Val{:calc_load_from_storage})
    @test calc_load_from_storage(make_selector(EnergyReservoirStorage), results_uc) isa
          ResultType
end

function test_metric(::Val{:calc_net_load_forecast})
    @test calc_load_from_storage(make_selector(EnergyReservoirStorage), results_uc) isa
          ResultType
end

function test_metric(::Val{:calc_production_cost})
    @test calc_production_cost(make_selector(ThermalStandard), results_uc) isa ResultType
end

function test_metric(::Val{:calc_shutdown_cost})
    @test calc_shutdown_cost(make_selector(ThermalStandard), results_uc) isa ResultType
end

function test_metric(::Val{:calc_startup_cost})
    @test calc_startup_cost(make_selector(ThermalStandard), results_uc) isa ResultType
end

function test_metric(::Val{:calc_stored_energy})
    @test calc_stored_energy(make_selector(EnergyReservoirStorage), results_uc) isa
          ResultType
end

function test_metric(::Val{:calc_sum_bytes_alloc})
    @test calc_sum_bytes_alloc(results_uc) isa ResultType
end

function test_metric(::Val{:calc_sum_objective_value})
    @test calc_sum_objective_value(results_uc) isa ResultType
end

function test_metric(::Val{:calc_sum_solve_time})
    @test calc_sum_solve_time(results_uc) isa ResultType
end

function test_metric(::Val{:calc_system_load_forecast})
    @test calc_system_load_forecast(results_uc) isa ResultType
end

function test_metric(::Val{:calc_system_load_from_storage})
    @test calc_system_load_from_storage(results_uc) isa ResultType
end

function test_metric(::Val{:calc_system_slack_up})
    @test calc_system_slack_up(results_ed) isa ResultType
end

function test_metric(::Val{:calc_total_cost})
    @test calc_total_cost(make_selector(ThermalStandard), results_uc) isa ResultType
end

all_metric_names = filter(x -> getproperty(PowerAnalytics.Metrics, x) isa Metric,
    names(PowerAnalytics.Metrics))

@testset for metric_name in all_metric_names
    @test isconst(PowerAnalytics.Metrics, metric_name)
    test_metric(Val(metric_name))
end

# Regression test for https://github.com/Sienna-Platform/PowerAnalytics.jl/issues/54.
# Computing a `ComponentTimedMetric` over a type-based `ComponentSelector` (the original
# reproducer was `calc_active_power(make_selector(ThermalStandard), results_uc)`) was
# reported to hit `StackOverflowError`. The bug is not reproducible on current `main`
# (the `IS.ComponentSelector` contract guarantees `get_components` returns components, not
# selectors, so `_compute_one` cannot recurse via dispatch). This test pins the reproducer
# down explicitly so any future regression of either the IS contract or PowerAnalytics'
# dispatch chain is caught immediately.
@testset "Regression: Issue #54 — calc_active_power with ComponentSelector dispatch" begin
    result = calc_active_power(make_selector(ThermalStandard), results_uc)
    @test result isa ResultType
    @test DATETIME_COL in names(result)
    @test length(get_data_cols(result)) >= 1
end
