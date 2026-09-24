# PowerAnalytics.jl

## Overview

PowerAnalytics.jl is a Julia package designed to support power system simulation outputs analysis. It relies on outputs generated from [`PowerSimulations.jl`](https://sienna-platform.github.io/PowerSimulations.jl/stable/) and data structures defined in [`PowerSystems.jl`](https://sienna-platform.github.io/PowerSystems.jl/stable/). PowerAnalytics also provides the data collection, aggregation, and subsetting for [`PowerGraphics.jl`](https://sienna-platform.github.io/PowerGraphics.jl/stable/).

The tutorial, how-to, and explanation sections of the documentation are still under construction; the most informative section is the [public API reference](reference/public.md). PowerAnalytics depends heavily on the `ComponentSelector` feature of PowerSystems.jl, documented [here](https://sienna-platform.github.io/PowerSystems.jl/stable/api/public/#InfrastructureSystems.ComponentSelector).

## Installation

The latest stable release of PowerAnalytics can be installed using the Julia package manager with

```julia
] add PowerAnalytics
```

!!! note
    
    The latest stable release of `PowerAnalytics.jl` supports the `PowerSystems.jl` 5.0
    ecosystem, except that all output processing is done in wide format rather than long
    format, which precludes support for greater than two dimensional outputs. For now,
    greater than two dimensional outputs must be processed manually; we are working to add
    support for these in a future release.

## About Sienna

`PowerAnalytics.jl` is part of the National Laboratory of the Rockies'
[Sienna ecosystem](https://sienna-platform.github.io/Sienna/), an open source framework for
power system modeling, simulation, and optimization. The Sienna ecosystem can be
[found on GitHub](https://github.com/Sienna-Platform/Sienna). It contains three applications:

  - [Sienna\Data](https://sienna-platform.github.io/Sienna/pages/applications/sienna_data.html) enables
    efficient data input, analysis, and transformation
  - [Sienna\Ops](https://sienna-platform.github.io/Sienna/pages/applications/sienna_ops.html) enables
    enables system scheduling simulations by formulating and solving optimization problems
  - [Sienna\Dyn](https://sienna-platform.github.io/Sienna/pages/applications/sienna_dyn.html) enables
    system transient analysis including small signal stability and full system dynamic
    simulations

Each application uses multiple packages written in the [`Julia`](http://www.julialang.org)
programming language.
