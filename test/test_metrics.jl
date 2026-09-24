# Parked for the psy6 port. Depends on `run_test_sim`'s `PSI.Simulation` outputs — the
# blocker is PA's test env and a fixture that needs rebuilding, not a missing PSI symbol.
# Re-home against a rebuilt single-`DecisionModel` fixture using IOM's same-named key types
# and `IOM.read_outputs_with_keys`.

# LOAD OUTPUTS
(outputs_uc, outputs_ed) = run_test_sim(TEST_OUTPUT_DIR, TEST_SIM_NAME)
outputs_prob = run_test_prob()
outputs_by_name = Dict("UC" => outputs_uc, "ED" => outputs_ed, "prob" => outputs_prob)
@assert all(
    in.(
        "ActivePowerVariable__ThermalStandard",
        list_variable_names.(values(outputs_by_name)),
    ),
) "Expected all outputs to contain ActivePowerVariable__ThermalStandard"

# CONSTRUCT COMMON TEST RESOURCES
"Calculate the active power output of the specified `ComponentSelector`"
test_calc_active_power = ComponentTimedMetric(;
    name = "ActivePower",
    eval_fn = (outputs::IS.Outputs, comp::Component;
        start_time::Union{Nothing, Dates.DateTime} = nothing,
        len::Union{Int, Nothing} = nothing) -> let
        key = PSI.VariableKey(ActivePowerVariable, typeof(comp))
        output_values = IOM.read_outputs_with_keys(
            outputs,
            [key];
            start_time = start_time,
            len = len,
            table_format = IS.TableFormat.WIDE,
        )
        first(values(output_values))[!, [DATETIME_COL, get_name(comp)]]
    end,
)

"Calculate the production cost of the specified `ComponentSelector`"
test_calc_production_cost = ComponentTimedMetric(;
    name = "ProductionCost",
    eval_fn = (outputs::IS.Outputs, comp::Component;
        start_time::Union{Nothing, Dates.DateTime} = nothing,
        len::Union{Int, Nothing} = nothing) -> let
        key = PSI.ExpressionKey(ProductionCostExpression, typeof(comp))
        output_values = IOM.read_outputs_with_keys(
            outputs,
            [key];
            start_time = start_time,
            len = len,
            table_format = IS.TableFormat.WIDE,
        )
        first(values(output_values))[!, [DATETIME_COL, get_name(comp)]]
    end,
)

"Calculate the system balance slack up"
test_calc_system_slack_up = SystemTimedMetric(;
    name = "SystemSlackUp",
    eval_fn = (outputs::IS.Outputs;
        start_time::Union{Nothing, Dates.DateTime} = nothing,
        len::Union{Int, Nothing} = nothing) -> let
        key = PSI.VariableKey(SystemBalanceSlackUp, System)
        output_values = IOM.read_outputs_with_keys(
            outputs,
            [key];
            start_time = start_time,
            len = len,
            table_format = IS.TableFormat.WIDE,
        )
        df = first(values(output_values))
        # If there's more than a datetime column and a data column, we are misunderstanding
        @assert size(df, 2) == 2
        return DataFrames.rename(
            df,
            findfirst(!=(DATETIME_COL), names(df)) => SYSTEM_COL,
        )
    end,
)

"Sum the objective values achieved in the optimization problems"
test_calc_sum_objective_value = OutputsTimelessMetric(
    "SumObjectiveValue",
    (outputs::IS.Outputs) ->
        sum(PSI.read_optimizer_stats(outputs)[!, "objective_value"]),
)

"Sum the solve times taken by the optimization problems"
test_calc_sum_solve_time = OutputsTimelessMetric(
    "SumSolveTime",
    (outputs::IS.Outputs) -> sum(PSI.read_optimizer_stats(outputs)[!, "solve_time"]),
)

thermal_vals = [1, 2, 3]
thermal_weights = [1, 1, 3]
other_vals = [4, 5, 6]
other_weights = [2, 1, 1]
"Return some simple numbers with some simple metadata"
test_calc_dummy_meta = ComponentTimedMetric(;
    name = "DummyMeta",
    eval_fn = (outputs::IS.Outputs, comp::Component;
        start_time::Union{Nothing, Dates.DateTime} = nothing,
        len::Union{Int, Nothing} = nothing) -> let
        (start_time !== nothing && len !== nothing) &&
            error("Not implemented for non-nothing `start_time`, `len`")
        dates = collect(DateTime(2023, 1, 1):Hour(8):DateTime(2023, 1, 1, 16))
        values = (typeof(comp) == ThermalStandard) ? thermal_vals : other_vals
        agg_meta = (typeof(comp) == ThermalStandard) ? thermal_weights : other_weights
        result = DataFrame(DATETIME_COL => dates, get_name(comp) => values)
        set_agg_meta!(result, agg_meta)
    end,
    component_agg_fn = weighted_mean,
    time_agg_fn = weighted_mean,
)

my_dates = [DateTime(2023), DateTime(2024)]
my_data1 = [3.14, 2.71]
my_data2 = [1.61, 1.41]
my_meta = [1, 2]

my_df1 = DataFrame(DATETIME_COL => my_dates, "MyComponent" => my_data1)
colmetadata!(my_df1, DATETIME_COL, META_COL_KEY, true; style = :note)

my_df2 = DataFrame(
    DATETIME_COL => my_dates,
    "Component1" => my_data1,
    "Component2" => my_data2,
    "MyMeta" => my_meta,
)
colmetadata!(my_df2, DATETIME_COL, META_COL_KEY, true; style = :note)
colmetadata!(my_df2, "MyMeta", META_COL_KEY, true; style = :note)

missing_df = DataFrame(
    DATETIME_COL => Vector{Union{Missing, Dates.DateTime}}([missing]),
    "MissingComponent" => 0.0)
colmetadata!(missing_df, DATETIME_COL, META_COL_KEY, true; style = :note)

my_df_agg_meta = copy(my_df2)
my_agg_meta = [[1, 2], [3, 4]]
colmetadata!(my_df_agg_meta, "Component1", AGG_META_KEY, my_agg_meta[1]; style = :note)
colmetadata!(my_df_agg_meta, "Component2", AGG_META_KEY, my_agg_meta[2]; style = :note)

my_dates_long = collect(DateTime(2023, 1, 1):Hour(8):DateTime(2023, 3, 31, 16))
my_data_long_1 = collect(range(0, 100, length(my_dates_long)))
my_data_long_2 = collect(range(24, 0, length(my_dates_long))) .+ 0.5 / length(my_dates_long)
my_meta_long = (my_dates_long .|> day) .% 2
my_df3 = DataFrame(
    DATETIME_COL => my_dates_long,
    "Component1" => my_data_long_1,
    "Component2" => my_data_long_2,
    "MyMeta" => my_meta_long,
)

wind_sel = make_selector(RenewableDispatch, "WindBusA")
solar_sel = make_selector(RenewableDispatch, "SolarBusC")
thermal_sel = make_selector(ThermalStandard, "Brighton")
test_selectors = [wind_sel, solar_sel, thermal_sel]

function _generate_comp_results()
    comp_results = Dict()
    for (label, outputs) in pairs(outputs_by_name)
        comps1 = collect(get_components(RenewableDispatch, get_system(outputs)))
        comps2 = collect(get_components(ThermalStandard, get_system(outputs)))
        for comp in vcat(comps1, comps2)
            computed_alltime = compute(test_calc_active_power, outputs, comp)
            test_start_time = computed_alltime[2, DATETIME_COL]
            test_len = 3
            computed_sometime = compute(test_calc_active_power, outputs, comp;
                start_time = test_start_time, len = test_len)
            comp_results[(label, get_name(comp))] = (computed_alltime, computed_sometime)
        end
    end
    return comp_results
end
comp_results = _generate_comp_results()

# HELPER FUNCTIONS
function test_timed_metric_helper(computed_alltime, met, data_colname)
    test_generic_metric_helper(computed_alltime, met, data_colname)
    @test names(computed_alltime) == [DATETIME_COL, data_colname]
    @test eltype(computed_alltime[!, DATETIME_COL]) <: Union{Missing, DateTime}

    # Row tests, all time
    # TODO check that the number of rows is correct?
end

function test_generic_metric_helper(computed, met, data_colname)
    @test get(metadata(computed), "title", nothing) == met.name
    @test get(metadata(computed), "metric", nothing) === met
    @test get(colmetadata(computed, data_colname), "metric", nothing) ==
          get(metadata(computed), "metric", nothing)
    @test eltype(computed[!, data_colname]) <: Union{Missing, Number}  # TODO
end

function test_component_timed_metric(met, outputs, sel)
    computed_alltime = compute(met, outputs, sel)
    col_sel = (sel isa ComponentSelector) ? only(get_groups(sel, get_system(outputs))) : sel
    test_timed_metric_helper(computed_alltime, met, get_name(col_sel))

    the_components =
        (sel isa Component) ? [sel] :
        collect(get_components(sel, get_system(outputs)))
    @test all(
        get(colmetadata(computed_alltime, get_name(col_sel)), "components", nothing) .==
        the_components,
    )
    (sel isa ComponentSelector) &&
        @test get(
            colmetadata(computed_alltime, get_name(col_sel)),
            "ComponentSelector",
            nothing,
        ) == col_sel

    # Row tests, specified time. Skip for test on empty selector, there is no time axis to base computed_sometime off in this case
    if length(the_components) > 0
        test_start_time = computed_alltime[2, DATETIME_COL]
        test_len = 3
        computed_sometime = compute(met, outputs, sel;
            start_time = test_start_time, len = test_len)
        @test computed_sometime[1, DATETIME_COL] == test_start_time
        @test size(computed_sometime, 1) == test_len
    else
        computed_sometime = nothing
    end

    return computed_alltime, computed_sometime
end

function test_system_timed_metric(met, outputs)
    computed_alltime = compute(met, outputs)
    test_timed_metric_helper(computed_alltime, met, SYSTEM_COL)
    @test compute(met, outputs, nothing) == computed_alltime

    # Row tests, specified time
    test_start_time = computed_alltime[2, DATETIME_COL]
    test_len = 3
    computed_sometime = compute(met, outputs; start_time = test_start_time, len = test_len)
    @test computed_sometime[1, DATETIME_COL] == test_start_time
    @test size(computed_sometime, 1) == test_len

    return computed_alltime, computed_sometime
end

function test_outputs_timeless_metric(met, outputs)
    computed = compute(met, outputs)
    test_generic_metric_helper(computed, met, OUTPUTS_COL)
    @test compute(met, outputs, nothing) == computed
    return computed
end

function test_df_approx_equal(lhs, rhs)
    @test all(names(lhs) .== names(rhs))
    for (lhs_col, rhs_col) in zip(eachcol(lhs), eachcol(rhs))
        if eltype(lhs_col) <: AbstractFloat || eltype(lhs_col) <: AbstractFloat
            @test all(isapprox.(lhs_col, rhs_col))
        else
            @test all(lhs_col .== rhs_col)
        end
    end
end

# BEGIN TEST SETS
@testset "Test metrics helper functions" begin
    @test metric_selector_to_string(
        test_calc_active_power,
        make_selector(ThermalStandard),
    ) ==
          "ActivePower__ThermalStandard"

    @test is_col_meta(my_df2, DATETIME_COL)
    @test !is_col_meta(my_df2, "Component1")
    @test is_col_meta(my_df2, "MyMeta")

    my_df1_copy = copy(my_df1)
    @test !is_col_meta(my_df1_copy, "MyComponent")
    set_col_meta!(my_df1_copy, "MyComponent")
    @test is_col_meta(my_df1_copy, "MyComponent")
    set_col_meta!(my_df1_copy, "MyComponent", false)
    @test !is_col_meta(my_df1_copy, "MyComponent")

    @test get_time_df(my_df1) == DataFrame(DATETIME_COL => copy(my_dates))
    @test get_time_vec(my_df1) == copy(my_dates)
    @test get_data_df(my_df1) == DataFrame(; MyComponent = copy(my_data1))
    @test get_data_vec(my_df1) == copy(my_data1)
    @test get_data_mat(my_df1) == copy(my_data1)[:, :]

    @test get_data_cols(my_df2) == ["Component1", "Component2"]
    @test get_time_df(my_df2) == DataFrame(DATETIME_COL => copy(my_dates))
    @test get_time_vec(my_df2) == copy(my_dates)
    @test get_data_df(my_df2) ==
          DataFrame("Component1" => copy(my_data1), "Component2" => copy(my_data2))
    @test_throws ArgumentError get_data_vec(my_df2)
    @test get_data_mat(my_df2) == hcat(copy(my_data1), copy(my_data2))

    @test hcat_timed_dfs(
        my_df1,
        DataFrames.rename(my_df1, "MyComponent" => "YourComponent"),
    ) ==
          DataFrame(
        DATETIME_COL => my_dates,
        "MyComponent" => my_data1,
        "YourComponent" => my_data1,
    )
end

@testset "Test aggregate_time" begin
    test_df_approx_equal(
        aggregate_time(my_df3; agg_fn = sum),
        DataFrame(
            DATETIME_COL => first(my_dates_long),
            "Component1" => sum(my_data_long_1),
            "Component2" => sum(my_data_long_2),
            "MyMeta" => sum(my_meta_long),
        ),
    )
    @test is_col_meta(aggregate_time(my_df3; agg_fn = sum), DATETIME_COL)

    month_agg =
        aggregate_time(my_df3; groupby_fn = dt -> (year(dt), month(dt)), agg_fn = sum)
    @test size(month_agg, 1) == 3
    test_df_approx_equal(
        month_agg[1:1, :],
        DataFrame(
            DATETIME_COL => first(my_dates_long),
            "Component1" => sum(my_data_long_1[1:(31 * 3)]),
            "Component2" => sum(my_data_long_2[1:(31 * 3)]),
            "MyMeta" => sum(my_meta_long[1:(31 * 3)]),
        ),
    )

    day_agg = aggregate_time(my_df3; groupby_fn = Date, agg_fn = sum)
    @test size(day_agg, 1) == 31 + 28 + 31
    test_df_approx_equal(
        day_agg[1:1, :],
        DataFrame(
            DATETIME_COL => first(my_dates_long),
            "Component1" => sum(my_data_long_1[1:3]),
            "Component2" => sum(my_data_long_2[1:3]),
            "MyMeta" => sum(my_meta_long[1:3]),
        ),
    )

    hour_agg = aggregate_time(my_df3; groupby_fn = hour, agg_fn = sum)
    @test size(hour_agg, 1) == 3
    test_df_approx_equal(
        hour_agg[1:1, :],
        DataFrame(
            DATETIME_COL => first(my_dates_long),
            "Component1" => sum(my_data_long_1[1:3:end]),
            "Component2" => sum(my_data_long_2[1:3:end]),
            "MyMeta" => sum(my_meta_long[1:3:end]),
        ),
    )

    day_agg_2 = aggregate_time(my_df3; groupby_fn = Date, groupby_col = "day", agg_fn = sum)
    @test "day" in names(day_agg_2)
    @test is_col_meta(day_agg_2, "day")
    @test day_agg_2[!, "day"] == Date.(get_time_vec(day_agg_2))
end

@testset "Test ComponentTimedMetric on Components" begin
    for (label, outputs) in pairs(outputs_by_name)
        comps1 = collect(get_components(RenewableDispatch, get_system(outputs)))
        comps2 = collect(get_components(ThermalStandard, get_system(outputs)))
        for comp in vcat(comps1, comps2)
            test_component_timed_metric(test_calc_active_power, outputs, comp)
        end
    end
end

@testset "Test ComponentTimedMetric on SingularComponentSelectors" begin
    for (label, outputs) in pairs(outputs_by_name)
        for sel in test_selectors
            computed_alltime, computed_sometime =
                test_component_timed_metric(test_calc_active_power, outputs, sel)

            # SingularComponentSelector results should be the same as Component results
            component_name = get_name(first(get_components(sel, get_system(outputs))))
            base_computed_alltime, base_computed_sometime =
                comp_results[(label, component_name)]
            @test get_time_df(computed_alltime) == get_time_df(base_computed_alltime)
            # Using get_data_vec because the column names are allowed to differ
            @test get_data_vec(computed_alltime) == get_data_vec(base_computed_alltime)
            @test get_time_df(computed_sometime) == get_time_df(base_computed_sometime)
            @test get_data_vec(computed_sometime) == get_data_vec(base_computed_sometime)
        end
    end
end

@testset "Test ComponentTimedMetric on PluralComponentSelectors" begin
    test_selector_sets = [
        make_selector(make_selector(wind_sel, solar_sel)),
        make_selector(make_selector(test_selectors...)),
        make_selector(ThermalStandard; groupby = :all),
    ]

    for (label, outputs) in pairs(outputs_by_name)
        for sel in test_selector_sets
            my_test_metric = test_calc_active_power
            computed_alltime, computed_sometime =
                test_component_timed_metric(my_test_metric, outputs, sel)

            component_names = get_name.(get_components(sel, get_system(outputs)))
            if length(component_names) == 0
                @test isequal(get_time_vec(computed_alltime),
                    Vector{Union{Missing, Dates.DateTime}}([missing]))
                @test get_data_vec(computed_alltime) ==
                      [get_component_agg_fn(my_test_metric)(Vector{Float64}())]
            else
                (base_computed_alltimes, base_computed_sometimes) =
                    zip([comp_results[(label, cn)] for cn in component_names]...)
                @test get_time_df(computed_alltime) ==
                      get_time_df(first(base_computed_alltimes))
                @test get_data_vec(computed_alltime) ==
                      sum([get_data_vec(sub) for sub in base_computed_alltimes])
                @test get_time_df(computed_sometime) ==
                      get_time_df(first(base_computed_sometimes))
                @test get_data_vec(computed_sometime) ==
                      sum([get_data_vec(sub) for sub in base_computed_sometimes])
            end
        end
    end
end

@testset "Test SystemTimedMetric" begin
    # The relevant data only exists in the ED outputs
    test_system_timed_metric(test_calc_system_slack_up, outputs_ed)
end

@testset "Test OutputsTimelessMetric" begin
    for (label, outputs) in pairs(outputs_by_name)
        test_outputs_timeless_metric(test_calc_sum_objective_value, outputs)
    end
end

@testset "Test compute with multiple columns" begin
    combo_selector = make_selector(test_selectors...)
    mymet = test_calc_active_power
    for (label, outputs) in pairs(outputs_by_name)
        computed_alltime = compute(mymet, outputs, combo_selector)
        cols = get_data_cols(computed_alltime)
        sels = colmetadata.(Ref(computed_alltime), cols, "ComponentSelector")
        @test all(sels .== test_selectors)  # One column for each subselector in the input
        @test all(cols .== get_name.(sels))  # Named properly

        # TODO bit of code duplication between here and test_component_timed_metric
        test_start_time = computed_alltime[2, DATETIME_COL]
        test_len = 3
        computed_sometime = compute(mymet, outputs, combo_selector;
            start_time = test_start_time, len = test_len)
        @test computed_sometime[1, DATETIME_COL] == test_start_time
        @test size(computed_sometime, 1) == test_len

        # DateTime plus data column slices of compute() should be identical to results of compute_one()
        for (col_name, this_selector) in zip(cols, sels)
            test_timed_metric_helper(
                computed_alltime[!, [DATETIME_COL, col_name]],
                mymet,
                col_name,
            )
            this_components = collect(get_components(this_selector, get_system(outputs)))
            @test all(
                get(colmetadata(computed_alltime, col_name), "components", nothing) .==
                this_components,
            )

            base_computed_alltime, base_computed_sometime =
                comp_results[(label, get_name(first(this_components)))]
            @test get_time_df(computed_alltime) == get_time_df(base_computed_alltime)
            @test computed_alltime[!, col_name] == get_data_vec(base_computed_alltime)
            @test get_time_df(computed_sometime) == get_time_df(base_computed_sometime)
            @test computed_sometime[!, col_name] == get_data_vec(base_computed_sometime)
        end
    end
end

@testset "Test compute_all" begin
    my_metrics = [test_calc_active_power, test_calc_active_power,
        test_calc_production_cost, test_calc_production_cost]
    my_component = first(get_components(RenewableDispatch, get_system(outputs_uc)))
    my_selectors =
        [make_selector(ThermalStandard; groupby = :all),
            make_selector(RenewableDispatch; groupby = :all),
            make_selector(ThermalStandard; groupby = :all),
            my_component]
    all_result = compute_all(outputs_uc, my_metrics, my_selectors)

    for (metric, selector) in zip(my_metrics, my_selectors)
        one_result = compute(metric, outputs_uc, selector)
        @test get_time_df(all_result) == get_time_df(one_result)
        @test all_result[!, metric_selector_to_string(metric, selector)] ==
              get_data_vec(one_result)
        @test get(metadata(all_result), "outputs", nothing) ==
              get(metadata(one_result), "outputs", nothing)
        # Comparing the components iterators with == gives false failures
        # TODO why do we need collect here but not in test_component_timed_metric?
        @test all(
            collect(
                colmetadata(
                    all_result,
                    metric_selector_to_string(metric, selector),
                    "components",
                ),
            ) .== collect(colmetadata(one_result, 2, "components")),
        )
        @test colmetadata(
            all_result,
            metric_selector_to_string(metric, selector),
            "metric",
        ) ==
              colmetadata(one_result, 2, "metric")
        (selector isa Component) || @test colmetadata(
            all_result,
            metric_selector_to_string(metric, selector),
            "ComponentSelector",
        ) == colmetadata(one_result, 2, "ComponentSelector")
    end

    my_names = ["Thermal Power", "Renewable Power", "Thermal Cost", "Renewable Cost"]
    all_result_named = compute_all(outputs_uc, my_metrics, my_selectors, my_names)
    @test names(all_result_named) == vcat(DATETIME_COL, my_names...)
    @test get_time_df(all_result_named) == get_time_df(all_result)
    @test get_data_mat(all_result_named) == get_data_mat(all_result)

    @test_throws ArgumentError compute_all(outputs_uc, my_metrics, my_selectors[2:end])
    @test_throws ArgumentError compute_all(outputs_uc, my_metrics, my_selectors,
        my_names[2:end])

    for (label, outputs) in pairs(outputs_by_name)
        @test compute_all(outputs,
            [test_calc_sum_objective_value, test_calc_sum_solve_time],
            nothing, ["Met1", "Met2"]) == DataFrame(
            "Met1" => first(get_data_mat(compute(test_calc_sum_objective_value, outputs))),
            "Met2" => first(get_data_mat(compute(test_calc_sum_solve_time, outputs))))
    end

    broadcasted_compute_all = compute_all(
        outputs_uc,
        [test_calc_active_power, test_calc_active_power],
        make_selector(ThermalStandard; groupby = :all),
        ["discard", "ThermalStandard"],
    )
    @test broadcasted_compute_all[!, [DATETIME_COL, "ThermalStandard"]] ==
          compute(test_calc_active_power, outputs_uc,
        make_selector(ThermalStandard; groupby = :all))

    @test compute_all(outputs_uc, my_metrics, my_selectors, my_names) ==
          compute_all(outputs_uc, collect(zip(my_metrics, my_selectors, my_names))...)
    @test compute_all(
        outputs_uc,
        [test_calc_sum_objective_value, test_calc_sum_solve_time],
        nothing,
        ["obje", "solv"],
    ) == compute_all(
        outputs_uc,
        (test_calc_sum_objective_value, nothing, "obje"),
        (test_calc_sum_solve_time, nothing, "solv"),
    )

    @test_throws MethodError compute_all(  # Can't mix TimedMetrics and TimelessMetrics
        outputs_uc,
        [(test_calc_active_power, make_selector(ThermalStandard), "therm"),
            (test_calc_sum_objective_value, nothing, "obje")],
    )
end

@testset "Test compose_metrics" begin
    # TODO broken for groupby = :each?
    mysel = make_selector(ThermalStandard; groupby = :all)
    "Computes ActivePower*3"
    mymet1 = compose_metrics(
        "ThriceActivePower",
        (+),
        test_calc_active_power,
        test_calc_active_power,
        test_calc_active_power,
    )
    results1 = compute_all(
        outputs_uc,
        [test_calc_active_power, mymet1],
        [mysel, mysel],
        ["once", "thrice"],
    )
    @test all(results1[!, "once"] * 3 .== results1[!, "thrice"])

    "Computes SystemSlackUp*3"
    mymet2 = compose_metrics(
        "ThriceSystemSlackUp",
        (+),
        test_calc_system_slack_up,
        test_calc_system_slack_up,
        test_calc_system_slack_up,
    )
    results2 = compute_all(
        outputs_ed,
        [test_calc_system_slack_up, mymet2],
        nothing,
        ["once", "thrice"],
    )
    @test all(results2[!, "once"] * 3 .== results2[!, "thrice"])

    "Computes SumObjectiveValue*3"
    mymet3 = compose_metrics(
        "ThriceSumObjectiveValue",
        (+),
        test_calc_sum_objective_value,
        test_calc_sum_objective_value,
        test_calc_sum_objective_value,
    )
    results3 = compute_all(
        outputs_uc,
        [test_calc_sum_objective_value, mymet3],
        nothing,
        ["once", "thrice"],
    )
    @test all(results3[!, "once"] * 3 .== results3[!, "thrice"])

    "Computes SystemSlackUp^2*ActivePower (element-wise)"
    mymet4 = compose_metrics(
        "SlackSlackPower",
        (.*),
        test_calc_system_slack_up,
        test_calc_active_power,
        test_calc_system_slack_up,
    )
    results4 = compute_all(
        outputs_ed,
        [test_calc_system_slack_up, test_calc_active_power, mymet4],
        [nothing, mysel, mysel],
        ["slack", "power", "final"],
    )
    @test all(
        isapprox.(
            results4[!, "slack"] .^ 2 .* results4[!, "power"],
            results4[!, "final"],
        ),
    )
end

@testset "Test agg_meta basics" begin
    @test get_agg_meta(my_df_agg_meta, "Component1") == my_agg_meta[1]
    @test get_agg_meta(my_df_agg_meta, "Component2") == my_agg_meta[2]
    new_df = copy(my_df2)
    set_agg_meta!(new_df, "Component1", my_agg_meta[1])
    set_agg_meta!(new_df, "Component2", my_agg_meta[2])
    @test get_agg_meta(new_df, "Component1") == my_agg_meta[1]
    @test get_agg_meta(new_df, "Component2") == my_agg_meta[2]

    newer_df = copy(my_df1)
    @test get_agg_meta(newer_df) === nothing
    set_agg_meta!(newer_df, my_meta)
    @test get_agg_meta(newer_df) == my_meta
end

@testset "Test component_agg_fn and corresponding `compute` aggregation behavior" begin
    # TODO broken for groupby = :each?
    my_selector = make_selector(ThermalStandard; groupby = :all)
    my_outputs = outputs_uc
    sum_metric = test_calc_active_power
    @test get_component_agg_fn(sum_metric) == sum  # Should be the default
    my_mean(x) = sum(x) / length(x)
    mean_metric = rebuild_metric(sum_metric; component_agg_fn = my_mean)
    @test get_component_agg_fn(mean_metric) == my_mean
    # NOTE a more thorough approach would test the getter and "with-er" on all subtypes

    results = compute_all(
        my_outputs,
        [sum_metric, mean_metric],
        [my_selector, my_selector],
        ["sum_col", "mean_col"],
    )
    @assert !all(results[!, "sum_col"] .== 0) "Cannot test with all-zero data"
    n_components = get_components(my_selector, get_system(my_outputs)) |> collect |> length
    @assert n_components > 1 "Cannot test without multiple components"

    @test all(isapprox.(results[!, "mean_col"] .* n_components, results[!, "sum_col"]))

    results2 = compute_all(
        my_outputs,
        repeat([test_calc_dummy_meta], 3),
        [thermal_sel, wind_sel, make_selector(make_selector(thermal_sel, wind_sel))],
        ["thermal", "wind", "combo"])
    @test isapprox(
        get_data_mat(results2),
        [thermal_vals other_vals weighted_mean(
            [thermal_vals, other_vals],
            [thermal_weights, other_weights],
        )],
    )
    @test get_agg_meta.(Ref(results2), get_data_cols(results2)) ==
          [thermal_weights, other_weights, sum([thermal_weights, other_weights])]
end

@testset "Test time_agg_fn and corresponding `aggregate_time` aggregation behavior" begin
    my_selector = make_selector(ThermalStandard; groupby = :all)
    my_outputs = outputs_uc
    sum_metric = test_calc_active_power
    @test get_time_agg_fn(sum_metric) == sum  # Should be the default
    mean_metric = rebuild_metric(sum_metric; time_agg_fn = mean)
    @test get_time_agg_fn(mean_metric) == mean

    results = compute_all(
        my_outputs,
        [sum_metric, mean_metric],
        [my_selector, my_selector],
        ["sum_col", "mean_col"],
    )
    results_agg = aggregate_time(results)
    @assert !all(results[!, "sum_col"] .== 0) "Cannot test with all-zero data"
    n_times = size(results, 1)
    @assert n_times > 1 "Cannot test without multiple time periods"

    @test isapprox(first(results_agg[!, "sum_col"]), sum(results[!, "sum_col"]))
    @test isapprox(first(results_agg[!, "mean_col"]), mean(results[!, "sum_col"]))

    results2 = compute_all(
        my_outputs,
        repeat([test_calc_dummy_meta], 3),
        [thermal_sel, wind_sel, make_selector(make_selector(thermal_sel, wind_sel))],
        ["thermal", "wind", "combo"])
    results2_agg = aggregate_time(results2)
    answer1 = weighted_mean(thermal_vals, thermal_weights)
    answer2 = weighted_mean(other_vals, other_weights)
    @test results2_agg[!, "thermal"] == [answer1]
    @test results2_agg[!, "wind"] == [answer2]
    @test results2_agg[!, "combo"] ==
          [weighted_mean([answer1, answer2], [sum(thermal_weights), sum(other_weights)])]
end
