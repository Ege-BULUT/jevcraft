-- Build a 3x3 hut (walls 2 high, roof, wooden door) around the player.
local U, A = jev.u, jev.a

local NEED = 23
local RING = {{-1, -1}, {0, -1}, {1, -1}, {1, 0}, {1, 1}, {0, 1}, {-1, 1}, {-1, 0}}
local DOOR = {0, -1}

jev.register_skill({
	id = "build_shelter", label = "🏠 Build shelter", timeout = 120,
	offer = function(p, x)
		local near = x.shelter and U.dist(x.pos, x.shelter) < 64
		local door = x.n("mcl_doors:wooden_door") > 0 and "a door" or (x.planks >= 6 and "a door from 6 planks" or "no door (doorway gets blocked)")
		if x.blocks < NEED then
			return {ok = false, prio = (x.night and not near) and 45 or 5, detail = string.format(
				"need %d building blocks (cobble/dirt/planks), have %d", NEED, x.blocks)}
		end
		local prio = ((x.night or x.tod > 0.70) and not near) and 68 or (near and 3 or 15)
		return {ok = true, prio = prio, detail = string.format("3x3 hut around you from %d of your %d blocks, with %s%s",
			NEED, x.blocks, door, near and ("; you already have a shelter " .. U.where(x.pos, x.shelter)) or "")}
	end,
	run = function(p)
		local c = A.feet(p)
		if not A.standable(c) then
			return false, "not standing on solid ground"
		end
		-- Door: carried, or crafted from 6 planks at a crafting table.
		if not U.has(p, "mcl_doors:wooden_door") and U.count(p, "group:wood") >= 6 and A.near_node(p, "mcl_crafting_table:crafting_table") then
			A.craft(p, "mcl_doors:wooden_door")
		end
		local has_door = U.has(p, "mcl_doors:wooden_door")
		local placed, failed = 0, 0
		local function put(q)
			if A.buildable(q) then
				A.status("building shelter (" .. placed .. " blocks)")
				if A.place_any_block(p, q) then placed = placed + 1 else failed = failed + 1 end
			end
		end
		for dy = 0, 1 do
			for _, o in ipairs(RING) do
				if has_door and o[1] == DOOR[1] and o[2] == DOOR[2] then
					-- leave the doorway open
				else
					put(vector.offset(c, o[1], dy, o[2]))
				end
			end
		end
		for _, o in ipairs(RING) do
			put(vector.offset(c, o[1], 2, o[2]))
		end
		put(vector.offset(c, 0, 2, 0))
		local door_pos = vector.offset(c, DOOR[1], 0, DOOR[2])
		local door_ok = false
		if has_door then
			A.face(p, door_pos)
			door_ok = A.place(p, door_pos, "mcl_doors:wooden_door", vector.offset(door_pos, 0, -1, 0))
			if not door_ok then
				put(door_pos)
				put(vector.offset(door_pos, 0, 1, 0))
			end
		end
		if failed > 4 then
			return false, "only placed " .. placed .. " blocks (" .. failed .. " failed)"
		end
		jev.mem.shelter = minetest.pos_to_string(c)
		jev.mem.shelter_door = door_ok and minetest.pos_to_string(door_pos) or nil
		jev.save_mem()
		return true, "shelter built at " .. U.pos_text(c) .. " (" .. placed .. " blocks" .. (door_ok and ", door on the south side" or ", no door") .. ")"
	end,
})
