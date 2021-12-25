################################################################################
################################################################################
################################## Scan script #################################
################################################################################
################################################################################

include("scanner.jl")

using NEVArt

using Catch22
using DataStructures

include("dataset-analysis.jl")

train_seed = 2

################################################################################
############################# SUPERVISED MODE ##################################
################################################################################

supervised_mode = :classification
# supervised_mode = :regression

################################################################################
################################################################################
################################################################################

################################################################################
#################################### FOLDERS ###################################
################################################################################

results_dir = "./NEVArt/journal-v4-feature-selection-$(supervised_mode)"

iteration_progress_json_file_path = results_dir * "/progress.json"
data_savedir  = results_dir * "/data_cache"
model_savedir = results_dir * "/models_cache"
selected_features_savedir = results_dir * "/selected_features_cache"

dry_run = false
# dry_run = :dataset_only
# dry_run = :model_study
# dry_run = true

skip_training = false

# save_datasets = true
save_datasets = false

perform_consistency_check = false # true #  = false

iteration_blacklist = []

################################################################################
##################################### TREES ####################################
################################################################################

# Optimization arguments for single-tree
tree_args = [
#	(
#		loss_function = nothing,
#		min_samples_leaf = 1,
#		min_purity_increase = 0.01,
#		max_purity_at_leaf = 0.6,
#	)
]

if supervised_mode == :regression
	for loss_function in [nothing]
		for min_samples_leaf in [3] # TODO try other values of this if the number of instances changes
			for min_purity_increase in [0.02]
				for max_purity_at_leaf in [0.001]
					push!(tree_args,
						(
							loss_function       = loss_function,
							min_samples_leaf    = min_samples_leaf,
							min_purity_increase = min_purity_increase,
							max_purity_at_leaf  = max_purity_at_leaf,
							perform_consistency_check = perform_consistency_check,
						)
					)
				end
			end
		end
	end
elseif supervised_mode == :classification
	for loss_function in [nothing]
		for min_samples_leaf in [2,4] # [1,2]
			for min_purity_increase in [0.01] # [0.01, 0.001]
				for max_purity_at_leaf in [0.4, 0.5, 0.6] # [0.4, 0.6]
					push!(tree_args,
						(
							loss_function       = loss_function,
							min_samples_leaf    = min_samples_leaf,
							min_purity_increase = min_purity_increase,
							max_purity_at_leaf  = max_purity_at_leaf,
							perform_consistency_check = perform_consistency_check,
						)
					)
				end
			end
		end
	end
else
	throw(ExceptionError("Invalid `supervised_mode` passed: `:$(supervised_mode)`"))
end

println(" $(length(tree_args)) trees")

################################################################################
#################################### FORESTS ###################################
################################################################################

forest_runs = 5
# optimize_forest_computation = false
optimize_forest_computation = true


forest_args = []

# for n_trees in []
for n_trees in [50]
	for n_subfeatures in [half_f]
		for n_subrelations in [id_f]
			for partial_sampling in [0.7]
				push!(forest_args, (
					n_subfeatures       = n_subfeatures,
					n_trees             = n_trees,
					partial_sampling    = partial_sampling,
					n_subrelations      = n_subrelations,
					# Optimization arguments for trees in a forest (no pruning is performed)
					loss_function       = nothing,
					# min_samples_leaf    = 1,
					# min_purity_increase = 0.0,
					# max_purity_at_leaf  = Inf,
					perform_consistency_check = perform_consistency_check,
				))
			end
		end
	end
end


println(" $(length(forest_args)) forests " * (length(forest_args) > 0 ? "(repeated $(forest_runs) times)" : ""))

################################################################################
################################## MODAL ARGS ##################################
################################################################################

modal_args = (;
	initConditions = DecisionTree.startWithRelationGlob,
	# initConditions = DecisionTree.startAtCenter,
	# allowRelationGlob = true,
	allowRelationGlob = false,
)

data_modal_args = [
# (;
# 	ontology = getIntervalOntologyOfDim(Val(1)),
# 	ontology = getIntervalOntologyOfDim(Val(2)),
# 	ontology = Ontology{ModalLogic.Interval}([ModalLogic.IA_A]),
# 	ontology = Ontology{ModalLogic.Interval}([ModalLogic.IA_A, ModalLogic.IA_L, ModalLogic.IA_Li, ModalLogic.IA_D]),
# )
]


################################################################################
##################################### MISC #####################################
################################################################################

# log_level = Logging.Warn
log_level = DecisionTree.DTOverview
# log_level = DecisionTree.DTDebug
# log_level = DecisionTree.DTDetail

# timing_mode = :none
timing_mode = :time
# timing_mode = :btime
#timing_mode = :profile

round_dataset_to_datatype = false
# round_dataset_to_datatype = UInt8
# round_dataset_to_datatype = UInt16
# round_dataset_to_datatype = UInt32
# round_dataset_to_datatype = UInt64
# round_dataset_to_datatype = Float16
# round_dataset_to_datatype = Float32
# round_dataset_to_datatype = Float64

n_cv_folds = 7

# split_threshold_regression = 0.8
split_threshold_regression = 1.0
# split_threshold_regression = false

split_threshold_classification = 0.8
# split_threshold_classification = 1.0
# split_threshold_classification = false

# use_training_form = :dimensional
# use_training_form = :fmd
# use_training_form = :stump
# use_training_form = :stump_with_memoization

test_flattened = false
test_averaged  = false

################################################################################
##################################### SCAN #####################################
################################################################################

exec_dataseed = 1:n_cv_folds

# exec_use_training_form = [:dimensional]
exec_use_training_form = [:stump_with_memoization]

EEG_default = (nbands = 60, wintime = 0.05, steptime = 0.025)
ECG_default = (nbands = 30, wintime = 0.025, steptime = 0.0175)

# attributes selection
exec_n_desired_attributes = [10, 25]
exec_n_desired_features   = [5]

savefigs = true
# savefigs = false

perform_target_aware_analysis = false
# perform_target_aware_analysis = true

exec_convert_to_class_ttest = [(Tuple{Int8}(25), ("NO", "YES")), nothing, (Tuple{Int8, Int8}([17, 34]), ("NO", "MAYBE", "YES"))]

exec_dataset_params = [
	# (ids,signals,lables,static_attrs,signal_transformation,keep_only_bands,classification_splits,force_single_frame)
	("sure-v1",[:EEG],["liked"],String[],Dict{Symbol,NamedTuple}(:EEG => EEG_default),Dict{Symbol,Union{Vector{Int64},Symbol}}(:EEG => :auto),(25,),false),
	("sure-v1",[:EEG],["liked"],String[],Dict{Symbol,NamedTuple}(:EEG => EEG_default),Dict{Symbol,Union{Vector{Int64},Symbol}}(:EEG => :auto),(17,34),false),
	("sure-v1",[:EEG],["liked"],String[],Dict{Symbol,NamedTuple}(:EEG => EEG_default),Dict{Symbol,Union{Vector{Int64},Symbol}}(:EEG => collect(1:25)),(25,),false),
	("sure-v1",[:EEG],["liked"],String[],Dict{Symbol,NamedTuple}(:EEG => EEG_default),Dict{Symbol,Union{Vector{Int64},Symbol}}(:EEG => collect(1:25)),(17,34),false),

	# ("sure-v1",[:EEG],["liked"],String[],Dict{Symbol,NamedTuple}(:EEG => EEG_default),Dict{Symbol,Union{Vector{Int64},Symbol}}(:EEG => collect(1:25)),nothing,false),
	# ("sure-v1",[:ECG],["liked"],String[],Dict{Symbol,NamedTuple}(:ECG => ECG_default),Dict{Symbol,Union{Vector{Int64},Symbol}}(:ECG => collect(1:7)),nothing,false),

	# ("sure-v1",[:EEG,:ECG],["liked"],String[],Dict{Symbol,NamedTuple}(:EEG => EEG_default, :ECG => ECG_default),Dict{Symbol,Union{Vector{Int64},Symbol}}(:EEG => collect(1:25), :ECG => collect(1:7)),nothing,false),
	# ("sure-v1",[:EEG,:ECG],["liked"],String[],Dict{Symbol,NamedTuple}(:EEG => EEG_default, :ECG => ECG_default),Dict{Symbol,Union{Vector{Int64},Symbol}}(:EEG => collect(1:25), :ECG => collect(1:7)),nothing,true),

	# ("sure-v1",[:EEG,:ECG],["liked"],String[],Dict{Symbol,NamedTuple}(:EEG => EEG_default, :ECG => ECG_default),Dict{Symbol,Union{Vector{Int64},Symbol}}(:EEG => :auto, :ECG => :auto),nothing,false),
	# ("sure-v1",[:EEG,:ECG],["liked"],String[],Dict{Symbol,NamedTuple}(:EEG => EEG_default, :ECG => ECG_default),Dict{Symbol,Union{Vector{Int64},Symbol}}(:EEG => :auto, :ECG => :auto),nothing,true)
]

const datasets_dict = Dict{String,Vector{Int64}}(
	"sure-v1" => sure_dataset_ids
)

exec_aggr_points = [5, 20]
exec_length = ["2/4", "4/4"]
# exec_aggr_points = [5, 10, 15, 20]
# exec_length = ["1/4", "2/4", "3/4", "4/4"]

length_dict = Dict{String,Function}(
	"1/4" => x -> max(1, floor(Int64, size(x, 1) * 0.25)),
	"2/4" => x -> max(1, floor(Int64, size(x, 1) * 0.5)),
	"3/4" => x -> max(1, floor(Int64, size(x, 1) * 0.75)),
	"4/4" => x -> size(x, 1)
)
cut_length(X::AbstractArray{T,3} where T, l::Integer) = X[collect(1:l),:,:]
cut_length(X::AbstractArray{T,3} where T, l::AbstractString) = cut_length(X, length_dict[l](X))
cut_length(X::AbstractArray, l) = X

aggr_points(X::AbstractArray, n::Integer) = X
function aggr_points(X::AbstractArray{T,3}, n::Integer) where T
	chunksize = max(ceil(Int64, size(X, 1) / n), 1)

	res = Array{T,3}(undef, (n, size(X, 2), size(X, 3)))

	for i in 0:(n-1)
		left = (i * chunksize) + 1
		right = i == n-1 ? size(X, 1) : (i+1) * chunksize
		for j in 1:size(X, 2)
			for k in 1:size(X, 3)
				res[i+1,j,k] = mean(X[collect(left:right),j,k])
			end
		end
	end

	return res
end

# https://github.com/JuliaIO/JSON.jl/issues/203
# https://discourse.julialang.org/t/json-type-serialization/9794
# TODO: make test operators types serializable
# exec_canonical_features = [ "TestOp" ]
exec_canonical_features = [ ["TestOp_80", "TestOp_80"] ]

const canonical_features_union = Union{ModalLogic.CanonicalFeature,Function,Tuple{TestOperatorFun,Function}}

canonical_features_dict = Dict(
	"TestOp_70" => canonical_features_union[ModalLogic.TestOpGeq_70, ModalLogic.TestOpLeq_70],
	"TestOp_80" => canonical_features_union[ModalLogic.TestOpGeq_80, ModalLogic.TestOpLeq_80],
	"TestOp"    => canonical_features_union[ModalLogic.TestOpGeq,    ModalLogic.TestOpLeq],
)

exec_ontology = [ ["IA", "IA"] ] # "IA7", "IA3",

ontology_dict = Dict(
	"-"     => ModalLogic.OneWorldOntology,
	"RCC8"  => getIntervalRCC8OntologyOfDim(Val(2)),
	"RCC5"  => getIntervalRCC5OntologyOfDim(Val(2)),
	"IA"    => getIntervalOntologyOfDim(Val(1)),
	"IA7"   => Ontology{ModalLogic.Interval}(ModalLogic.IA7Relations),
	"IA3"   => Ontology{ModalLogic.Interval}(ModalLogic.IA3Relations),
	"IA2D"  => getIntervalOntologyOfDim(Val(2)),
	# "o_ALLiDxA" => Ontology{ModalLogic.Interval2D}([ModalLogic.IA_AA, ModalLogic.IA_LA, ModalLogic.IA_LiA, ModalLogic.IA_DA]),
)

############################################################################################

if dry_run != :dataset_only
	@info "Overwriting `exec_convert_to_class_ttest` to `$(exec_convert_to_class_ttest[[1]])`: allowed only in " *
		"`supervised_mode` = `:regression` and `dry_run` = `:dataset_only`"
	global exec_convert_to_class_ttest = exec_convert_to_class_ttest[[1]]
end

# exclude iterations that will change only unused parameters
first_skipped = false
black_list_prototype = (exec_n_desired_attributes = nothing, exec_n_desired_features = nothing, exec_convert_to_class_ttest = nothing)
for plural_auto_combination in Base.product(exec_n_desired_attributes, exec_n_desired_features, exec_convert_to_class_ttest)

	global first_skipped
	if !first_skipped
		first_skipped = true
		continue
	end

	for non_auto_dataset_parameters in filter(x -> !(:auto in values(x[end-2])), exec_dataset_params)
		push!(iteration_blacklist, merge(NamedTuple([keys(black_list_prototype)[i] => plural_auto_combination[i] for i in 1:length(black_list_prototype)]), (exec_dataset_params = non_auto_dataset_parameters,)))
	end
end

change_tuple_element(t::Tuple, value::Any, i::Integer) = Tuple(setindex!([t...], value, i))

# if there is just one signal convert all `force_single_frame` in all dataset_params
enqueued = []
for (i_ed, ed) in enumerate(exec_dataset_params)
	new_ed = ed

	if length(ed[2]) < 2 && ed[end] != false
		new_ed = change_tuple_element(ed, false, length(ed))
	end

	if !(new_ed in enqueued)
		push!(enqueued, new_ed)
	end
end
exec_dataset_params = deepcopy(enqueued)
empty!(enqueued)

# remove reduntant iterations in both :regression and :classification tasks
if supervised_mode == :regression
	## convert classification parametrizations to regression
	global exec_dataset_params
	local enqueued = []
	for (i_ed, ed) in enumerate(exec_dataset_params)
		if ed[end-1] != nothing
			new_ed = change_tuple_element(ed, nothing, length(ed) - 1)
			if !(new_ed in enqueued)
				push!(enqueued, new_ed)
			end
		else
			push!(enqueued, ed)
		end
	end
	exec_dataset_params = enqueued

else
	global exec_convert_to_class_ttest
	if exec_convert_to_class_ttest != [nothing]
		@info "Overwriting `exec_convert_to_class_ttest` to `[nothing]` because `supervised_mode` = :$(supervised_mode)"
		exec_convert_to_class_ttest = [nothing]
	end

	global exec_dataset_params
	local enqueued = []
	for ed in exec_dataset_params
		if ed[end-1] != nothing
			push!(enqueued, ed)
		end
	end
	exec_dataset_params = enqueued
end

# println("\n\nAutomatically selected iterations to be skipped:")
# for iter in iteration_blacklist
# 	println(iter)
# end
# println("")


exec_ranges = (; # Order: faster-changing to slower-changing
	exec_aggr_points            = exec_aggr_points,
	exec_length                 = exec_length,
	exec_n_desired_attributes   = exec_n_desired_attributes,
	exec_n_desired_features     = exec_n_desired_features,
	exec_convert_to_class_ttest = exec_convert_to_class_ttest,
	exec_dataset_params         = exec_dataset_params,
	use_training_form           = exec_use_training_form,
	canonical_features          = exec_canonical_features,
	ontology                    = exec_ontology,
)

nsplits2labels = Dict{Int,Vector{String}}(
	1 => ["NO", "YES"],
	2 => ["NO", "MAYBE", "YES"],
	3 => ["NO", "LITTLE", "ENOUGH", "YES"],
)

function dataset_function(
	dataset_name::AbstractString,
	signals::AbstractVector{Symbol},
	labels::AbstractVector{<:AbstractString},
	static_attrs::AbstractVector{<:AbstractString},
	signal_transformation::Dict{Symbol,<:NamedTuple},
	keep_only_bands::Dict{Symbol,<:Union{<:AbstractVector{<:Integer},Symbol}},
	class_splits::Union{NTuple{N,T},Nothing},
	force_single_frame::Bool
) where {N,T}
	copied_keep_only_bands = deepcopy(keep_only_bands)
	for (k, v) in keep_only_bands
		if v isa Symbol
			@assert v in [:all, :auto] "`keep_only_bands` values can only be :all, :auto or an AbstractVector{<:Integer}"
			# NOTE: both :all and :auto will load all bands but when keep_only_bands is :auto
			# the auto feature selection block will be executed
			if haskey(signal_transformation[k], :nbands)
				copied_keep_only_bands[k] = collect(1:signal_transformation[k].nbands)
			else
				@warn "No `nbands` key in `signal_transformation`: defaulting value to 60"
				copied_keep_only_bands[k] = collect(1:60)
			end
		end
	end

	classification =
		if supervised_mode == :regression
			nothing
		else
			(class_splits, nsplits2labels[length(class_splits)])
		end

	return NEVArtDataset(
		"$(data_dir)/NEVArt";
		ids = datasets_dict[dataset_name],
		signals = signals,
		labels = labels,
		static_attrs = static_attrs,
		mode = :painting,
		use_classification = classification,
		apply_transfer_function = true,
		normalize_after_transfer_function = true,
		forget_samplerate = false,
	    signal_transformation = signal_transformation,
		keep_only_bands = Dict{Symbol,Vector{Int64}}(copied_keep_only_bands),
		return_type = :Matricial, # :MFD, :DataFrame
		force_single_frame = force_single_frame
	)
end

################################################################################
################################### SCAN FILTERS ###############################
################################################################################

# TODO let iteration_white/blacklist a decision function and not a "in-array" condition?
iteration_whitelist = []

################################################################################
################################################################################
################################################################################
################################################################################

models_to_study = Dict([
	(
		"fcmel",8000,false,"stump_with_memoization",("c",3,true,"KDD-norm-partitioned-v1",["NG","Normalize","RemSilence"]),30,(max_points = 50, ma_size = 30, ma_step = 20),false,"TestOp_80","IA"
	) => [
		"tree_d3377114b972e5806a9e0631d02a5b9803c1e81d6cd6633b3dab4d9e22151969"
	],
])

models_to_study = Dict(JSON.json(k) => v for (k,v) in models_to_study)

MakeOntologicalDataset(Xs, canonical_features, ontology) = begin
	MultiFrameModalDataset([
		begin
			features = FeatureTypeFun[]

			for i_attr in 1:n_attributes(X)
				for test_operator in canonical_features
					if test_operator == TestOpGeq
						push!(features, ModalLogic.AttributeMinimumFeatureType(i_attr))
					elseif test_operator == TestOpLeq
						push!(features, ModalLogic.AttributeMaximumFeatureType(i_attr))
					elseif test_operator isa _TestOpGeqSoft
						push!(features, ModalLogic.AttributeSoftMinimumFeatureType(i_attr, test_operator.alpha))
					elseif test_operator isa _TestOpLeqSoft
						push!(features, ModalLogic.AttributeSoftMaximumFeatureType(i_attr, test_operator.alpha))
					else
						throw_n_log("Unknown test_operator type: $(test_operator), $(typeof(test_operator))")
					end
				end
			end

			featsnops = Vector{<:TestOperatorFun}[
				if any(map(t->isa(feature,t), [AttributeMinimumFeatureType, AttributeSoftMinimumFeatureType]))
					[≥]
				elseif any(map(t->isa(feature,t), [AttributeMaximumFeatureType, AttributeSoftMaximumFeatureType]))
					[≤]
				else
					throw_n_log("Unknown feature type: $(feature), $(typeof(feature))")
					[≥, ≤]
				end for feature in features
			]

			OntologicalDataset(X, ontology, features, featsnops)
		end for X in Xs])
end

################################################################################
################################################################################
################################################################################
################################################################################

mkpath(results_dir)

if "-f" in ARGS
	if isfile(iteration_progress_json_file_path)
		println("Backing up existing $(iteration_progress_json_file_path)...")
		backup_file_using_creation_date(iteration_progress_json_file_path)
	end
end

# Copy scan script into the results folder
backup_file_using_creation_date(PROGRAM_FILE; copy_or_move = :copy, out_path = results_dir)

exec_ranges_names, exec_ranges_iterators = collect(string.(keys(exec_ranges))), collect(values(exec_ranges))
history = load_or_create_history(
	iteration_progress_json_file_path, exec_ranges_names, exec_ranges_iterators
)

# Log to console AND to .out file, & send Telegram message with Errors
using Logging, LoggingExtras
using Telegram, Telegram.API
using ConfigEnv

i_log_filename,log_filename = 0,""
while i_log_filename == 0 || isfile(log_filename)
	global i_log_filename,log_filename
	i_log_filename += 1
	log_filename =
		results_dir * "/" *
		(dry_run == :dataset_only ? "datasets-" : "") *
		"$(i_log_filename).out"
end
logfile_io = open(log_filename, "w+")
dotenv()

tg = TelegramClient()
tg_logger = TelegramLogger(tg; async = false)

new_logger = TeeLogger(
	current_logger(),
	SimpleLogger(logfile_io, log_level),
	MinLevelLogger(tg_logger, Logging.Error), # Want to ignore Telegram? Comment out this
)
global_logger(new_logger)

################################################################################
################################################################################
################################################################################
################################################################################
# TODO actually,no need to recreate the dataset when changing, say, testoperators. Make a distinction between dataset params and run params
n_interations = 0
n_interations_done = 0
for params_combination in IterTools.product(exec_ranges_iterators...)

	flush(logfile_io);

	# Unpack params combination
	# params_namedtuple = (zip(Symbol.(exec_ranges_names), params_combination) |> Dict |> namedtuple)
	params_namedtuple = (;zip(Symbol.(exec_ranges_names), params_combination)...)

	# FILTER ITERATIONS
	if (!is_whitelisted_test(params_namedtuple, iteration_whitelist)) || is_blacklisted_test(params_namedtuple, iteration_blacklist)
		continue
	end

	global n_interations += 1

	##############################################################################
	##############################################################################
	##############################################################################

	run_name = join([replace(string(values(value)), ", " => ",") for value in params_combination], ",")

	# Placed here so we can keep track of which iteration is being skipped
	print("Iteration \"$(run_name)\"")

	# Check whether this iteration was already computed or not
	if all(iteration_in_history(history, (params_namedtuple, dataseed)) for dataseed in exec_dataseed) && (!save_datasets)
		println(": skipping")
		continue
	else
		println("...")
	end

	global n_interations_done += 1

	if dry_run == true
		continue
	end

	##############################################################################
	##############################################################################
	##############################################################################

	curr_aggr_points,
	curr_length_fraction,
	n_desired_attributes,
	n_desired_features,
	make_bins,
	(dataset_name,signals,lables,static_attrs,signal_transformation,keep_only_bands,classification_splits,force_single_frame),
	use_training_form,
	canonical_features,
	ontology = params_combination

	cur_modal_args = modal_args

	cur_n_frames = force_single_frame ? 1 : length(signals)

	global data_modal_args
	cur_dmas = deepcopy(data_modal_args)
	if length(cur_dmas) == 0
		# init empty cur_dmas for each frame
		cur_dmas = fill(NamedTuple(), cur_n_frames)
	elseif length(cur_dmas) == 1 && cur_n_frames > 1
		# extend cur_dmas to each frame
		cur_dmas = [cur_dmas for i in 1:cur_n_frames]
	end

	cur_data_modal_args = [
		merge(cur_dmas[i],
			(
				canonical_features = canonical_features_dict[canonical_features[i]],
				ontology           = ontology_dict[ontology[i]],
			)
		) for i in 1:cur_n_frames] # NOTE: times the number of frames

	dataset_fun_sub_params = (
		dataset_name,
		signals,
		lables,
		static_attrs,
		signal_transformation,
		keep_only_bands,
		classification_splits,
		force_single_frame
	)

	if dry_run == :model_study
		# println(JSON.json(params_combination))
		# println(models_to_study)
		# println(keys(models_to_study))
		if JSON.json(params_combination) in keys(models_to_study)

			trees = models_to_study[JSON.json(params_combination)]

			println()
			println()
			println("Study models for $(params_combination): $(trees)")

			if length(trees) == 0
				continue
			end

			println("dataset_fun_sub_params: $(dataset_fun_sub_params)")

			# @assert dataset_fun_sub_params isa String

			# dataset_fun_sub_params = merge(dataset_fun_sub_params, (; mode = :testing))

			datasets = []
			println("TODO")
			# datasets = [
			# 	(mode,if dataset_fun_sub_params isa Tuple
			# 		dataset = dataset_function(dataset_fun_sub_params...; mode = mode)
			# 		# dataset = @cachefast "dataset" data_savedir dataset_fun_sub_params dataset_function
			# 		(X, Y), (n_pos, n_neg) = dataset
			# 		# elseif dataset_fun_sub_params isa String
			# 		# 	# load_cached_obj("dataset", data_savedir, dataset_fun_sub_params)
			# 		# 	dataset = Serialization.deserialize("$(data_savedir)/dataset_$(dataset_fun_sub_params).jld").train_n_test
			# 		# 	println(typeof(dataset))
			# 		# 	(X, Y), (n_pos, n_neg) = dataset
			# 		# 	(X, Y, nothing), (n_pos, n_neg)

			# 		# TODO should not need these at test time. Instead, extend functions so that one can use a MatricialDataset instead of an OntologicalDataset
			# 		X = MakeOntologicalDataset(X, canonical_features, ontology)
			# 		# println(length(Y))
			# 		# println((n_pos, n_neg))

			# 		println(display_structure(X))
			# 		# println(Y)
			# 		dataset = (X, Y), (n_pos, n_neg)
			# 		dataset
			# 	else
			# 		throw_n_log("$(typeof(dataset_fun_sub_params))")
			# 	end) for mode in [:testing, :development]
			# ]

			for model_hash in trees

				println()
				println()
				println("Loading model: $(model_hash)...")

				model = load_model(model_hash, model_savedir)

				println()
				println("Original model (training):")
				if model isa DTree
					print_model(model)
				end

				for (mode,dataset) in datasets
					(X, Y), (n_pos, n_neg) = dataset

					println()

					println()
					println("Regenerated model ($(mode)):")

					if model isa DTree
						regenerated_model = print_apply_model(model, X, Y; print_relative_confidence = true)
						println()
						# print_model(regenerated_model)
					end

					preds = apply_model(model, X);
					cm = confusion_matrix(Y, preds)
					println(cm)

					# readline()
				end
			end
		end
	end

	# Load Dataset
	dataset = @cachefast "dataset" data_savedir dataset_fun_sub_params dataset_function

	######### aggregate points
	for (i_frame, frame) in enumerate(dataset[1])
		# 1) cut length
		dataset[1][i_frame] = cut_length(dataset[1][i_frame], curr_length_fraction)
		# 2) real aggregation
		dataset[1][i_frame] = aggr_points(dataset[1][i_frame], curr_aggr_points)
	end

	if supervised_mode == :regression
		###### convert labels to float64
		dataset = (dataset[1], Float64[dataset[2]...])
	end

	############### AUTOMATIC FEATURE SELECTION
	if :auto in values(keep_only_bands)
		new_frames = Vector{AbstractArray}(undef, length(dataset[1]))

		grouped_descriptors = OrderedDict([
			"Basic stats" => [
				:mean_m
				:min_m
				:max_m
			], "Distribution" => [
				:DN_HistogramMode_5
				:DN_HistogramMode_10
			], "Simple temporal statistics" => [
				:SB_BinaryStats_mean_longstretch1
				:DN_OutlierInclude_p_001_mdrmd
				:DN_OutlierInclude_n_001_mdrmd
			], "Linear autocorrelation" => [
				:CO_f1ecac
				:CO_FirstMin_ac
				:SP_Summaries_welch_rect_area_5_1
				:SP_Summaries_welch_rect_centroid
				:FC_LocalSimple_mean3_stderr
			], "Nonlinear autocorrelation" => [
				:CO_trev_1_num
				:CO_HistogramAMI_even_2_5
				:IN_AutoMutualInfoStats_40_gaussian_fmmi
			], "Successive differences" => [
				:MD_hrv_classic_pnn40
				:SB_BinaryStats_diff_longstretch0
				:SB_MotifThree_quantile_hh
				:FC_LocalSimple_mean1_tauresrat
				:CO_Embed2_Dist_tau_d_expfit_meandiff
			], "Fluctuation Analysis" => [
				:SC_FluctAnal_2_dfa_50_1_2_logi_prop_r1
				:SC_FluctAnal_2_rsrangefit_50_1_logi_prop_r1
			], "Others" => [
				:SB_TransitionMatrix_3ac_sumdiagcov
				:PD_PeriodicityWang_th0_01
			],
		])

		descriptor_abbrs = Dict([
		 	##########################################################################
		 	:mean_m                                        => "M",
		 	:max_m                                         => "MAX",
		 	:min_m                                         => "MIN",
		 	##########################################################################
		 	:DN_HistogramMode_5                            => "Z5",
		 	:DN_HistogramMode_10                           => "Z10",
		 	##########################################################################
		 	:SB_BinaryStats_mean_longstretch1              => "C",
		 	:DN_OutlierInclude_p_001_mdrmd                 => "A",
		 	:DN_OutlierInclude_n_001_mdrmd                 => "B",
		 	##########################################################################
			:CO_f1ecac                                     => "FC",
			:CO_FirstMin_ac                                => "FM",
			:SP_Summaries_welch_rect_area_5_1              => "TP",
			:SP_Summaries_welch_rect_centroid              => "C",
			:FC_LocalSimple_mean3_stderr                   => "ME",
		 	##########################################################################
			:CO_trev_1_num                                 => "TR",
			:CO_HistogramAMI_even_2_5                      => "AI",
			:IN_AutoMutualInfoStats_40_gaussian_fmmi       => "FMAI",
		 	##########################################################################
			:MD_hrv_classic_pnn40                          => "PD",
			:SB_BinaryStats_diff_longstretch0              => "LP",
			:SB_MotifThree_quantile_hh                     => "EN",
			:FC_LocalSimple_mean1_tauresrat                => "CC",
			:CO_Embed2_Dist_tau_d_expfit_meandiff          => "EF",
		 	##########################################################################
			:SC_FluctAnal_2_dfa_50_1_2_logi_prop_r1        => "FDFA",
			:SC_FluctAnal_2_rsrangefit_50_1_logi_prop_r1   => "FLF",
		 	##########################################################################
			:SB_TransitionMatrix_3ac_sumdiagcov            => "TC",
			:PD_PeriodicityWang_th0_01                     => "PM",
		 	##########################################################################
		])

		for f_name in getnames(catch22)
 			@eval (function $(Symbol(string(f_name)*"_pos"))(channel)
 				val = $(catch22[f_name])(channel)

 				if isnan(val)
 					# println("WARNING!!! NaN value found! channel = $(channel)")
 					-Inf # aggregator_bottom(existential_aggregator(≥), Float64)
 				else
 					val
 				end
 			end)
 			@eval (function $(Symbol(string(f_name)*"_neg"))(channel)
 				val = $(catch22[f_name])(channel)

 				if isnan(val)
 					# println("WARNING!!! NaN value found! channel = $(channel)")
 					Inf # aggregator_bottom(existential_aggregator(≤), Float64)
 				else
 					val
 				end
 			end)
 		end

 		function getCanonicalFeature(f_name)
 			if f_name == :min_m
 				[CanonicalFeatureGeq_80]
 			elseif f_name == :max_m
 				[CanonicalFeatureLeq_80]
 			elseif f_name == :mean_m
 				[StatsBase.mean]
 			else
 				[(≥, @eval $(Symbol(string(f_name)*"_pos"))),(≤, @eval $(Symbol(string(f_name)*"_neg")))]
 			end
 		end

		signal_i_offset = 0
		for (i_frame, frame) in enumerate(dataset[1])
			if ndims(frame) != 3
				signal_i_offset += 1
				new_frames[i_frame] = dataset[1][i_frame]
			elseif keep_only_bands[signals[i_frame+signal_i_offset]] == :auto
				curr_signal = signals[i_frame+signal_i_offset]

				attribute_names =
					if force_single_frame
						["$(curr_signal)_B$(i_attr)" for i_attr in 1:size(dataset[1][i_frame], 2)]
					else
						["$(s)_B$(i_attr)" for s in signals for i_attr in 1:(haskey(signal_transformation[s], :nbands) ? signal_transformation[s].nbands : 60)]
					end

				safe_run_name = replace(run_name, "\"" => "")
				safe_run_name = replace(safe_run_name, "/" => ".")
				safe_run_name = replace(safe_run_name, "\\" => ".")
				safe_run_name = replace(safe_run_name, r"Dict{(?!.*\bDict\b).*}" => "")

				run_file_prefix = "$(results_dir)/plots/$(curr_signal)-$(safe_run_name)/plotdescription"
				mkpath(dirname(run_file_prefix))

				blind_feature_selection_params = (
					(dataset[1][i_frame],dataset[2]),
					attribute_names,
					grouped_descriptors,
					run_file_prefix,
					n_desired_attributes,
					n_desired_features
				)
				blind_feature_selection_kwparams = (
					savefigs = savefigs,
					descriptor_abbrs = descriptor_abbrs,
					attribute_abbrs = attribute_names, # use attirbute names as they are
					export_csv = true,
					# join_plots = [],
				)
				best_attributes_idxs, best_descriptors =
					@cache "selected_features" selected_features_savedir blind_feature_selection_params blind_feature_selection_kwparams single_frame_blind_feature_selection

				new_frames[i_frame] = dataset[1][i_frame][:,best_attributes_idxs,:]

				if perform_target_aware_analysis
					single_frame_target_aware_analysis(
						(new_frames[i_frame],dataset[2]),
						attribute_names[best_attributes_idxs],
						best_descriptors,
						run_file_prefix*"-sub";
						make_bins = make_bins,
						savefigs = savefigs,
						descriptor_abbrs = descriptor_abbrs,
						attribute_abbrs = attribute_names[best_attributes_idxs], # use attirbute names as they are
						export_csv = true,
					)
				end

				cur_data_modal_args[i_frame] = merge(cur_data_modal_args[i_frame], (;
					canonical_features = Vector{canonical_features_union}(collect(Iterators.flatten(getCanonicalFeature.(best_descriptors))))
				))
			else
				new_frames[i_frame] = dataset[1][i_frame]
			end
		end

		dataset = (new_frames, dataset[2])
	end

	## Dataset slices
	# obtain dataseeds that are were not done before
	todo_dataseeds = filter((dataseed)->!iteration_in_history(history, (params_namedtuple, dataseed)), exec_dataseed)

	dataset, dataset_slices =
		if supervised_mode == :regression
			X, Y = dataset
			dataset_slices = begin
				n_insts = length(Y)
				@assert (n_insts % n_cv_folds == 0) "$(n_insts) % $(n_cv_folds) != 0"
				n_insts_fold = div(n_insts, n_cv_folds)
				# todo_dataseeds = 1:10
				[(dataseed, begin
						if dataseed == 0
							(Vector{Integer}(collect(1:n_insts)), Vector{Integer}(collect(1:n_insts)))
						else
							test_idxs = 1+(dataseed-1)*n_insts_fold:(dataseed-1)*n_insts_fold+(n_insts_fold)
							(Vector{Integer}(collect(setdiff(Set(1:n_insts), Set(test_idxs)))), Vector{Integer}(collect(test_idxs)))
						end
					end) for dataseed in todo_dataseeds]
			end
			dataset, dataset_slices
		else
			class_names = nsplits2labels[length(classification_splits)]
			class_counts = Tuple([length(findall(x -> x == cn, dataset[2])) for cn in class_names])

			sorted_by_class_indices = vcat([findall(x -> x == cn, dataset[2]) for cn in class_names]...)

			linearized_dataset, dataset_slices = balanced_dataset_slice(
				(([frame[:,:,sorted_by_class_indices] for frame in dataset[1]], dataset[2][sorted_by_class_indices]), class_counts),
				todo_dataseeds
			)
			dataset_slices = collect(zip(todo_dataseeds, dataset_slices))

			linearized_dataset, dataset_slices
		end

	X, Y = dataset

	println("Dataseeds = $(todo_dataseeds)")

	if dry_run == :dataset_only
		continue
	end

	##############################################################################
	##############################################################################
	##############################################################################

	if dry_run == false
		exec_scan(
			params_namedtuple,
			dataset;
			is_regression_problem           =   (eltype(Y) != String),
			### Training params
			train_seed                      =   train_seed,
			modal_args                      =   cur_modal_args,
			tree_args                       =   tree_args,
			tree_post_pruning_purity_thresh =   [],
			forest_args                     =   forest_args,
			forest_runs                     =   forest_runs,
			optimize_forest_computation     =   optimize_forest_computation,
			test_flattened                  =   test_flattened,
			test_averaged                   =   test_averaged,
			### Dataset params
			split_threshold                 =   (eltype(Y) != String) ? split_threshold_regression : split_threshold_classification,
			data_modal_args                 =   cur_data_modal_args,
			dataset_slices                  =   dataset_slices,
			round_dataset_to_datatype       =   round_dataset_to_datatype,
			use_training_form               =   use_training_form,
			### Run params
			results_dir                     =   results_dir,
			data_savedir                    =   data_savedir,
			model_savedir                   =   model_savedir,
			# logger                          =   logger,
			timing_mode                     =   timing_mode,
			### Misc
			save_datasets                   =   save_datasets,
			skip_training                   =   skip_training,
			callback                        =   (dataseed)->begin
				# Add this step to the "history" of already computed iteration
				push_iteration_to_history!(history, (params_namedtuple, dataseed))
				save_history(iteration_progress_json_file_path, history)
			end
		);
	end

end

println("Done!")
println("# Iterations $(n_interations_done)/$(n_interations)")

# Notify the Telegram Bot
try
	@error "Done!"
catch
end

close(logfile_io);

exit(0)
