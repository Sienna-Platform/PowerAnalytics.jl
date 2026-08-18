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
const TEST_OUTPUTS = joinpath(BASE_DIR, "test", "test_results")
!isdir(TEST_OUTPUTS) && mkdir(TEST_OUTPUTS)
const TEST_RESULT_DIR = joinpath(TEST_OUTPUTS, "results")
!isdir(TEST_RESULT_DIR) && mkdir(TEST_RESULT_DIR)
const TEST_SIM_NAME = "results_sim"
const TEST_DUPLICATE_RESULTS_NAME = "temp_duplicate_results"

import PowerSystemCaseBuilder
const PSB = PowerSystemCaseBuilder

# Depend on the PSI Simulation fixture in test/test_data/results_data.jl, which psy6 has
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
