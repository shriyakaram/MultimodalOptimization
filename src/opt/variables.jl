"""
    Create vehicle and zone variables
"""
function add_vehicle_zone_variables!(model::Model, data::OnDemandTransitData)

    zones = zone_id_list(data)

    #number of on-demand vehicles per zone
    @variable(model, veh_od_zone[i = zones] >= 0, Int)

    #mode assignment
    @variable(model, m[i = data.zone_pairs, k = 1:3], Bin)

    return veh_od_zone, m
end

"""
    Create transit variables
"""
function add_transit_variables!(model::Model, data::OnDemandTransitData)
    
    #assign passengers p to transit routes for each line l and frequency f 
    @variable(model, z_tr[p = eachindex(data.passengers), l = lines_passenger(p, data), r = routes_passenger(p, l, data)], Bin)
        
    #assign passengers p to transit routes for each line l and frequency f (multimodal)
    @variable(model, z_mm[p = eachindex(data.passengers), l = lines_passenger_feeder(p, data), r = routes_passenger_feeder(p, l, data)], Bin)

    return z_tr, z_mm
end

"""
    Create on-demand variables
"""
function add_ondemand_variables!(model::Model, data::OnDemandTransitData)

    #number of od routes g selected
    @variable(model, y_od[g = eachindex(data.OnD_routes)] >= 0, Int)
    
    #number of pick-up routes g selected
    @variable(model, y_pickup[g = eachindex(data.pickup_routes)] >= 0, Int)

    #number of drop-off routes g selected
    @variable(model, y_dropoff[g = eachindex(data.dropoff_routes)] >= 0, Int)

    return y_od, y_pickup, y_dropoff
end


