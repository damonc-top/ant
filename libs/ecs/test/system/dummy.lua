local ecs = ...
local world = ecs.world

local dummy = ecs.system "dummy"

dummy.singleton "init"
dummy.depend "init"
dummy.import "foobar"	-- import foobar methods

function dummy:init()
	print ("Dummy init")
	self:init_print()
	world:new_entity "foobar"
end

function dummy:update()
	print ("Dummy update")
end

function dummy.notify:foobar(set)
	for _, eid in ipairs(set) do
		print ("Notify", eid)
		local e = world[eid]
		if e then
			e:foobar_print()
		end
	end
end
