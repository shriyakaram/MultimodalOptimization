"On-demand route"
mutable struct OnDRoute
	"Number of passenger types on the route"
	num_passenger_types::Int
	"Ordered list of (origin) passenger IDs that will be visited on the route"
	origin_order::Vector{Int}
	"Ordered list of (destination) passenger IDs that will be visited on the route"
	destination_order::Vector{Int}
	"Passenger ID => number of passengers on the route"
	num_passenger_dict::Dict{Int, Int}
	"Ordered list of (origin) travel times between passengers, includes last origin to first dest."
	origin_passenger_travel_times::Vector{Float64}
	"Ordered list of (destination) travel times between passengers"
	destination_passenger_travel_times::Vector{Float64}
	"Ordered list of waiting times for each passenger"
	passenger_waiting_times::Vector{Float64}
	"Passenger cost of the route"
	passenger_cost::Float64
	"Route start time"
	start_time::Float64
	"Route end time"
	end_time::Float64
	"Time zone dictionary"
	time_zone_dict::Dict{Int, Int}
end

"Pick-up route"
mutable struct PickupRoute
	"Number of passenger types on the route"
	num_passenger_types::Int
	"Ordered list of passenger IDs that will be visited on the route"
	passenger_order::Vector{Int}
	"Passenger ID => number of passengers on the route"
	num_passenger_dict::Dict{Int, Int}
	"Ordered list of travel times between passengers"
	passenger_travel_times::Vector{Float64}
	"Ordered list of waiting times for each passenger"
	passenger_waiting_times::Vector{Float64}
	"Passenger cost of the route"
	passenger_cost::Float64
	"Route start time"
	start_time::Float64
	"Route end time"
	end_time::Float64
	"Transit station"
	transit_station::Int
	"Transit line"
	line::Int
	"Zone"
	zone::Int
end

"Drop-off route"
mutable struct DropoffRoute
	"Number of passenger types on the route"
	num_passenger_types::Int
	"Ordered list of passenger IDs that will be visited on the route"
	passenger_order::Vector{Int}
	"Passenger ID => number of passengers on the route"
	num_passenger_dict::Dict{Int, Int}
	"Ordered list of travel times between passengers"
	passenger_travel_times::Vector{Float64}
	"Passenger cost of the route"
	passenger_cost::Float64
	"Route start time"
	start_time::Float64
	"Route end time"
	end_time::Float64
	"Transit station"
	transit_station::Int
	"Transit line"
	line::Int
	"Zone"
	zone::Int
end

"Transit node (station, time) pair"
mutable struct TransitNode
	"Station"
	station::Int
	"Departure time"
	time::Float64
end

"Transit route (origin node, destination node) pair"
mutable struct TransitRoute
	"Origin transit node"
	origin_node::TransitNode
	"Destination transit node"
	destination_node::TransitNode
end

"Line/frequency pair"
mutable struct LineFrequency
	"List of transit (station, time) pairs"
	transit_nodes::Vector{TransitNode}
	"Line"
	line::Int
	"Frequency"
	frequency::Int
	"Line/frequency start times"
	start_times::Vector{Float64}
	"Line/frequency end times"
	end_times::Vector{Float64}
	"Station IDs for line"
	stations_ids::Vector{Int}
end

"Transit routes for a passenger"
mutable struct PassengerTransitRoute
	"Passenger ID"
	passenger_id::Int
	"Line"
	line::Int
	"Frequency"
	frequency::Int
	"List of transit routes"
	transit_routes::Vector{TransitRoute}
	"Travel time"
	travel_time::Vector{Float64}
end

"Passenger type"
mutable struct Passenger
	"Passenger ID"
	passenger_id::Int
	"List of passenger transit routes for the passenger"
	passenger_transit_routes::Vector{PassengerTransitRoute}
	"List of passenger feeder routes for the passenger"
	passenger_feeder_routes::Vector{PassengerTransitRoute}
	"Passenger type origin (lat/lon)"
	origin::Tuple{Float64, Float64}
	"Passenger type destination (lat/lon)"
	destination::Tuple{Float64, Float64}
	"Origin zone"
	origin_zone::Int
	"Destination zone"
	destination_zone::Int
	"Passenger type departure time"
	departure_time::Float64
	"Passenger type demand"
	demand::Int
end

"On-demand/transit data structure"
mutable struct OnDemandTransitData
	"Passengers"
	passengers::Vector{Passenger}
	"On demand routes"
	OnD_routes::Vector{OnDRoute}
	"Pick up routes"
	pickup_routes::Vector{PickupRoute}
	"Drop off routes"
	dropoff_routes::Vector{DropoffRoute}
	"All line frequencies"
	line_frequencies::Vector{LineFrequency}
	"All zone pairs"
	zone_pairs::Vector{Tuple{Int, Int}}
end

"""
	Stores parameters (cannot be changed without redo-ing the pre-processing)
"""
@with_kw struct PermanentParameters
    "Maximum walking time"
    max_walking_time::Int
    "Vehicle capacity"
    kappa::Int
    "Time horizon"
    time_horizon::Float64
    "Frequency set"
    frequency_set::Vector{Int} 
    "Maximum on-demand route time"
    max_on_demand_time::Int
    "Maximum first waiting time"
    max_first_waiting_time::Float64
    "On-demand time step"
    on_demand_time_step::Int
    "Transit time step"
    transit_time_step::Int
	"Maximum waiting time"
    max_waiting::Int
end

"""
	Stores the model object after optimization
"""
mutable struct OnDemandTransitModel
	"Optimized model"
	model::JuMP.Model
	"Data"
	data::OnDemandTransitData
	"Permanent parameters"
	pp::PermanentParameters
	"Fleet size"
    F::Int
end