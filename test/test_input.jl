# Parked for the psy6 port. Calls PA's own `read_system_output` and
# `create_problem_outputs_dict`, neither of which exists in PA — re-home once PA grows
# those, against a rebuilt single-`DecisionModel` fixture.

stock_decision_outputs_sets = run_test_sim(TEST_OUTPUT_DIR, TEST_SIM_NAME)
stock_outputs_prob = run_test_prob()

sim_outputs = SimulationOutputs(TEST_OUTPUT_DIR, TEST_SIM_NAME)
decision_problem_names = ("UC", "ED")
my_outputs_sets = get_decision_problem_outputs.(Ref(sim_outputs), decision_problem_names)

(outputs_uc, outputs_ed) = stock_decision_outputs_sets
outputs_by_name = Dict("UC" => outputs_uc, "ED" => outputs_ed, "prob" => stock_outputs_prob)

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

# Create another outputs directory
function setup_duplicate_outputs()
    teardown_duplicate_outputs()
    cptree(
        joinpath(TEST_OUTPUT_DIR, TEST_SIM_NAME),
        joinpath(TEST_OUTPUT_DIR, TEST_DUPLICATE_OUTPUTS_NAME),
    )
end

function teardown_duplicate_outputs()
    rm(joinpath(TEST_OUTPUT_DIR, TEST_DUPLICATE_OUTPUTS_NAME);
        force = true, recursive = true)
end

@testset "Test create_problem_outputs_dict" begin
    setup_duplicate_outputs()
    for (problem, stock_outputs) in zip(decision_problem_names, stock_decision_outputs_sets)
        scenario_names = [TEST_SIM_NAME, TEST_DUPLICATE_OUTPUTS_NAME]
        scenarios = create_problem_outputs_dict(TEST_OUTPUT_DIR, problem)
        @test Set(keys(scenarios)) == Set(scenario_names)
        scenarios = create_problem_outputs_dict(
            TEST_OUTPUT_DIR,
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
        #     get_system(stock_outputs),
        # )
    end
    teardown_duplicate_outputs()
end

@testset "Test read_component_output" begin
    for output in values(outputs_by_name)
        entry = ActivePowerVariable
        comp = get_component(ThermalStandard, get_system(output), "Solitude")
        my_result = PA.read_component_output(output, entry, comp)
        key = PSI.VariableKey(entry, ThermalStandard)
        existing_result = only(
            values(
                IOM.read_outputs_with_keys(
                    output,
                    [key];
                    table_format = IS.TableFormat.WIDE,
                ),
            ),
        )[
            !,
            ["DateTime", "Solitude"],
        ]
        @test my_result == existing_result
    end
end

@testset "Test read_system_output" begin
    entry = SystemBalanceSlackUp
    my_result = PA.read_system_output(outputs_ed, entry)
    key = PSI.VariableKey(entry, System)
    existing_result = only(
        values(
            IOM.read_outputs_with_keys(
                outputs_ed,
                [key];
                table_format = IS.TableFormat.WIDE,
            ),
        ),
    )
    @test get_time_vec(my_result) == get_time_vec(existing_result)
    @test get_data_vec(my_result) == get_data_vec(existing_result)
end

@testset "Test get_branch_data" begin
    # outputs_ed runs a PTDF network with StaticBranch lines and in-loop DC power flow,
    # so it carries branch flow variables and/or PowerFlowBranch aux variables.
    branch_data = PA.get_branch_data(outputs_ed)
    @test branch_data isa PA.PowerData
    @test !isempty(branch_data.data)

    branch_names =
        PSY.get_name.(PSY.get_components(PSY.ACBranch, PSI.get_system(outputs_ed)))
    for df in values(branch_data.data)
        @test "DateTime" in names(df)
        @test DataFrames.nrow(df) > 0
        mapped = setdiff(names(df), ["DateTime"])
        @test !isempty(mapped)
        @test all(in(branch_names), mapped)
    end

    # outputs_uc is a CopperPlate model with no branch flows; the result is empty but valid.
    @test PA.get_branch_data(outputs_uc) isa PA.PowerData
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
    ac_outputs = IOM.OptimizationProblemOutputs(model)

    @test isempty(PA.get_branch_variable_keys(ac_outputs))
    aux_keys = PA.get_branch_aux_variable_keys(ac_outputs)
    @test !isempty(aux_keys)
    @test PSI.PowerFlowBranchActivePowerFromTo in PSI.get_entry_type.(aux_keys)

    branch_data = PA.get_branch_data(ac_outputs)
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
