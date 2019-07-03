local ecs = ...
local world = ecs.world

ecs.import "ant.event"

local render = import_package "ant.render"
local mathbaselib = require "math3d.baselib"
local ru = render.util

local filterutil = require "filter.util"

local mathpkg = import_package "ant.math"
local ms = mathpkg.stack
local mu = mathpkg.util

local filter_properties = ecs.system "filter_properties"
function filter_properties:update()
	for _, prim_eid in world:each("primitive_filter") do
		local e = world[prim_eid]
		local filter = e.primitive_filter
		filterutil.load_lighting_properties(world, filter)
		if e.shadow == nil then
			filterutil.load_shadow_properties(world, filter)
		end

		filterutil.load_postprocess_properties(world, filter)
	end
end

local primitive_filter_sys = ecs.system "primitive_filter_system"
primitive_filter_sys.dependby "filter_properties"
primitive_filter_sys.singleton "hierarchy_transform_result"
primitive_filter_sys.singleton "event"

local function update_transform(transform, hierarchy_cache)
	local peid = transform.parent
	local localmat = ms:srtmat(transform)
	if peid then
		local parentresult = hierarchy_cache[peid]
		local parentmat = parentresult.world
		if parentmat then
			local hie_result = parentresult.hierarchy
			local slotname = transform.slotname
			if hie_result and slotname then
				local hiemat = ms:matrix(hie_result[slotname])
				localmat = ms(parentmat, hiemat, localmat, "**P")
			else
				localmat = ms(parentmat, localmat, "*P")
			end
		end
	end

	local w = transform.world
	ms(w, localmat, "=")
	return w
end

--luacheck: ignore self
local function reset_results(results)
	for k, result in pairs(results) do
		result.cacheidx = 1
	end
end

local function get_material(prim, primidx, materialcontent, material_refs)
	if material_refs then
		local idx = material_refs[primidx] or 1
		return materialcontent[idx]
	end

	local materialidx = prim.material or 0
	return materialcontent[materialidx+1] or materialcontent[1]
end

local function is_visible(meshname, submesh_refs)
	if submesh_refs == nil then
		return true
	end

	if submesh_refs then
		local ref = submesh_refs[meshname]
		if ref then
			return ref.visible
		end
	end
end

local function get_material_refs(meshname, submesh_refs)
	if submesh_refs then
		local ref = assert(submesh_refs[meshname])
		return assert(ref.material_refs)
	end
end

local function get_scale_mat(worldmat, scenescale)
	if scenescale and scenescale ~= 1 then
		return ms(worldmat, ms:srtmat(mu.scale_mat(scenescale)), "*P")
	end
	return worldmat
end

local function filter_mesh(eid, meshcomp, worldmat, materialcontent, filter)
	local meshscene = meshcomp.assetinfo.handle

	local lodlevel = meshcomp.lod or 1
	local sceneidx = meshscene.scenelods and (meshscene.scenelods[lodlevel]) or meshscene.sceneidx

	local scenes = meshscene.scenes[sceneidx]
	local submesh_refs = meshcomp.submesh_refs
	for _, meshnode in ipairs(scenes) do
		local name = meshnode.name
		if is_visible(name, submesh_refs) then
			local trans = get_scale_mat(worldmat, meshscene.scenescale)
			if meshnode.transform then
				trans = ms(trans, meshnode.transform, "*P")
			end

			local material_refs = get_material_refs(name, submesh_refs)

			for groupidx, group in ipairs(meshnode) do
				local material = get_material(group, groupidx, materialcontent, material_refs)
				ru.insert_primitive(eid, group, material, trans, filter)
			end
		end
	end
end

function primitive_filter_sys:update()	

	for _, prim_eid in world:each("primitive_filter") do
		local e = world[prim_eid]
		local filter = e.primitive_filter
		reset_results(filter.result)
		local viewtag = filter.view_tag
		local filtertag = filter.filter_tag

		for _, eid in world:each(filtertag) do
			local ce = world[eid]
			local vt = ce[viewtag]
			local ft = ce[filtertag]
			if vt and ft then
				filter_mesh(eid, ce.mesh, ce.transform.world, ce.material.content, filter)
			end
		end
	end
end

function primitive_filter_sys:post_init()	
	for eid in world:each_new("transform") do
		self.event:new(eid, "transform")
	end
end

function primitive_filter_sys:event_changed()
	local hierarchy_cache = self.hierarchy_transform_result
	for eid, events, init in self.event:each("transform") do
		local e = world[eid]
		local trans = e.transform

		if init then
			assert(not next(events))
			update_transform(e.transform, hierarchy_cache)
		else
			for k, v in pairs(events) do
				if k == 's' or k == 'r' or k == 't' then
					ms(trans[k], v, "=")
					update_transform(e.transform, hierarchy_cache)
				elseif k == 'parent' then
					trans.parent = v
					update_transform(e.transform, hierarchy_cache)
				elseif k == 'base' then
					ms(trans.base, v, "=")
					update_transform(e.transform, hierarchy_cache)
				end
			end
		end
	end
end

