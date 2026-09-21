-- Build a 3x3 hut (walls 2 high, roof, wooden door) around the player.
local U, A = jev.u, jev.a

local NEED = 23
local RING = {{-1, -1}, {0, -1}, {1, -1}, {1, 0}, {1, 1}, {0, 1}, {-1, 1}, {-1, 0}}
local DOOR = {0, -1}

-- Emergency shelter: dig two blocks down and close the hole above the head.
local function burrow(p)
	local f = A.feet(p)
	for k = 1, 3 do
		local q = vector.offset(f, 0, -k, 0)
		if A.dangerous(q) or A.liquid(q) then
			return false, "cannot burrow here: " .. U.desc(minetest.get_node(q).name) .. " below"
		end
	end
	for k = 1, 2 do
		local q = vector.offset(f, 0, -k, 0)
		if not A.dig(p, q, true) then
			return false, "cannot dig down"
		end
		A.glide(p, p:get_pos(), vector.offset(q, 0, -0.5, 0))
	end
	A.collect(p, p:get_pos(), 2)
	if not A.buildable(f) or not A.place_any_block(p, f) then
		return false, "could not seal the hole"
	end
	local c = vector.offset(f, 0, -2, 0)
	jev.mem.shelter = minetest.pos_to_string(c)
	jev.mem.shelter_door = nil
	jev.save_mem()
	return true, "burrowed into the ground at " .. U.pos_text(c) .. " and sealed the top"
end

jev.register_skill({
	id = "build_shelter", label = "🏠 Build shelter", timeout = 120,
	offer = function(p, x)
		local near = x.shelter and U.dist(x.pos, x.shelter) < 64
		local door = x.n("mcl_doors:wooden_door") > 0 and "a door" or (x.planks >= 6 and "a door from 6 planks" or "no door (doorway gets blocked)")
		local dark = x.night or x.tod > 0.72
		if not x.outdoors then
			return {ok = false, prio = 0, detail = "you are underground or under a roof already"}
		end
		if x.blocks < NEED then
			if x.blocks >= 1 then
				return {ok = true, prio = (dark and not near) and 84 or 4, detail = string.format(
					"only %d blocks (hut needs %d): dig a 2-deep hole here and seal the top with 1 block", x.blocks, NEED)}
			end
			return {ok = false, prio = (dark and not near) and 45 or 5, detail = string.format(
				"need %d building blocks (cobble/dirt/planks), have %d", NEED, x.blocks)}
		end
		local prio = (dark and not near) and 84 or (near and 3 or 15)
		return {ok = true, prio = prio, detail = string.format("3x3 hut around you from %d of your %d blocks, with %s%s",
			NEED, x.blocks, door, near and ("; you already have a shelter " .. U.where(x.pos, x.shelter)) or "")}
	end,
	run = function(p)
		if A.block_count(p) < NEED then
			return burrow(p)
		end
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
