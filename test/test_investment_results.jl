investment_test_data = run_test_investment_prob()
integer_investment_test_data = run_test_investment_prob(;
    supply_investment = PSIN.IntegerInvestment,
    storage_investment = PSIN.IntegerInvestment)
multi_region_investment_test_data = run_test_investment_prob(; multi_region_supply = true)

@testset "Test saved investment time mapping" begin
    test_data = investment_test_data
    results = test_data.results
    saved = PSIN.InvestmentProblemResults(PSIN.get_output_dir(results))
    @test_throws ArgumentError investment_results(saved)
    @test_throws ArgumentError operational_results(saved)
    PSIN.set_portfolio!(saved, PSIN.get_portfolio(results))
    loaded_investment = investment_results(saved)
    loaded_operations = operational_results(saved)
    portfolio = deepcopy(PSIN.get_portfolio(results))
    PSIN.set_portfolio!(saved, portfolio)
    @test IS.get_source_data(loaded_investment) === portfolio
    @test get_investment_periods(loaded_investment) == test_data.periods
    @test compute(calc_capacity_additions, loaded_investment, test_data.thermal[1]) ==
          compute(
        calc_capacity_additions,
        investment_results(results),
        test_data.thermal[1],
    )
    @test compute(calc_active_power, loaded_operations, test_data.thermal[1]) ==
          compute(calc_active_power, operational_results(results), test_data.thermal[1])
end

@testset "Test ComponentTimedMetric on portfolio technologies" begin
    test_data = investment_test_data
    results = operational_results(test_data.results)
    expected = PSIN.read_variable(test_data.results, test_data.dispatch_key;
        table_format = IS.TableFormat.WIDE)
    thermal_type = typeof(first(test_data.thermal))
    selector = make_selector(thermal_type; groupby = :all)
    generation = compute(calc_active_power, results, selector)
    @test get_time_vec(generation) == expected.DateTime
    @test get_data_vec(generation) ≈ expected.gas_1 + expected.gas_2
    @test Set(IS.get_name.(IS.get_components(selector, results))) ==
          Set(IS.get_name.(test_data.thermal[1:2]))
    @test DataFrames.metadata(generation, "results") === results
    @test Set(
        PA.get_data_cols(compute(calc_active_power, results,
            make_selector(thermal_type))),
    ) == Set(get_name.(make_selector.(test_data.thermal[1:2])))

    by_zone = make_selector(thermal_type;
        groupby = technology -> PSIP.get_name(only(PSIP.get_region(technology))))
    grouped = compute(calc_active_power, results, by_zone)
    @test Set(get_data_cols(grouped)) == Set(["Zone_1", "Zone_2"])
    @test grouped.Zone_1 ≈ expected.gas_1
    @test grouped.Zone_2 ≈ expected.gas_2
    filtered = make_selector(t -> PSIP.get_name(t) == "gas_2", thermal_type; groupby = :all)
    @test get_data_vec(compute(calc_active_power, results, filtered)) ≈ expected.gas_2

    @test get_data_vec(compute(calc_active_power, results, test_data.thermal[1])) ≈
          expected.gas_1
end

@testset "Test operational results for a technology in multiple regions" begin
    test_data = multi_region_investment_test_data
    technology = first(test_data.thermal)
    results = operational_results(test_data.results)
    expected = PSIN.read_variable(test_data.results, test_data.dispatch_key;
        table_format = IS.TableFormat.WIDE)
    result_names = PSIN.get_variable_names(technology)
    @test all(name -> maximum(expected[!, name]) > 0.0, result_names)
    total = sum(expected[!, name] for name in result_names)
    generation = compute(calc_active_power, results, technology)
    @test get_time_vec(generation) == expected.DateTime
    @test get_data_vec(generation) ≈ total
    selector = make_selector(typeof(technology); groupby = :all)
    @test get_data_vec(compute(calc_active_power, results, selector)) ≈
          total + expected.gas_2
    window = compute(calc_active_power, results, technology;
        start_time = DateTime(2035, 1, 1), len = 2)
    @test get_time_vec(window) == expected.DateTime[25:26]
    @test get_data_vec(window) ≈ total[25:26]
end

@testset "Test investment storage metrics" begin
    test_data = investment_test_data
    results = operational_results(test_data.results)
    charging = PSIN.read_variable(test_data.results,
        PSIN.VariableKey(PSIN.ActiveInPowerVariable, typeof(test_data.battery),
            string(PSIN.CyclicalStorageDispatch)); table_format = IS.TableFormat.WIDE)
    discharging = PSIN.read_variable(test_data.results,
        PSIN.VariableKey(PSIN.ActiveOutPowerVariable, typeof(test_data.battery),
            string(PSIN.CyclicalStorageDispatch)); table_format = IS.TableFormat.WIDE)
    stored_energy = PSIN.read_variable(test_data.results,
        PSIN.VariableKey(PSIN.StateOfChargeVariable, typeof(test_data.battery),
            string(PSIN.CyclicalStorageDispatch)); table_format = IS.TableFormat.WIDE)

    storage_selector = make_selector(typeof(test_data.battery); groupby = :all)
    for (expected, metric) in (
        (charging, calc_active_power_in),
        (discharging, calc_active_power_out),
        (stored_energy, calc_stored_energy),
    )
        @test maximum(expected.battery) > 0.0
        @test get_data_vec(compute(metric, results, storage_selector)) ≈ expected.battery
    end
    @test get_data_vec(compute(calc_load_from_storage, results, storage_selector)) ≈
          charging.battery - discharging.battery
end

@testset "Test compute_all with investment results" begin
    test_data = investment_test_data
    results = operational_results(test_data.results)
    expected = PSIN.read_variable(test_data.results, test_data.dispatch_key;
        table_format = IS.TableFormat.WIDE)
    stored_energy = PSIN.read_variable(test_data.results,
        PSIN.VariableKey(PSIN.StateOfChargeVariable, typeof(test_data.battery),
            string(PSIN.CyclicalStorageDispatch)); table_format = IS.TableFormat.WIDE)
    combined = compute_all(results, [calc_active_power, calc_stored_energy],
        [test_data.thermal[1], test_data.battery], ["generation", "energy"])
    @test names(combined) == ["DateTime", "generation", "energy"]
    @test combined.generation ≈ expected.gas_1
    @test combined.energy ≈ stored_energy.battery
end

@testset "Test make_component_metric_from_entry with investment results" begin
    test_data = investment_test_data
    results = operational_results(test_data.results)
    flow =
        PA.make_component_metric_from_entry(
            "ZoneConnectionFlow",
            PSIN.FlowActivePowerVariable,
        )
    expected_flow = PSIN.read_variable(test_data.results,
        PSIN.VariableKey(PSIN.FlowActivePowerVariable, typeof(test_data.line),
            string(PSIN.BasicDispatch)); table_format = IS.TableFormat.WIDE)
    @test minimum(expected_flow.zone_connection) < 0.0 <
          maximum(expected_flow.zone_connection)
    @test get_data_vec(compute(flow, results, test_data.line)) ≈
          expected_flow.zone_connection
end

@testset "Test operational time windows" begin
    test_data = investment_test_data
    results = operational_results(test_data.results)
    technology = first(test_data.thermal)
    expected = PSIN.read_variable(test_data.results, test_data.dispatch_key;
        table_format = IS.TableFormat.WIDE)
    window = compute(calc_active_power, results, technology;
        start_time = DateTime(2035, 1, 1), len = 2)
    @test get_time_vec(window) == test_data.timestamps[25:26]
    @test get_data_vec(window) ≈ expected.gas_1[25:26]
end

@testset "Test operational formulation selection" begin
    test_data = investment_test_data
    expected = PSIN.read_variable(test_data.results, test_data.dispatch_key;
        table_format = IS.TableFormat.WIDE)
    split = make_investment_results(test_data; other_formulation = :split)
    split_results = operational_results(split)
    @test get_data_vec(compute(calc_active_power, split_results, test_data.thermal[1])) ≈
          expected.gas_1
    @test get_data_vec(compute(calc_active_power, split_results, test_data.thermal[2])) ≈
          2 .* expected.gas_2

    overlapping = make_investment_results(test_data; other_formulation = :overlap)
    results = operational_results(overlapping)
    @test_throws ArgumentError compute(calc_active_power, results, test_data.thermal[2])
    @test get_data_vec(
        compute(calc_active_power, results, test_data.thermal[2];
            meta = string(PSIN.BasicDispatch)),
    ) ≈ expected.gas_2
    @test get_data_vec(
        compute(calc_active_power, results, test_data.thermal[2];
            meta = "OtherDispatch"),
    ) ≈ 2 .* expected.gas_2
    @test_throws PA.NoResultError compute(calc_active_power, results,
        test_data.thermal[2]; meta = "MissingDispatch")
end

@testset "Test operational source identity and timestamps" begin
    test_data = investment_test_data
    results = operational_results(test_data.results)
    @test_throws ArgumentError operational_results(
        make_investment_results(test_data;
            source_uuid = IS.get_uuid(PSIP.Portfolio())),
    )
    _, other_thermal, _, _, _ = make_investment_portfolio()
    @test_throws ArgumentError compute(calc_active_power, results, first(other_thermal))
    for timestamps in (DateTime[], reverse(test_data.timestamps),
        fill(first(test_data.timestamps), length(test_data.timestamps)))
        @test_throws ArgumentError operational_results(
            make_investment_results(test_data; timestamps = timestamps))
    end
end

@testset "Test unsupported operational requests" begin
    test_data = investment_test_data
    results = operational_results(test_data.results)
    technology = first(test_data.thermal)
    @test_throws ArgumentError compute(calc_active_power, results,
        make_selector(PSY.ThermalStandard))
    @test_throws PA.NoResultError PA.read_component_result(results,
        PSIN.WeightedEnergyGeneration, technology; len = 2)
    @test_throws PA.NoResultError compute(
        calc_production_cost,
        results,
        test_data.thermal[1],
    )
end

@testset "Test read_component_result with investment capacity results" begin
    test_data = integer_investment_test_data
    results = investment_results(test_data.results)
    technology = first(test_data.thermal)
    for (key, tables) in (
        (
            PSIN.VariableKey(PSIN.BuildCapacity, typeof(technology),
                string(PSIN.IntegerInvestment)), PSIN.get_variable_values(test_data.results)),
        (
            PSIN.ExpressionKey(PSIN.CapacityAdditions, typeof(technology),
                string(PSIN.IntegerInvestment)), PSIN.get_expression_values(test_data.results)),
        (
            PSIN.ExpressionKey(PSIN.CumulativeCapacity, typeof(technology),
                string(PSIN.IntegerInvestment)), PSIN.get_expression_values(test_data.results)),
    )
        name = PSIP.get_name(technology)
        result_table = sort(filter(:name => ==(name), tables[key]), :time_index)
        expected = DataFrame("DateTime" => DateTime.(first.(test_data.periods)),
            name => result_table.value)
        @test PA.read_component_result(results, ISOPT.get_entry_type(key), technology) ==
              expected
        @test PA.read_component_result(results, key, technology) == expected
        @test PA.read_component_result(results, key, technology;
            start_time = DateTime(2035, 1, 1), len = 1) == expected[2:2, :]
    end
end

@testset "Test capacity results for a technology in multiple regions" begin
    test_data = multi_region_investment_test_data
    technology = first(test_data.thermal)
    results = investment_results(test_data.results)
    result_names = PSIN.get_variable_names(technology)
    for (key, metric) in (
        (
            PSIN.VariableKey(PSIN.BuildCapacity, typeof(technology),
                string(PSIN.ContinuousInvestment)), nothing),
        (
            PSIN.ExpressionKey(PSIN.CapacityAdditions, typeof(technology),
                string(PSIN.ContinuousInvestment)), calc_capacity_additions),
        (
            PSIN.ExpressionKey(PSIN.CumulativeCapacity, typeof(technology),
                string(PSIN.ContinuousInvestment)), calc_installed_capacity),
    )
        table = PSIN.read_results_with_keys(test_data.results, [key];
            table_format = IS.TableFormat.WIDE)[key]
        total = sum(table[!, name] for name in result_names)
        expected = DataFrame("DateTime" => table.DateTime,
            PSIP.get_name(technology) => total)
        @test PA.read_component_result(results, ISOPT.get_entry_type(key), technology) ==
              expected
        @test PA.read_component_result(results, key, technology) == expected
        @test PA.read_component_result(results, key, technology;
            start_time = DateTime(2035, 1, 1), len = 1) == expected[2:2, :]
        if !isnothing(metric)
            selector = make_selector(typeof(technology); groupby = :all)
            @test get_data_vec(compute(metric, results, selector)) ≈ total + table.gas_2
        end
    end
end

@testset "Test investment capacity metrics" begin
    integer_key = PSIN.VariableKey(PSIN.BuildCapacity,
        typeof(first(integer_investment_test_data.thermal)),
        string(PSIN.IntegerInvestment))
    integer_builds =
        PSIN.get_variable_values(integer_investment_test_data.results)[integer_key]
    original_integer_builds = copy(integer_builds)
    for (test_data, formulation) in ((investment_test_data, PSIN.ContinuousInvestment),
        (integer_investment_test_data, PSIN.IntegerInvestment))
        psin_results = test_data.results
        results = investment_results(psin_results)
        variables = PSIN.get_variable_values(psin_results)
        expressions = PSIN.get_expression_values(psin_results)
        for (technology, build_entry, installed_entry, unit_size) in (
            (first(test_data.thermal), PSIN.BuildCapacity, PSIN.CumulativeCapacity,
                PSIP.get_unit_size(first(test_data.thermal))),
            (test_data.battery, PSIN.BuildPowerCapacity, PSIN.CumulativePowerCapacity,
                PSIP.get_unit_size_discharge(test_data.battery)),
        )
            for (metric, key, tables, multiplier) in (
                (calc_capacity_additions,
                    PSIN.VariableKey(build_entry, typeof(technology), string(formulation)),
                    variables, formulation == PSIN.IntegerInvestment ? unit_size : 1.0),
                (calc_installed_capacity,
                    PSIN.ExpressionKey(
                        installed_entry,
                        typeof(technology),
                        string(formulation),
                    ),
                    expressions, 1.0))
                expected =
                    sort(filter(:name => ==(PSIP.get_name(technology)), tables[key]),
                        :time_index)
                computed = compute(metric, results, technology)
                @test get_time_vec(computed) == DateTime.(first.(test_data.periods))
                @test get_data_vec(computed) ≈ expected.value .* multiplier
            end
            additions = compute(calc_capacity_additions, results, technology)
            installed = compute(calc_installed_capacity, results, technology)
            @test sum(get_data_vec(additions)) > 0.0
            @test get_data_vec(installed) ≈ cumsum(get_data_vec(additions))
        end
    end
    @test integer_builds == original_integer_builds
end

@testset "Test investment formulation metadata" begin
    test_data = integer_investment_test_data
    technology = first(test_data.thermal)
    results = investment_results(test_data.results)
    renamed = investment_results(
        make_investment_results(test_data;
            formulation_meta = string(PSIN.IntegerInvestment) => "CustomInvestment"),
    )
    for metric in (calc_capacity_additions, calc_installed_capacity)
        @test compute(metric, renamed, technology) == compute(metric, results, technology)
    end
end

@testset "Test storage energy capacity metrics" begin
    for (test_data, formulation) in ((investment_test_data, PSIN.ContinuousInvestment),
        (integer_investment_test_data, PSIN.IntegerInvestment))
        psin_results = test_data.results
        results = investment_results(psin_results)
        battery = test_data.battery
        variables = PSIN.get_variable_values(psin_results)
        expressions = PSIN.get_expression_values(psin_results)
        unit_size =
            formulation == PSIN.IntegerInvestment ? PSIP.get_unit_size_energy(battery) : 1.0
        for (metric, key, tables, multiplier) in (
            (calc_storage_energy_additions,
                PSIN.VariableKey(
                    PSIN.BuildEnergyCapacity,
                    typeof(battery),
                    string(formulation),
                ),
                variables, unit_size),
            (calc_installed_storage_energy,
                PSIN.ExpressionKey(
                    PSIN.CumulativeEnergyCapacity,
                    typeof(battery),
                    string(formulation),
                ),
                expressions, 1.0),
        )
            expected =
                sort(filter(:name => ==(PSIP.get_name(battery)), tables[key]), :time_index)
            computed = compute(metric, results, battery)
            @test get_time_vec(computed) == DateTime.(first.(test_data.periods))
            @test get_data_vec(computed) ≈ expected.value .* multiplier
        end
        additions = compute(calc_storage_energy_additions, results, battery)
        installed = compute(calc_installed_storage_energy, results, battery)
        @test sum(get_data_vec(additions)) > 0.0
        @test get_data_vec(installed) ≈ cumsum(get_data_vec(additions))
    end
end

@testset "Test investment technology categories" begin
    _, thermal, battery, _, _ = make_investment_portfolio()
    mapping = PA.get_generator_mapping()
    gas = first(thermal)
    wind = PSIP.SupplyTechnology{PSY.RenewableDispatch}(;
        name = "wind",
        id = 6,
        available = true,
        financial_data = PSIP.get_financial_data(gas),
        power_systems_type = "RenewableDispatch",
        prime_mover_type = PSY.PrimeMovers.WT,
    )
    @test PA.get_generator_category(gas, mapping) == "NG-CT"
    @test PA.get_generator_category(wind, mapping) == "Wind"
    @test PA.get_generator_category(battery, mapping) == "Storage"

    PSIP.set_fuel!(gas,
        [PSY.ThermalFuels.NATURAL_GAS, PSY.ThermalFuels.DISTILLATE_FUEL_OIL])
    @test_throws ArgumentError PA.get_generator_category(gas, mapping)
end

@testset "Test investment category mapping overrides" begin
    _, thermal, battery, _, _ = make_investment_portfolio()
    mapping = PA.get_generator_mapping()
    for (technology, fuel, category) in (
        (first(thermal), "NATURAL_GAS", "NG-CT"),
        (battery, nothing, "Storage"),
    )
        PSIP.get_ext(technology)["ext_category"] = "custom"
        @test PA.get_generator_category(technology, mapping) == category
        custom_mapping = copy(mapping)
        custom_mapping[(gentype = string(nameof(PSIP.get_parameter_type(technology))),
            fuel = fuel, primemover = string(PSIP.get_prime_mover_type(technology)),
            ext = "CUSTOM")] = "Custom"
        @test PA.get_generator_category(technology, custom_mapping) == "Custom"
    end
end

@testset "Test investment categories with missing metadata" begin
    _, thermal, battery, _, _ = make_investment_portfolio()
    mapping = PA.get_generator_mapping()
    gas = first(thermal)
    PSIP.set_fuel!(gas, PSY.ThermalFuels[])
    PSIP.set_prime_mover_type!(battery, PSY.PrimeMovers.OT)
    for technology in (gas, battery)
        category =
            @test_logs (:error, r"No mapping defined") match_mode = :any PA.get_generator_category(
                technology, mapping,
            )
        @test isnothing(category)
    end
end

@testset "Test capacity aggregation by category" begin
    test_data = investment_test_data
    results = investment_results(test_data.results)
    mapping = PA.get_generator_mapping()
    by_category = make_selector(PSIP.ResourceTechnology;
        groupby = technology -> PA.get_generator_category(technology, mapping))
    for metric in (calc_capacity_additions, calc_installed_capacity)
        grouped = compute(metric, results, by_category)
        @test Set(get_data_cols(grouped)) == Set(["NG-CT", "Storage"])
        @test grouped[!, "NG-CT"] ≈ sum(
            get_data_vec(compute(metric, results, technology))
            for technology in test_data.thermal[1:2])
        @test grouped.Storage ≈ get_data_vec(compute(metric, results, test_data.battery))
    end
end

@testset "Test capacity aggregation" begin
    test_data = investment_test_data
    results = investment_results(test_data.results)
    selector = make_selector(typeof(first(test_data.thermal)); groupby = :all)
    additions = compute(calc_capacity_additions, results, selector)
    installed = compute(calc_installed_capacity, results, selector)
    expected = sum(
        get_data_vec(compute(calc_capacity_additions, results, technology))
        for technology in test_data.thermal[1:2]
    )
    @test get_data_vec(additions) ≈ expected
    @test get_data_vec(aggregate_time(additions)) ≈ [sum(expected)]
    @test get_data_vec(aggregate_time(installed)) ≈ [last(get_data_vec(installed))]
    @test metadata(additions, "time_axis") == "investment_period"
    @test metadata(additions, "investment_periods") == test_data.periods
    @test metadata(additions, "results") === results
    empty_selector =
        make_selector(t -> false, typeof(first(test_data.thermal)); groupby = :all)
    empty_result = compute(calc_capacity_additions, results, empty_selector)
    @test get_data_cols(empty_result) == [get_name(empty_selector)]
    @test get_time_vec(empty_result) == get_time_vec(additions)
    @test get_data_vec(empty_result) == [0.0, 0.0]
end

@testset "Test storage energy capacity aggregation" begin
    test_data = investment_test_data
    results = investment_results(test_data.results)
    selector = make_selector(typeof(test_data.battery); groupby = :all)
    for (metric, aggregate) in ((calc_storage_energy_additions, sum),
        (calc_installed_storage_energy, last))
        grouped = compute(metric, results, selector)
        expected = get_data_vec(compute(metric, results, test_data.battery))
        @test get_data_vec(grouped) ≈ expected
        @test get_data_vec(aggregate_time(grouped)) ≈ [aggregate(expected)]
        @test metadata(grouped, "time_axis") == "investment_period"
    end
end

@testset "Test compute_all with investment capacity results" begin
    test_data = investment_test_data
    results = investment_results(test_data.results)
    selector = make_selector(typeof(first(test_data.thermal)); groupby = :all)
    additions = compute(calc_capacity_additions, results, selector)
    installed = compute(calc_installed_capacity, results, selector)
    combined = compute_all(results, [calc_capacity_additions, calc_installed_capacity],
        [selector, selector], ["new_mw", "installed_mw"])
    @test combined.new_mw ≈ get_data_vec(additions)
    @test combined.installed_mw ≈ get_data_vec(installed)
end

@testset "Test investment periods and capacity time windows" begin
    test_data = investment_test_data
    technology = first(test_data.thermal)
    results = investment_results(test_data.results)
    for metric in (calc_capacity_additions, calc_installed_capacity)
        expected = compute(metric, results, technology)
        window =
            compute(metric, results, technology; start_time = DateTime(2035, 1, 1), len = 1)
        @test get_time_vec(window) == [DateTime(2035, 1, 1)]
        @test get_data_vec(window) ≈ get_data_vec(expected)[2:2]
        @test metadata(window, "investment_periods") == test_data.periods[2:2]
    end
end

@testset "Test unsupported capacity requests" begin
    test_data = investment_test_data
    technology = first(test_data.thermal)
    results = investment_results(test_data.results)
    results_uc, _ = run_test_sim(TEST_RESULT_DIR, TEST_SIM_NAME)
    @test_throws PA.NoResultError calc_capacity_additions(
        make_selector(ThermalStandard), results_uc)
    @test_throws ArgumentError investment_results(
        make_investment_results(test_data; source_uuid = IS.get_uuid(PSIP.Portfolio())))
    @test_throws PA.NoResultError compute(calc_capacity_additions, results, test_data.line)
    @test_throws PA.NoResultError compute(calc_capacity_additions,
        operational_results(test_data.results), technology)
    @test_throws PA.NoResultError compute(calc_active_power, results, technology)
    @test_throws PA.NoResultError PA.read_component_result(results,
        PSIN.BuildEnergyCapacity, technology)
    key = PSIN.VariableKey(PSIN.BuildCapacity, typeof(technology),
        string(PSIN.ContinuousInvestment))
    @test_throws ArgumentError PA.read_component_result(results, key, technology;
        meta = "OtherInvestment")
    _, other_thermal, _, _, _ = make_investment_portfolio()
    @test_throws ArgumentError PA.read_component_result(results, key, first(other_thermal))
    @test_throws PA.NoResultError PA.read_component_result(
        results,
        key,
        test_data.thermal[3],
    )
    missing_key =
        PSIN.VariableKey(PSIN.BuildCapacity, typeof(technology), "MissingInvestment")
    @test_throws PA.NoResultError PA.read_component_result(results, missing_key, technology)
end
