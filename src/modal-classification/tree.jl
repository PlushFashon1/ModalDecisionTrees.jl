# The code in this file is a small port from scikit-learn's and numpy's
# library which is distributed under the 3-Clause BSD license.
# The rest of DecisionTree.jl is released under the MIT license.

# written by Poom Chiarawongse <eight1911@gmail.com>

module treeclassifier
	
	export fit

	using ..ModalLogic
	using ..DecisionTree
	using DecisionTree.util
	
	import Random

	mutable struct NodeMeta{S<:Real} # {S,U}
		features    :: Vector{Int}      # a list of features
		region      :: UnitRange{Int}   # a slice of the samples used to decide the split of the node
		# worlds      :: AbstractVector{WorldSet{W}} # current set of worlds for each training instance
		depth       :: Int
		modal_depth :: Int
		is_leaf     :: Bool             # whether this is a leaf node, or a split one
		label       :: Label            # most likely label
		# split properties
		split_at    :: Int              # index of samples
		l           :: NodeMeta{S}      # left child
		r           :: NodeMeta{S}      # right child
		# purity      :: U              # purity grade attained if this is a split
		modality         :: R where R<:AbstractRelation # modal operator (e.g. RelationId for the propositional case)
		feature          :: Int                      # feature used for splitting
		test_operator    :: ModalLogic.TestOperator  # test_operator (e.g. <=)
		threshold        :: S                        # threshold value
		function NodeMeta{S}(
				region      :: UnitRange{Int},
				depth       :: Int,
				modal_depth :: Int
				) where S<:Real
			node = new{S}()
			node.region = region
			node.depth = depth
			node.modal_depth = modal_depth
			node.is_leaf = false
			node
		end
	end

	struct Tree{S, T}
		root           :: NodeMeta{S}
		list           :: Vector{T}
		labels         :: Vector{Label}
		initCondition  :: DecisionTree._initCondition
	end

	@inline setfeature!(i::Integer, ud::MatricialUniDataset{T,1}, d::MatricialDataset{T,2}, idx::Integer, feature::Integer) where T = begin
		@views ud[i] = ModalLogic.getFeature(d, idx, feature) # ::T
	end
	@inline setfeature!(i::Integer, ud::MatricialUniDataset{T,2}, d::MatricialDataset{T,3}, idx::Integer, feature::Integer) where T = begin
		@views ud[:,i] = ModalLogic.getFeature(d, idx, feature) # ::AbstractArray{T,2}
	end
	@inline setfeature!(i::Integer, ud::MatricialUniDataset{T,3}, d::MatricialDataset{T,4}, idx::Integer, feature::Integer) where T = begin
		@views ud[:,:,i] = ModalLogic.getFeature(d, idx, feature) # ::AbstractArray{T,3}
	end
	# TODO:
	# @inline setfeature!(i::Integer, Xf::AbstractArray{T, M}, X::OntologicalDataset{T,N}, idx::Integer, feature::Integer) where {T,N,M} = begin
		# Xf[i,[(:) for i in 1:N]...] = ModalLogic.getFeature(X, idx, feature)
	# end

	# find an optimal split satisfying the given constraints
	# (e.g. max_depth, min_samples_leaf, min_purity_increase)
	# TODO not using max_features, rng (which is still useful e.g. rand(rng, 1:10)) anymore
	function _split!(
							X                   :: OntologicalDataset{T, N}, # the ontological dataset
							Y                   :: AbstractVector{Label},    # the label array
							W                   :: AbstractVector{U},        # the weight vector
							S                   :: AbstractVector{WorldSet{WorldType}}, # the vector of current worlds (TODO AbstractVector{<:AbstractSet{X.ontology.worldType}})
							
							purity_function     :: Function,
							node                :: NodeMeta{T},              # the node to split
							# max_features        :: Int,                      # number of features to consider
							max_depth           :: Int,                      # the maximum depth of the resultant tree
							min_samples_leaf    :: Int,                      # the minimum number of samples each leaf needs to have
							min_purity_increase :: AbstractFloat,            # minimum purity increase needed for a split
							max_purity_split    :: AbstractFloat,            # maximum purity allowed on a split
							test_operators      :: AbstractVector{<:ModalLogic.TestOperator},
							p_test_operators    :: AbstractVector{<:ModalLogic.TestOperator},

							indX                :: AbstractVector{Int},      # an array of sample indices (we split using samples in indX[node.region])
							
							# The six arrays below are given for optimization purposes
							
							nc                  :: AbstractVector{U},   # nc maintains a dictionary of all labels in the samples
							ncl                 :: AbstractVector{U},   # ncl maintains the counts of labels on the left
							ncr                 :: AbstractVector{U},   # ncr maintains the counts of labels on the right
							
							Xf                  :: MatricialUniDataset{T, M},
							Yf                  :: AbstractVector{Label},
							Wf                  :: AbstractVector{U},
							Sf                  :: AbstractVector{WorldSet{WorldType}},
							# Sogliole            :: AbstractVector{<:AbstractDict{<:ModalLogic.AbstractRelation,<:AbstractVector{<:AbstractDict{WorldType,Tuple{T,T}}}}},
							# Sogliole            :: TODO Union with AbstractArray{<:AbstractDict{WorldType,Tuple{T,T}},3},
							Sogliole            :: AbstractArray{Tuple{T,T},L},
							# TODO Ef                  :: AbstractArray{T},
							
							rng                 :: Random.AbstractRNG,
							relationSet         :: Vector{<:ModalLogic.AbstractRelation},
							indR                :: AbstractVector{Int},
							) where {WorldType<:AbstractWorld, T, U, N, M,L}  # WT<:X.ontology.worldType

		# Region of indx to use to perform the split
		region = node.region
		n_samples = length(region)
		r_start = region.start - 1

		# Class counts
		nc[:] .= zero(U)
		@simd for i in region
			@inbounds nc[Y[indX[i]]] += W[indX[i]]
		end
		nt = sum(nc)
		node.label = argmax(nc) # Assign the most likely label before the split

		# Check leaf conditions
		if (min_samples_leaf * 2 >  n_samples
		 || nc[node.label]       == nt
		 || nc[node.label] / nt  >= max_purity_split # TODO this purity has to be the purity function, not the number of training samples.
		 || max_depth            <= node.depth)
			node.is_leaf = true
			return
		end

		# Gather all values needed for the current set of instances
		@simd for i in 1:n_samples
			Yf[i] = Y[indX[i + r_start]]
			Wf[i] = W[indX[i + r_start]]
			Sf[i] = S[indX[i + r_start]]
		end

		# Optimization tracking variables
		best_purity = typemin(U)
		best_relation = ModalLogic.RelationNone
		best_feature = -1
		best_test_operator = ModalLogic.TestOpNone
		best_threshold = T(-1)
		# threshold_lo = ...
		# threshold_hi = ...

		# true if every feature is constant
		unsplittable = true
		
		#####################
		## Find best split ##
		#####################

		# For each variable
		feature = 1
		@inbounds while feature <= n_variables(X) # && unsplittable # TODO Uncomment this to stop at the first valid split encountered for any feature
			
			# Gather all values needed for the current feature
			@simd for i in 1:n_samples
				# TODO make this a view? featureview?
				setfeature!(i, Xf, X.domain, indX[i + r_start], feature)
			end

			## Test all conditions
			# For each relational operator
			for relation_id in indR
				relation = relationSet[relation_id]
				@info "Testing relation " relation

				########################################################################
				########################################################################
				########################################################################
				# Find, for each instance, the highest value for any world
				#                       and the lowest value for any world
				# @info "Computing peaks..." # channel
				# opGeqMaxThresh_old     = fill(typemin(T), n_samples)
				# opLesMinThresh_old     = fill(typemax(T), n_samples)
				# for i in 1:n_samples
				# 	# if relation == ModalLogic.Topo_TPP println("relation ", relation, " ", relation_id) end
				# 	# if relation == ModalLogic.Topo_TPP println("instance ", i) end
				# 	# if relation == ModalLogic.Topo_TPP println("Sf[i] ", Sf[i]) end
				# 	channel = ModalLogic.getChannel(Xf, i)
				# 	# if relation == ModalLogic.Topo_TPP println("channel ", channel) end
				# 	# @info " instance $i/$n_samples" # channel
				# 	# TODO this findmin/findmax can be made more efficient, and even more efficient for intervals.
				# 	for w in ModalLogic.enumAcc(Sf[i], relation, channel)
				# 		# if relation == ModalLogic.Topo_TPP println("world ", w) end
				#     TODO expand this code to multiple test_operators
				# 		(_wmin,_wmax) = ModalLogic.WExtrema(test_operators, w, channel)
				# 		# if relation == ModalLogic.Topo_TPP println("wmin, wmax ", _wmin, " ", _wmax) end
				# 		opGeqMaxThresh_old[i] = max(opGeqMaxThresh_old[i], _wmin)
				# 		opLesMinThresh_old[i] = min(opLesMinThresh_old[i], _wmax)
				# 	end
				# 	# if relation == ModalLogic.Topo_TPP println("opGeqMaxThresh_old ", opGeqMaxThresh_old[i]) end
				# 	# if relation == ModalLogic.Topo_TPP println("opLesMinThresh_old ", opLesMinThresh_old[i]) end
				# end

				########################################################################
				########################################################################
				########################################################################

				opGeqMaxThresh = fill(typemin(T), n_samples)
				opLesMinThresh = fill(typemax(T), n_samples)

				if relation != ModalLogic.RelationAll
					for i in 1:n_samples
						# if relation == ModalLogic.Topo_TPP println("relation ", relation, " ", relation_id) end
						# if relation == ModalLogic.Topo_TPP println("instance ", i) end
						# if relation == ModalLogic.Topo_TPP println("Sf[i] ", Sf[i]); channel = ModalLogic.getChannel(Xf, i) end
						# if relation == ModalLogic.Topo_TPP println("channel ", channel) end
						# TODO slice Sogliole in Sogliolef?
						@info " instance $(i)/$(n_samples)" indX[i + r_start] # Sogl
						for w in Sf[i]
							# if relation == ModalLogic.Topo_TPP println("world ", w) end
							(w_opGeqMaxThresh,w_opLesMinThresh) = readSogliole(Sogliole, w, indX[i + r_start], relation_id, feature)
							# if relation == ModalLogic.Topo_TPP println("w_opGeqMaxThresh, w_opLesMinThresh ", w_opGeqMaxThresh, " ", w_opLesMinThresh) end
							@info "wmin,wmax " w w_opGeqMaxThresh w_opLesMinThresh
							opGeqMaxThresh[i] = max(opGeqMaxThresh[i], w_opGeqMaxThresh)
							opLesMinThresh[i] = min(opLesMinThresh[i], w_opLesMinThresh)
						end
						# if relation == ModalLogic.Topo_TPP println("opGeqMaxThresh ", opGeqMaxThresh[i]) end
						# if relation == ModalLogic.Topo_TPP println("opLesMinThresh ", opLesMinThresh[i]) end
					end
				else
					# TODO check and improve, at least this computation should be easier
					for i in 1:n_samples
						# @views Sogl = readSogliole(Sogliole, indX[i + r_start], 1, feature) # TODO relationId_id = 1 (ModalLogic.RelationId)
						for w in ModalLogic.enumAcc(worldType[], ModalLogic.RelationAll, channel)
							(w_opGeqMaxThresh,w_opLesMinThresh) = readSogliole(Sogliole, w, indX[i + r_start], 1, feature)
							opGeqMaxThresh[i] = max(opGeqMaxThresh[i], w_opGeqMaxThresh)
							opLesMinThresh[i] = min(opLesMinThresh[i], w_opLesMinThresh)
						end
					end
				end
				@info "Thresh " opGeqMaxThresh opLesMinThresh

				# if ! (all(opGeqMaxThresh .== opGeqMaxThresh_old) && all(opLesMinThresh .== opLesMinThresh_old))
				# 	println("Thresholds computation is incorrect (relation=$(relation)):")
				# 	# println("$(opGeqMaxThresh), $(opGeqMaxThresh_old)")
				# 	# println("$(opLesMinThresh), $(opLesMinThresh_old)")
				# 	for (i,tup) in enumerate(zip(opGeqMaxThresh, opGeqMaxThresh_old, opLesMinThresh, opLesMinThresh_old))
				# 		if length(unique(tup[[1,2]])) > 1 && length(unique(tup[[2,3]])) > 1
				# 			channel = ModalLogic.getChannel(Xf, i)
				# 			println("relation ", relation)
				# 			println("instance ", i)
				# 			println("Sf[i] ", Sf[i])
				# 			println("channel ", channel)
				# 			println("opGeqMaxThresh ", opGeqMaxThresh[i])
				# 			println("opGeqMaxThresh_old ", opGeqMaxThresh_old[i])
				# 			println("opLesMinThresh ", opLesMinThresh[i])
				# 			println("opLesMinThresh_old ", opLesMinThresh_old[i])
				# 		end
				# 	end
				# 	@assert all(opGeqMaxThresh .== opGeqMaxThresh_old) "opGeqMaxThresh computation is incorrect (relation=$(relation)):\n$(opGeqMaxThresh), $(opGeqMaxThresh_old)"
				# 	@assert all(opLesMinThresh .== opLesMinThresh_old) "opLesMinThresh computation is incorrect (relation=$(relation)):\n$(opLesMinThresh), $(opLesMinThresh_old)"
				# end

				# @info "  (maxPeak,minPeak) $opLesMinThresh,$opGeqMaxThresh"
				
				# TODO sort this and optimize?
				# Obtain the list of reasonable thresholds
				thresholdDomain = setdiff(union(Set(opGeqMaxThresh),Set(opLesMinThresh)),Set([typemin(T), typemax(T)]))
				@info "thresholdDomain " thresholdDomain

				# Look for thresholds 'a' for the propositions like "feature >= a"
				for threshold in thresholdDomain
					# Look for the correct test operator
					for test_operator in (relation == ModalLogic.RelationId ? p_test_operators : test_operators)
						@info " test condition: $(ModalLogic.display_modal_test(relation, test_operator, feature, threshold))"
						# Re-initialize right class counts
						@info " Testing..."
						nr = zero(U)
						ncr[:] .= zero(U)
						for i in 1:n_samples
							@info " instance $i/$n_samples ExtremeThresh ($(opGeqMaxThresh[i])/$(opLesMinThresh[i]))"
							satisfied = true
							# No world to go
							if opGeqMaxThresh[i] == typemin(T) # && opGeqMaxThresh[i] == typemax(T)
								# @info "   NO!"
								satisfied = false
							elseif test_operator == ModalLogic.TestOpGeq && ! (threshold <= opGeqMaxThresh[i])
								# @info "   YES!!!"
								satisfied = false
							elseif test_operator == ModalLogic.TestOpLes && ! (threshold > opLesMinThresh[i])
								# @info "   YES!!!"
								satisfied = false
							end
							
							if !satisfied
								@info "NO"
								nr += Wf[i]
								ncr[Yf[i]] += Wf[i]
							else
								@info "YES"
							end
						end

						# Calculate left class counts
						@simd for lab in 1:length(nc) # TODO something like @simd ncl .= nc - ncr instead
							ncl[lab] = nc[lab] - ncr[lab]
						end
						nl = nt - nr
						@info " (n_left,n_right) = ($nl,$nr)\n"

						# Honor min_samples_leaf
						if nl >= min_samples_leaf && n_samples - nl >= min_samples_leaf
							unsplittable = false
							# TODO what is this purity?
							purity = -(nl * purity_function(ncl, nl) +
								      	 nr * purity_function(ncr, nr))
							@info " purity = " purity
							if purity > best_purity && !isapprox(purity, best_purity)
								best_purity    = purity
								best_relation  = relation
								best_feature   = feature
								best_test_operator  = test_operator # TODO expand
								best_threshold = threshold
								# TODO: At the end, we should take the average between current and last.
								#  This requires thresholds to be sorted
								# threshold_lo, threshold_hi  = last_f, curr_f
								@info " new optimum:"
								@info " best_purity = " best_purity
								@info " " best_relation
								@info ", " best_feature
								@info ", " best_test_operator
								@info ", " best_threshold
								# @info threshold_lo, threshold_hi
							end
						end
					end # for test_operator
				end # for threshold
			end # for relation
			feature += 1
		end # while feature

		# If the split is good, partition and split according to the optimum
		@inbounds if (unsplittable # no splits honor min_samples_leaf
			|| (best_purity / nt + purity_function(nc, nt) < min_purity_increase))
			@info " LEAF" (best_purity / nt)
			node.is_leaf = true
			return
		else
			@info " BRANCH" (best_purity / nt)
			# try
			# 	node.threshold = (threshold_lo + threshold_hi) / 2.0
			# catch
			# 	node.threshold = threshold_hi
			# end

			# split the samples into two parts:
			# - ones that are > threshold
			# - ones that are <= threshold

			# node.purity    = best_purity
			node.modality       = best_relation
			node.feature        = best_feature
			node.test_operator  = best_test_operator
			node.threshold      = best_threshold

			@info " Best test condition: $(ModalLogic.display_modal_test(best_relation, best_test_operator, best_feature, best_threshold)) (purity $(best_purity))"

			println("Split $(n_samples) samples: $(ModalLogic.display_modal_test(best_relation, best_test_operator, best_feature, best_threshold)) (purity $(best_purity))")
			
			# Compute new world sets (= make a modal step)
			@simd for i in 1:n_samples
				setfeature!(i, Xf, X.domain, indX[i + r_start], best_feature)
			end
			# TODO instead of using memory, here, just use two opposite indices and perform substitutions. indj = n_samples
			unsatisfied_flags = fill(1, n_samples)
			for i in 1:n_samples
				channel = ModalLogic.getChannel(Xf, i)
				@info " instance $(i)/$(n_samples)" channel Sf[i]
				(satisfied,S[indX[i + r_start]]) = ModalLogic.modalStep(Sf[i], best_relation, channel, best_test_operator, best_threshold)
				unsatisfied_flags[i] = !satisfied # I'm using unsatisfied because then sorting puts YES instances first but TODO use the inverse sorting and use satisfied flag instead
			end
			@info " unsatisfied_flags" unsatisfied_flags

			@assert length(unique(unsatisfied_flags)) > 1 "Uninformative split. Something's wrong with the optimization steps."
			@info "pre-partition" region indX[region] unsatisfied_flags[:]
			# println(unsatisfied_flags)
			node.split_at = util.partition!(indX, unsatisfied_flags, 0, region)
			@info "post-partition" indX[region] node.split_at

			# For debug:
			# indX = rand(1:10, 10)
			# unsatisfied_flags = rand([1,0], 10)
			# partition!(indX, unsatisfied_flags, 0, 1:10)
			
			# Sort [Xf, Yf, Wf, Sf and indX] by Xf
			# util.q_bi_sort!(unsatisfied_flags, indX, 1, n_samples, r_start)
			# node.split_at = searchsortedfirst(unsatisfied_flags, true)
		end
	end
	# Split node at a previously-set node.split_at value.
	# The children inherits some of the data
	@inline function fork!(node::NodeMeta{S}) where S
		ind = node.split_at
		region = node.region
		depth = node.depth+1
		# println(ind)
		# println(region)
		mdepth = (node.modality == ModalLogic.RelationNone ? node.modal_depth : node.modal_depth+1)
		# no need to copy because we will copy at the end
		node.l = NodeMeta{S}(region[    1:ind], depth, mdepth)
		node.r = NodeMeta{S}(region[ind+1:end], depth, mdepth)
	end

	include("compute-thresholds.jl")

	function check_input(
			X                   :: OntologicalDataset{T, N},
			Y                   :: AbstractVector{Label},
			W                   :: AbstractVector{U},
			# max_features        :: Int,
			max_depth           :: Int,
			min_samples_leaf    :: Int,
			min_purity_increase :: AbstractFloat,
			max_purity_split    :: AbstractFloat) where {T, U, N}
			n_instances, n_vars = n_samples(X), n_variables(X)
		if length(Y) != n_instances
			throw("dimension mismatch between X and Y ($(size(X.domain)) vs $(size(Y))")
		elseif length(W) != n_instances
			throw("dimension mismatch between X and W ($(size(X.domain)) vs $(size(W))")
		elseif max_depth < -1
			throw("unexpected value for max_depth: $(max_depth) (expected:"
				* " max_depth >= 0, or max_depth = -1 for infinite depth)")
		# elseif n_vars < max_features
			# throw("number of features $(n_vars) is less than the number "
				# * "of max features $(max_features)")
		# elseif max_features < 0
			# throw("number of features $(max_features) must be >= zero ")
		elseif min_samples_leaf < 1
			throw("min_samples_leaf must be a positive integer "
				* "(given $(min_samples_leaf))")
		elseif max_purity_split > 1.0 || max_purity_split <= 0.0
			throw("max_purity_split must be in (0,1]"
				* "(given $(max_purity_split))")
		end
		# TODO check that X doesn't have nans, typemin(T), typemax(T), missings, nothing etc. ...
	end

	function _fit(
			X                       :: OntologicalDataset{T, N},
			Y                       :: AbstractVector{Label},
			W                       :: AbstractVector{U},
			loss                    :: Function,
			n_classes               :: Int,
			# max_features            :: Int,
			max_depth               :: Int,
			min_samples_leaf        :: Int, # TODO generalize to min_samples_leaf_relative and min_weight_leaf
			min_purity_increase     :: AbstractFloat,
			max_purity_split        :: AbstractFloat,
			initCondition           :: DecisionTree._initCondition,
			test_operators          :: AbstractVector{<:ModalLogic.TestOperator},
			rng = Random.GLOBAL_RNG :: Random.AbstractRNG) where {T, U, N}

		# Dataset sizes
		n_instances = n_samples(X)

		# Array memory for class counts
		nc  = Vector{U}(undef, n_classes)
		ncl = Vector{U}(undef, n_classes)
		ncr = Vector{U}(undef, n_classes)

		# TODO We need to write on S, thus it cannot be a static array like X Y and W;
		# Should belong inside each meta-node and then be copied? That's a waste of space(for each instance),
		# We only need the worlds for the currentinstance set.
		# What if it's not fixed size? Maybe it should be like the subset of indX[region], so that indX[region.start] is parallel to node.S[1]
		# TODO make the initial entity and initial modality a training parameter?
		#  But then you have to know that at test time as well... So it must be part of the tree in some way
		#  TODO Maybe it's enough to just create a default constructor for any world type.

		w0params =
			if initCondition == startWithRelationAll
				[ModalLogic.emptyWorld]
			elseif initCondition == startAtCenter
				[ModalLogic.centeredWorld, channel_size(X)...]
		end
		S = WorldSet{X.ontology.worldType}[[X.ontology.worldType(w0params...)] for i in 1:n_instances]

		# Array memory for dataset
		Xf = Array{T, N+1}(undef, channel_size(X)..., n_instances)
		Yf = Vector{Label}(undef, n_instances)
		Wf = Vector{U}(undef, n_instances)
		# TODO Maybe it's worth to allocate this vector as well?
		Sf = Vector{WorldSet{X.ontology.worldType}}(undef, n_instances)

		# Binary relations (= unary modal operators)
		# Note: the equality operator is the first, and is the one representing
		#  the propositional case.
		relationSet = [ModalLogic.RelationId, ModalLogic.RelationAll, (X.ontology.relationSet)...]
		relationId_id = 1
		relationAll_id = 2
		relation_ids = map((x)->x+2, 1:length(X.ontology.relationSet))

		# Note: in the propositional case, some pairs of operators (e.g. <= and >)
		#  are complementary, and thus it is redundant to check both at the same node.
		#  We avoid this by creating a dedicated set of relations for propositional splits
		# TODO optimize this: use opposite_test_operator() to check pairs.
		# TODO First, check that TestOpGeq095 and TestOpLes095 are actually complementary
		propositional_test_operators = 
			if [ModalLogic.TestOpGeq, ModalLogic.TestOpLes] ⊆ test_operators
				filter!(e->e ≠ ModalLogic.TestOpLes,test_operators)
			else
				test_operators
			end
		
		# TODO use Ef = Dict(X.ontology.worldType,Tuple{T,T})
		# Fill with ModalLogic.enumAcc(Sf[i], ModalLogic.RelationAll, channel)... 
		# TODO Ef = Array{T,1+worldTypeSize(X.ontology.worldType)}(undef, )

		# Calculate Sogliole
		# TODO expand for generic test operators
		# TODO test with array-only Sogliole = Array{T, 4}(undef, 2, n_worlds(X.ontology.worldType, channel_size(X)), n_instances, n_variables(X))
		# TODO try something like Sogliole = fill(No: Dict{X.ontology.worldType,Tuple{T,T}}(), n_instances, n_variables(X))
		
		# TODO improve code leveraging world/dimensional dataset structure

		# Sogliole = Vector{Dict{ModalLogic.AbstractRelation,Vector{Dict{X.ontology.worldType,Tuple{T,T}}}}}(undef, n_variables(X))
		println("Computing Sogliole...")
		
		@info " Computing Sogliole..."
		# TODO maybe use offset-arrays? https://docs.julialang.org/en/v1/devdocs/offset-arrays/
		Sogliole = computeSogliole(X,X.ontology.worldType,test_operators,relationSet,relationId_id,relation_ids)

		# println(Sogliole)

		# Sample indices (array of indices that will be sorted and partitioned across the leaves)
		indX = collect(1:n_instances)
		# Create root node
		root = NodeMeta{T}(1:n_instances, 0, 0)
		# Stack of nodes to process
		stack = Tuple{NodeMeta{T},Bool}[(root,(initCondition == startWithRelationAll))]
		# The first iteration is treated sightly differently
		@inbounds while length(stack) > 0
			# Pop node and process it
			(node,onlyUseRelationAll) = pop!(stack)
			_split!(
				X, Y, W, S,
				loss, node,
				# max_features,
				max_depth,
				min_samples_leaf,
				min_purity_increase,
				max_purity_split,
				test_operators,
				propositional_test_operators,
				indX,
				nc, ncl, ncr, Xf, Yf, Wf, Sf, Sogliole,
				rng,
				relationSet,
				(onlyUseRelationAll ? [relationAll_id] : [relationId_id, relation_ids...])
				)
			# After processing, if needed, perform the split and push the two children for a later processing step
			if !node.is_leaf
				fork!(node)
				# Note: the left (positive) child is not limited to RelationAll, whereas the right child is only if the current node is as well.
				push!(stack, (node.l, false))
				push!(stack, (node.r, onlyUseRelationAll))
			end
		end

		return (root, indX)
	end

	function fit(;
			# In the modal case, dataset instances are Kripke models.
			# In this implementation, we don't accept a generic Kripke model in the explicit form of
			#  a graph; instead, an instance is a dimensional domain (e.g. a matrix or a 3D matrix) onto which
			#  worlds and relations are determined by a given Ontology.
			X                       :: OntologicalDataset{T, N},
			Y                       :: AbstractVector{S},
			W                       :: Union{Nothing, AbstractVector{U}},
			loss = util.entropy     :: Function,
			# max_features            :: Int, # TODO remove this parameter
			max_depth               :: Int,
			min_samples_leaf        :: Int,
			min_samples_split       :: Int,
			min_purity_increase     :: AbstractFloat,
			max_purity_split        :: AbstractFloat, # TODO add this to scikit's interface.
			initCondition           :: DecisionTree._initCondition,
			test_operators          :: AbstractVector{<:ModalLogic.TestOperator} = [ModalLogic.TestOpGeq, ModalLogic.TestOpLes],
			rng = Random.GLOBAL_RNG :: Random.AbstractRNG) where {T, S, U, N}

		# Obtain the dataset's "outer size": number of samples and number of features
		n_instances = n_samples(X)

		# Translate labels to categorical form
		labels, Y_ = util.assign(Y)

		min_samples_leaf = min(min_samples_leaf, div(min_samples_split, 2))

		# Use unary weights if no weight is supplied
		if W == nothing
			# TODO optimize w in the case of all-ones: write a subtype of AbstractVector:
			#  AllOnesVector, so that getindex(W, i) = 1 and sum(W) = size(W).
			#  This allows the compiler to optimize constants at compile-time
			W = fill(1, n_instances)
		end

		# Check validity of the input
		check_input(
			X, Y, W,
			# max_features,
			max_depth,
			min_samples_leaf,
			min_purity_increase,
			max_purity_split)

		# Call core learning function
		root, indX = _fit(
			X, Y_, W,
			loss,
			length(labels),
			# max_features,
			max_depth,
			min_samples_leaf,
			min_purity_increase,
			max_purity_split,
			initCondition,
			test_operators,
			rng)

		return Tree{T, S}(root, labels, indX, initCondition)
	end
end
