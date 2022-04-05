# this simple code assumes a plugin AbstractInterpreter manages its own code cache
# in a way that it is totally separated from the native code cache

# TODO more composable way
global PLUGIN_INTERPRETER::AbstractInterpreter = NativeInterpreter()
setplugin!(interp::AbstractInterpreter) = let
    global PLUGIN_INTERPRETER
    PLUGIN_INTERPRETER = interp
end
isplugin(interp::AbstractInterpreter) = let
    global PLUGIN_INTERPRETER
    interp === PLUGIN_INTERPRETER
end

function new_opaque_closure(ci::CodeInfo, nargs::Int, @nospecialize(env...))
    @assert ci.inferred "unoptimized IR unsupported"
    argt = argtypes_to_type((ci.slottypes::Vector{Any})[2:nargs+1])
    # NOTE: we need ir.argtypes[1] == typeof(env)
    return ccall(:jl_new_opaque_closure_from_code_info, Any,
        (Any, Any, Any, Any, Any, Cint, Any, Cint, Cint, Any),
        argt, Union{}, Any, @__MODULE__, ci, 0, nothing, nargs, false, env)
end

function execute_with_plugin(f, args...; interp::AbstractInterpreter = PLUGIN_INTERPRETER)
    tt = Tuple{Core.Typeof(f), Any[Core.Typeof(args[i]) for i = 1:length(args)]...}
    world = get_world_counter() # TODO make this world match with the world of `interp`
    matches = _methods_by_ftype(tt, -1, world)
    matches !== nothing || throw(MethodError(f, args, world))
    length(matches) ≠ 1 && throw(MethodError(f, args, world))
    m = first(matches)::MethodMatch
    ci, rt = typeinf_code(interp,
        m.method, m.spec_types, m.sparams, true)
    if ci === nothing
        # builtin, or bad generated function
        return f(args...) # XXX
    end
    # TODO support varargs
    oc = new_opaque_closure(ci, length(args))
    return oc(args...)
end

module Plugin
import ..execute_with_plugin, ..setplugin!
export execute_with_plugin, setplugin!
end
