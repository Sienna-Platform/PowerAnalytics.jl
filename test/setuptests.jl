using Test
using TestSetExtensions
using Logging
using Dates
using DataFrames
using DataStructures
import InfrastructureSystems
import InfrastructureSystems: Deterministic, Probabilistic, Scenarios, Forecast
using PowerSystems
using PowerAnalytics
using PowerAnalytics.Selectors
using PowerAnalytics.Metrics
using HiGHS
using TimeSeries
import InfrastructureOptimizationModels

const PA = PowerAnalytics
const IS = InfrastructureSystems
const PSY = PowerSystems
const IOM = InfrastructureOptimizationModels
const LOG_FILE = "PowerAnalytics-test.log"

const BASE_DIR = dirname(dirname(pathof(PowerAnalytics)))
const TEST_DIR = joinpath(BASE_DIR, "test")
# Cache the test outputs, no need to regenerate every time we test
const TEST_OUTPUTS = joinpath(BASE_DIR, "test", "test_outputs")
!isdir(TEST_OUTPUTS) && mkdir(TEST_OUTPUTS)
const TEST_OUTPUT_DIR = joinpath(TEST_OUTPUTS, "outputs")
!isdir(TEST_OUTPUT_DIR) && mkdir(TEST_OUTPUT_DIR)
const TEST_SIM_NAME = "outputs_sim"
const TEST_DUPLICATE_OUTPUTS_NAME = "temp_duplicate_outputs"

import PowerSystemCaseBuilder
const PSB = PowerSystemCaseBuilder

# Depend on the PSI Simulation fixture in test/test_data/outputs_data.jl, which psy6 has
# no equivalent for. Parked pending a rebuilt fixture.
const DISABLED_TEST_FILES = [  # Can generate with ls -1 test | grep "test_.*.jl"
    "test_builtin_metrics.jl",
    "test_input.jl",
    "test_metrics.jl",
    "test_result_sorting.jl",
]

LOG_LEVELS = Dict(
    "Debug" => Logging.Debug,
    "Info" => Logging.Info,
    "Warn" => Logging.Warn,
    "Error" => Logging.Error,
)
