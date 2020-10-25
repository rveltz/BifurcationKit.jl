using DiffEqBase

####################################################################################################
# Poincare shooting based on Sánchez, J., M. Net, B. Garcı́a-Archilla, and C. Simó. “Newton–Krylov Continuation of Periodic Orbits for Navier–Stokes Flows.” Journal of Computational Physics 201, no. 1 (November 20, 2004): 13–33. https://doi.org/10.1016/j.jcp.2004.04.018.

"""

`pb = PoincareShootingProblem(flow::Flow, M, sections; δ = 1e-8, interp_points = 50, parallel = false)`

This composite type implements the Poincaré Shooting method to locate periodic orbits by relying on Poincaré return maps. The arguments are as follows
- `flow::Flow`: implements the flow of the Cauchy problem though the structure [`Flow`](@ref).
- `M`: the number of Poincaré sections. If `M==1`, then the simple shooting is implemented and the multiple one otherwise.
- `sections`: function or callable struct which implements a Poincaré section condition. The evaluation `sections(x)` must return a scalar number when `M==1`. Otherwise, one must implement a function `section(out, x)` which populates `out` with the `M` sections. See [`SectionPS`](@ref) for type of section defined as a hyperplane.
- `δ = 1e-8` used to compute the jacobian of the fonctional by finite differences. If set to `0`, an analytical expression of the jacobian is used instead.
- `interp_points = 50` number of interpolation point used to define the callback (to compute the hitting of the hyperplan section)
- `parallel = false` whether the shooting are computed in parallel (threading). Only available through the use of Flows defined by `EnsembleProblem`.

## Simplified constructors
- A simpler way is to create a functional is

`pb = PoincareShootingProblem(F, p, prob::ODEProblem, alg, section; kwargs...)`

for simple shooting or

`pb = PoincareShootingProblem(F, p, prob::Union{ODEProblem, EnsembleProblem}, alg, M::Int, section; kwargs...)`

for multiple shooting . Here `F(x,p)` is the vector field, `p` is a parameter (to be passed to the vector and the flow), `prob` is an `Union{ODEProblem, EnsembleProblem}` which is used to create a flow using the ODE solver `alg` (for example `Tsit5()`). Finally, the arguments `kwargs` are passed to the ODE solver defining the flow. We refere to `DifferentialEquations.jl` for more information.

- Another convenient call is

`pb = PoincareShootingProblem(F, p, prob::Union{ODEProblem, EnsembleProblem}, alg, normals::AbstractVector, centers::AbstractVector; δ = 1e-8, kwargs...)`

where `normals` (resp. `centers`) is a list of normals (resp. centers) which defines a list of hyperplanes ``\\Sigma_i``. These hyperplanes are used to define partial Poincaré return maps.

## Computing the functionals
A functional, hereby called `G` encodes this shooting problem. You can then call `pb(orbitguess, par)` to apply the functional to a guess. Note that `orbitguess::AbstractVector` must be of size M * N where N is the number of unknowns in the state space and `M` is the number of Poincaré maps. Another accepted `guess` is such that `guess[i]` is the state of the orbit on the `i`th section. This last form allows for non-vector state space which can be convenient for 2d problems for example.

- `pb(orbitguess, par)` evaluates the functional G on `orbitguess`
- `pb(orbitguess, par, du)` evaluates the jacobian `dG(orbitguess).du` functional at `orbitguess` on `du`

!!! tip "Tip"
    You can use the function `getPeriod(pb, sol, par)` to get the period of the solution `sol` for the problem with parameters `par`.
"""
@with_kw struct PoincareShootingProblem{Tf, Tsection <: SectionPS} <: AbstractShootingProblem
	M::Int64 = 0								# number of Poincaré sections
	flow::Tf = Flow()							# should be a Flow{TF, Tf, Td}
	section::Tsection = SectionPS(M)			# Poincaré sections
	δ::Float64 = 0e-8							# Numerical value used for the Matrix-Free Jacobian by finite differences. If set to 0, analytical jacobian is used
	parallel::Bool = false					# whether we use DE in Ensemble mode for multiple shooting
end

@inline isParallel(psh::PoincareShootingProblem) = psh.parallel

function PoincareShootingProblem(F, p,
			prob::ODEProblem, alg,
			hyp::SectionPS;
			δ = 1e-8, interp_points = 50, parallel = false, kwargs...)
	pSection(out, u, t, integrator) = (hyp(out, u); out .= out .* (integrator.iter > 1))
	affect!(integrator, idx) = terminate!(integrator)
	# we put nothing option to have an upcrossing
	cb = VectorContinuousCallback(pSection, affect!, hyp.M; interp_points = interp_points, affect_neg! = nothing)
	# change the ODEProblem -> EnsembleProblem for the parallel case
	_M = hyp.M
	parallel = _M==1 ? false : parallel
	_pb = parallel ? EnsembleProblem(prob) : prob
	return PoincareShootingProblem(flow = Flow(F, p, _pb, alg; callback = cb, kwargs...), M = hyp.M, section = hyp, δ = δ, parallel = parallel)
end

# this is the "simplest" constructor to use in automatic branching from Hopf
# this is a Hack to pass the arguments to construct a Flow. Indeed, we need to provide the
# appropriate callback for Poincare Shooting to work
PoincareShootingProblem(M::Int, par, prob::ODEProblem, alg; parallel = false, kwargs...) = PoincareShootingProblem(M = M, flow = (par = par, prob = prob, alg = alg), parallel = parallel)

PoincareShootingProblem(M::Int, par, prob1::ODEProblem, alg1, prob2::ODEProblem, alg2; parallel = false, kwargs...) = PoincareShootingProblem(M = M, flow = (par = par, prob1 = prob1, alg1 = alg1, prob2 = prob2, alg2 = alg2), parallel = parallel)

function PoincareShootingProblem(F, p,
			prob::ODEProblem, alg,
			normals::AbstractVector, centers::AbstractVector;
			δ = 1e-8, interp_points = 50, parallel = false, kwargs...)
	return PoincareShootingProblem(F, p,
					prob, alg,
					SectionPS(normals, centers);
					δ = δ, interp_points = interp_points, parallel = parallel, kwargs...)
end

function PoincareShootingProblem(F, p,
				prob1::ODEProblem, alg1,
				prob2::ODEProblem, alg2,
				hyp::SectionPS;
				δ = 1e-8, interp_points = 50, parallel = false, kwargs...)
	pSection(out, u, t, integrator) = (hyp(out, u); out .= out .* (integrator.iter > 1))
	affect!(integrator, idx) = terminate!(integrator)
	# we put nothing option to have an upcrossing
	cb = VectorContinuousCallback(pSection, affect!, hyp.M; interp_points = interp_points, affect_neg! = nothing)
	# change the ODEProblem -> EnsembleProblem for the parallel case
	_M = hyp.M
	parallel = _M==1 ? false : parallel
	_pb1 = parallel ? EnsembleProblem(prob1) : prob1
	_pb2 = parallel ? EnsembleProblem(prob2) : prob2
	return PoincareShootingProblem(flow = Flow(F, p, _pb1, alg1, _pb2, alg2; callback = cb, kwargs...), M = hyp.M, section = hyp, δ = δ, parallel = parallel)
end

function PoincareShootingProblem(F, p,
				prob1::ODEProblem, alg1,
				prob2::ODEProblem, alg2,
				normals::AbstractVector, centers::AbstractVector;
				δ = 1e-8, interp_points = 50, parallel = false, kwargs...)
	return PoincareShootingProblem(F, p,
					prob1, alg2, prob2, alg2,
					SectionPS(normals, centers);
					δ = δ, interp_points = interp_points, parallel = parallel, kwargs...)
end

"""
	update!(pb::PoincareShootingProblem, centers_bar; _norm = norm)

This function updates the normals and centers of the hyperplanes defining the Poincaré sections.
"""
@views function updateSection!(pb::PoincareShootingProblem, centers_bar, par; _norm = norm)
	M = getM(pb); Nm1 = div(length(centers_bar), M)
	centers_barc = reshape(centers_bar, Nm1, M)
	centers = [E(pb.section, centers_barc[:, ii], ii) for ii = 1:M]
	normals = [pb.flow.F(c, par) for c in centers]

	for ii in eachindex(normals)
		normals[ii] ./= _norm(normals[ii])
	end
	update!(pb.section, normals, centers)
end

"""
$(SIGNATURES)

Compute the period of the periodic orbit associated to `x_bar`.
"""
function getPeriod(psh::PoincareShootingProblem, x_bar, par)
	M = getM(psh); Nm1 = div(length(x_bar), M)

	# reshape the period orbit guess
	x_barc = reshape(x_bar, Nm1, M)

	# variable to hold the computed result
	xc = similar(x_bar, Nm1 + 1, M)
	outc = similar(xc)

	Th = eltype(x_barc)
	period = Th(0)

	# we extend the state space to be able to call the flow, so we fill xc
	if ~isParallel(psh)
		for ii in 1:M
			E!(psh.section, view(xc, :, ii), view(x_barc, :, ii), ii)
			# We need the callback to be active here!!!
			period += @views psh.flow(Val(:TimeSol), xc[:, ii], par, Inf64).t
		end
	else
		for ii in 1:M
			E!(psh.section, view(xc, :, ii), view(x_barc, :, ii), ii)
		end
		solOde =  psh.flow(Val(:TimeSol), xc, par, repeat([Inf64], M))
		for ii in 1:M
			period += solOde[ii].t
		end
	end
	return period
end

"""
$(SIGNATURES)

Compute the full trajectory associated to `x`. Mainly for plotting purposes.
"""
function getTrajectory(prob::PoincareShootingProblem, x_bar::AbstractVector, p)
	# this function extracts the amplitude of the cycle
	M = getM(prob); Nm1 = length(x_bar) ÷ M

	# reshape the period orbit guess
	x_barc = reshape(x_bar, Nm1, M)
	xc = similar(x_bar, Nm1 + 1, M)

	# !!!! we could use @views but then Sundials will complain !!!
	if ~isParallel(prob)
		T = getPeriod(prob, x_bar, p)
		E!(prob.section, view(xc, :, 1), view(x_barc, :, 1), 1)
		# We need the callback to be active here!!!
		sol1 =  @views prob.flow(Val(:Full), xc[:, 1], p, T; callback = nothing)
		return sol1
	else # threaded version
		sol = prob.flow(Val(:Full), xc, p, prob.ds .* T)
		# return sol
		# we put all the simulations in the first one and return it
		for ii =2:M
			append!(sol[1].t, sol[1].t[end] .+ sol[ii].t)
			append!(sol[1].u.u, sol[ii].u.u)
		end
		return sol[1]
	end
end

function _getExtremum(psh::PoincareShootingProblem, x_bar::AbstractVector, par; ratio = 1, op = (max, maximum))
	# this function extracts the amplitude of the cycle
	M = getM(psh)
	Nm1 = div(length(x_bar), M)

	# reshape the period orbit guess
	x_barc = reshape(x_bar, Nm1, M)
	xc = similar(x_bar, Nm1 + 1, M)

	Th = eltype(x_bar)
	n = div(Nm1, ratio)

	if ~isParallel(psh)
		E!(psh.section, view(xc, :, 1), view(x_barc, :, 1), 1)
		# We need the callback to be active here!!!
		sol = @views psh.flow(Val(:Full), xc[:, 1], par, Inf64)
		mx = op[2](sol[1:n, :])
		for ii in 2:M
			E!(psh.section, view(xc, :, ii), view(x_barc, :, ii), ii)
			# We need the callback to be active here!!!
			sol = @views psh.flow(Val(:Full), xc[:, ii], par, Inf64)
			mx = op[1](mx, op[2](sol[1:n, :]))
		end
	else
		for ii in 1:M
			E!(psh.section, view(xc, :, ii), view(x_barc, :, ii), ii)
		end
		solOde =  psh.flow(Val(:Full), xc, par, repeat([Inf64], M) )
		mx = op[2](solOde[1].u[1:n, :])
		for ii in 1:M
			mx = op[1](mx, op[2](solOde[ii].u[1:n, :]))
		end
	end
	return mx
end

# Poincaré (multiple) shooting with hyperplanes parametrization
function (psh::PoincareShootingProblem)(x_bar::AbstractVector, par; verbose = false)
	M = getM(psh)
	Nm1 = div(length(x_bar), M)

	# reshape the period orbit guess
	x_barc = reshape(x_bar, Nm1, M)

	# TODO the following declaration of xc allocates. It would be better to make it inplace
	xc = similar(x_bar, Nm1 + 1, M)

	# variable to hold the result of the computations
	outc = similar(xc)

	# we extend the state space to be able to call the flow, so we fill xc
	#TODO create the projections on the fly
	for ii in 1:M
		E!(psh.section, view(xc, :, ii), view(x_barc, :, ii), ii)
	end

	if ~isParallel(psh)
		for ii in 1:M
			im1 = (ii == 1 ? M : ii - 1)
			# We need the callback to be active here!!!
			outc[:, ii] .= xc[:, ii] .- psh.flow(xc[:, im1], par, Inf64)
		end
	else
		solOde = psh.flow(xc, par, repeat([Inf64],M))
		for ii in 1:M
			im1 = (ii == 1 ? M : ii - 1)
			# We need the callback to be active here!!!
			@views outc[:, ii] .= xc[:, ii] .- solOde[im1][2]
		end
	end

	# build the array to be returned
	out_bar = similar(x_bar)
	out_barc = reshape(out_bar, Nm1, M)
	for i in 1:M
		R!(psh.section, view(out_barc, :, i), view(outc, :, i), i)
	end
	return out_bar
end

function diffPoincareMap(psh::PoincareShootingProblem, x, par, dx, ii::Int)
	normal = psh.section.normals[ii]
	abs(dot(normal, dx)) > 1e-12 && @warn "Vector does not belong to hyperplane!  dot(normal, dx) = $(abs(dot(normal, dx))) and $(dot(dx, dx))"
	# compute the Poincare map from x
	tΣ, solΣ = psh.flow(Val(:TimeSol), x, par, Inf64)
	z = psh.flow.F(solΣ, par)
	# solution of the variational equation at time tΣ
	# We need the callback to be INACTIVE here!!!
	y = psh.flow(x, par, dx, tΣ; callback = nothing).du
	out = y .- (dot(normal, y) / dot(normal, z)) .* z
end

# jacobian of the shooting functional
function (psh::PoincareShootingProblem)(x_bar::AbstractVector, par, dx_bar::AbstractVector)
	δ = psh.δ
	if δ > 0
		# mostly for debugging purposes
		return (psh(x_bar .+  δ .* dx_bar, par) .- psh(x_bar, par)) ./ δ
	end

	# otherwise analytical Jacobian
	M = getM(psh)
	Nm1 = div(length(x_bar), M)

	# reshape the period orbit guess
	x_barc  = reshape( x_bar, Nm1, M)
	dx_barc = reshape(dx_bar, Nm1, M)

	# variable to hold the computed result
	xc  = similar( x_bar, Nm1 + 1, M)
	dxc = similar(dx_bar, Nm1 + 1, M)
	outc = similar(xc)

	# we extend the state space to be able to call the flow, so we fill xc
	for ii in 1:M
		 E!(psh.section,  view(xc, :, ii),  view(x_barc, :, ii), ii)
		dE!(psh.section, view(dxc, :, ii), view(dx_barc, :, ii), ii)
	end

	if ~isParallel(psh)
		for ii in 1:M
			im1 = (ii == 1 ? M : ii - 1)
			@views outc[:, ii] .= dxc[:, ii] .- diffPoincareMap(psh, xc[:, im1], par, dxc[:, im1], im1)
		end
	else
		@assert 1==0 "Analytical Jacobian for parallel Poincare Shooting not implemented yet. Please use the option δ > 0."
	end

	# build the array to be returned
	out_bar = similar(x_bar)
	out_barc = reshape(out_bar, Nm1, M)
	for ii in 1:M
		dR!(psh.section, view(out_barc, :, ii), view(outc, :, ii), ii)
	end
	return out_bar
end

####################################################################################################
# functions needed for Branch switching from Hopf bifurcation point
function updateForBS(prob::PoincareShootingProblem, F, dF, hopfpt, ζr, centers, period)
	# make the section
	normals = [F(u, hopfpt.params) for u in centers]
	for n in normals; n ./= norm(n); end

	@assert ~(prob.flow isa Flow) "Somehow, this method was not called as it should. prob.flow should be a Named Tuple, prob should be constructed with the simple constructor, not yielding a Flow for its flow field."

	# update the problem
	if length(prob.flow) == 3
	probPSh = PoincareShootingProblem(F, prob.flow.par, prob.flow.prob, prob.flow.alg, normals, centers)
	else
		probPSh = PoincareShootingProblem(F, prob.flow.par, prob.flow.prob1, prob.flow.alg1, prob.flow.prob2, prob.flow.alg2, normals, centers)
	end

	# create initial guess. We have to pass it through the projection R
	hyper = probPSh.section
	M = getM(probPSh)
	orbitguess_bar = zeros(length(centers[1])-1, M)
	for ii=1:length(normals)
		orbitguess_bar[:, ii] .= R(hyper, centers[ii], ii)
	end

	return probPSh, vec(orbitguess_bar)
end