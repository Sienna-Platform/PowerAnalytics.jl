# `compute` time windows and missing-result errors on simulation results. The UC problem of
# the test simulation has two daily windows of hourly steps, so a window can start in the
# middle of a simulation window and span both of them.
(results_uc, results_ed) = run_test_sim(TEST_RESULT_DIR, TEST_SIM_NAME)

const WINDOW_START_INDEX = 6
const WINDOW_STEPS = 30  # longer than one simulation window

window_sys = get_system(results_uc)
window_thermal = first(get_components(ThermalStandard, window_sys))
window_load = first(get_components(PowerLoad, window_sys))

@testset "initial_time and horizon select a step-granular window" begin
    cases = [
        (calc_active_power, (results_uc, window_thermal)),
        (calc_load_forecast, (results_uc, window_load)),
        (calc_active_power, (results_uc, make_selector(ThermalStandard; groupby = :all))),
        (calc_system_load_forecast, (results_uc,)),
    ]
    for (metric, args) in cases
        full = compute(metric, args...)
        t0 = full[WINDOW_START_INDEX, DATETIME_COL]
        window = compute(metric, args...; initial_time = t0, horizon = WINDOW_STEPS)
        expected = WINDOW_START_INDEX:(WINDOW_START_INDEX + WINDOW_STEPS - 1)
        @test size(window, 1) == WINDOW_STEPS
        @test get_time_vec(window) == get_time_vec(full)[expected]
        @test get_data_vec(window) ≈ get_data_vec(full)[expected]

        # A period horizon selects the same rows as the equivalent step count
        @test compute(metric, args...; initial_time = t0, horizon = Hour(WINDOW_STEPS)) ==
              window
        # `start_time`/`len` is the resolved form that evaluation functions receive
        @test compute(metric, args...; start_time = t0, len = WINDOW_STEPS) == window
    end

    # A horizon no longer than the number of simulation windows is a number of steps, not
    # of windows
    @test size(compute(calc_active_power, results_uc, window_thermal; horizon = 2), 1) == 2

    @test size(calc_is_slack_up(results_ed; horizon = 3), 1) == 3
end

@testset "invalid time windows" begin
    t0 = first(get_time_vec(compute(calc_active_power, results_uc, window_thermal)))
    @test_throws ArgumentError compute(calc_active_power, results_uc, window_thermal;
        horizon = Minute(90))
    @test_throws ArgumentError compute(calc_active_power, results_uc, window_thermal;
        horizon = Month(1))
    @test_throws ArgumentError compute(calc_active_power, results_uc, window_thermal;
        initial_time = t0, start_time = t0)
    @test_throws ArgumentError compute(calc_active_power, results_uc, window_thermal;
        horizon = 3, len = 3)
end

@testset "get_generation_data accepts a period horizon" begin
    by_steps = get_generation_data(results_uc; horizon = 12)
    by_period = get_generation_data(results_uc; horizon = Hour(12))
    @test by_steps.time == by_period.time
    @test length(by_period.time) == 12
end

@testset "missing results raise NoResultError" begin
    # Entry type never stored: `RenewableNonDispatch` is modeled with `FixedOutput`
    nondispatch = first(get_components(RenewableNonDispatch, window_sys))
    @test_throws NoResultError compute(calc_active_power, results_uc, nondispatch)
    # Component missing from a stored entry
    ghost = ThermalStandard(nothing)
    @test_throws NoResultError compute(calc_active_power, results_uc, ghost)
    # System entry never stored: the UC problem has no balance slacks
    @test_throws NoResultError calc_system_slack_up(results_uc)
end
