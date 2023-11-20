local cr = require "thread.compile"
local serialize = import_package "ant.serialize"
local bgfx = require "bgfx"
local fastio = require "fastio"

local PM = require "programan.server"
PM.program_init{
    max = bgfx.get_caps().limits.maxPrograms - bgfx.get_stats "n".numPrograms
}

local function readall(path)
    local realpath = cr.compile(path) or error(("`%s` cannot compile."):format(path))
    return fastio.readall(realpath, path)
end

local function uniform_info(shader, uniforms)
    local shader_uniforms = bgfx.get_shader_uniforms(shader)
    if shader_uniforms then
        for _, h in ipairs(shader_uniforms) do
            local name, type, num = bgfx.get_uniform_info(h)
            local u = uniforms[name]
            if u then
                if u.handle ~= h or u.type ~= type or u.num ~= num then
                    error(("same uniform name, but with different field: handle:%d, %d, type:%d, %d, num: %d, %d"):format(u.handle, h, u.type, type, u.num, num))
                end
            else
                uniforms[name] = { handle = h, name = name, type = type, num = num }
            end
        end
    end
end

local function loadShader(shaderfile)
    if shaderfile then
        local h = bgfx.create_shader(bgfx.memory_buffer(readall(shaderfile)))
        bgfx.set_name(h, shaderfile)
        return h
    end
end

local function fetch_uniforms(h, ...)
    local uniforms = {}
    local function fetch_uniforms_(h, ...)
        if h then
            uniform_info(h, uniforms)
            return fetch_uniforms_(...)
        end
    end
    fetch_uniforms_(h, ...)
    return uniforms
end

local function from_handle(handle)
    if handle then
        local pid = PM.program_new()
        PM.program_set(pid, handle)
        return pid
    end
end

local function createRenderProgram(fxcfg)
    local dh, depth_prog, depth_uniforms
    if fxcfg.depth then
        dh = loadShader(fxcfg.depth)
        depth_prog = bgfx.create_program(dh, false)
        if nil == depth_prog then
            error "Depth shader provided, but create depth program faield"
        end

        depth_uniforms = fetch_uniforms(dh)
    end

    local prog, uniforms, vh, fh
    if fxcfg.vs or fxcfg.fs then
        vh = loadShader(fxcfg.vs)
        fh = loadShader(fxcfg.fs)
        prog = bgfx.create_program(vh, fh, false)
        uniforms = fetch_uniforms(vh, fh)
    end

    if not (prog or depth_prog) then
        error(("create program failed, filename:%s"):format(fxcfg.vs))
    end

    local fx = {
        shader_type     = fxcfg.shader_type,
        setting         = fxcfg.setting or {},
        vs              = vh,
        fs              = fh,
        prog            = prog,
        uniforms        = uniforms,
        varyings        = fxcfg.varyings,
    }

    if depth_prog then
        fx.depth = {
            handle  = dh,
            prog    = depth_prog,
            uniforms= depth_uniforms,
            varyings= fxcfg.depth_varyings,
        }
    end

    return fx
end

local function createComputeProgram(fxcfg)
    local ch = loadShader(fxcfg.cs)
    local prog = bgfx.create_program(ch, false)
    if prog then
        return {
            shader_type = fxcfg.shader_type,
            setting     = fxcfg.setting or {},
            cs          = ch,
            prog        = prog,
            uniforms    = fetch_uniforms(ch),
        }
    else
        error(string.format("create program failed, cs:%d", ch))
    end
end

local S = require "thread.main"

local function is_compute_material(fxcfg)
    return fxcfg.shader_type == "COMPUTE"
end

local function absolute_path(path, base)
    if path:sub(1,1) == "/" then
        return path
    end
    return base:match "^(.-)[^/|]*$" .. (path:match "^%./(.+)$" or path)
end

local MATERIALS = {}

local MATERIAL_MARKED = {}

local function build_fxcfg(filename, fx)
    local function stage_filename(stage)
        if fx[stage] then
            return ("%s|%s.bin"):format(filename, stage)
        end
    end
    return {
        shader_type = fx.shader_type,
        setting     = fx.setting,
        vs          = stage_filename "vs",
        fs          = stage_filename "fs",
        cs          = stage_filename "cs",
        depth       = stage_filename "depth",
        varyings    = fx.varyings,
        depth_varyings=fx.depth and fx.depth.varyings or nil,
    }
end

local function create_fx(cfg)
    return is_compute_material(cfg) and
        createComputeProgram(cfg) or
        createRenderProgram(cfg)
end

local function is_uniform_obj(t)
    return nil ~= ('ut'):match(t)
end

local function update_uniforms_handle(attrib, uniforms, filename)
    for n, v in pairs(attrib) do
        if is_uniform_obj(v.type) then
            v.handle = assert(uniforms[n]).handle
        end
        local tex = v.texture or v.image
        if tex then
            local texturename = absolute_path(tex, filename)
            local sampler = v.sampler or "SAMPLER2D"
            v.value = S.texture_create_fast(texturename, sampler)
        end
    end
end

local function material_create(filename)
    local material  = serialize.parse(filename, readall(filename .. "|main.cfg"))
    local attribute = serialize.parse(filename, readall(filename .. "|attr.cfg"))
    local fxcfg = build_fxcfg(filename, assert(material.fx, "Invalid material"))
    material.fx = create_fx(fxcfg)
    update_uniforms_handle(attribute.attribs, material.fx.uniforms, filename)

    if attribute.depth then
        update_uniforms_handle(attribute.depth.attribs, material.fx.depth.uniforms, filename)
    end

    material.fx.prog = from_handle(material.fx.prog)
    if material.fx.depth then
        material.fx.depth.prog = from_handle(material.fx.depth.prog)
    end
    return material, fxcfg, attribute
end

function S.material_create(filename)
    local material, fxcfg, attribute = material_create(filename)
    local pid = material.fx.prog
    if pid then
        MATERIALS[pid] = {
            filename = filename,
            material = material,
            cfg      = fxcfg,
            attr     = attribute
        }
    end

    if material.fx.depth then
        local dpid = material.fx.depth.prog
        MATERIALS[dpid] = {
            filename = filename,
            material = material,
            cfg      = fxcfg,
            attr     = attribute
        }
    end

    return material, attribute
end

function S.material_mark(pid)
    MATERIAL_MARKED[pid] = true
end

function S.material_unmark(pid)
    MATERIAL_MARKED[pid] = nil
end

local function material_destroy(material)
    local fx = material.fx

    -- why? PM only keep 16 bit data(it's bgfx handle data), but program type in high 16 bit with int32 data, we need to recover the type for handle when destroy
    local function make_prog_handle(h)
        assert(h ~= 0xffff)
        --handle type, see: luabgfx.h:7, with enum BGFX_HANDLE
        local PROG_TYPE<const> = 1
        return (PROG_TYPE<<16)|h
    end

    --DO NOT clean fx.prog to nil
    local h = PM.program_reset(fx.prog)
    bgfx.destroy(make_prog_handle(h))

    local function destroy_stage(stage)
        if fx[stage] then
            bgfx.destroy(fx[stage])
            fx[stage] = nil
        end
    end
    destroy_stage "vs"
    destroy_stage "fs"
    destroy_stage "cs"
end

--the serive call will fully remove this material, both cpu and gpu side
function S.material_destroy(material)
    local pid = material.fx.prog
    assert(MATERIALS[pid])
    MATERIALS[pid] = nil

    material_destroy(material)
end

-- local REMOVED_PROGIDS = {}
-- local REQUEST_PROGIDS = {}

function S.material_check()
    local removed = PM.program_remove()
    if removed then
        for _, removeid in ipairs(removed) do
            if nil == MATERIAL_MARKED[removeid] then
                local mi = assert(MATERIALS[removeid])
                log.info(("Remove prog:%d, from file:%s"):format(removeid, mi.filename))
                -- we just destroy bgfx program handle and shader handles, but not remove 'material' from cpu side
                material_destroy(mi.material)
            end
        end
    end

    local requested = PM.program_request()
    if requested then
        for _, requestid in ipairs(requested) do
            local mi = MATERIALS[requestid]
            if mi then
                assert(not MATERIAL_MARKED[requestid])
                log.info(("Recreate prog:%d, from file:%s"):format(requestid, mi.filename))
                local newfx = create_fx(mi.cfg)
                PM.program_set(requestid, newfx.prog)
                newfx.prog = requestid

                mi.material.fx = newfx
            else
                log.info(("Can not create prog:%d, it have been fully remove by 'S.material_destroy'"):format(requestid))
            end
        end
    end
end
