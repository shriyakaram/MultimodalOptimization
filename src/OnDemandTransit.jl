module OnDemandTransit

using DataFrames, CSV
using JuMP, Gurobi
using Distances
using Combinatorics
using PyCall
using Printf
using LinearAlgebra
using Statistics
using Parameters

include("data/struct.jl")
include("data/load.jl")
include("data/on_demand_tools.jl")
include("data/pickup_routes.jl")
include("data/dropoff_routes.jl")
include("data/od_routes.jl")
include("data/transit_tools.jl")
include("data/full_transit.jl")
include("data/feeder_transit.jl")

include("opt/tools.jl")
include("opt/variables.jl")
include("opt/objective.jl")
include("opt/constraints.jl")
include("opt/optimize.jl")

include("output/output.jl")



end