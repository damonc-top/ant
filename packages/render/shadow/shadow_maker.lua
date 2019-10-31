-- TODO: should move to scene package

local ecs = ...
local world = ecs.world

ecs.import "ant.scene"

local viewidmgr = require "viewid_mgr"
local renderutil= require "util"
local camerautil= require "camera.util"
local shadowutil= require "shadow.util"
local fbmgr 	= require "framebuffer_mgr"

local assetpkg 	= import_package "ant.asset"
local assetmgr 	= assetpkg.mgr

local mathpkg 	= import_package "ant.math"
local ms 		= mathpkg.stack
local mc 		= mathpkg.constant
local fs 		= require "filesystem"
local mathbaselib= require "math3d.baselib"

local platform  = require "platform"
local platOS 	= platform.OS

local function is_hw_support_depth_sample()
	if platOS == "iOS" then
		local iosinfo = import_package "ant.ios"
		local a_series = iosinfo.cpu:lower():match "apple a(%d)"
		if a_series then
			local num = tonumber(a_series)
			return num > 8
		end
	end
end

local hw_support_depth_sample = is_hw_support_depth_sample()

ecs.component "csm" {depend = "material"}
	.split_ratios "real[2]"
	.index "int" (0)
	.stabilize "boolean" (true)

ecs.component "omni"	-- for point/spot light

ecs.component "csm_split_config"
	.min_ratio		"real"(0.0)
	.max_ratio		"real"(1.0)
	.pssm_lambda	"real"(1.0)
	.num_split		"int" (4)
	.ratios	 		"real[]"


ecs.component "shadow"
	.shadowmap_size "int" 	(1024)
	.bias 			"real"	(0.003)
	.normal_offset 	"real" (0)
	.depth_type 	"string"("linear")		-- "inv_z" / "linear"
	["opt"].split	"csm_split_config"

local maker_camera = ecs.system "shadowmaker_camera"
maker_camera.depend "primitive_filter_system"
maker_camera.dependby "filter_properties"
local function get_directional_light_dir_T()
	local ld = shadowutil.get_directional_light_dir(world)
	return ms(ld, "T")
end

-- local function create_crop_matrix(shadow)
-- 	local view_camera = camerautil.get_camera(world, "main_view")

-- 	local csm = shadow.csm
-- 	local csmindex = csm.index
-- 	local shadowcamera = camerautil.get_camera(world, "csm" .. csmindex)
-- 	local shadow_viewmatrix = ms:view_proj(shadowcamera)

-- 	local bb_LS = get_frustum_points(view_camera, view_camera.frustum, shadow_viewmatrix, shadow.csm.split_ratios)
-- 	local aabb = bb_LS:get "aabb"
-- 	local min, max = aabb.min, aabb.max
-- 	min[4], max[4] = 1, 1	-- as point

-- 	local _, proj = ms:view_proj(nil, shadowcamera.frustum)
-- 	local minproj, maxproj = ms(min, proj, "%", max, proj, "%TT")

-- 	local scalex, scaley = 2 / (maxproj[1] - minproj[1]), 2 / (maxproj[2] - minproj[2])
-- 	if csm.stabilize then
-- 		local quantizer = shadow.shadowmap_size
-- 		scalex = quantizer / math.ceil(quantizer / scalex);
-- 		scaley = quantizer / math.ceil(quantizer / scaley);
-- 	end

-- 	local function calc_offset(a, b, scale)
-- 		return (a + b) * 0.5 * scale
-- 	end

-- 	local offsetx, offsety = 
-- 		calc_offset(maxproj[1], minproj[1], scalex), 
-- 		calc_offset(maxproj[2], minproj[2], scaley)

-- 	if csm.stabilize then
-- 		local half_size = shadow.shadowmap_size * 0.5;
-- 		offsetx = math.ceil(offsetx * half_size) / half_size;
-- 		offsety = math.ceil(offsety * half_size) / half_size;
-- 	end
	
-- 	return {
-- 		scalex, 0, 0, 0,
-- 		0, scaley, 0, 0,
-- 		0, 0, 1, 0,
-- 		offsetx, offsety, 0, 1,
-- 	}
-- end

local function keep_shadowmap_move_one_texel(minextent, maxextent, shadowmap_size)
	local texsize = 1 / shadowmap_size

	local unit_pretexel = ms(maxextent, minextent, "-", {texsize, texsize, 0, 0}, "*P")
	local invunit_pretexel = ms(unit_pretexel, "rP")

	local function limit_move_in_one_texel(value)
		-- value /= unit_pretexel;
		-- value = floor( value );
		-- value *= unit_pretexel;
		return ms(value, invunit_pretexel, "*f", unit_pretexel, "*T")
	end

	local newmin = limit_move_in_one_texel(minextent)
	local newmax = limit_move_in_one_texel(maxextent)
	
	minextent[1], minextent[2] = newmin[1], newmin[2]
	maxextent[1], maxextent[2] = newmax[1], newmax[2]
end

local function calc_shadow_camera(view_camera, split_ratios, lightdir, shadowmap_size, stabilize, shadowcamera)
	shadowcamera.viewdir = lightdir

	-- frustum_desc can cache, only camera distance changed or ratios change need recalculate
	local frustum_desc = shadowutil.split_new_frustum(view_camera.frustum, split_ratios)
	local _, _, vp = ms:view_proj(view_camera, frustum_desc, true)
	local viewfrustum = mathbaselib.new_frustum(ms, vp)
	local corners_WS = viewfrustum:points()

	local center_WS = viewfrustum:center(corners_WS)
	local min_extent, max_extent
	if stabilize then
		local radius = viewfrustum:max_radius(center_WS, corners_WS)
		--radius = math.ceil(radius * 16.0) / 16.0	-- round to 16
		min_extent, max_extent = {-radius, -radius, -radius}, {radius, radius, radius}
		keep_shadowmap_move_one_texel(min_extent, max_extent, shadowmap_size)
	else
		-- using camera world matrix right axis as light camera matrix up direction
		-- look at matrix up direction should select one that not easy parallel with view direction
		local shadow_viewmatrix = ms:lookat(center_WS, lightdir, nil, true)
		local minv, maxv = ms:minmax(corners_WS, shadow_viewmatrix)
		min_extent, max_extent = ms(minv, "T", maxv, "T")
	end

	shadowcamera.eyepos = ms(center_WS, "T")--ms(center_WS, lightdir, {-min_extent[3]}, "*+P"))
	--shadowcamera.updir(updir)
	shadowcamera.frustum = {
		ortho=true,
		l = min_extent[1], r = max_extent[1],
		b = min_extent[2], t = max_extent[2],
		n = min_extent[3], f = max_extent[3],
	}
end

function maker_camera:update()
	local lightdir = shadowutil.get_directional_light_dir(world)
	local shadowentity = world:first_entity "shadow"
	local shadowcfg = shadowentity.shadow
	local stabilize = shadowcfg.stabilize
	local shadowmap_size = shadowcfg.shadowmap_size

	local view_camera = camerautil.get_camera(world, "main_view")

	for _, eid in world:each "csm" do
		local csmentity = world[eid]

		local shadowcamera = camerautil.get_camera(world, csmentity.camera_tag)
		local csm = world[eid].csm
		calc_shadow_camera(view_camera, csm.split_ratios, lightdir, shadowmap_size, stabilize, shadowcamera)
	end
end
local sm = ecs.system "shadow_maker"
sm.depend "primitive_filter_system"
sm.depend "shadowmaker_camera"
sm.dependby "render_system"
--sm.dependby "debug_shadow_maker"

local function create_csm_entity(view_camera, lightdir, index, ratios, viewrect, shadowmap_size, linear_shadow)
	local camera_tag = "csm" .. index
	local csmcamera = {type = "csm", updir = mc.Y_AXIS}
	local stabilize = false
	calc_shadow_camera(view_camera, ratios, lightdir, shadowmap_size, stabilize, csmcamera)
	camerautil.bind_camera(world, camera_tag, csmcamera)

	local cast_material_path = linear_shadow and 
		fs.path "/pkg/ant.resources/depiction/materials/shadow/csm_cast_linear.material" or
		fs.path "/pkg/ant.resources/depiction/materials/shadow/csm_cast.material"

	local eid = world:create_entity {
		material = {
			{ref_path = cast_material_path},
		},
		csm = {
			split_ratios= ratios,
			index 		= index,
			stabilize 	= stabilize,
		},
		viewid = viewidmgr.get(camera_tag),
		primitive_filter = {
			view_tag = "main_view",
			filter_tag = "can_cast",
		},
		camera_tag = camera_tag,
		render_target = {
			viewport = {
				rect = viewrect,
				clear_state = {
					color = 0xffffffff,
					depth = 1,
					stencil = 0,
					clear = linear_shadow and "colordepth" or "depth",
				}
			},
		},
		name = "direction light shadow maker:" .. index,
	}

	local e = world[eid]
	e.csm.split_distance_VS = csmcamera.frustum.f - view_camera.frustum.n
	return eid
end

local function get_render_buffers(width, height, linear_shadow)
	if linear_shadow then
		local flags = renderutil.generate_sampler_flag {
			RT="RT_ON",
			MIN="LINEAR",
			MAG="LINEAR",
			U="CLAMP",
			V="CLAMP",
		}

		return {
			{
				format = "RGBA8",
				w=width,
				h=height,
				layers=1,
				flags=flags,
			},
			{
				format = "D24S8",
				w=width,
				h=height,
				layers=1,
				flags=flags,
			},
		}

	end

	return {
		{
			format = "D32F",
			w=width,
			h=height,
			layers=1,
			flags=renderutil.generate_sampler_flag{
				RT="RT_ON",
				MIN="LINEAR",
				MAG="LINEAR",
				U="CLAMP",
				V="CLAMP",
				COMPARE="COMPARE_LEQUAL",
				BOARD_COLOR="0",
			},
		}
	}
end

local function create_shadow_entity(view_camera, shadowmap_size, numsplit, depth_type)
	local height = shadowmap_size
	local width = shadowmap_size * numsplit

	local viewfrustum = view_camera.frustum

	local min_ratio, max_ratio 	= 0.03, 1.0
	local pssm_lambda 			= 0.85
	
	local ratios = shadowutil.calc_split_distance_ratio(min_ratio, max_ratio, 
						viewfrustum.n, viewfrustum.f, 
						pssm_lambda, numsplit)

	return world:create_entity {
		shadow = {
			shadowmap_size 	= shadowmap_size,
			bias 			= 0.003,
			depth_type 		= depth_type,
			normal_offset 	= 0,
			split = {
				min_ratio 	= min_ratio,
				max_ratio 	= max_ratio,
				pssm_lambda = pssm_lambda,
				num_split 	= numsplit,
				ratios 		= ratios,
			}
		},
		frame_buffer = {
			render_buffers = get_render_buffers(width, height, depth_type == "linear"),
		}
	}
end

function sm:post_init()
	-- this function should move to somewhere which call 'entity spawn'
	local shadowmap_size 	= 1024
	local depth_type 		= hw_support_depth_sample and "inv_z" or "linear"
	local linear_shadow 	= depth_type == "linear"
	local numsplit 			= 4

	local view_camera		= camerautil.get_camera(world, "main_view")
	local seid 	= create_shadow_entity(view_camera, shadowmap_size, numsplit, depth_type)
	local se 	= world[seid]
	local fb 	= se.frame_buffer
	local lightdir = get_directional_light_dir_T()

	local ratios = se.shadow.split.ratios

	local viewrect = {x=0, y=0, w=shadowmap_size, h=shadowmap_size}
	for ii=1, numsplit do
		local tagname = "csm" .. ii
		local csm_viewid = viewidmgr.get(tagname)
		fbmgr.bind(csm_viewid, fb)
		viewrect.x = (ii-1)*shadowmap_size
		create_csm_entity(view_camera, lightdir, ii, ratios[ii], viewrect, shadowmap_size, linear_shadow)
	end
end

function sm:update()
	for _, eid in world:each "csm" do
		local sm = world[eid]
		local filter = sm.primitive_filter
		local results = filter.result
		local function replace_material(result, material)
			local mi = assetmgr.get_resource(material.ref_path)	-- must only one material content
			for i=1, result.cacheidx - 1 do
				local r = result[i]
				r.material = mi
			end
		end
	
		local shadowmaterial = sm.material
		replace_material(results.opaticy, 		shadowmaterial)
		replace_material(results.translucent, 	shadowmaterial)
	end
end