
include("scanner.jl")
# include("datasets.jl")
# include("lib.jl")
# include("caching.jl")
include("wav2stft_time_series.jl")
include("local.jl")

# using DSP: filt
# using Weave
# import Pkg
# Pkg.activate("..")

using DecisionTree
using DecisionTree.ModalLogic

using Plots
using MFCC: hz2mel, mel2hz

MFCC.mel2hz(f::AbstractFloat, htk=false)  = mel2hz([f], htk)[1]

"""
Calculate frequency response
"""
# https://weavejl.mpastell.com/stable/examples/FIR_design.pdf
function FIRfreqz(b::Array; w = range(0, stop=π, length=1024))::Array{ComplexF32}
    n = length(w)
    h = Array{ComplexF32}(undef, n)
    sw = 0
    for i = 1:n
        for j = 1:length(b)
        sw += b[j]*exp(-im*w[i])^-j
        end
        h[i] = sw
        sw = 0
    end
    h
end

"""
Plot the frequency and impulse response
"""
function plotfilter(
        filter;
        samplerate = 100,
        xlims::Union{Nothing,Tuple{Real,Real}} = (0, 0),
        ylims::Union{Nothing,Tuple{Real,Real}} = (-24, 0),
        plotfunc = plot
    )

    w = range(0, stop=π, length=1024)
    h = FIRfreqz(filter; w = w)
    ws = w / π * (samplerate / 2)
    if xlims[2] == 0
        xlims = (xlims[1], maximum(ws))
    end
    plotfunc(ws, amp2db.(abs.(h)), xlabel="Frequency (Hz)", ylabel="Magnitude (db)", xlims = xlims, ylims = ylims, leg = false, size = (1920, 1080))
end
plotfilter(filter::Filters.Filter; kwargs...) = plotfilter(digitalfilter(filter, firwindow); kwargs...)

plotfilter!(filter::Filters.Filter; args...) = plotfilter(filter; args..., plotfunc = plot!)
plotfilter!(filter; args...)                 = plotfilter(filter; args..., plotfunc = plot!)

function multibandpass_digitalfilter(
        vec::Vector{Tuple{T, T}},
        fs::Real,
        window_f::Function;
        nbands::Integer = 60,
        nwin = nbands,
        weights::Vector{F} where F <:AbstractFloat = fill(1., length(vec))
    )::AbstractVector where T

    @assert length(weights) == length(vec) "length(weights) != length(vec): $(length(weights)) != $(length(vec))"

    result_filter = zeros(T, nbands)
    i = 1
    @simd for t in vec
        result_filter += digitalfilter(Filters.Bandpass(t..., fs = fs), FIRWindow(window_f(nwin))) * weights[i]
        i=i+1
    end
    result_filter
end
function multibandpass_digitalfilter(
        selected_bands::Vector{Int},
        fs::Real,
        window_f::Function;
        nbands::Integer = 60,
        minfreq = 0.0,
        maxfreq = fs / 2,
        nwin = nbands,
        weights::Vector{F} where F <:AbstractFloat = fill(1., length(selected_bands))
    )::AbstractVector

    @assert length(weights) == length(selected_bands) "length(weights) != length(selected_bands): $(length(weights)) != $(length(selected_bands))"

    band_width = (maxfreq - minfreq) / nbands

    result_filter = zeros(Float64, nwin)
    i = 1
    @simd for b in selected_bands
        l = b * band_width
        r = ((b+1) * band_width) - 1
        result_filter += digitalfilter(Filters.Bandpass(l <= 0 ? eps(typof(l)) : l, r >= maxfreq ? r - 0.000001 : r, fs = fs), FIRWindow(window_f(nwin))) * weights
        i=i+1
    end
    result_filter
end

struct MelBand
    left  :: Real
    right :: Real
    peak  :: Real
    MelBand(left::Real, right::Real, peak::Real) = new(max(eps(Float64), left), right, peak)
end

struct MelScale
    nbands :: Int
    bands  :: Vector{MelBand}
    MelScale(nbands::Int) = new(nbands, Vector{MelBand}(undef, nbands))
    MelScale(nbands::Int, bands::Vector{MelBand}) = begin
        @assert length(bands) == nbands "nbands != length(bands): $(nbands) != $(length(bands))"
        new(nbands, bands)
    end
    MelScale(bands::Vector{MelBand}) = new(length(bands), bands)
end

import Base: getindex, setindex!, length

length(scale::MelScale)::Int = length(scale.bands)
getindex(scale::MelScale, idx::Int)::MelBand = scale.bands[idx]
setindex!(scale::MelScale, band::MelBand, idx::Int)::MelBand = scale.bands[idx] = band

function melbands(nbands::Int, minfreq::Real = 0.0, maxfreq::Real = 8_000.0; htkmel = false)::Vector{Float64}
    minmel = hz2mel(minfreq, htkmel)
    maxmel = hz2mel(maxfreq, htkmel)
    mel2hz(minmel .+ collect(0:(nbands+1)) / (nbands+1) * (maxmel-minmel), htkmel)
end
function get_mel_bands(nbands::Int, minfreq::Real = 0.0, maxfreq::Real = 8_000.0; htkmel = false)::MelScale
    bands = melbands(nbands, minfreq, maxfreq; htkmel = htkmel)
    MelScale(nbands, [ MelBand(bands[i], bands[i+2] >= maxfreq ? bands[i+2] - 0.0000001 : bands[i+2], bands[i+1]) for i in 1:(length(bands)-2) ])
end

function digitalfilter_mel(band::MelBand, fs::Real, window_f::Function = triang; nwin = 60, filter_type = Filters.Bandpass)
    digitalfilter(filter_type(band.left, band.right, fs = fs), FIRWindow(window_f(nwin)))
end

function multibandpass_digitalfilter_mel(
        selected_bands::Vector{Int},
        fs::Real,
        window_f::Function;
        nbands::Integer = 60,
        minfreq::Real = 0.0,
        maxfreq::Real = fs / 2,
        nwin::Int = nbands,
        weights::Vector{F} where F <:AbstractFloat = fill(1., length(selected_bands))
    )::AbstractVector

    @assert length(weights) == length(selected_bands) "length(weights) != length(selected_bands): $(length(weights)) != $(length(selected_bands))"

    result_filter = zeros(Float64, nwin)
    scale = get_mel_bands(nbands, minfreq, maxfreq)
    i = 1
    @simd for b in selected_bands
        result_filter += digitalfilter_mel(scale[b], fs, window_f, nwin = nwin) * weights[i]
        i=i+1
    end
    result_filter
end

function draw_mel_filters_graph(fs::Real, window_f::Function; nbands::Integer = 60, minfreq = 0.0, maxfreq = fs / 2)
    scale = get_mel_bands(nbands, minfreq, maxfreq)
    filters = [ digitalfilter_mel(scale[i], fs, window_f; nwin = nbands) for i in 1:nbands ]
    plotfilter(filters[1]; samplerate = fs)
    for i in 2:(length(filters)-1)
        plotfilter!(filters[i]; samplerate = fs)
    end
    # last call to plot has to "return" from function otherwise the graph will not be displayed
    plotfilter!(filters[end]; samplerate = fs)
end

function plot_band(band::MelBand; minfreq::Real = 0.0, maxfreq::Real = 8_000.0, ylims = (0.0, 1.0), show_freq = true, plot_func = plot)
    common_args = (ylims = ylims, xlims = (minfreq, maxfreq), xguide = "Frequency (Hz)", yguide = "Amplitude", leg = false)
    texts = ["", show_freq ? text(string(round(Int64, band.peak)), font(pointsize = 8)) : "", ""]
    plot_func([band.left, band.peak, band.right], [ylims[1], ylims[2], ylims[1]]; annotationfontsize = 8, texts = texts, size = (1920, 1080), common_args...)
end
plot_band!(band::MelBand; kwargs...) = plot_band(band; plot_func = plot!, kwargs...)

function draw_synthetic_mel_filters_graph(; nbands::Integer = 60, minfreq::Real = 0.0, maxfreq::Real = 8_000.0)
    scale = get_mel_bands(nbands, minfreq, maxfreq)
    plot_band(scale[1]; minfreq = minfreq, maxfreq = maxfreq)
    for i in 2:(length(scale)-1)
        plot_band!(scale[i]; minfreq = minfreq, maxfreq = maxfreq)
    end
    # last call to plot has to "return" from function otherwise the graph will not be displayed
    plot_band!(scale[length(scale)]; minfreq = minfreq, maxfreq = maxfreq)
end

timerange2points(range::Tuple{T, T} where T <:Number, fs::Real)::UnitRange{Int64} = max(1, round(Int64, range[1] * fs)):round(Int64, range[2] * fs)

function draw_audio_anim(
        # TODO: figure out a way to generalize this Float64 and Float32 without getting error...
        audio_files    :: Vector{Tuple{Vector{Float64},Float32}};
        labels         :: Vector{String} = fill("", length(audio_files)),
        colors         :: Union{Vector{Symbol},Vector{RGB{Float64}}} = fill(:auto, length(audio_files)),
        outfile        :: String = homedir() * "/gif.gif",
        size           :: Tuple{Int64,Int64} = (1000, 150 * length(audio_files)),
        fps            :: Int64 = 60,
        # selected_range:
        # - 1:1000 means from point 1 to point 1000
        # - (1.1, 2.3) means from time 1.1 to time 2.3 (in seconds)
        # - :whole means "do not slice"
        selected_range :: Union{UnitRange{Int64},Tuple{Number,Number},Symbol} = :whole,
        single_graph   :: Bool = false
    )
    function draw_wav(points::Vector{Float64}, fs::Number; color = :auto, title = "", func = plot)
        func(
            collect(0:(length(points) - 1)),
            points,
            title = title,
            xlims = (0, length(points)),
            ylims = (-1, 1),
            framestyle = :zerolines,       # show axis at zeroes
            fill = 0,                      # show area under curve
            leg = false,                   # hide legend
            yshowaxis = false,             # hide y axis
            grid = false,                  # hide y grid
            ticks = false,                 # hide y ticks
            tick_direction = :none,
            linecolor = color,
            fillcolor = color,
            size = size
        )
    end
    draw_wav!(points::Vector{Float64}, fs::Number; title = "", color = :auto) = draw_wav(points, fs, func = plot!; title = title, color = color)

    @assert length(audio_files) > 0 "No audio file provided"
    @assert length(audio_files) == length(labels) "audio_files and labels mismatch in length: $(length(audio_files)) != $(length(labels))"

    wavs = []
    fss = []
    for f in audio_files
        push!(wavs, merge_channels(f[1]))
        push!(fss, f[2])
    end

    @assert length(unique(fss)) == 1 "Inconsistent bitrate across multiple files"
    @assert length(unique([x -> length(x) for wav in wavs])) == 1 "Inconsistent length across multiple files"

    if selected_range isa Tuple
        # convert seconds to points
        println("Selected time range from $(selected_range[1])s to $(selected_range[2])s")
        selected_range = timerange2points(selected_range, fss[1])
        #round(Int64, selected_range[1] * fss[1]):round(Int64, selected_range[2] * fss[1])
    end
    # slice all wavs
    if selected_range != :whole
        println("Slicing from point $(collect(selected_range)[1]) to $(collect(selected_range)[end])")
        for i in 1:length(wavs)
            wavs[i] = wavs[i][selected_range]
        end
    end
    wavlength = length(wavs[1])
    freq = fss[1]
    wavlength_seconds = wavlength / freq

    total_frames = ceil(Int64, wavlength_seconds * fps)
    step = wavlength / total_frames

    anim = nothing
    plts = []
    for (i, w) in enumerate(wavs)
        if i == 1
            push!(plts, draw_wav(w, freq; title = labels[i], color = colors[i]))
        else
            if single_graph
                draw_wav!(w, freq; title = labels[i], color = colors[i])
            else
                push!(plts, draw_wav(w, freq; title = labels[i], color = colors[i]))
            end
        end
    end

    anim = @animate for f in 1:total_frames
        println("Processing frame $(f) / $(total_frames)")
        if f != 1
            Threads.@threads for p in 1:length(plts)
                # Make previous vline invisible
                plts[p].series_list[end][:linealpha] = 0.0
            end
        end
        #Threads.@threads 
        for p in 1:length(plts)
            vline!(plts[p], [ (f-1) * step ], line = (:black, 1))
        end
        plot(plts..., layout = (length(wavs), 1))
    end

    gif(anim, outfile, fps = fps)
end

function draw_audio_anim(audio_files::Vector{String}; kwargs...)
    @assert length(audio_files) > 0 "No audio file provided"

    converted_input = []
    for f in audio_files
        wav, fs = wavread(f)
        push!(converted_input, (merge_channels(wav), fs))
    end

    draw_audio_anim(converted_input; kwargs...)
end

function draw_spectrogram(
        samples::Vector{T},
        fs::Real;
        gran::Int = 50,
        title::String = "",
        clims = (-150, 0),
        spectrogram_plot_options = (),
        melbands = (draw = false, nbands = 60, minfreq = 0.0, maxfreq = fs / 2, htkmel = false)
    ) where T <: AbstractFloat
    nw_orig::Int = round(Int64, length(samples) / gran)

    spec = spectrogram(samples, nw_orig, round(Int64, nw_orig/2); fs = fs)
    hm = heatmap(spec.time, spec.freq, pow2db.(spec.power); title = title, xguide = "Time (s)", yguide = "Frequency (Hz)", ylims = (0, fs / 2), clims = clims, background_color_inside = :black, size = (1600, 900), leg = false, spectrogram_plot_options...)
    if melbands[:draw]
        bands = get_mel_bands(melbands[:nbands], melbands[:minfreq], melbands[:maxfreq]; htkmel = melbands[:htkmel])
        yticks!(hm, push!([ bands[i].peak for i in 1:melbands[:nbands] ], melbands[:maxfreq]), push!([ string("A", i) for i in 1:melbands[:nbands] ], string(melbands[:maxfreq])))
        for i in 1:melbands[:nbands]
            hline!(hm, [ bands[i].left ], line = (1, :white), leg = false)
        end
    end
    hm
end

struct DecisionPathNode
    taken         :: Bool
    feature       :: ModalLogic.FeatureTypeFun
    test_operator :: TestOperatorFun
    threshold     :: T where T
    # TODO: add here info about the world(s)
end

const DecisionPath = Vector{DecisionPathNode}

mutable struct InstancePathInTree{S}
    file_name    :: String
    label        :: S
    tree         :: Union{Nothing,DTree{T}} where T
    predicted    :: Union{Nothing,S}
    path         :: DecisionPath
    dataset_info :: Any
    InstancePathInTree{S}(file_name::String, label::S) where S = new(file_name, label, nothing, nothing, [], ())
    InstancePathInTree{S}(file_name::String, label::S, dataset_info) where S = new(file_name, label, nothing, nothing, [], dataset_info)
    InstancePathInTree{S}(file_name::String, label::S, tree::DTree) where S = new(file_name, label, tree, nothing, [], ())
    InstancePathInTree{S}(file_name::String, label::S, tree::DTree, dataset_info) where S = new(file_name, label, tree, nothing, [], dataset_info)
end

is_correctly_classified(inst::InstancePathInTree)::Bool = inst.label === inst.predicted

get_path_in_tree(leaf::DTLeaf, X::Any, i_instance::Integer, worlds::AbstractVector{<:AbstractWorldSet}, paths::Vector{DecisionPath} = Vector(DecisionPath()))::Vector{DecisionPath} = return paths
function get_path_in_tree(tree::DTInternal, X::MultiFrameModalDataset, i_instance::Integer, worlds::AbstractVector{<:AbstractWorldSet}, paths::Vector{DecisionPath} = Vector(DecisionPath()))::Vector{DecisionPath}
    satisfied = true
	(satisfied,new_worlds) =
		ModalLogic.modal_step(
						get_frame(X, tree.i_frame),
						i_instance,
						worlds[tree.i_frame],
						tree.relation,
						tree.feature,
						tree.test_operator,
						tree.threshold)

    # TODO: add here info about the worlds that generated the decision
    push!(paths[i_instance], DecisionPathNode(satisfied, tree.feature, tree.test_operator, tree.threshold))

	worlds[tree.i_frame] = new_worlds
	get_path_in_tree((satisfied ? tree.left : tree.right), X, i_instance, worlds, paths)
end
function get_path_in_tree(tree::DTree{S}, X::GenericDataset)::Vector{DecisionPath} where {S}
	n_instances = n_samples(X)
	paths::Vector{DecisionPath} = fill([], n_instances)
	for i_instance in 1:n_instances
		worlds = DecisionTree.inst_init_world_sets(X, tree, i_instance)
		get_path_in_tree(tree.root, X, i_instance, worlds, paths)
	end
	paths
end

function get_internalnode_dirname(node::DTInternal)::String
    replace(DecisionTree.display_decision(node), " " => "_")
end

mk_tree_path(leaf::DTLeaf; path::String = "") = touch(path * "/" * string(leaf.majority) * ".txt")
function mk_tree_path(node::DTInternal; path::String = "")
    dir_name = get_internalnode_dirname(node)
    mkpath(path * "/Y_" * dir_name)
    mkpath(path * "/N_" * dir_name)
    mk_tree_path(node.left; path = path * "/Y_" * dir_name)
    mk_tree_path(node.right; path = path * "/N_" * dir_name)
end
function mk_tree_path(tree_hash::String, tree::DTree; path::String = "filtering-results/filtered")
    mkpath(path * "/" * tree_hash)
    mk_tree_path(tree.root; path = path * "/" * tree_hash)
end

function get_tree_path_as_dirpath(tree_hash::String, tree::DTree, decpath::DecisionPath; path::String = "filtering-results/filtered")::String
    current = tree.root
    result = path * "/" * tree_hash
    for node in decpath
        if current isa DTLeaf break end
        result *= "/" * (node.taken ? "Y" : "N") * "_" * get_internalnode_dirname(current)
        current = node.taken ? current.left : current.right
    end
    result
end

function apply_tree_to_datasets_wavs(
        tree_hash::String,
        tree::DTree{S},
        dataset::GenericDataset,
        wav_paths::Vector{String},
        labels::Vector{S};
        postprocess_wavs =        [ trim_wav!,      normalize! ],
        postprocess_wavs_kwargs = [ (level = 0.0,), (level = 1.0,) ],
        filter_kwargs = (),
        window_f::Function = triang,
        use_original_dataset_filesystem_tree::Bool = false,
        destination_dir::String = "filtering-results/filtered",
        remove_from_path::String = "",
        generate_spectrogram::Bool = true
    ) where {S}

    n_instances = n_samples(dataset)

    println()
    println("Applying tree $(tree_hash):")
    print_tree(tree)
    println()

    @assert n_instances == length(wav_paths) "dataset and wav_paths length mismatch! $(n_instances) != $(length(wav_paths))"
    @assert n_instances == length(labels) "dataset and labels length mismatch! $(n_instances) != $(length(labels))"

    if dataset isa MultiFrameModalDataset
        @assert n_frames(dataset) == 1 "MultiFrameModalDataset with more than one frame is still not supported! n_frames(dataset): $(n_frames(dataset))"
    end

    results = Vector{InstancePathInTree}(undef, n_instances)
    predictions = apply_tree(tree, dataset)
    paths = get_path_in_tree(tree, dataset)
    Threads.@threads for i in 1:n_instances
        results[i] = InstancePathInTree{S}(wav_paths[i], labels[i], tree)
        
        results[i].predicted = predictions[i]
        results[i].path = paths[i]
    end

    originals = Vector{Vector{Float64}}(undef, n_instances)
    samplerates = Vector{Number}(undef, n_instances)
    Threads.@threads for i in 1:n_instances
        curr_orig, samplerates[i] = wavread(wav_paths[i])
        originals[i] = merge_channels(curr_orig)
    end
    
    filtered = Vector{Vector{Float64}}(undef, n_instances)
    Threads.@threads for i in 1:n_instances
        # TODO: use path + worlds to generate dynamic filters
        if !is_correctly_classified(results[i])
            println("Skipping file $(wav_paths[i]) because it was not correctly classified...")
            continue
        end
        n_features = length(results[i].path)
        bands = Vector{Int64}(undef, n_features)
        weights = Vector{AbstractFloat}(undef, n_features)
        for j in 1:n_features
            # TODO: here goes the logic interpretation of the tree
            weights[j] =
                if ((isequal(results[i].path[j].test_operator, >=) || isequal(results[i].path[j].test_operator, >)) && results[i].path[j].taken) ||
                   ((isequal(results[i].path[j].test_operator, <=) || isequal(results[i].path[j].test_operator, <)) && !results[i].path[j].taken)
                    if results[i].path[j].threshold <= 1
                        # > than low
                        0.5
                    else
                        # > than high
                        1.0
                    end
                else
                    if results[i].path[j].threshold <= 1
                        # < than low
                        0.25
                    else
                        # < than high
                        0.5
                    end
                end
            bands[j] = results[i].path[j].feature.i_attribute
        end
        println("Applying filter to file $(wav_paths[i]) with bands $(string(collect(zip(bands, weights))))...")
        filter = multibandpass_digitalfilter_mel(bands, samplerates[i], window_f; weights = weights, filter_kwargs...)
        filtered[i] = filt(filter, originals[i])
    end

    mk_tree_path(tree_hash, tree; path = destination_dir)

    real_destination = destination_dir * "/" * tree_hash
    mkpath(real_destination)
    heatmap_png_path = Vector{String}(undef, n_instances)
    Threads.@threads for i in 1:n_instances
        if !is_correctly_classified(results[i])
            println("Skipping file $(wav_paths[i]) because it was not correctly classified...")
            continue
        end
        save_path = replace(wav_paths[i], remove_from_path => "")
        if use_original_dataset_filesystem_tree
            while startswith(save_path, "../")
                save_path = replace(save_path, "../" => "")
            end
            save_dir = real_destination
        else
            save_dir = get_tree_path_as_dirpath(tree_hash, tree, results[i].path; path = destination_dir)
        end
        filtered_file_path = save_dir * "/" * replace(save_path, ".wav" => ".filt.wav")
        original_file_path = save_dir * "/" * replace(save_path, ".wav" => ".orig.wav")
        heatmap_png_path[i] = save_dir * "/" * replace(save_path, ".wav" => ".spectrogram.png")
        mkpath(dirname(filtered_file_path))
        for (i_pp, pp) in enumerate(postprocess_wavs)
            pp(filtered[i]; (postprocess_wavs_kwargs[i_pp])...)
            pp(originals[i]; (postprocess_wavs_kwargs[i_pp])...)
        end
        println("Saving filtered file $(filtered_file_path)...")
        wavwrite(filtered[i], filtered_file_path; Fs = samplerates[i])
        wavwrite(originals[i], original_file_path; Fs = samplerates[i])
    end

    if generate_spectrogram
        for i in 1:n_instances
            if !is_correctly_classified(results[i]) continue end
            hm_filt = draw_spectrogram(filtered[i], samplerates[i]; title = "Filtered")
            hm_orig = draw_spectrogram(originals[i], samplerates[i]; title = "Original")
            plot(hm_orig, hm_filt, layout = (1, 2))
            savefig(heatmap_png_path[i])
        end
    end

    results
end

# TODO: implement this function for real (it is just a draft for now...)
# function apply_dynfilter!(
#         dynamic_filter::Matrix{Integer},
#         sample::AbstractVector{T};
#         samplerate = 16000,
#         wintime = 0.025,
#         steptime = 0.01,
#         window_f::Function
#     )::Vector{T} where {T <: Real}

#     nbands = size(dynamic_filter, 2)
#     ntimechunks = ntimechunks
#     nwin = round(Integer, wintime * sr)
#     nstep = round(Integer, steptime * sr)

#     window = window_f(nwin)

#     winsize = (samplerate / 2) / nwin

#     # init filters
#     filters = [ digitalfilter(Filters.Bandpass((i-1) * winsize, (i * winsize) - 1, fs = samplerate), window) for i in 1:nbands ]

#     # combine filters to generate EQs
#     slice_filters = Vector{Vector{Float64}}(undef, ntimechunks)
#     for i in 1:ntimechunks
#         step_filters = (@view filters[findall(isequal(1), dynamic_filter[i])])
#         slice_filters[i] = maximum.(collect(zip(step_filters...)))
#     end

#     # write filtered time chunks to new_track
#     new_track = Vector{T}(undef, length(sample) - 1)
#     time_chunk_length = length(sample) / ntimechunks
#     for i in 1:ntimechunks
#         new_track[i:(i*time_chunk_length) - 1] = filt(slice_filters[i], sample[i:(i*time_chunk_length) - 1])
#     end

#     new_track
# end
