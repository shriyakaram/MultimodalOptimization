"""
    Return the total on-demand cost
"""
function total_ond_cost(odt::OnDemandTransitModel)
    data = odt.data
    y_od = JuMP.value.(odt.model[:y_od])
    od_cost = 0
    walk_cost = 0
    waiting_cost = 0
    in_vehicle_cost = 0
    routes_selected = findall(y_od .!= 0)
    routes = data.OnD_routes
    for g in routes_selected
        od_cost += y_od[g]*routes[g].passenger_cost
        walk, waiting, in_vehicle = post_compute_route_cost(routes[g])
        walk_cost += y_od[g]*walk
        waiting_cost += y_od[g]*waiting
        in_vehicle_cost += y_od[g]*in_vehicle
    end
    return walk_cost, waiting_cost, in_vehicle_cost, od_cost
end

"""
    Return the total pick-up route cost
"""
function total_pickup_cost(odt::OnDemandTransitModel)
    data = odt.data
    y_pickup = JuMP.value.(odt.model[:y_pickup])
    routes_selected = findall(y_pickup .!= 0)
    routes = data.pickup_routes
    pickup_cost = 0
    walk_cost = 0
    waiting_cost = 0
    in_vehicle_cost = 0
    for g in routes_selected
        pickup_cost += y_pickup[g]*routes[g].passenger_cost
        walk, waiting, in_vehicle = post_compute_pickup_route_cost(routes[g])
        walk_cost += y_pickup[g]*walk
        waiting_cost += y_pickup[g]*waiting
        in_vehicle_cost += y_pickup[g]*in_vehicle
    end
    return walk_cost, waiting_cost, in_vehicle_cost, pickup_cost
end

"""
    Return the total dropff-off route cost
"""
function total_dropoff_cost(odt::OnDemandTransitModel)
    data = odt.data
    y_dropoff = JuMP.value.(odt.model[:y_dropoff])
    routes_selected = findall(y_dropoff .!= 0)
    routes = data.dropoff_routes
    dropoff_cost = 0
    walk_cost = 0
    waiting_cost = 0
    in_vehicle_cost = 0
    for g in routes_selected
        dropoff_cost += y_dropoff[g]*routes[g].passenger_cost
        walk, waiting, in_vehicle = post_compute_dropoff_route_cost(routes[g])
        walk_cost += y_dropoff[g]*walk
        waiting_cost += y_dropoff[g]*waiting
        in_vehicle_cost += y_dropoff[g]*in_vehicle
    end
    return walk_cost, waiting_cost, in_vehicle_cost, dropoff_cost
end

"""
    Return the total transit cost
"""
function total_transit_cost(odt::OnDemandTransitModel)
    data = odt.data
    z_tr = JuMP.value.(odt.model[:z_tr])
    full_transit_cost = 0
    passenger_ids = [p.passenger_id for p in data.passengers]
    for p in passenger_ids
        for l in lines_passenger(p, data)
            for f in freq_passenger(p, l, data)
                for r in routes_passenger(p, l, f, data)
                    full_transit_cost += route_cost_passenger(p, l, f, r, data) * z_tr[p, l, f, r]
                end
            end
        end
    end
    return full_transit_cost
end

"""
    Return the total transit feeder cost
"""
function total_transit_feeder_cost(odt::OnDemandTransitModel)
    data = odt.data
    z_mm = JuMP.value.(odt.model[:z_mm])
    feeder_cost = 0
    passenger_ids = [p.passenger_id for p in data.passengers]
    for p in passenger_ids
        for l in lines_passenger_feeder(p, data)
            for f in freq_passenger_feeder(p, l, data)
                for r in routes_passenger_feeder(p, l, f, data)
                    feeder_cost += route_cost_passenger_feeder(p, l, f, r, data) * z_mm[p, l, f, r]
                end
            end
        end
    end
    return feeder_cost
end

"""
    For each passenger p, return a dictionary of p --> mode (1 = full on-demand, 2 = transit, 3 = multimodal) 
"""
function passenger_mode_solution(odt::OnDemandTransitModel, tol::Float64=1e-6)
    data = odt.data
    m = JuMP.value.(odt.model[:m])
    passenger_mode_dict = Dict{Int, Int}()
    for p in data.passengers
        passenger_id = p.passenger_id
        origin_zone = p.origin_zone 
        destination_zone = p.destination_zone 
        modes_p = m[(origin_zone, destination_zone),:]
        for mode in eachindex(modes_p)
            if abs(modes_p[mode] - 1) <= tol
                passenger_mode_dict[passenger_id] = mode
            end
        end        
    end
    return passenger_mode_dict
end

"""
    Return a dataframe for the number of full on-demand and multimodal vehicles per zone
"""
function vehicle_zone_solution(odt::OnDemandTransitModel)
    veh_od_zone = odt.model[:veh_od_zone]
    veh_mm_zone = odt.model[:veh_mm_zone]
    zone_ids = zone_id_list(odt.data)
    vehicle_zone_df = DataFrame()
    for z in zone_ids
        row = (zone_id = z, veh_ond = value(veh_od_zone[z]), veh_mm = value(veh_mm_zone[z]))
        push!(vehicle_zone_df, row)
    end
    return vehicle_zone_df
end

"""
    Return transit stations/lines assigned to each passenger
"""
function passenger_station_solution(odt::OnDemandTransitModel, passenger_mode_dict::Dict{Int, Int}, tol::Float64=1e-6)
    data = odt.data
    z_mm = odt.model[:z_mm]
    z_tr = odt.model[:z_tr]
    passenger_station_df = DataFrame()
    passenger_ids = [p.passenger_id for p in data.passengers]
    for p in passenger_ids
        if passenger_mode_dict[p] == 1
            row = (passenger_id = p, mode = "Full on-demand", origin_station = 0, destination_station = 0, line = 0)
            push!(passenger_station_df, row)
        end

        if passenger_mode_dict[p] == 2
            for l in lines_passenger(p, data)
                for f in freq_passenger(p, l, data)
                    for r in routes_passenger(p, l, f, data)
                        if value(z_tr[p, l, f, r]) >= 1
                            origin_station = r.origin_node.station
                            destination_station = r.destination_node.station
                            row = (passenger_id = p, mode = "Full transit", origin_station = origin_station, destination_station = destination_station, line = l)
                            push!(passenger_station_df, row)
                        end
                    end
                end
            end
        end

        if passenger_mode_dict[p] == 3
            for l in lines_passenger_feeder(p, data)
                for f in freq_passenger_feeder(p, l, data)
                    for r in routes_passenger_feeder(p, l, f, data)
                        if value(z_mm[p, l, f, r]) >= 1
                            origin_station = r.origin_node.station
                            destination_station = r.destination_node.station
                            row = (passenger_id = p, mode = "Multimodal", origin_station = origin_station, destination_station = destination_station, line = l)
                            push!(passenger_station_df, row)
                        end
                    end
                end
            end
        end
        
    end
    return passenger_station_df
end

"""
    Return optimal line/frequencies
"""
function line_frequency_solution(odt::OnDemandTransitModel)
    x = JuMP.value.(odt.model[:x])
    data = odt.data
    lines, frequencies = line_frequency_pairs(data.line_frequencies)
    line_frequency_df = DataFrame()
    for l in lines
        freq_l = x[l,:]
        for freq in eachindex(freq_l)
            if freq_l[freq] == 1
                row = (line = l, frequency = frequencies[freq])
                push!(line_frequency_df, row)
            end
        end
    end
    return line_frequency_df
end

"""
    Return selected on-demand routes
"""
function selected_ond_routes(odt::OnDemandTransitModel)
    data = odt.data
    y_od = JuMP.value.(odt.model[:y_od])
    routes_selected = findall(y_od .!= 0)
    routes = OnDRoute[]
    for g in routes_selected
        push!(routes, data.OnD_routes[g])
    end
    return routes
end

"""
    Return selected pick-up routes
"""
function selected_pickup_routes(odt::OnDemandTransitModel)
    data = odt.data
    y_pickup = JuMP.value.(odt.model[:y_pickup])
    routes_selected = findall(y_pickup .!= 0)
    routes = PickupRoute[]
    for g in routes_selected
        push!(routes, data.pickup_routes[g])
    end
    return routes
end

"""
    Return selected drop-off routes
"""
function selected_dropoff_routes(odt::OnDemandTransitModel)
    data = odt.data
    y_dropoff = JuMP.value.(odt.model[:y_dropoff])
    routes_selected = findall(y_dropoff .!= 0)
    routes = DropoffRoute[]
    for g in routes_selected
        push!(routes, data.dropoff_routes[g])
    end
    return routes
end

"""
    Return transit vs. on-demand cost components for multimodal only for each passenger
"""
function multimodal_passenger_cost(p::Int, odt::OnDemandTransitModel)
    data = odt.data
    z_mm = JuMP.value.(odt.model[:z_mm])
    y_pickup = JuMP.value.(odt.model[:y_pickup])
    y_dropoff = JuMP.value.(odt.model[:y_dropoff])

    #transit cost
    feeder_cost = 0
    for l in lines_passenger_feeder(p, data)
        for f in freq_passenger_feeder(p, l, data)
            for r in routes_passenger_feeder(p, l, f, data)
                feeder_cost += route_cost_passenger_feeder(p, l, f, r, data) * z_mm[p, l, f, r]
            end
        end
    end

    #pickup cost
    pickup_cost = 0
    pickup_waiting_cost = 0
    pickup_in_vehicle_cost = 0
    routes_selected = findall(y_pickup .!= 0)
    routes = data.pickup_routes
    for g in routes_selected
        if p in routes[g].passenger_order
            pickup_cost += y_pickup[g]*routes[g].passenger_cost
            _, waiting, in_vehicle = post_compute_pickup_route_cost(routes[g])
            pickup_waiting_cost += y_pickup[g]*waiting
            pickup_in_vehicle_cost += y_pickup[g]*in_vehicle
        end
    end

    #dropoff cost
    dropoff_cost = 0
    dropoff_waiting_cost = 0
    dropoff_in_vehicle_cost = 0
    routes_selected = findall(y_dropoff .!= 0)
    routes = data.dropoff_routes
    for g in routes_selected
        if p in routes[g].passenger_order
            dropoff_cost += y_dropoff[g]*routes[g].passenger_cost
            _, waiting, in_vehicle = post_compute_dropoff_route_cost(routes[g])
            dropoff_waiting_cost += y_dropoff[g]*waiting
            dropoff_in_vehicle_cost += y_dropoff[g]*in_vehicle
        end
    end
    return feeder_cost, pickup_waiting_cost, pickup_in_vehicle_cost, dropoff_waiting_cost, dropoff_in_vehicle_cost
end