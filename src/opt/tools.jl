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
    Return the unique lines
"""
function line_frequency_pairs(line_frequencies::Vector{LineFrequency})
    lines = Int[]

    for line_freq in line_frequencies
        push!(lines, line_freq.line)
    end
    return unique(sort(lines))
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
    Return the list of stations for a line 
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
    Return the transit routes accessible to passenger p and line l
"""
function routes_passenger(p::Int, l::Int, data::OnDemandTransitData)
    return [ptr.transit_routes for ptr in data.passengers[p].passenger_transit_routes if ptr.line == l][1]
end

"""
    Return the cost of transit route r for passenger p, line l, and frequency f
"""
function route_cost_passenger(p::Int, l::Int, r::TransitRoute, data::OnDemandTransitData)
    routes = routes_passenger(p, l, data)
    index = findfirst(x -> x == r, routes)
    travel_times = [ptr.travel_time for ptr in data.passengers[p].passenger_transit_routes if ptr.line == l][1]
    return travel_times[index]
end

"""
    Return the lines accessible to passenger p (feeder)
"""
function lines_passenger_feeder(p::Int, data::OnDemandTransitData)
    return unique([pfr.line for pfr in data.passengers[p].passenger_feeder_routes])
end

"""
    Return the transit routes accessible to passenger p, line l, and frequency f (feeder)
"""
function routes_passenger_feeder(p::Int, l::Int, data::OnDemandTransitData)
    return [pfr.transit_routes for pfr in data.passengers[p].passenger_feeder_routes if pfr.line == l][1]
end

"""
    Return the cost of transit route r for passenger p, line l, and frequency f (feeder)
"""
function route_cost_passenger_feeder(p::Int, l::Int, r::TransitRoute, data::OnDemandTransitData)
    routes = routes_passenger_feeder(p, l, data)
    index = findfirst(x -> x == r, routes)
    travel_times = [pfr.travel_time for pfr in data.passengers[p].passenger_feeder_routes if pfr.line == l][1]
    return travel_times[index]
end

"""
    Return outgoing nodes for a (station, time) pair for a passenger ID and line, frequency 
"""
function outgoing_transit_nodes(p::Int, l::Int, s::Int, t::Float64, data::OnDemandTransitData)
    transit_routes = routes_passenger_feeder(p, l, data)
    return [tr for tr in transit_routes if (tr.origin_node.station == s) && (tr.origin_node.time == t)]
end

"""
    Return incoming nodes for a (station, time) pair for a passenger ID and line, frequency
"""
function incoming_transit_nodes(p::Int, l::Int, s::Int, t::Float64, data::OnDemandTransitData)
    transit_routes = routes_passenger_feeder(p, l, data)
    return [tr for tr in transit_routes if (tr.destination_node.station == s) && (tr.destination_node.time == t)]
end

"""
    Check whether route operates at time t in zone i
"""
function check_time_zone_route(time::Float64, zone_id::Int, route::Union{PickupRoute, DropoffRoute, OnDRoute})
    zone = route.zone
    start_time = route.start_time
    end_time = route.end_time
    if (time >= start_time) && (time < end_time) && (zone == zone_id)
        return 1
    else
        return 0
    end
end