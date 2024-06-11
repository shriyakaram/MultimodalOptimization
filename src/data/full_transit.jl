"""
    Calculate route travel time for a passenger and transit route
"""
function compute_transit_route_time(departure_time::Float64, destination::Tuple{Float64, Float64}, transit_route::TransitRoute, 
    transit_stops_line::DataFrame, transit_time_step::Int)

    origin_node = transit_route.origin_node
    destination_node = transit_route.destination_node
    station_boarding_time = origin_node.time
    destination_station = destination_node.station
    station_alight_time = destination_node.time

    pre_boarding_time = station_boarding_time - departure_time
    transit_time = station_alight_time - station_boarding_time

    destination_station_lat_lon = station_lat_lon(destination_station, transit_stops_line)
    destination_walking_time = walking_time_station(destination, destination_station_lat_lon, transit_time_step)

    total_time = pre_boarding_time + transit_time + destination_walking_time
    return total_time
end

"""
    Find stations within a maximum walking time threshold for a passenger (origin)
"""
function find_origin_stations(max_walking_time::Int, origin::Tuple{Float64, Float64}, transit_stops_line::DataFrame,
    transit_time_step::Int)

    stations_list = Int[]
    for row in eachrow(transit_stops_line)
        station_location = station_lat_lon(row.stop_sequence, transit_stops_line)
        walking_time = walking_time_station(origin, station_location, transit_time_step)
        if walking_time <= max_walking_time
            push!(stations_list, row.stop_sequence)
        end
    end
    return stations_list
end

"""
    Find stations within a maximum walking time threshold for a passenger (destination)
"""
function find_destination_stations(max_walking_time::Int, destination::Tuple{Float64, Float64}, transit_stops_line::DataFrame,
    transit_time_step::Int)
    stations_list = Int[]
    for row in eachrow(transit_stops_line)
        station_location = station_lat_lon(row.stop_sequence, transit_stops_line)
        walking_time = walking_time_station(destination, station_location, transit_time_step)
        if walking_time <= max_walking_time
            push!(stations_list, row.stop_sequence)
        end
    end
    return stations_list
end

"""
    Check if a transit node is accessible to a passenger (origin)
"""
function check_origin_node(origin_node::TransitNode, origin::Tuple{Float64, Float64}, departure_time::Float64, transit_stops_line::DataFrame,
    transit_time_step::Int)
    origin_station = origin_node.station
    station_boarding_time = origin_node.time
    station_location = station_lat_lon(origin_station, transit_stops_line)
    walking_time = walking_time_station(origin, station_location, transit_time_step)
    if (departure_time + walking_time) <= station_boarding_time
        return true
    else
        return false
    end
end

"""
    Find transit origin nodes accessible to a passenger (origin)
"""
function find_origin_nodes(max_walking_time::Int, line_frequency::LineFrequency, origin::Tuple{Float64, Float64}, 
    departure_time::Float64, transit_stops_line::DataFrame, transit_time_step::Int)
    origin_nodes = TransitNode[]
    transit_nodes = line_frequency.transit_nodes
    origin_station_list = find_origin_stations(max_walking_time, origin, transit_stops_line, transit_time_step)
    filtered_nodes = filter(node -> in(node.station, origin_station_list), transit_nodes)
    for n in filtered_nodes
        if check_origin_node(n, origin, departure_time, transit_stops_line, transit_time_step)
            push!(origin_nodes, n)
        end
    end
    return origin_nodes
end

"""
    Find all transit routes accessible to a passenger for a particular line/frequency
"""
function find_routes(max_walking_time::Int, line_frequency::LineFrequency, origin::Tuple{Float64, Float64}, 
    destination::Tuple{Float64, Float64}, departure_time::Float64, transit_stops_line::DataFrame, transit_time_step::Int)
    
    origin_nodes = find_origin_nodes(max_walking_time, line_frequency, origin, departure_time, transit_stops_line, transit_time_step)
    destination_stations = find_destination_stations(max_walking_time, destination, transit_stops_line, transit_time_step)
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
    For a passenger origin, destination, and departure time, create a vector of all PassengerTransitRoute objects
"""
function create_passenger_transit_routes(passenger_id::Int, max_walking_time::Int, line_frequency_list::Vector{LineFrequency}, 
    origin::Tuple{Float64, Float64}, destination::Tuple{Float64, Float64}, departure_time::Float64, transit_stops::DataFrame,
    transit_time_step::Int)

    passenger_transit_routes = PassengerTransitRoute[]
    routes_cost = Int[]

    for line_frequency in line_frequency_list
        line = line_frequency.line
        frequency = line_frequency.frequency
        transit_stops_line = filter(row -> row.line == line, transit_stops)
        routes = find_routes(max_walking_time, line_frequency, origin, destination, departure_time, transit_stops_line, transit_time_step)
        
        if !isempty(routes)
            routes_cost = [compute_transit_route_time(departure_time, destination, r, transit_stops_line, transit_time_step) for r in routes]
            ptr = PassengerTransitRoute(passenger_id, line, frequency, routes, routes_cost)
            push!(passenger_transit_routes, ptr)
        end
    end
    return passenger_transit_routes
end

"""
    Post calculate route travel time for a passenger and transit route
"""
function compute_full_transit_route_time(passenger::Passenger, transit_route::TransitRoute, line::Int, transit_stops::DataFrame)
    departure_time = passenger.departure_time
    destination = passenger.destination
    origin = passenger.origin
    transit_stops_line = filter(row -> row.line == line, transit_stops)
    
    origin_node = transit_route.origin_node
    destination_node = transit_route.destination_node
    origin_station = origin_node.station
    station_boarding_time = origin_node.time
    destination_station = destination_node.station
    station_alight_time = destination_node.time

    destination_station_lat_lon = station_lat_lon(destination_station, transit_stops_line)
    origin_station_lat_lon = station_lat_lon(origin_station, transit_stops_line)
    destination_walking_time = walking_time_station(destination, destination_station_lat_lon, transit_time_step)
    origin_walking_time = walking_time_station(origin, origin_station_lat_lon, transit_time_step)
    walking = origin_walking_time + destination_walking_time

    waiting = station_boarding_time - (departure_time + origin_walking_time)
    in_vehicle = station_alight_time - station_boarding_time

    return walking, waiting, in_vehicle
end