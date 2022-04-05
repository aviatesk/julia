# %%
const CC = Core.Compiler
using Test, .CC.Plugin
import Core: MethodInstance, CodeInstance
import .CC: WorldRange, WorldView

# %%
# SinCosRewriter
# --------------

struct SinCosRewriterCache
    dict::IdDict{MethodInstance,CodeInstance}
end
struct SinCosRewriter <: CC.AbstractInterpreter
    interp::CC.NativeInterpreter
    cache::SinCosRewriterCache
    SinCosRewriter(world = Base.get_world_counter();
        interp = CC.NativeInterpreter(world),
        cache = SinCosRewriterCache(IdDict{MethodInstance,CodeInstance}())
        ) = new(interp, cache)
end
CC.InferenceParams(interp::SinCosRewriter) = CC.InferenceParams(interp.interp)
CC.OptimizationParams(interp::SinCosRewriter) = CC.OptimizationParams(interp.interp)
CC.get_world_counter(interp::SinCosRewriter) = CC.get_world_counter(interp.interp)
CC.get_inference_cache(interp::SinCosRewriter) = CC.get_inference_cache(interp.interp)
CC.code_cache(interp::SinCosRewriter) = WorldView(interp.cache, WorldRange(CC.get_world_counter(interp)))
CC.get(wvc::WorldView{<:SinCosRewriterCache}, mi::MethodInstance, default) = get(wvc.cache.dict, mi, default)
CC.getindex(wvc::WorldView{<:SinCosRewriterCache}, mi::MethodInstance) = getindex(wvc.cache.dict, mi)
CC.haskey(wvc::WorldView{<:SinCosRewriterCache}, mi::MethodInstance) = haskey(wvc.cache.dict, mi)
CC.setindex!(wvc::WorldView{<:SinCosRewriterCache}, ci::CodeInstance, mi::MethodInstance) = setindex!(wvc.cache.dict, ci, mi)

function CC.abstract_call_gf_by_type(
    interp::SinCosRewriter, @nospecialize(f),
    arginfo::CC.ArgInfo, @nospecialize(atype),
    sv::CC.InferenceState, max_methods::Int)
    if f === sin
        f = cos
        atype′ = CC.unwrap_unionall(atype)::DataType
        atype′ = Tuple{typeof(cos), atype′.parameters[2:end]...}
        atype = CC.rewrap_unionall(atype′, atype)
    end
    return Base.@invoke CC.abstract_call_gf_by_type(
        interp::CC.AbstractInterpreter, f,
        arginfo::CC.ArgInfo, atype,
        sv::CC.InferenceState, max_methods::Int)
end

setplugin!(SinCosRewriter())

# simple
@test execute_with_plugin() do
    sin(42)
end == cos(42)
@test execute_with_plugin(42) do a
    sin(a)
end == cos(42)
@test execute_with_plugin(sin, 42) do f, a
    f(a)
end == cos(42)

# # global # FIXME this segfaults
# nested(a) = sin(a) # => cos(a)
# @test execute_with_plugin(42) do a
#     nested(a)
# end == cos(42)

# dynamic
gv::Any = 42
@test execute_with_plugin() do
    sin(gv::Any) # dynamic dispatch
end == cos(42)
@test execute_with_plugin(sin) do f
    f(gv)
end == cos(42)
gf::Any = sin
@test execute_with_plugin() do
    (gf::Any)(gv::Any)
end == cos(42)

# end to end
function kernel(n)
    r = 0
    for i = 1:n
        r += sum(sincos(i))
    end
    return r
end
function kernel_transformed(n)
    r = 0
    for i = 1:n
        r += sum((cos(i), cos(i)))
    end
    return r
end
@test execute_with_plugin(kernel, 20) == kernel_transformed(20)
