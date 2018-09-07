using Libdl

const config_path = joinpath(@__DIR__, "ext.jl")
const previous_config_path = config_path * ".bak"

function write_ext(config, path)
    open(path, "w") do io
        println(io, "# autogenerated file, do not edit")
        for (key,val) in config
            println(io, "const $key = $(repr(val))")
        end
    end
end

function read_ext(path)
    config = Dict{Symbol,Any}()
    r = r"^const (\w+) = (.+)$"
    open(path, "r") do io
        for line in eachline(io)
            m = match(r, line)
            if m != nothing
                config[Symbol(m.captures[1])] = eval(Meta.parse(m.captures[2]))
            end
        end
    end
    return config
end

function main()
    ispath(config_path) && mv(config_path, previous_config_path; force=true)
    config = Dict{Symbol,Any}()


    ## discover stuff

    VERSION >= v"0.7.0-DEV.2576" || error("This version of LLVM.jl requires Julia 0.7")

    # figure out the path to libLLVM by looking at the libraries loaded by Julia
    libllvm_paths = filter(Libdl.dllist()) do lib
        occursin("LLVM", basename(lib))
    end
    if isempty(libllvm_paths)
        error("""Cannot find the LLVM library loaded by Julia.
                 Please use a version of Julia that has been built with USE_LLVM_SHLIB=1 (like the official binaries).
                 If you are, please file an issue and attach the output of `Libdl.dllist()`.""")
    end
    if length(libllvm_paths) > 1
        error("""Multiple LLVM libraries loaded by Julia.
                 Please file an issue and attach the output of `Libdl.dllist()`.""")
    end
    config[:libllvm_path] = first(libllvm_paths)

    config[:libllvm_version] = Base.libllvm_version::VersionNumber
    vercmp_match(a,b)  = a.major==b.major &&  a.minor==b.minor
    vercmp_compat(a,b) = a.major>b.major  || (a.major==b.major && a.minor>=b.minor)

    llvmjl_wrappers = filter(path->isdir(joinpath(@__DIR__, "..", "lib", path)),
                             readdir(joinpath(@__DIR__, "..", "lib")))

    matching_wrappers = filter(wrapper->vercmp_match(config[:libllvm_version],
                                                     VersionNumber(wrapper)),
                               llvmjl_wrappers)
    config[:llvmjl_wrapper] = if !isempty(matching_wrappers)
        @assert length(matching_wrappers) == 1
        matching_wrappers[1]
    else
        compatible_wrappers = filter(wrapper->vercmp_compat(config[:libllvm_version],
                                                            VersionNumber(wrapper)),
                                     llvmjl_wrappers)
        isempty(compatible_wrappers) && error("Could not find any compatible wrapper for LLVM $(config[:libllvm_version])")
        last(compatible_wrappers)
    end

    # TODO: figure out the name of the native target
    config[:libllvm_targets] = [:NVPTX, :AMDGPU]

    # backwards-compatibility
    config[:libllvm_system] = false
    config[:configured] = true


    ## (re)generate ext.jl

    if isfile(previous_config_path)
        @debug "Checking validity of existing ext.jl..."
        previous_config = read_ext(previous_config_path)

        if config == previous_config
            @info "LLVM.jl has already been built for this toolchain, no need to rebuild"
            mv(previous_config_path, config_path; force=true)
            return
        end
    end

    write_ext(config, config_path)

    return
end

main()
