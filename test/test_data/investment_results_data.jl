function make_investment_portfolio()
    financial_data = PSIP.TechnologyFinancialData(;
        capital_recovery_period = 30,
        technology_base_year = 2025,
        debt_fraction = 0.6,
        debt_rate = 0.04,
        return_on_equity = 0.1,
        tax_rate = 0.21,
    )
    portfolio = PSIP.Portfolio(;
        time_series_in_memory = true,
        financial_data = PSIP.PortfolioFinancialData(2025, 0.07, 0.0, 0.04),
    )
    zones = [PSIP.Zone(; name = "Zone_$i", id = i) for i in 1:2]
    foreach(z -> PSIP.add_region!(portfolio, z), zones)
    thermal = [
        PSIP.SupplyTechnology{PSY.ThermalStandard}(;
            name = "gas_$i",
            id = i,
            available = i != 3,
            financial_data = financial_data,
            region = [zones[mod1(i, 2)]],
            power_systems_type = "ThermalStandard",
            prime_mover_type = PSY.PrimeMovers.GT,
            fuel = [PSY.ThermalFuels.NATURAL_GAS],
            capacity_limits = (min = 0.0, max = i == 1 ? 150.0 : 300.0),
            capital_costs = PSIP.CapitalCost(LinearCurve(1000.0), 0.0),
            operation_costs = ThermalGenerationCost(;
                variable = CostCurve(LinearCurve(i == 1 ? 10.0 : 50.0)),
                fixed = 0.0,
                start_up = 0.0,
                shut_down = 0.0,
            ),
        ) for i in 1:3
    ]
    battery = PSIP.StorageTechnology{PSY.EnergyReservoirStorage}(;
        name = "battery",
        id = 4,
        available = true,
        financial_data = financial_data,
        region = [zones[1]],
        storage_tech = PSIP.StorageTech.LIB,
        prime_mover_type = PSY.PrimeMovers.BA,
        power_systems_type = "EnergyReservoirStorage",
        capacity_limits_discharge = (min = 0.0, max = 50.0),
        capacity_limits_energy = (min = 0.0, max = 200.0),
        duration_limits = (min = 4.0, max = 4.0),
        efficiency = (in = 0.9, out = 0.9),
        capital_costs_storage = PSIP.StorageCapitalCost(;
            charge_capital_cost = LinearCurve(0.0),
            discharge_capital_cost = LinearCurve(1000.0),
            energy_capital_cost = LinearCurve(500.0),
            interconnection_cost = 0.0,
        ),
        operation_costs = StorageCost(;
            charge_variable_cost = CostCurve(LinearCurve(1.0)),
            discharge_variable_cost = CostCurve(LinearCurve(1.0)),
            fixed = 0.0,
        ),
    )
    line = PSIP.AggregateTransportTechnology{PSY.ACBranch}(;
        name = "zone_connection",
        id = 5,
        available = true,
        financial_data = financial_data,
        start_region = zones[1],
        end_region = zones[2],
        power_systems_type = "ACBranch",
        capacity_limits = (min = 0.0, max = 100.0),
        capital_costs = PSIP.CapitalCost(LinearCurve(100.0), 0.0),
    )
    for technology in [thermal; battery; line]
        PSIP.add_technology!(portfolio, technology)
    end

    days = [collect(DateTime(y, 1, 1):Hour(1):DateTime(y, 1, 1, 23)) for y in (2030, 2035)]
    for (i, zone) in enumerate(zones)
        demand = PSIP.DemandRequirement{PSY.PowerLoad}(;
            name = "demand_$i",
            id = 5 + i,
            available = true,
            region = [zone],
            power_systems_type = "PowerLoad",
            value_of_lost_load = 10000.0,
        )
        PSIP.add_technology!(portfolio, demand)
        profile = i == 1 ? vcat(fill(60.0, 12), fill(180.0, 12)) : fill(25.0, 24)
        for (period, timestamps) in enumerate(days)
            values = profile .* (1.0 + 0.2 * (period - 1))
            PSIP.add_time_series!(portfolio, demand,
                IS.SingleTimeSeries("ops_demand", TimeArray(timestamps, values));
                year = string(year(first(timestamps))), rep_day = period)
        end
    end
    return portfolio, thermal, battery, line, days
end

function run_test_investment_prob(;
    supply_investment = PSIN.ContinuousInvestment,
    storage_investment = PSIN.ContinuousInvestment,
)
    portfolio, thermal, battery, line, days = make_investment_portfolio()
    if supply_investment == PSIN.IntegerInvestment
        foreach(t -> PSIP.set_unit_size!(t, 25.0), thermal)
    end
    if storage_investment == PSIN.IntegerInvestment
        PSIP.set_unit_size_discharge!(battery, 10.0)
        PSIP.set_unit_size_energy!(battery, 40.0)
    end
    periods = [(Date(y, 1, 1), Date(y + 4, 12, 31)) for y in (2030, 2035)]
    template = PSIN.InvestmentModelTemplate(
        PSIN.DiscountedCashFlow(0.07, Year(2025), periods),
        PSIN.OperationalRepresentativeDays(days, [365, 365]),
        PSIN.RepresentativePeriods(Vector{DateTime}[]),
        PSIN.TransportModel(PSIN.MultiRegionBalanceModel; use_slacks = false),
    )
    for (technology_type, investment, dispatch) in (
        (
            PSIP.DemandRequirement{PSY.PowerLoad},
            PSIN.StaticLoadInvestment,
            PSIN.BasicDispatch,
        ),
        (
            PSIP.SupplyTechnology{PSY.ThermalStandard},
            supply_investment,
            PSIN.BasicDispatch,
        ),
        (
            PSIP.StorageTechnology{PSY.EnergyReservoirStorage},
            storage_investment,
            PSIN.CyclicalStorageDispatch,
        ),
        (
            PSIP.AggregateTransportTechnology{PSY.ACBranch},
            PSIN.ContinuousInvestment,
            PSIN.BasicDispatch,
        ),
    )
        names =
            PSIP.get_name.(
                collect(PSIP.get_available_technologies(technology_type, portfolio))
            )
        PSIN.set_technology_model!(template, names, technology_type,
            investment, dispatch, PSIN.BasicDispatchFeasibility)
    end
    model = PSIN.InvestmentModel(
        template,
        PSIN.SingleInstanceSolve,
        portfolio;
        optimizer = HiGHS.Optimizer,
        portfolio_to_file = false,
        store_variable_names = true,
    )
    PSIN.build!(model; output_dir = mktempdir())
    PSIN.solve!(model)
    results = PSIN.InvestmentProblemResults(model)
    timestamps = PSIN.get_timestamps(results)
    dispatch_key = PSIN.VariableKey(
        PSIN.ActivePowerVariable,
        typeof(first(thermal)),
        string(PSIN.BasicDispatch),
    )
    return (; results, thermal, battery, line, timestamps, dispatch_key, periods)
end

function make_investment_results(test_data;
    dispatch_indices = nothing,
    investment_indices = nothing,
    other_formulation = :none,
    attach_portfolio = true,
    source_uuid = nothing,
    timestamps = nothing,
)
    results = deepcopy(test_data.results)
    optimization_results = PSIN.OptimizationProblemResults(results)
    variables = PSIN.get_variable_values(results)
    dispatch_key = test_data.dispatch_key
    if !isnothing(dispatch_indices)
        table = variables[dispatch_key]
        variables[dispatch_key] = vcat([
            filter(row -> row.time_index == t, table) for t in dispatch_indices
        ]...)
    end
    if !isnothing(investment_indices)
        for tables in (variables, PSIN.get_expression_values(results))
            for key in keys(tables)
                PSIN.is_investment_entry(ISOPT.get_entry_type(key)) || continue
                table = tables[key]
                tables[key] = vcat(
                    [
                        filter(row -> row.time_index == t, table) for
                        t in investment_indices
                    ]...,
                )
            end
        end
    end
    if other_formulation != :none
        other_key = PSIN.VariableKey(
            PSIN.ActivePowerVariable,
            typeof(first(test_data.thermal)),
            "OtherDispatch",
        )
        name = PSIP.get_name(test_data.thermal[2])
        variables[other_key] = filter(row -> row.name == name, variables[dispatch_key])
        variables[other_key].value .*= 2
        if other_formulation == :split
            filter!(row -> row.name != name, variables[dispatch_key])
        end
    end
    if !attach_portfolio
        optimization_results.source_data = nothing
    end
    if !isnothing(source_uuid)
        optimization_results.source_data_uuid = source_uuid
    end
    if !isnothing(timestamps)
        optimization_results.timestamps = timestamps
    end
    return results
end
