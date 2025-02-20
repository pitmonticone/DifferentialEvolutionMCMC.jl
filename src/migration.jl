"""
    migration!(de, groups)

Select a subset of groups and swap one poorly particle from each selected groups.

# Arguments

- `de`: differential evolution object
- `groups`: groups of particles
"""
function migration!(de, groups)
    # select groups for migration
    sub_group = select_groups(de, groups)
    # select particles within groups for migration
    p_idx,particles = select_particles(sub_group)
    # swap the particles so that p1->pn, p2 -> p1,..., pn -> pn-1
    shift_particles!(sub_group, p_idx, particles)
    return nothing
end

"""
    select_groups(de, groups)

Select a subset of groups for migration and return their indices.

# Arguments

- `de`: differential evolution object
- `groups`: groups of particles
"""
function select_groups(de, groups)
    N = rand(2:de.n_groups)
    sub_group = sample(groups, N, replace=false)
    return sub_group
end

"""
    select_particles(sub_group)

Select particles from groups for migration. Returns particle index and particles.

# Arguments

- `sub_group`: vector of particles
"""
function select_particles(sub_group)
    Ng = length(sub_group)
    p_idx = fill(0, Ng)
    particles = Vector{eltype(sub_group[1])}(undef, Ng)
    for (i,g) in enumerate(sub_group)
        p_idx[i],particles[i] = select_particle(g)
    end
    return p_idx,particles
end

"""
    select_particle(group)
Select particle from a single chain inversely proportional to its weight.

# Arguments

- `group`: a group of particles
"""
function select_particle(group)
    w = map(x -> x.weight, group)
    θ = exp.(-w) / sum(exp.(-w))
    idx = sample(1:length(group), Weights(θ))
    # if numberical error occurs, select the worst particle index (lower is worse)
    idx = any(isnan, θ) ? findmin(w)[2] : idx
    return idx,group[idx]
end

"""
    shift_particles!(sub_group, p_idx, particles)

Swap the particles so that p1->pn, p2 -> p1,..., pn -> pn-1 where
pi is the particle belonging to the ith group.

# Arguments

- `sub_group`: group of particles
- `p_idx`: particle index
- `particles`: particle objects representing position in parameter space
"""
function shift_particles!(sub_group, p_idx, particles)
    # perform a circular shift
    particles = circshift(particles, 1)
    # assign shifted particles to the new chain
    for (g,j,p) in zip(sub_group, p_idx, particles)
        g[j] = p
    end
end
