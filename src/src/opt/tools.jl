"""
    Return a list of the unique zone IDs
"""
function zone_id_list(data::OnDemandTransitData)
    zones = Int[]
    for i in data.zone_pairs
        (origin_zone, destination_zone) = i
        push!(zones, origin_zone)
        push!(zones, destination_zone)
    end
    return unique(zones)
end

"""
    Return the unique line, frequency pairs
"""
function line_frequency_pairs(line_frequencies::Vector{LineFrequency})
    lines = Int[]
    frequencies = Int[]

    for line_freq in line_frequencies
        push!(lines, line_freq.line)
        push!(frequencies, line_freq.frequency)
    end
    return unique(sort(lines)), unique(sort(frequencies))
end

"""
    Return the vector of start times for a line l and frequency f
"""
function line_frequency_start_times(l::Int, f::Int, data::OnDemandTransitData)
    start_times = [lf.start_times for lf in data.line_frequencies if lf.line == l && lf.frequency == f][1]
    return start_times
end

"""
    Return the vector of end times for a line l and frequency f
"""
function line_frequency_end_times(l::Int, f::Int, data::OnDemandTransitData)
    end_times = [lf.end_times for lf in data.line_frequencies if lf.line == l && lf.frequency == f][1]
    return end_times
end

"""
    Find the number of passengers for a passenger_id in an od route
"""
function num_passengers_type_od(passenger_id::Int, ondemand_route::OnDRoute)
    origin_order = ondemand_route.origin_order
    num_passenger_dict = ondemand_route.num_passenger_dict
    if passenger_id in origin_order
        num_passenger = num_passenger_dict[passenger_id]
        return num_passenger
    else
        return 0
    end
end

"""
    Find the number of passengers for a passenger_id in a pick-up route
"""
function num_passengers_type_route(passenger_id::Int, route::Union{PickupRoute, DropoffRoute})
    passenger_order = route.passenger_order
    num_passenger_dict = route.num_passenger_dict
    if passenger_id in passenger_order
        num_passenger = num_passenger_dict[passenger_id]
        return num_passenger
    else
        return 0
    end
end

"""
    Return the list of stations for a line index 
"""
function line_stations(l::Int, data::OnDemandTransitData)
    line_station_ids = [lf.stations_ids for lf in data.line_frequencies if lf.line == l][1]
    return line_station_ids
end

"""
    Return the lines accessible to passenger p
"""
function lines_passenger(p::Int, data::OnDemandTransitData)
    return unique([ptr.line for ptr in data.passengers[p].passenger_transit_routes])
end

"""
    Return the frequencies accessible to passenger p and line l
"""
function freq_passenger(p::Int, l::Int, data::OnDemandTransitData)
    return unique([ptr.frequency for ptr in data.passengers[p].passenger_transit_routes if (ptr.line == l)])
end

"""
    Return the transit routes accessible to passenger p, line l, and frequency f
"""
function routes_passenger(p::Int, l::Int, f::Int, data::OnDemandTransitData)
    return [ptr.transit_routes for ptr in data.passengers[p].passenger_transit_routes if (ptr.line == l) && (ptr.frequency == f)][1]
end

"""
    Return the cost of transit route r for passenger p, line l, and frequency f
"""
function route_cost_passenger(p::Int, l::Int, f::Int, r::TransitRoute, data::OnDemandTransitData)
    routes = routes_passenger(p, l, f, data)
    index = findfirst(x -> x == r, routes)
    travel_times = [ptr.travel_time for ptr in data.passengers[p].passenger_transit_routes if (ptr.line == l) && (ptr.frequency == f)][1]
    return travel_times[index]
end

"""
    Return the lines accessible to passenger p (feeder)
"""
function lines_passenger_feeder(p::Int, data::OnDemandTransitData)
    return unique([pfr.line for pfr in data.passengers[p].passenger_feeder_routes])
end

"""
    Return the frequencies accessible to passenger p and line l (feeder)
"""
function freq_passenger_feeder(p::Int, l::Int, data::OnDemandTransitData)
    return unique([pfr.frequency for pfr in data.passengers[p].passenger_feeder_routes if (pfr.line == l)])
end

"""
    Return the transit routes accessible to passenger p, line l, and frequency f (feeder)
"""
function routes_passenger_feeder(p::Int, l::Int, f::Int, data::OnDemandTransitData)
    return [pfr.transit_routes for pfr in data.passengers[p].passenger_feeder_routes if (pfr.line == l) && (pfr.frequency == f)][1]
end

"""
    Return the cost of transit route r for passenger p, line l, and frequency f (feeder)
"""
function route_cost_passenger_feeder(p::Int, l::Int, f::Int, r::TransitRoute, data::OnDemandTransitData)
    routes = routes_passenger_feeder(p, l, f, data)
    index = findfirst(x -> x == r, routes)
    travel_times = [pfr.travel_time for pfr in data.passengers[p].passenger_feeder_routes if (pfr.line == l) && (pfr.frequency == f)][1]
    return travel_times[index]
end

"""
    Return outgoing nodes for a (station, time) pair for a passenger ID and line, frequency 
"""
function outgoing_transit_nodes(p::Int, l::Int, f::Int, s::Int, t::Float64, data::OnDemandTransitData)
    transit_routes = routes_passenger_feeder(p, l, f, data)
    return [tr for tr in transit_routes if (tr.origin_node.station == s) && (tr.origin_node.time == t)]
end

"""
    Return incoming nodes for a (station, time) pair for a passenger ID and line, frequency
"""
function incoming_transit_nodes(p::Int, l::Int, f::Int, s::Int, t::Float64, data::OnDemandTransitData)
    transit_routes = routes_passenger_feeder(p, l, f, data)
    return [tr for tr in transit_routes if (tr.destination_node.station == s) && (tr.destination_node.time == t)]
end

"""
    Check whether route operates at time t in zone i
"""
function check_time_zone_route(time::Float64, zone_id::Int, route::Union{PickupRoute, DropoffRoute, OnDRoute})
    time_zone_dict = route.time_zone_dict
    if time_zone_dict[Int(time)] == zone_id
        return 1
    else
        return 0
    end
end

"""
    Return 1 if od route enters zone i at time t
"""
function od_route_enter(time::Float64, zone_id::Int, route::OnDRoute, on_demand_time_step::Int)
    time_zone_dict = route.time_zone_dict
    if (time_zone_dict[Int(time)] == zone_id) && (time_zone_dict[Int(time)-on_demand_time_step] != zone_id)
        return 1
    else
        return 0
    end
end

"""
    Return 1 if od route exits zone i at time t
"""
function od_route_exit(time::Float64, zone_id::Int, route::OnDRoute, on_demand_time_step::Int)
    time_zone_dict = route.time_zone_dict
    if (time_zone_dict[Int(time)] != zone_id) && (time_zone_dict[Int(time)-on_demand_time_step] == zone_id)
        return 1
    else
        return 0
    end
end
