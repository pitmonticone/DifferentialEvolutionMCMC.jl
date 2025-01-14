"""
    init_particle!(model, de, p, n_iter)
    
Initializes values for a particle.

# Arguments

- `model`: model containing a likelihood function with data and priors
- `de`: differential evolution object
- `p`: a particle
- `n_iter`: the number of iterations
"""
function init_particle(de, model, id, n_iter)
    @unpack n_initial = de
    Θ = de.n_initial > 0 ? de.samples[1,:,id] : model.sample_prior()
    p = Particle(;Θ, id)
    N = n_iter + n_initial
    p.accept = fill(false, N)
    de.evaluate_fitness!(de, model, p)
    p.lp = fill(0.0, N)
    return p
end

function initialize_samples(sample_prior)
    s = sample_prior()
    return Array{eltype(s), 3}(undef,0,0,0)
end

function initialize_samples(de::DE, model, n_iter)
    n = n_iter + de.n_initial
    s = model.sample_prior()
    n_parms = length(s)
    n_p = de.Np * de.n_groups
    samples = Array{eltype(de.samples), 3}(undef,n,n_parms,n_p)
    for p in 1:n_p
        for i in 1:de.n_initial
            samples[i,:, p] = model.sample_prior()
        end
    end
    return samples
end

"""
    accept(proposal, current, log_adj=0.0)

Metropolis-Hastings proposal selection
Note: assumes weights are posterior log likelihoods

# Arguments

- `proposal`: weight of proposal e.g. posterior log likelihood
- `current`: weight of current value e.g. posterior log likelihood
- `adj`: an adjustment term for the snooker update
"""
function accept(proposal, current, log_adj=0.0)
    p = min(1.0, exp(proposal - current + log_adj))
    return rand() <= p ? true : false
end

"""
    in_bounds(b, θ::Real)

Checks whether parameter is within lower and upper bounds.

# Arguments

- `b`: boundary (lowerbound,upperbound)
- `θ`: a parameter value
"""
in_bounds(b, θ::Real) = θ >= b[1] && θ <= b[2]
in_bounds(b, θ::Array{<:Real,N}) where {N} = all(x -> in_bounds(b, x), θ)

function in_bounds(de::DE, proposal)
    for (b,θ) in zip(de.bounds, proposal.Θ)
        !in_bounds(b, θ) ? (return false) : nothing
    end
    return true
end

"""
    compute_posterior!(de, model, proposal)

Computes posterior log likelihood of proposal particle. The value -Inf 
is returned if the proposal is out of bounds. 

# Arguments

- `de`: differential evolution object
- `model`: model containing a likelihood function with data and priors
- `proposal`: the proposed particle
"""
function compute_posterior!(de, model, proposal)
    if in_bounds(de, proposal)
        proposal.weight = model.prior_loglike(proposal.Θ) + model.loglike(proposal.Θ)
    else
        proposal.weight = -Inf
    end
    return nothing
end

"""
    evaluate_fun!(de, model, proposal))

Evaluates the fitness of an arbitrary function called `loglike`. This is used for 
point estimation as it does not use a prior distribution.  

# Arguments

- `de`: differential evolution object
- `model`: model containing a likelihood function with data and priors
- `proposal`: the proposed particle
"""
function evaluate_fun!(de, model, proposal)
    if in_bounds(de, proposal)
        proposal.weight = model.loglike(proposal.Θ)
    else
        proposal.weight = de.update_particle! == maximize! ? -Inf : Inf
    end
    return nothing
end

"""
    get_names(model, p)

Returns parameters names.

# Arguments
- `p`: a particle
- `model`: model containing a likelihood function with data and priors
"""
function get_names(model, p)
    N = size.(p.Θ)
    n_parms = length.(p.Θ)
    parm_names = fill("", sum(n_parms))
    cnt = 0
    for (k,n) in zip(model.names, N)
        if isempty(n)
            cnt += 1
            parm_names[cnt] = string(k)
        else
            for i in CartesianIndices(n)
                cnt += 1
                parm_names[cnt] = string(k, "[", join([i.I...], ","), "]")
            end
        end
    end
    push!(parm_names, "acceptance", "lp")
    return parm_names
end

"""
    store_samples!(de, groups)

Store samples after burnin period. 

# Arguments

- `de`: differential evolution object
- `groups`: groups of particles
"""
function store_samples!(de, groups)
    for group in groups
        for p in group
            add_sample!(de, p)
        end
    end
    return nothing
end

function add_sample!(de, p::Particle{T}) where {T <: Real}
    i = de.iter
    de.samples[i,:,p.id] = p.Θ'
    return nothing
end

function add_sample!(de, p)
    i = de.iter
    de.samples[i,:,p.id] = p.Θ
    return nothing
end

function as_union(p) 
    T = find_type(p)
    return Array{T}(p)
end

find_type(p) = Union{unique(typeof.(p))...}

"""
    mh_update!(de, current, proposal, log_adj=0.0)

Update particle based on Metropolis-Hastings rule.

# Arguments

- `de`: differential evolution object
- `current`: current particle
- `proposal`: proposal particle
- `log_adj`: an adjustment term for snooker update
"""
function mh_update!(de, current, proposal, log_adj=0.0)
    accepted = accept(proposal.weight, current.weight, log_adj)
    if accepted
        current.Θ = proposal.Θ
        current.weight = proposal.weight
    end
    current.accept[de.iter] = accepted
    current.lp[de.iter] = current.weight
    return nothing
end

function maximize!(de, current, proposal)
    if proposal.weight > current.weight
        current.Θ = proposal.Θ
        current.weight = proposal.weight
     end
    return nothing
end

function minimize!(de, current, proposal)
    if proposal.weight < current.weight
        current.Θ = proposal.Θ
        current.weight = proposal.weight
     end
    return nothing
end

"""
    project(p1::Particle, p2::Particle)

Returns the projection of particle `p1` onto particle `p2`. This method 
works for vectors and nested arrays. 

# Arguments

- `p1::Particle`: base particle
- `p2::Particle`: particle projected onto `p1`
"""
function project(p1::Particle, p2::Particle)
    v1,v2 = (0.0,0.0)
    for (Θ1,Θ2) in zip(p1.Θ, p2.Θ)
        v1 += sum(Θ1 .* Θ2)
        v2 += sum(Θ2.^2)
    end
    return p2 * (v1 / v2)
end

norm(p::Particle) = norm(p.Θ)

function best_particle(particles, fun)
    mx = particles[1]
    for p in particles
        if fun(p.weight, mx.weight)
            mx = p
        end
    end
    return mx
end

function get_optimal(de, model, particles)
    fun = de.update_particle!  == maximize! ? (>) : (<) 
    mxp = best_particle(particles, fun)
    Θ = NamedTuple{Symbol.(model.names)}(mxp.Θ)
    max_val = mxp.weight
    return Θ,max_val
end

# Type-stable arithmatic operations for Union{Array{T,1},T} types (which return Any otherwise)
import Base: +, - ,*

function +(x::Particle, y::Particle)
    N = length(x.Θ)
    z = similar(x.Θ)
    for i in 1:N
        z[i] = x.Θ[i] + y.Θ[i]
    end
    return Particle(Θ=z)
end

+(x::Real, y::Particle) = +(y, x)

function +(x::Particle, y::Real)
    N = length(x.Θ)
    z = similar(x.Θ)
    for i in 1:N
        z[i] = x.Θ[i] .+ y
    end
    return Particle(Θ=z)
end

function +(x::Particle, d::Distribution)
    N = length(x.Θ)
    z = similar(x.Θ)
    for i in 1:N
        z[i] = x.Θ[i] .+′ draw(d, x.Θ[i])
    end
    return Particle(Θ=z)
end

function draw(d, v::Float64)
    return rand(d)
end

function draw(d, v)
    return rand(d, size(v))
end

function *(x::Particle, y::Particle)
    N = length(x.Θ)
    z = similar(x.Θ)
    for i in 1:N
        z[i] = x.Θ[i] .*′ y.Θ[i]
    end
    return Particle(Θ=z)
end

*(x::Real, y::Particle) = *(y, x)

function *(x::Particle, y::Real)
    N = length(x.Θ)
    z = similar(x.Θ)
    for i in 1:N
        z[i] = x.Θ[i] .*′ y
    end
    return Particle(Θ=z)
end

*(x::Array{<:Real,1}, y::Particle) = *(y, x)

function *(x::Particle, y::Array{<:Real,1})
    N = length(x.Θ)
    z = similar(x.Θ)
    for i in 1:N
        z[i] = x.Θ[i] .* y[i]
    end
    return Particle(Θ=z)
end

function -(x::Particle, y::Particle)
    N = length(x.Θ)
    z = similar(x.Θ)
    for i in 1:N
        z[i] = x.Θ[i] - y.Θ[i]
    end
    return Particle(Θ=z)
end

-(x::Real, y::Particle) = -(y, x)

function -(x::Particle, y::Real)
    N = length(x.Θ)
    z = similar(x.Θ)
    for i in 1:N
        z[i] = x.Θ[i] .- y
    end
    return Particle(Θ=z)
end

# arithmetic methods for hanlding discrete parameters
*′(x, y) = x * y
*′(x::Int64, y::Float64) = Int(round(x * y))
*′(x::Float64, y::Int64) = Int(round(x * y))
*′(x::Array{Int64,N}, y::Float64) where {N} = @. Int(round(x * y))
*′(x::Float64, y::Array{Int64,N}) where {N} = @. Int(round(x * y))
+′(x, y) = x + y
+′(x::Int64, y::Float64) = Int(round(x + y))
+′(x::Float64, y::Int64) = Int(round(x + y))
+′(x::Array{Int64,N}, y::Float64) where {N} = @. Int(round(x + y))
+′(x::Float64, y::Array{Int64,N}) where {N} = @. Int(round(x + y))