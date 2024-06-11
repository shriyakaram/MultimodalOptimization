
"""
    Create the vector of on-demand routes 
    Implemented for kappa = 4  
"""
function create_od_routes(kappa::Int, max_on_demand_time::Int, max_first_waiting_time::Float64, ond_locations_data::DataFrame,
    time_horizon::Float64, on_demand_time_step::Int)

    passenger_ids = ond_locations_data.passenger_id
    passenger_dict = compute_passenger_dict(ond_locations_data, on_demand_time_step)
    routes = OnDRoute[]

    for p in passenger_ids
        route_start_times = calc_route_start_times(max_first_waiting_time, p, ond_locations_data, on_demand_time_step)
        for start_time in route_start_times
            routes = build_1_string(kappa, p, max_on_demand_time, start_time, ond_locations_data, routes, time_horizon, 
                on_demand_time_step)
            if kappa >= 2
                passenger_list = passenger_dict[p]
                for l in passenger_list
                    bool_cost, routes = build_k_route_1(2, max_on_demand_time, start_time, ond_locations_data, [p,l], routes, time_horizon, 
                        on_demand_time_step)
                    if bool_cost && kappa >= 3
                        for q in filter(x -> !(x in Set(l)), passenger_list)
                            bool_cost, routes = build_k_route_1(3, max_on_demand_time, start_time, ond_locations_data, [p,l,q], routes, 
                                time_horizon, on_demand_time_step)
                            if bool_cost && kappa >= 4
                                for w in filter(x -> !(x in [l,q]), passenger_list)
                                    bool_cost, routes = build_k_route_1(4, max_on_demand_time, start_time, ond_locations_data, [p,l,q,w], routes, 
                                        time_horizon, on_demand_time_step)
                                end
                                routes = build_3_string(max_on_demand_time, start_time, ond_locations_data, [p,l,q],
                                    routes, time_horizon, on_demand_time_step)
                            end
                        end
                        routes = build_2_string(kappa, max_on_demand_time, start_time, ond_locations_data, [p,l],
                            routes, time_horizon, on_demand_time_step)
                    end
                end
            end
        end
    end

    return routes
end

"""
    Create pick-up routes for all lines/stations
    Implemented for kappa = 4 
"""
function create_pickup_routes(kappa::Int, max_on_demand_time::Int, max_first_waiting_time::Float64, time_horizon::Float64,
    ond_locations_data::DataFrame, transit_stops::DataFrame, on_demand_time_step::Int)

    routes = PickupRoute[]
    for row in eachrow(transit_stops)
        line = row.line 
        station = row.stop_sequence
        routes = create_pickup_routes_line_station(kappa, max_on_demand_time, max_first_waiting_time, line, station, time_horizon,
            ond_locations_data, transit_stops, routes, on_demand_time_step)
    end

    return routes
end

"""
    Create drop-off routes for all lines/stations
    Implemented for kappa = 4
"""
function create_dropoff_routes(kappa::Int, max_on_demand_time::Int, time_horizon::Float64, ond_locations_data::DataFrame, 
    transit_stops::DataFrame, passengers::Vector{Passenger}, on_demand_time_step::Int, max_waiting::Int)

    routes = DropoffRoute[]
    for row in eachrow(transit_stops)
        line = row.line
        station = row.stop_sequence
        routes = create_dropoff_routes_line_station(kappa, max_on_demand_time, line, station, time_horizon, ond_locations_data, 
            transit_stops, routes, passengers, on_demand_time_step, max_waiting)
    end

    return routes
end

"""
    For the input data, create a list of all line/frequency pairs
"""
function create_line_frequency(frequency_set::Vector{Int}, time_horizon::Float64, transit_stops::DataFrame)
    line_frequency_list = LineFrequency[]
    lines = unique(transit_stops.line)

    for l in lines
        for f in frequency_set
            transit_stops_line = filter(row -> row.line == l, transit_stops)
            f_nodes = frequency_nodes(f, time_horizon, transit_stops_line)
            start_times, end_times = find_start_end_times(transit_stops_line, f_nodes)
            stations_ids = transit_stops_line[!, "stop_sequence"]
            push!(line_frequency_list, LineFrequency(f_nodes, l, f, start_times, end_times, stations_ids))
        end
    end
    return line_frequency_list
end

"""
    For the input data, create a list of all passengers
"""
function create_passengers(ond_locations_data::DataFrame, transit_stops::DataFrame, max_walking_time::Int, 
    line_frequency_list::Vector{LineFrequency}, transit_time_step::Int)

    Passengers = Passenger[]
    for row in eachrow(ond_locations_data)
        passenger_id = row.passenger_id
        origin = (row.origin_lat, row.origin_lon)
        destination = (row.dest_lat, row.dest_lon)
        origin_zone = row.origin_zone
        destination_zone = row.dest_zone
        departure_time = row.departure_time
        demand = row.demand
        transit_routes_passenger = create_passenger_transit_routes(passenger_id, max_walking_time, line_frequency_list, origin, 
            destination, departure_time, transit_stops, transit_time_step)
        feeder_routes_passenger = create_passenger_transit_routes_feeder(passenger_id, line_frequency_list, origin, origin_zone, 
            destination_zone, departure_time, transit_stops, transit_time_step)
        push!(Passengers, Passenger(passenger_id, transit_routes_passenger, feeder_routes_passenger, origin, destination, origin_zone, 
            destination_zone, departure_time, demand))
    end
    return Passengers
end

"""
    For the input data, get the unique zone pairs
"""
function get_unique_zones(ond_locations_data::DataFrame)
    unique_zones = unique([(ond_locations_data.origin_zone[i], ond_locations_data.dest_zone[i]) for i in 1:size(ond_locations_data, 1)])
    return unique_zones
end

"""
    Load data from files
"""
function load_data(transit_file::AbstractString, on_demand_file::AbstractString, pp::PermanentParameters)
    transit_stops = CSV.read(transit_file, DataFrame)
    ond_locations_data = CSV.read(on_demand_file, DataFrame)

    #parameters
    max_walking_time = pp.max_walking_time
    kappa = pp.kappa
    time_horizon = pp.time_horizon
    frequency_set = pp.frequency_set
    max_on_demand_time = pp.max_on_demand_time
    max_first_waiting_time = pp.max_first_waiting_time
    on_demand_time_step = pp.on_demand_time_step
    transit_time_step = pp.transit_time_step
    max_waiting = pp.max_waiting

    transit_stops.time_prev_stop = ceil.(transit_stops.time_prev_stop ./ transit_time_step) .* transit_time_step
    t = time()
    line_frequencies = create_line_frequency(frequency_set, time_horizon, transit_stops)
    @printf("%.2f line frequency seconds\n", time() - t)
    t = time()
    passengers = create_passengers(ond_locations_data, transit_stops, max_walking_time, line_frequencies, transit_time_step)
    @printf("%.2f passenger seconds\n", time() - t)
    t = time()
    zone_pairs = get_unique_zones(ond_locations_data)
    @printf("%.2f zones seconds\n", time() - t)
    t = time()
    on_demand_routes = create_od_routes(kappa, max_on_demand_time, max_first_waiting_time, ond_locations_data, time_horizon, on_demand_time_step)
    @printf("%.2f on-demand seconds\n", time() - t)
    t = time()
    pickup_routes = create_pickup_routes(kappa, max_on_demand_time, max_first_waiting_time, time_horizon, ond_locations_data, 
        transit_stops, on_demand_time_step)
    @printf("%.2f pick-up seconds\n", time() - t)
    t = time()
    dropoff_routes = create_dropoff_routes(kappa, max_on_demand_time, time_horizon, ond_locations_data, transit_stops, passengers, 
        on_demand_time_step, max_waiting)
    @printf("%.2f drop-off seconds\n", time() - t)
    return OnDemandTransitData(passengers, on_demand_routes, pickup_routes, dropoff_routes, line_frequencies, zone_pairs)
end