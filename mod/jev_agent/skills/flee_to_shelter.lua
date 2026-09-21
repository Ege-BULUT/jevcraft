-- Run into the known shelter (through its door), or away from hostiles.
local U, A = jev.u, jev.a

jev.register_skill({
	id = "flee_to_shelter", label = "🏃 Flee to shelter", timeout = 60,
	offer = function(p, x)
		local threat = x.hostile and x.hostile.dist <= 16
		if not threat and not x.night then
			return nil
		end
		local inside = x.shelter and U.dist(x.pos, x.shelter) < 1.5
		if inside then
			return {ok = false, detail = "you are already inside your shelter", prio = 0}
		end
		local prio = (threat and x.hp <= 8) and 96 or ((x.night and x.shelter) and 72 or 30)
		if x.shelter and U.dist(x.pos, x.shelter) < 96 then
			return {ok = true, prio = prio, detail = "walk into your shelter " .. U.where(x.pos, x.shelter) .. " and shut the door"}
		end
		if threat then
			return {ok = true, prio = prio, detail = "no shelter built; run ~20 m away from " .. x.hostile.short .. " " ..
				U.where(x.pos, x.hostile.pos)}
		end
		return {ok = false, detail = "no shelter built yet (build_shelter needs 23 blocks)", prio = 20}
	end,
	run = function(p)
		local sh = jev.mem.shelter and minetest.string_to_pos(jev.mem.shelter)
		if sh and U.dist(p:get_pos(), sh) < 96 then
			local door = jev.mem.shelter_door and minetest.string_to_pos(jev.mem.shelter_door)
			if door then
				local front = vector.add(door, vector.subtract(door, sh))
				A.status("heading to the shelter door")
				local ok, why = A.approach(p, vector.offset(front, 0, 1, 0), 1.2)
				if not ok then
					return false, "could not reach the shelter door: " .. (why or "no path")
				end
				A.dig(p, door) -- opens the door
				A.glide(p, p:get_pos(), vector.offset(door, 0, -0.5, 0))
				A.glide(p, p:get_pos(), vector.offset(sh, 0, -0.5, 0))
				local node = minetest.get_node(door)
				local def = minetest.registered_nodes[node.name]
				if minetest.get_meta(door):get_int("is_open") == 1 and def and def.on_rightclick then
					A.face(p, door)
					def.on_rightclick(door, node, p, ItemStack(""))
				end
			else
				local ok, why = A.approach(p, vector.offset(sh, 0, 1, 0), 1.2)
				if not ok then
					return false, "could not reach the shelter: " .. (why or "no path")
				end
			end
			return true, "inside the shelter"
		end
		local h = U.first(U.mobs(p:get_pos(), 24), function(m) return m.kind == "hostile" end)
		if not h then
			return true, "no hostile mob around any more"
		end
		local away = vector.direction(h.pos, p:get_pos())
		local target = vector.round(vector.add(p:get_pos(), vector.multiply(vector.new(away.x, 0, away.z), 20)))
		for dy = 6, -8, -1 do
			local f = vector.offset(target, 0, dy, 0)
			if A.standable(f) then
				A.status("running away from " .. h.short)
				local ok = A.approach(p, vector.offset(f, 0, 1, 0), 2, {no_tunnel = true})
				return ok, ok and ("ran away from " .. h.short) or "no escape route"
			end
		end
		return false, "no escape route found"
	end,
})
