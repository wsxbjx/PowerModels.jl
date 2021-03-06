export
    SDPWRMPowerModel, SDPWRMForm

""
abstract type AbstractWRMForm <: AbstractConicPowerFormulation end

""
abstract type SDPWRMForm <: AbstractWRMForm end

""
const SDPWRMPowerModel = GenericPowerModel{SDPWRMForm}

""
SDPWRMPowerModel(data::Dict{String,Any}; kwargs...) = GenericPowerModel(data, SDPWRMForm; kwargs...)


""
function variable_voltage(pm::GenericPowerModel{T}; nw::Int=pm.cnw, ph::Int=pm.cph, bounded = true) where T <: AbstractWRMForm
    wr_min, wr_max, wi_min, wi_max = calc_voltage_product_bounds(ref(pm, nw, :buspairs), ph)
    bus_ids = ids(pm, nw, :bus)

    w_index = 1:length(bus_ids)
    lookup_w_index = Dict([(bi,i) for (i,bi) in enumerate(bus_ids)])

    WR = var(pm, nw, ph)[:WR] = @variable(pm.model,
        [1:length(bus_ids), 1:length(bus_ids)], Symmetric, basename="$(nw)_$(ph)_WR"
    )
    WI = var(pm, nw, ph)[:WI] = @variable(pm.model,
        [1:length(bus_ids), 1:length(bus_ids)], basename="$(nw)_$(ph)_WI"
    )

    # bounds on diagonal
    for (i, bus) in ref(pm, nw, :bus)
        w_idx = lookup_w_index[i]
        wr_ii = WR[w_idx,w_idx]
        wi_ii = WR[w_idx,w_idx]

        if bounded
            setlowerbound(wr_ii, getmpv(bus["vmin"], ph)^2)
            setupperbound(wr_ii, getmpv(bus["vmax"], ph)^2)

            #this breaks SCS on the 3 bus exmple
            #setlowerbound(wi_ii, 0)
            #setupperbound(wi_ii, 0)
        else
             setlowerbound(wr_ii, 0)
        end
    end

    # bounds on off-diagonal
    for (i,j) in ids(pm, nw, :buspairs)
        wi_idx = lookup_w_index[i]
        wj_idx = lookup_w_index[j]

        if bounded
            setupperbound(WR[wi_idx, wj_idx], wr_max[(i,j)])
            setlowerbound(WR[wi_idx, wj_idx], wr_min[(i,j)])

            setupperbound(WI[wi_idx, wj_idx], wi_max[(i,j)])
            setlowerbound(WI[wi_idx, wj_idx], wi_min[(i,j)])
        end
    end

    var(pm, nw, ph)[:w] = Dict{Int,Any}()
    for (i, bus) in ref(pm, nw, :bus)
        w_idx = lookup_w_index[i]
        var(pm, nw, ph, :w)[i] = WR[w_idx,w_idx]
    end

    var(pm, nw, ph)[:wr] = Dict{Tuple{Int,Int},Any}()
    var(pm, nw, ph)[:wi] = Dict{Tuple{Int,Int},Any}()
    for (i,j) in ids(pm, nw, :buspairs)
        w_fr_index = lookup_w_index[i]
        w_to_index = lookup_w_index[j]

        var(pm, nw, ph, :wr)[(i,j)] = WR[w_fr_index, w_to_index]
        var(pm, nw, ph, :wi)[(i,j)] = WI[w_fr_index, w_to_index]
    end

end


""
function constraint_voltage(pm::GenericPowerModel{T}, nw::Int, ph::Int) where T <: AbstractWRMForm
    WR = var(pm, nw, ph)[:WR]
    WI = var(pm, nw, ph)[:WI]

    @SDconstraint(pm.model, [WR WI; -WI WR] >= 0)

    # place holder while debugging sdp constraint
    #for (i,j) in ids(pm, nw, :buspairs)
    #    InfrastructureModels.relaxation_complex_product(pm.model, w[i], w[j], wr[(i,j)], wi[(i,j)])
    #end
end
