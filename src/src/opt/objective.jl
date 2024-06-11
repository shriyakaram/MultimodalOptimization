
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
    for g in eachindex(y_od)
        add_to_expression!(obj_expression, data.OnD_routes[g].passenger_cost, y_od[g])
    end

    #pick-up cost to obj_expression
    for g in eachindex(y_pickup)
        add_to_expression!(obj_expression, data.pickup_routes[g].passenger_cost, y_pickup[g])
    end

    #pick-up cost to obj_expression
    for g in eachindex(y_dropoff)
        add_to_expression!(obj_expression, data.dropoff_routes[g].passenger_cost, y_dropoff[g])
    end

    #full transit cost to obj_expression
    for p in eachindex(data.passengers)
        for l in lines_passenger(p, data)
            for f in freq_passenger(p, l, data)
                routes = routes_passenger(p, l, f, data)
                for r in routes
                    add_to_expression!(obj_expression, data.passengers[p].demand * route_cost_passenger(p, l, f, r, data), z_tr[p, l, f, r])
                end
            end
        end
    end

    #feeder transit cost to obj_expression
    for p in eachindex(data.passengers)
        for l in lines_passenger_feeder(p, data)
            for f in freq_passenger_feeder(p, l, data)
                routes = routes_passenger_feeder(p, l, f, data)
                for r in routes
                    add_to_expression!(obj_expression, data.passengers[p].demand * route_cost_passenger_feeder(p, l, f, r, data), z_mm[p, l, f, r])
                end
            end
        end
    end
        
    @objective(model, Min, obj_expression)
end



