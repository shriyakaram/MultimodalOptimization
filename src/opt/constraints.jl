"""
    Add fleet assignment constraints
"""
function add_fleet_assignment_constraints!(model::Model, data::OnDemandTransitData, F::Int)
    veh_od_zone = model[:veh_od_zone]
    zones = zone_id_list(data)
    @constraint(model, fleet_assignment, sum(veh_od_zone[i] for i in zones) == F)
    
    return nothing
end

"""
    Add on-demand vehicle constraints
"""
function add_ondemand_vehicle_constraints!(ondemand_times::Vector{Float64}, model::Model, data::OnDemandTransitData)

    veh_od_zone = model[:veh_od_zone] 
    y_od = model[:y_od] 
    y_pickup = model[:y_pickup] 
    y_dropoff = model[:y_dropoff] 
    zones = zone_id_list(data)

    #odvehicle flow balance over time
    @constraint(model, od_vehicle_flow[t = ondemand_times, i = zones], 
        sum(check_time_zone_route(t, i, data.OnD_routes[g])*y_od[g] for g in eachindex(data.OnD_routes)) + 
        sum(check_time_zone_route(t, i, data.pickup_routes[g])*y_pickup[g] for g in eachindex(data.pickup_routes)) +
        sum(check_time_zone_route(t, i, data.dropoff_routes[g])*y_dropoff[g] for g in eachindex(data.dropoff_routes)) <= veh_od_zone[i])
    
    return nothing
end

"""
    Add mode assignment constraints
"""
function add_mode_assignment_constraints!(model::Model, data::OnDemandTransitData)
    m = model[:m]
    @constraint(model, mode_assignment[i = data.zone_pairs], sum(m[i,k] for k in 1:3) == 1)
    #@constraint(model, check[i = data.zone_pairs], m[i,1] == 1)
    return nothing
end

"""
    Add transit passenger assignment constraints
"""
function add_transit_passenger_constraints!(model::Model, data::OnDemandTransitData)
    z_tr = model[:z_tr]
    m = model[:m]

    #assign transit route if transit selected for a passenger
    @constraint(model, transit_routes[p = eachindex(data.passengers)], sum(z_tr[p, l, r] for l in lines_passenger(p, data) 
        for r in routes_passenger(p, l, data)) == m[(data.passengers[p].origin_zone, data.passengers[p].destination_zone), 2])

    return nothing
end

"""
    Add od passenger assignment constraints
"""
function add_od_passenger_constraints!(model::Model, data::OnDemandTransitData)
    y_od = model[:y_od]
    m = model[:m]

    #select an on-demand route only if on-demand selected for a passenger 
    for g in eachindex(data.OnD_routes)
        for p in data.OnD_routes[g].origin_order
            @constraint(model, num_passengers_type_od(p, data.OnD_routes[g])*y_od[g] <= data.passengers[p].demand * 
                m[(data.passengers[p].origin_zone, data.passengers[p].destination_zone), 1])
        end
    end

    #select the number of on-demand routes if on-demand selected for a passenger
    @constraint(model, num_ondemand_routes[p = eachindex(data.passengers)],
        sum(y_od[g]*num_passengers_type_od(data.passengers[p].passenger_id, data.OnD_routes[g]) for g in eachindex(data.OnD_routes) 
        if p in data.OnD_routes[g].origin_order) == (data.passengers[p].demand * 
            m[(data.passengers[p].origin_zone, data.passengers[p].destination_zone), 1]))
    
    return nothing
end

"""
    Add multimodal passenger assignment constraints
"""
function add_multimodal_passenger_constraints!(max_waiting::Int, transit_times::Vector{Float64}, model::Model, data::OnDemandTransitData)
    
    z_mm = model[:z_mm]
    y_pickup = model[:y_pickup] 
    y_dropoff = model[:y_dropoff] 
    m = model[:m]
    
    #assign transit route if transit selected for a passenger
    @constraint(model, transit_routes_feeder[p = eachindex(data.passengers)],
        sum(z_mm[p, l, r] for l in lines_passenger_feeder(p, data) for r in routes_passenger_feeder(p, l, data)) == 
        m[(data.passengers[p].origin_zone, data.passengers[p].destination_zone), 3])
    
    #select a pick-up route only if multimodal selected for a passenger 
    for g in eachindex(data.pickup_routes)
        for p in data.pickup_routes[g].passenger_order
            @constraint(model, num_passengers_type_route(p, data.pickup_routes[g]) * y_pickup[g] <= data.passengers[p].demand * 
                m[(data.passengers[p].origin_zone, data.passengers[p].destination_zone), 3])
        end
    end

    #select a drop-off route only if multimodal selected for a passenger 
    for g in eachindex(data.dropoff_routes)
        for p in data.dropoff_routes[g].passenger_order
            @constraint(model, num_passengers_type_route(p, data.dropoff_routes[g]) * y_dropoff[g] <= data.passengers[p].demand * 
                m[(data.passengers[p].origin_zone, data.passengers[p].destination_zone), 3])
        end
    end

    t = time()
    #flow balance for pick-up routes
    @constraint(model, pickups_flow[p = eachindex(data.passengers), l = lines_passenger_feeder(p, data), s = line_stations(l, data), 
        t in transit_times], sum(y_pickup[g]*num_passengers_type_route(data.passengers[p].passenger_id, data.pickup_routes[g]) 
        for g in eachindex(data.pickup_routes) if ((p in data.pickup_routes[g].passenger_order) && (data.pickup_routes[g].line == l) && 
        (data.pickup_routes[g].transit_station == s) && (t >= data.pickup_routes[g].end_time) && 
        (t <= max_waiting + data.pickup_routes[g].end_time))) >= data.passengers[p].demand * sum(z_mm[p, l, r] 
        for r in outgoing_transit_nodes(p, l, s, t, data)))
    @printf("%.2f pick-ups seconds\n", time() - t)

    t = time()
    #flow balance for drop-off routes
    @constraint(model, dropoffs_flow[p = eachindex(data.passengers), l = lines_passenger_feeder(p, data), s = line_stations(l, data),
        t in transit_times], sum(y_dropoff[g]*num_passengers_type_route(data.passengers[p].passenger_id, data.dropoff_routes[g]) 
        for g in eachindex(data.dropoff_routes) if ((p in data.dropoff_routes[g].passenger_order) && 
        (data.dropoff_routes[g].line == l) && (data.dropoff_routes[g].transit_station == s) && 
        (t <= data.dropoff_routes[g].start_time) && (t >= data.dropoff_routes[g].start_time - max_waiting))) >= 
        data.passengers[p].demand * sum(z_mm[p, l, r] for r in incoming_transit_nodes(p, l, s, t, data)))
    @printf("%.2f drop-offs seconds\n", time() - t)

    return nothing
end