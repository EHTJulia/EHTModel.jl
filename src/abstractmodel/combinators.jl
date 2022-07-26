export add, convolved, smoothed, components

"""
    $(TYPEDEF)
Abstract type that denotes a composite model. Where we have
combined two models together.
# Implementation
Any implementation of a composite type must define the following methods:
- visibility_point
- uv_combinator
- imanalytic
- visanalytic
- ComradeBase.intensity_point if model intensity is `IsAnalytic`
- intensitymap! if model intensity is `NotAnalytic`
- intensitymap if model intensity is `NotAnalytic`
- flux
- radialextent
- visibilities (optional)
"""
abstract type CompositeModel{M1,M2} <: AbstractModel end

"""
function modelimage(::NotAnalytic,
    model::CompositeModel,
    image::ComradeBase.AbstractIntensityMap,
    alg::FourierTransform=FFTAlg(),
    executor=SequentialEx())

    m1 = @set model.m1 = modelimage(model.m1, image, alg, executor)
    @set m1.m2 = modelimage(m1.m2, copy(image), alg, executor)
end
"""

"""
function modelimage(::NotAnalytic,
    model::CompositeModel,
    cache::AbstractCache,
    executor=SequentialEx())

    m1 = @set model.m1 = modelimage(model.m1, cache, executor)
    @set m1.m2 = modelimage(m1.m2, cache, executor)
end
"""

function fouriermap(m::CompositeModel, fovx, fovy, nx, ny)
    m1 = fouriermap(m.m1, fovx, fovy, nx, ny)
    m2 = fouriermap(m.m2, fovx, fovy, nx, ny)
    return uv_combinator(m).(m1, m2)
end



radialextent(m::CompositeModel) = max(radialextent(m.m1), radialextent(m.m2))

@inline visanalytic(::Type{<:CompositeModel{M1,M2}}) where {M1,M2} = visanalytic(M1) * visanalytic(M2)
@inline imanalytic(::Type{<:CompositeModel{M1,M2}}) where {M1,M2} = imanalytic(M1) * imanalytic(M2)


"""
    $(TYPEDEF)
Pointwise addition of two models in the image and visibility domain.
An end user should instead call [`added`](@ref added) or `Base.+` when
constructing a model
# Example
```julia-repl
julia> m1 = Disk() + Gaussian()
julia> m2 = added(Disk(), Gaussian()) + Ring()
```
"""
struct AddModel{T1,T2} <: CompositeModel{T1,T2}
    m1::T1
    m2::T2
end

"""
    Base.:+(m1::AbstractModel, m2::AbstractModel)
Combine two models to create a composite [`AddModel`](@ref Comrade.AddModel).
This adds two models pointwise, i.e.
```julia-repl
julia> m1 = Gaussian()
julia> m2 = Disk()
julia> visibility(m1+m2, 1.0, 1.0) == visibility(m1, 1.0, 1.0) + visibility(m2, 1.0, 1.0)
true
```
"""
Base.:+(m1::AbstractModel, m2::AbstractModel) = AddModel(m1, m2)
Base.:-(m1, m2) = AddModel(m1, -1.0 * m2)

"""
    added(m1::AbstractModel, m2::AbstractModel)
Combine two models to create a composite [`AddModel`](@ref Comrade.AddModel).
This adds two models pointwise, i.e.
```julia-repl
julia> m1 = Gaussian()
julia> m2 = Disk()
julia> visibility(added(m1,m2), 1.0, 1.0) == visibility(m1, 1.0, 1.0) + visibility(m2, 1.0, 1.0)
true
```
"""
added(m1::AbstractModel, m2::AbstractModel) = AddModel(m1, m2)


"""
    components(m::AbstractModel)
Returns the model components for a composite model. This
will return a Tuple with all the models you have constructed.
# Example
```julia-repl
julia> m = Gaussian() + Disk()
julia> components(m)
(Gaussian{Float64}(), Disk{Float64}())
```
"""
components(m::AbstractModel) = (m,)
components(m::CompositeModel{M1,M2}) where
{M1<:AbstractModel,M2<:AbstractModel} = (components(m.m1)..., components(m.m2)...)

flux(m::AddModel) = flux(m.m1) + flux(m.m2)

"""
# Commented out until defining intensitymap
function intensitymap(m::AddModel, fovx::Real, fovy::Real, nx::Int, ny::Int; pulse=DeltaPulse())
    sim1 = intensitymap(m.m1, fovx, fovy, nx, ny; pulse)
    sim2 = intensitymap(m.m2, fovx, fovy, nx, ny; pulse)
    return sim1 .+ sim2
end


# Commented out until defining intensitymap
function intensitymap!(sim::IntensityMap, m::AddModel)
    csim = deepcopy(sim)
    intensitymap!(csim, m.m1)
    sim .= csim
    intensitymap!(csim, m.m2)
    sim .= sim .+ csim
    return sim
end
"""

@inline uv_combinator(::AddModel) = Base.:+
@inline xy_combinator(::AddModel) = Base.:+

@inline function _visibilities(model::M, u::AbstractArray, v::AbstractArray, args...) where {M<:CompositeModel}
    return _visibilities(visanalytic(M), model, u, v, args...)
end


@inline function _visibilities(::NotAnalytic, model::CompositeModel, u::AbstractArray, v::AbstractArray, args...)
    f = uv_combinator(model)
    return f.(_visibilities(model.m1, u, v), _visibilities(model.m2, u, v))
end

@inline function _visibilities(::IsAnalytic, model::CompositeModel, u::AbstractArray, v::AbstractArray, args...)
    f = uv_combinator(model)
    return f.(visibility_point.(Ref(model.m1), u, v), visibility_point.(Ref(model.m2), u, v))
end

@inline function visibility_point(model::CompositeModel{M1,M2}, u, v, args...) where {M1,M2}
    f = uv_combinator(model)
    v1 = visibility(model.m1, u, v, args...)
    v2 = visibility(model.m2, u, v, args...)
    return f(v1, v2)
end

@inline function intensity_point(model::CompositeModel, u, v)
    f = xy_combinator(model)
    v1 = intensity_point(model.m1, u, v)
    v2 = intensity_point(model.m2, u, v)
    return f(v1, v2)
end



"""
    $(TYPEDEF)
Pointwise addition of two models in the image and visibility domain.
An end user should instead call [`convolved`](@ref convolved).
Also see [`smoothed(m, σ)`](@ref smoothed) for a simplified function that convolves
a model `m` with a Gaussian with standard deviation `σ`.
"""
struct ConvolvedModel{M1,M2} <: CompositeModel{M1,M2}
    m1::M1
    m2::M2
end

"""
    convolved(m1::AbstractModel, m2::AbstractModel)
Convolve two models to create a composite [`ConvolvedModel`](@ref Comrade.ConvolvedModel).
```julia-repl
julia> m1 = Ring()
julia> m2 = Disk()
julia> convolved(m1, m2)
```
"""
convolved(m1::AbstractModel, m2::AbstractModel) = ConvolvedModel(m1, m2)

"""
    smoothed(m::AbstractModel, σ::Number)
Smooths a model `m` with a Gaussian kernel with standard deviation `σ`.
# Notes
This uses [`convolved`](@ref) to created the model, i.e.
```julia-repl
julia> m1 = Disk()
julia> m2 = Gaussian()
julia> convolved(m1, m2) == smoothed(m1, 1.0)
true
```
"""
smoothed(m, σ::Number) = convolved(m, stretched(Gaussian(), σ, σ))

@inline imanalytic(::Type{<:ConvolvedModel}) = NotAnalytic()


@inline uv_combinator(::ConvolvedModel) = Base.:*

flux(m::ConvolvedModel) = flux(m.m1) * flux(m.m2)

"""
# Commented out until defining intensitymap
function intensitymap(::NotAnalytic, model::ConvolvedModel, fovx::Real, fovy::Real, nx::Int, ny::Int; pulse=DeltaPulse(), executor=SequentialEx())
    vis1 = fouriermap(model.m1, fovx, fovy, nx, ny)
    vis2 = fouriermap(model.m2, fovx, fovy, nx, ny)
    vis = ifftshift(phasedecenter!(vis1 .* vis2, fovx, fovy, nx, ny))
    img = ifft(vis)
    return IntensityMap(real.(img) ./ (nx * ny), fovx, fovy, pulse)
end

# Commented out until defining intensitymap
function intensitymap!(::NotAnalytic, sim::IntensityMap, model::ConvolvedModel, executor=SequentialEx())
    ny, nx = size(sim)
    fovx, fovy = sim.fovx, sim.fovy
    vis1 = fouriermap(model.m1, fovx, fovy, nx, ny)
    vis2 = fouriermap(model.m2, fovx, fovy, nx, ny)
    vis = ifftshift(phasedecenter!(vis1 .* vis2, fovx, fovy, nx, ny))
    ifft!(vis)
    for I in eachindex(sim)
        sim[I] = real(vis[I]) / (nx * ny)
    end
end
"""