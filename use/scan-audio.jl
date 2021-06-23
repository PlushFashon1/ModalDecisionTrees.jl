################################################################################
################################################################################
################################## Scan script #################################
################################################################################
################################################################################

include("runner.jl")
include("table-printer.jl")
include("progressive-iterator-manager.jl")

main_rng = DecisionTree.mk_rng(1)

train_seed = 1


################################################################################
#################################### FOLDERS ###################################
################################################################################

results_dir = "./results-audio-scan"

iteration_progress_json_file_path = results_dir * "/progress.json"
concise_output_file_path = results_dir * "/grouped_in_models.csv"
full_output_file_path = results_dir * "/full_columns.csv"
data_savedir = results_dir * "/gammas"
tree_savedir = results_dir * "/trees"

column_separator = ";"

save_datasets = false
just_produce_datasets_jld = false
saved_datasets_path = results_dir * "/datasets"

################################################################################
##################################### TREES ####################################
################################################################################

# Optimization arguments for single-tree
tree_args = [
#	(
#		loss_function = DecisionTree.util.entropy,
#		min_samples_leaf = 1,
#		min_purity_increase = 0.01,
#		min_loss_at_leaf = 0.6,
#	)
]

for loss_function in [DecisionTree.util.entropy]
	for min_samples_leaf in [1] # [1,2]
		for min_purity_increase in [0.01] # [0.01, 0.001]
			for min_loss_at_leaf in [0.6] # [0.4, 0.6]
				push!(tree_args, 
					(
						loss_function = loss_function,
						min_samples_leaf = min_samples_leaf,
						min_purity_increase = min_purity_increase,
						min_loss_at_leaf = min_loss_at_leaf,
					)
				)
			end
		end
	end
end

println(" $(length(tree_args)) trees")

################################################################################
#################################### FORESTS ###################################
################################################################################

forest_runs = 5
optimize_forest_computation = true

forest_args = []

#for n_trees in [50,100]
#	for n_subfeatures in [id_f, half_f]
#		for n_subrelations in [id_f]
#			push!(forest_args, (
#				n_subfeatures       = n_subfeatures,
#				n_trees             = n_trees,
#				partial_sampling    = 1.0,
#				n_subrelations      = n_subrelations,
#				forest_tree_args...
#			))
#		end
#	end
#end

# Optimization arguments for trees in a forest (no pruning is performed)
forest_tree_args = (
	loss_function = DecisionTree.util.entropy,
	min_samples_leaf = 1,
	min_purity_increase = 0.0,
	min_loss_at_leaf = 0.0,
)

println(" $(length(forest_args)) forests (repeated $(forest_runs) times)")

################################################################################
################################## MODAL ARGS ##################################
################################################################################

modal_args = (
	initConditions = DecisionTree.startWithRelationGlob,
	# initConditions = DecisionTree.startAtCenter,
	useRelationGlob = false,
)

data_modal_args = (
	ontology = getIntervalOntologyOfDim(Val(1)),
	# ontology = Ontology{ModalLogic.Interval}([ModalLogic.IA_A]),
	# ontology = Ontology{ModalLogic.Interval}([ModalLogic.IA_A, ModalLogic.IA_L, ModalLogic.IA_Li, ModalLogic.IA_D]),
)


################################################################################
##################################### MISC #####################################
################################################################################

# log_level = Logging.Warn
log_level = DecisionTree.DTOverview
# log_level = DecisionTree.DTDebug
# log_level = DecisionTree.DTDetail

timing_mode = :none
# timing_mode = :time
# timing_mode = :btime

#round_dataset_to_datatype = Float32
# round_dataset_to_datatype = UInt16
round_dataset_to_datatype = false

split_threshold = 0.8
# split_threshold = 1.0
# split_threshold = false

use_ontological_form = false

test_flattened = true
test_averaged = true

legacy_gammas_check = true


################################################################################
##################################### SCAN #####################################
################################################################################

exec_dataseed = 1:5
exec_n_tasks = 1:1
exec_n_versions = 1:3
exec_nbands = [20,40,60]

max_points = 3
# max_points = 30

exec_dataset_kwargs =   [(
							max_points = max_points,
							ma_size = 75,
							ma_step = 50,
						),(
							max_points = max_points,
							ma_size = 45,
							ma_step = 30,
						)
						]

audio_kwargs_partial_mfcc = (
	wintime = 0.025, # in ms          # 0.020-0.040
	steptime = 0.010, # in ms         # 0.010-0.015
	fbtype = :mel,                    # [:mel, :htkmel, :fcmel]
	window_f = DSP.hamming, # [DSP.hamming, (nwin)->DSP.tukey(nwin, 0.25)]
	pre_emphasis = 0.97,              # any, 0 (no pre_emphasis)
	nbands = 40,                      # any, (also try 20)
	sumpower = false,                 # [false, true]
	dither = false,                   # [false, true]
	# bwidth = 1.0,                   # 
	# minfreq = 0.0,
	# maxfreq = (sr)->(sr/2),
	# usecmp = false,
)

audio_kwargs_full_mfcc = (
	wintime=0.025,
	steptime=0.01,
	numcep=13,
	lifterexp=-22,
	sumpower=false,
	preemph=0.97,
	dither=false,
	minfreq=0.0,
	# maxfreq=sr/2,
	nbands=20,
	bwidth=1.0,
	dcttype=3,
	fbtype=:htkmel,
	usecmp=false,
	modelorder=0
)

exec_use_full_mfcc = [false]


wav_preprocessors = Dict(
	"NG" => noise_gate!,
	"Normalize" => normalize!,
)

exec_preprocess_wavs = [
	["Normalize"],
	[],
#	["NG", "Normalize"]
]

# https://github.com/JuliaIO/JSON.jl/issues/203
# https://discourse.julialang.org/t/json-type-serialization/9794
# TODO: make test operators types serializable
# exec_test_operators = [ "TestOp" ]
exec_test_operators = [ "TestOp_80" ]

test_operators_dict = Dict(
	"TestOp_70" => [TestOpGeq_70, TestOpLeq_70],
	"TestOp_80" => [TestOpGeq_80, TestOpLeq_80],
	"TestOp" => [TestOpGeq, TestOpLeq],
)


exec_ranges_dict = (
	dataseed         = exec_dataseed,
	n_task           = exec_n_tasks,
	n_version        = exec_n_versions,
	nbands           = exec_nbands,
	dataset_kwargs   = exec_dataset_kwargs,
	use_full_mfcc    = exec_use_full_mfcc,
	preprocess_wavs  = exec_preprocess_wavs,
	test_operators   = exec_test_operators,
)

exec_ranges_names, exec_ranges = collect(string.(keys(exec_ranges_dict))), collect(values(exec_ranges_dict))
history = load_or_create_history(
	iteration_progress_json_file_path, exec_ranges_names, exec_ranges
)

################################################################################
################################### SCAN FILTERS ###############################
################################################################################

dry_run = false

# TODO let iteration_white/blacklist a decision function and not a "in-array" condition?
iteration_whitelist = [
	# TASK 1
	# (
	# 	n_version = 1,
	# 	nbands = 40,
	# 	dataset_kwargs = (max_points = 30, ma_size = 75, ma_step = 50),
	# ),
	# (
	# 	n_version = 1,
	# 	nbands = 60,
	# 	dataset_kwargs = (max_points = 30, ma_size = 75, ma_step = 50),
	# ),
	# # TASK 2
	# (
	# 	n_version = 2,
	# 	nbands = 20,
	# 	dataset_kwargs = (max_points = 30, ma_size = 45, ma_step = 30),
	# ),
	# (
	# 	n_version = 2,
	# 	nbands = 40,
	# 	dataset_kwargs = (max_points = 30, ma_size = 45, ma_step = 30),
	# )
]

iteration_blacklist = []


################################################################################
################################################################################
################################################################################
################################################################################

mkpath(saved_datasets_path)

if "-f" in ARGS
	if isfile(iteration_progress_json_file_path)
		println("Backing up existing $(iteration_progress_json_file_path)...")
		backup_file_using_creation_date(iteration_progress_json_file_path)
	end
	if isfile(concise_output_file_path)
		println("Backing up existing $(concise_output_file_path)...")
		backup_file_using_creation_date(concise_output_file_path)
	end
	if isfile(full_output_file_path)
		println("Backing up existing $(full_output_file_path)...")
		backup_file_using_creation_date(full_output_file_path)
	end
end

# if the output files does not exists initilize them
print_head(concise_output_file_path, tree_args, forest_args, tree_columns = [""], forest_columns = ["", "σ²", "t"], separator = column_separator)
print_head(full_output_file_path, tree_args, forest_args, separator = column_separator,
	forest_columns = ["K", "sensitivity", "specificity", "precision", "accuracy", "oob_error", "σ² K", "σ² sensitivity", "σ² specificity", "σ² precision", "σ² accuracy", "σ² oob_error", "t"],
)

################################################################################
################################################################################
################################################################################
################################################################################
# TODO actually,no need to recreate the dataset when changing, say, testoperators. Make a distinction between dataset params and run params
for params_combination in IterTools.product(exec_ranges...)

	# Unpack params combination
	params_namedtuple = (zip(Symbol.(exec_ranges_names), params_combination) |> Dict |> namedtuple)

	# FILTER ITERATIONS
	if (!is_whitelisted_test(params_namedtuple, iteration_whitelist)) || is_blacklisted_test(params_namedtuple, iteration_blacklist)
		continue
	end

	##############################################################################
	##############################################################################
	##############################################################################

	run_name = join([replace(string(values(value)), ", " => ",") for value in values(params_namedtuple)], ",")

	# Placed here so we can keep track of which iteration is being skipped
	checkpoint_stdout("Computing iteration $(run_name)...")

	if dry_run
		continue
	end

	# CHECK WHETHER THIS ITERATION WAS ALREADY COMPUTED OR NOT
	if iteration_in_history(history, params_namedtuple) && !just_produce_datasets_jld
		println("Iteration $(run_name) already done, skipping...")
		continue
	end

	##############################################################################
	##############################################################################
	##############################################################################
	
	dataset_seed, n_task, n_version, nbands, dataset_kwargs, use_full_mfcc, preprocess_wavs, test_operators = params_combination

	dataset_rng = Random.MersenneTwister(dataset_seed)

	# LOAD DATASET
	dataset_file_name = saved_datasets_path * "/" * run_name

	cur_audio_kwargs = merge(
		if use_full_mfcc
			audio_kwargs_full_mfcc
		else
			audio_kwargs_partial_mfcc
		end
		, (nbands=nbands,))

	cur_modal_args = modal_args
	
	cur_preprocess_wavs = [ wav_preprocessors[k] for k in preprocess_wavs ]

	# TODO reduce redundancy with caching function
	dataset = 
		if save_datasets && isfile(dataset_file_name * ".jld")
			if just_produce_datasets_jld
				continue
			end

			checkpoint_stdout("Loading dataset $(dataset_file_name * ".jld")...")
			
			dataset = nothing
			n_pos = nothing
			n_neg = nothing
			
			JLD2.@load (dataset_file_name * ".jld") dataset n_pos n_neg
			(X,Y) = dataset
			if isfile(dataset_file_name * "-balanced.jld")
				JLD2.@load (dataset_file_name * "-balanced.jld") balanced_dataset dataset_slice
			else
				n_per_class = min(n_pos, n_neg)
				dataset_slice = Array{Int,2}(undef, 2, n_per_class)
				dataset_slice[1,:] .=          Random.randperm(dataset_rng, n_pos)[1:n_per_class]
				dataset_slice[2,:] .= n_pos .+ Random.randperm(dataset_rng, n_neg)[1:n_per_class]
				dataset_slice = dataset_slice[:]

				balanced_dataset = slice_mf_dataset((X,Y), dataset_slice)
				typeof(balanced_dataset) |> println
				(X_train, Y_train), (X_test, Y_test) = traintestsplit(balanced_dataset, split_threshold)
				JLD2.@save (dataset_file_name * "-balanced.jld") balanced_dataset dataset_slice
				balanced_train = (X_train, Y_train)
				JLD2.@save (dataset_file_name * "-balanced-train.jld") balanced_train
				balanced_test = (X_test,  Y_test)
				JLD2.@save (dataset_file_name * "-balanced-test.jld")  balanced_test
			end

			dataset = (X,Y)
		else
			checkpoint_stdout("Creating dataset...")
			# TODO wrap dataset creation into a function accepting the rng and other parameters...
			dataset, n_pos, n_neg = KDDDataset_not_stratified(
				(n_task,n_version),
				cur_audio_kwargs;
				dataset_kwargs...,
				preprocess_wavs = cur_preprocess_wavs,
				use_full_mfcc = use_full_mfcc
			)

			n_per_class = min(n_pos, n_neg)

			dataset_slice = Array{Int,2}(undef, 2, n_per_class)
			dataset_slice[1,:] .=          Random.randperm(dataset_rng, n_pos)[1:n_per_class]
			dataset_slice[2,:] .= n_pos .+ Random.randperm(dataset_rng, n_neg)[1:n_per_class]
			dataset_slice = dataset_slice[:]

			if save_datasets
				checkpoint_stdout("Saving dataset $(dataset_file_name)...")
				(X, Y) = dataset
				JLD2.@save (dataset_file_name * ".jld")                dataset n_pos n_neg
				balanced_dataset = slice_mf_dataset((X,Y), dataset_slice)
				typeof(balanced_dataset) |> println
				(X_train, Y_train), (X_test, Y_test) = traintestsplit(balanced_dataset, split_threshold)
				JLD2.@save (dataset_file_name * "-balanced.jld") balanced_dataset dataset_slice
				balanced_train = (X_train, Y_train)
				JLD2.@save (dataset_file_name * "-balanced-train.jld") balanced_train
				balanced_test = (X_test,  Y_test)
				JLD2.@save (dataset_file_name * "-balanced-test.jld")  balanced_test
				if just_produce_datasets_jld
					continue
				end
			end
			dataset
		end
	# println(dataset_slice)

	cur_data_modal_args = merge(data_modal_args, (test_operators = test_operators_dict[test_operators],))
	
	##############################################################################
	##############################################################################
	##############################################################################
	
	# ACTUAL COMPUTATION
	Ts, Fs, Tcms, Fcms, Tts, Fts = execRun(
				run_name,
				dataset,
				split_threshold             =   split_threshold,
				log_level                   =   log_level,
				round_dataset_to_datatype   =   round_dataset_to_datatype,
				dataset_slice               =   dataset_slice,
				forest_args                 =   forest_args,
				tree_args                   =   tree_args,
				data_modal_args             =   cur_data_modal_args,
				modal_args                  =   cur_modal_args,
				test_flattened              =   test_flattened,
				legacy_gammas_check         =   legacy_gammas_check,
				use_ontological_form        =   use_ontological_form,
				optimize_forest_computation =   optimize_forest_computation,
				forest_runs                 =   forest_runs,
				data_savedir                =   (data_savedir, run_name),
				tree_savedir                =   tree_savedir,
				train_seed                  =   train_seed,
				timing_mode                 =   timing_mode
			);
	##############################################################################
	##############################################################################
	# PRINT RESULT IN FILES 
	##############################################################################
	##############################################################################

	# PRINT CONCISE
	concise_output_string = string(run_name, column_separator)
	for j in 1:length(tree_args)
		concise_output_string *= string(data_to_string(Ts[j], Tcms[j], Tts[j]; alt_separator=", ", separator = column_separator))
		concise_output_string *= string(column_separator)
	end
	for j in 1:length(forest_args)
		concise_output_string *= string(data_to_string(Fs[j], Fcms[j], Fts[j]; alt_separator=", ", separator = column_separator))
		concise_output_string *= string(column_separator)
	end
	concise_output_string *= string("\n")
	append_in_file(concise_output_file_path, concise_output_string)

	# PRINT FULL
	full_output_string = string(run_name, column_separator)
	for j in 1:length(tree_args)
		full_output_string *= string(data_to_string(Ts[j], Tcms[j], Tts[j]; start_s = "", end_s = "", alt_separator = column_separator))
		full_output_string *= string(column_separator)
	end
	for j in 1:length(forest_args)
		full_output_string *= string(data_to_string(Fs[j], Fcms[j], Fts[j]; start_s = "", end_s = "", alt_separator = column_separator))
		full_output_string *= string(column_separator)
	end
	full_output_string *= string("\n")
	append_in_file(full_output_file_path, full_output_string)

	##############################################################################
	##############################################################################
	# ADD THIS STEP TO THE "HISTORY" OF ALREADY COMPUTED ITERATION
	push_iteration_to_history!(history, params_namedtuple)
	save_history(iteration_progress_json_file_path, history)
	##############################################################################
	##############################################################################
end

checkpoint_stdout("Finished!")

# selected_args = merge(args, (loss_function = loss_function,
# 															min_samples_leaf = min_samples_leaf,
# 															min_purity_increase = min_purity_increase,
# 															min_loss_at_leaf = min_loss_at_leaf,
# 															))

# dataset_kwargs = (
# 	max_points = -1,
# 	ma_size = 1,
# 	ma_step = 1,
# )
# 
# dataset = KDDDataset_not_stratified((1,1), audio_kwargs; dataset_kwargs..., rng = main_rng); # 141/298
# dataset[1] |> size # (1413, 282)
# dataset = KDDDataset_not_stratified((1,2), audio_kwargs; dataset_kwargs..., rng = main_rng); # 141/298
# dataset[1] |> size # (2997, 282)
# dataset = KDDDataset_not_stratified((2,1), audio_kwargs; dataset_kwargs..., rng = main_rng); # 54/32
# dataset[1] |> size # (1413, 64)
# dataset = KDDDataset_not_stratified((2,2), audio_kwargs; dataset_kwargs..., rng = main_rng); # 54/32
# dataset[1] |> size # (2997, 64)
# dataset = KDDDataset_not_stratified((3,1), audio_kwargs; dataset_kwargs..., rng = main_rng); # 54/20
# dataset[1] |> size # (1413, 40)
# dataset = KDDDataset_not_stratified((3,2), audio_kwargs; dataset_kwargs..., rng = main_rng); # 54/20
# dataset[1] |> size # (2673, 40)

# execRun("Test", dataset, 0.8, 0, log_level=log_level,
# 			forest_args=forest_args, args=args, kwargs=modal_args,
# 			test_tree = true, test_forest = true);

