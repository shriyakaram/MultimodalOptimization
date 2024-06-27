
"""
    Create model objective
"""
function add_objective(model::Model, data::OnDemandTransitData)
    y_od = model[:y_od] 
    y_pickup = model[:y_pickup] 
    y_dropoff = model[:y_dropoff] 
    z_tr = model[:z_tr] 
    z_mm = model[:z_mm] 

    obj_expression = AffExpr()
    
    #od cost to obj_expression
    for g in eachindex(data.OnD_routes)
        add_to_expression!(obj_expression, data.OnD_routes[g].passenger_cost, y_od[g])
    end

    #pick-up cost to obj_expression
    for g in eachindex(data.pickup_routes)
        add_to_expression!(obj_expression, data.pickup_routes[g].passenger_cost, y_pickup[g])
    end

    #pick-up cost to obj_expression
    for g in eachindex(data.dropoff_routes)
        add_to_expression!(obj_expression, data.dropoff_routes[g].passenger_cost, y_dropoff[g])
    end

    #full transit cost to obj_expression
    for p in eachindex(data.passengers)
        for l in lines_passenger(p, data)
            routes = routes_passenger(p, l, data)
            for r in routes
                add_to_expression!(obj_expression, data.passengers[p].demand * route_cost_passenger(p, l, r, data), z_tr[p, l, r])
            end
        end
    end

    #feeder transit cost to obj_expression
    for p in eachindex(data.passengers)
        for l in lines_passenger_feeder(p, data)
            routes = routes_passenger_feeder(p, l, data)
            for r in routes
                add_to_expression!(obj_expression, data.passengers[p].demand * route_cost_passenger_feeder(p, l, r, data), z_mm[p, l, r])
            end
        end
    end
        
    @objective(model, Min, obj_expression)
end



