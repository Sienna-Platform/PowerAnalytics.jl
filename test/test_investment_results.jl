investment_test_data = run_test_investment_prob()
original_investment_variables =
    deepcopy(PSIN.get_variable_values(investment_test_data.results))

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
    for (native, metric) in (
        (charging, calc_active_power_in),
        (discharging, calc_active_power_out),
        (stored_energy, calc_stored_energy),
    )
        @test maximum(native.battery) > 0.0
        @test get_data_vec(compute(metric, results, storage_selector)) ≈ native.battery
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
        PA.make_component_metric_from_entry("InterzoneFlow", PSIN.FlowActivePowerVariable)
    native_flow = PSIN.read_variable(test_data.results,
        PSIN.VariableKey(PSIN.FlowActivePowerVariable, typeof(test_data.line),
            string(PSIN.BasicDispatch)); table_format = IS.TableFormat.WIDE)
    @test minimum(native_flow.interzone) < 0.0 < maximum(native_flow.interzone)
    @test get_data_vec(compute(flow, results, test_data.line)) ≈ native_flow.interzone
    @test PSIN.get_variable_values(test_data.results) == original_investment_variables
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
    @test_throws ArgumentError compute(calc_active_power, results, technology; len = 0)
    @test_throws IS.InvalidValue compute(calc_active_power, results, technology; len = 49)
    @test_throws IS.InvalidValue compute(calc_active_power, results, technology;
        start_time = DateTime(2032, 1, 1))

    for indices in ([1, 2], [collect(1:47); 47])
        incomplete = make_investment_results(test_data; dispatch_indices = indices)
        @test_throws ArgumentError compute(calc_active_power,
            operational_results(incomplete), technology; len = 2)
    end
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
        make_investment_results(test_data; attach_portfolio = false))
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
        PSIN.BuildCapacity, technology; len = 2)
    @test_throws PA.NoResultError PA.read_component_result(results,
        PSIN.WeightedEnergyGeneration, technology; len = 2)
    @test_throws PA.NoResultError compute(
        calc_production_cost,
        results,
        test_data.thermal[1],
    )
    @test_throws PA.NoResultError compute(
        calc_active_power_forecast,
        results,
        test_data.thermal[1],
    )
end
