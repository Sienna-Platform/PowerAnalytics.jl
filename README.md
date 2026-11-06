# PowerAnalytics.jl

| **Documentation** | **Build Status** |
|:---:|:---:|
| [![][docs-sienna-img]][docs-sienna-url] [![][docs-stable-img]][docs-stable-url] [![][docs-dev-img]][docs-dev-url] | [![main - CI](https://github.com/Sienna-Platform/PowerAnalytics.jl/actions/workflows/main-tests.yml/badge.svg)](https://github.com/Sienna-Platform/PowerAnalytics.jl/actions/workflows/main-tests.yml) [![codecov](https://codecov.io/gh/Sienna-Platform/PowerAnalytics.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/Sienna-Platform/PowerAnalytics.jl) [<img src="https://img.shields.io/badge/slack-@Sienna/PG-sienna.svg?logo=slack">](https://join.slack.com/t/core-sienna/shared_invite/zt-glam9vdu-o8A9TwZTZqqNTKHa7q3BpQ) [![PowerAnalytics Downloads](https://shields.io/endpoint?url=https://pkgs.genieframework.com/api/v1/badge/PowerAnalytics)](https://pkgs.genieframework.com?packages=PowerAnalytics) |

[docs-sienna-img]: https://img.shields.io/badge/Central_Sienna_docs-blue.svg
[docs-sienna-url]: https://sienna-platform.github.io/Sienna/SiennaDocs/docs/build/index/
[docs-stable-img]: https://img.shields.io/badge/docs-stable-blue.svg
[docs-stable-url]: https://sienna-platform.github.io/PowerAnalytics.jl/stable/
[docs-dev-img]: https://img.shields.io/badge/docs-dev-blue.svg
[docs-dev-url]: https://sienna-platform.github.io/PowerAnalytics.jl/dev/

PowerAnalytics.jl is a Julia package that contains analytic routines for power system simulation results in the Sienna ecosystem, specifically from [PowerSimulations.jl](https://github.com/Sienna-Platform/PowerSimulations.jl).

## Installation

```julia
julia> ]
pkg> add PowerAnalytics
```

## Usage

`PowerAnalytics.jl` uses [PowerSystems.jl](https://github.com/Sienna-Platform/PowerSystems.jl) and [PowerSimulations.jl](https://github.com/Sienna-Platform/PowerSimulations.jl) to handle the data structures related to and execution of power system simulations.

```julia
using PowerAnalytics
using PowerSystems
# where "res" is a PowerSimulations.SimulationResults object
renewable_generation = calc_active_power(make_selector(RenewableGen), res)
```

## Development

Contributions to the development and enhancement of PowerAnalytics is welcome. Please see [CONTRIBUTING.md](https://github.com/Sienna-Platform/PowerAnalytics.jl/blob/main/CONTRIBUTING.md) for code contribution guidelines.

## License

PowerAnalytics is released under a BSD [license](https://github.com/Sienna-Platform/PowerAnalytics.jl/blob/main/LICENSE). PowerAnalytics has been developed as part of the Scalable Integrated Infrastructure Planning (SIIP)
initiative at the U.S. Department of Energy's National Laboratory of the Rockies ([NLR](https://www.nlr.gov/), formerly NREL)
