stock_decision_results_sets = run_test_sim(TEST_RESULT_DIR, TEST_SIM_NAME)
stock_results_prob = run_test_prob()

sim_results = SimulationResults(TEST_RESULT_DIR, TEST_SIM_NAME)
decision_problem_names = ("UC", "ED")
my_results_sets = get_decision_problem_results.(Ref(sim_results), decision_problem_names)

(results_uc, results_ed) = stock_decision_results_sets
resultses = Dict("UC" => results_uc, "ED" => results_ed, "prob" => stock_results_prob)

# Reimplements Base.Filesystem.cptree since that isn't exported
function cptree(src::String, dst::String)
    mkdir(dst)
    for name in readdir(src)
        srcname = joinpath(src, name)
        if isdir(srcname)
            cptree(srcname, joinpath(dst, name))
        else
            cp(srcname, joinpath(dst, name))
        end
    end
end

# Create another results directory
function setup_duplicate_results()
    teardown_duplicate_results()
    cptree(
        joinpath(TEST_RESULT_DIR, TEST_SIM_NAME),
        joinpath(TEST_RESULT_DIR, TEST_DUPLICATE_RESULTS_NAME),
    )
end

function teardown_duplicate_results()
    rm(joinpath(TEST_RESULT_DIR, TEST_DUPLICATE_RESULTS_NAME);
        force = true, recursive = true)
end

@testset "Test create_problem_results_dict" begin
    setup_duplicate_results()
    for (problem, stock_results) in zip(decision_problem_names, stock_decision_results_sets)
        scenario_names = [TEST_SIM_NAME, TEST_DUPLICATE_RESULTS_NAME]
        scenarios = create_problem_results_dict(TEST_RESULT_DIR, problem)
        @test Set(keys(scenarios)) == Set(scenario_names)
        scenarios = create_problem_results_dict(
            TEST_RESULT_DIR,
            problem,
            scenario_names;
            populate_system = true,
        )
        @test Set(keys(scenarios)) == Set(scenario_names)
        # TODO(time-series-recovery): Re-enable once PowerSimulations recovers
        # simulation time series from recorded time-series parameters. PSI 0.34 no
        # longer serializes the system's time series, so a `populate_system = true`
        # system has 0 time series vs the stock system's, and `compare_values`
        # fails on the empty time-series store. Design parked in PowerSimulations:
        # docs/superpowers/specs/2026-05-18-results-time-series-recovery-design.md
        # @test IS.compare_values(
        #     get_system(scenarios[TEST_SIM_NAME]),
        #     get_system(stock_results),
        # )
    end
    teardown_duplicate_results()
end

@testset "Test read_component_result" begin
    for res in values(resultses)
        entry = ActivePowerVariable
        comp = get_component(ThermalStandard, get_system(res), "Solitude")
        my_result = PA.read_component_result(res, entry, comp)
        key = PSI.VariableKey(entry, ThermalStandard)
        existing_result = only(
            values(
                PSI.read_results_with_keys(res, [key]; table_format = IS.TableFormat.WIDE),
            ),
        )[
            !,
            ["DateTime", "Solitude"],
        ]
        @test my_result == existing_result
    end
end

@testset "Test read_system_result" begin
    entry = SystemBalanceSlackUp
    my_result = PA.read_system_result(results_ed, entry)
    key = PSI.VariableKey(entry, System)
    existing_result = only(
        values(
            PSI.read_results_with_keys(
                results_ed,
                [key];
                table_format = IS.TableFormat.WIDE,
            ),
        ),
    )
    @test get_time_vec(my_result) == get_time_vec(existing_result)
    @test get_data_vec(my_result) == get_data_vec(existing_result)
end

@testset "Test get_branch_data" begin
    # results_ed runs a PTDF network with StaticBranch lines and in-loop DC power flow,
    # so it carries branch flow variables and/or PowerFlowBranch aux variables.
    branch_data = PA.get_branch_data(results_ed)
    @test branch_data isa PA.PowerData
    @test !isempty(branch_data.data)

    branch_names =
        PSY.get_name.(PSY.get_components(PSY.ACBranch, PSI.get_system(results_ed)))
    for df in values(branch_data.data)
        @test "DateTime" in names(df)
        @test DataFrames.nrow(df) > 0
        mapped = setdiff(names(df), ["DateTime"])
        @test !isempty(mapped)
        @test all(in(branch_names), mapped)
    end

    # results_uc is a CopperPlate model with no branch flows; the result is empty but valid.
    @test PA.get_branch_data(results_uc) isa PA.PowerData
end

@testset "Test get_branch_data with AC power flow in the loop" begin
    # this exercises the aux-variable-only codepath of `get_branch_data`
    sys = PSB.build_system(PSB.PSISystems, "5_bus_hydro_ed_sys")
    template = ProblemTemplate(
        NetworkModel(
            CopperPlatePowerModel;
            use_slacks = true,
            power_flow_evaluation = PSI.PFS.ACPolarPowerFlow(),
        ),
    )
    set_device_model!(template, ThermalStandard, ThermalBasicDispatch)
    set_device_model!(template, PowerLoad, StaticPowerLoad)
    set_device_model!(template, HydroDispatch, FixedOutput)
    set_device_model!(template, HydroTurbine, HydroTurbineEnergyDispatch)
    set_device_model!(template, HydroReservoir, HydroEnergyModelReservoir)

    model = DecisionModel(
        template,
        sys;
        optimizer = optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.01),
        horizon = Hour(2),
    )
    @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
          PSI.ModelBuildStatus.BUILT
    @test solve!(model) == PSI.RunStatus.SUCCESSFULLY_FINALIZED
    ac_results = OptimizationProblemResults(model)

    @test isempty(PA.get_branch_variable_keys(ac_results))
    aux_keys = PA.get_branch_aux_variable_keys(ac_results)
    @test !isempty(aux_keys)
    @test PSI.PowerFlowBranchActivePowerFromTo in PSI.get_entry_type.(aux_keys)

    branch_data = PA.get_branch_data(ac_results)
    @test branch_data isa PA.PowerData
    # NOTE. written to current behavior. Only one aux variable per branch type is kept,
    # so to-from discarded.
    from_to_keys =
        filter(k -> PSI.get_entry_type(k) == PSI.PowerFlowBranchActivePowerFromTo, aux_keys)
    @test Set(keys(branch_data.data)) ==
          Set(Symbol.(PSI.encode_keys_as_strings(from_to_keys)))

    branch_names = PSY.get_name.(PSY.get_components(PSY.ACBranch, sys))
    for df in values(branch_data.data)
        @test "DateTime" in names(df)
        @test DataFrames.nrow(df) > 0
        mapped = setdiff(names(df), ["DateTime"])
        @test !isempty(mapped)
        @test all(in(branch_names), mapped)
    end
end
