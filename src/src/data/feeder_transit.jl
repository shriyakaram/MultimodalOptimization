"""
    Calculate route travel time for a passenger and transit route for multimodal
"""
function compute_feeder_route_time(transit_route::TransitRoute)
    origin_node = transit_route.origin_node
    destination_node = transit_route.destination_node
    station_boarding_time = origin_node.time
    station_alight_time = destination_node.time
    transit_time = station_alight_time - station_boarding_time
    return transit_time
end

"""
    Find stations within the same origin zone for a passenger
"""
function find_origin_stations_feeder(origin_zone::Int, transit_stops_line::DataFrame)
    filtered_df = transit_stops_line[transit_stops_line.zone_id .== origin_zone, :]
    origin_stations = filtered_df.stop_sequence
    return origin_stations
end

"""
    Find stations within the same origin zone for a passenger
"""
function find_destination_stations_feeder(destination_zone::Int, transit_stops_line::DataFrame)
    filtered_df = transit_stops_line[transit_stops_line.zone_id .== destination_zone, :]
    destination_stations = filtered_df.stop_sequence
    return destination_stations
end

"""
    Check if a transit node is accessible to a passenger (feeder)
"""
function check_origin_node_feeder(origin_node::TransitNode, origin::Tuple{Float64, Float64}, departure_time::Float64, 
    transit_stops_line::DataFrame, transit_time_step::Int)
    origin_station = origin_node.station
    station_boarding_time = origin_node.time
    station_location = station_lat_lon(origin_station, transit_stops_line)
    driving_time_origin_station = driving_time(origin, station_location, transit_time_step)
    if (departure_time + driving_time_origin_station) <= station_boarding_time
        return true
    else
        return false
    end
end

"""
    Find transit origin nodes accessible to a passenger (feeder)
"""
function find_origin_nodes_feeder(line_frequency::LineFrequency, origin_zone::Int, origin::Tuple{Float64, Float64}, departure_time::Float64, 
    transit_stops_line::DataFrame, transit_time_step::Int)

    origin_nodes = TransitNode[]
    transit_nodes = line_frequency.transit_nodes
    origin_station_list = find_origin_stations_feeder(origin_zone, transit_stops_line)
    filtered_nodes = filter(node -> in(node.station, origin_station_list), transit_nodes)
    for n in filtered_nodes
        if check_origin_node_feeder(n, origin, departure_time, transit_stops_line, transit_time_step)
            push!(origin_nodes, n)
        end
    end
    return origin_nodes
end

"""
    Find all transit routes accessible to a passenger for a particular line/frequency (feeder)
"""
function find_routes_feeder(line_frequency::LineFrequency, origin_zone::Int, origin::Tuple{Float64, Float64}, 
    destination_zone::Int, departure_time::Float64, transit_stops_line::DataFrame, transit_time_step::Int)

    if isempty(find_origin_stations_feeder(origin_zone, transit_stops_line)) || isempty(find_destination_stations_feeder(destination_zone,
        transit_stops_line))
        return []
    end

    origin_nodes = find_origin_nodes_feeder(line_frequency, origin_zone, origin, departure_time, transit_stops_line, transit_time_step)
    destination_stations = find_destination_stations_feeder(destination_zone, transit_stops_line)
    routes = TransitRoute[]
    transit_nodes = line_frequency.transit_nodes
    filtered_nodes = filter(node -> in(node.station, destination_stations), transit_nodes)

    for n1 in origin_nodes
        for n2 in filtered_nodes
            if n2.station > n1.station
                this_time = n2.time - n1.time
                if (this_time > 0) && (abs(station_travel_time(n1.station, n2.station, transit_stops_line) - this_time) < eps(Float16))
                    push!(routes, TransitRoute(n1, n2))
                end
            end
        end
    end
    return routes
end

"""
    For a passenger origin, destination, and departure time, create a vector of all PassengerTransitRoute objects (feeder)
"""
function create_passenger_transit_routes_feeder(passenger_id::Int, line_frequency_list::Vector{LineFrequency}, 
    origin::Tuple{Float64, Float64}, origin_zone::Int, destination_zone::Int, departure_time::Float64, transit_stops::DataFrame,
    transit_time_step::Int)

    passenger_feeder_routes = PassengerTransitRoute[]
    routes_cost = Int[]

    for line_frequency in line_frequency_list
        line = line_frequency.line
        frequency = line_frequency.frequency
        transit_stops_line = filter(row -> row.line == line, transit_stops)
        routes = find_routes_feeder(line_frequency, origin_zone, origin, destination_zone, departure_time, transit_stops_line, 
            transit_time_step)

        if !isempty(routes)
            routes_cost = [compute_feeder_route_time(r) for r in routes]
            ptr = PassengerTransitRoute(passenger_id, line, frequency, routes, routes_cost)
            push!(passenger_feeder_routes, ptr)
        end
    end
    return passenger_feeder_routes
end
