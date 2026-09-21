-- Sleep through the night in a bed (placing the carried bed if needed).
local U, A = jev.u, jev.a

local function bed_item(p)
	for name in pairs(U.counts(p)) do
		if name:match("^mcl_beds:bed_.*_bottom$") then
			return name
		end
	end
end

-- Places the bed in the first horizontal direction with two free, supported cells.
local function place_bed(p, item)
	local f = A.feet(p)
	for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
		local a = vector.offset(f, d[1], 0, d[2])
		local b = vector.offset(f, 2 * d[1], 0, 2 * d[2])
		if A.buildable(a) and A.buildable(b) and A.solid(vector.offset(a, 0, -1, 0)) and A.solid(vector.offset(b, 0, -1, 0)) then
			A.face(p, b)
			if A.place(p, a, item, vector.offset(a, 0, -1, 0)) then
				return a
			end
		end
	end
end

jev.register_skill({
	id = "sleep", label = "🛏 Sleep", timeout = 60,
	offer = function(p, x)
		local item = bed_item(p)
		if not x.night then
			return {ok = false, detail = "it is " .. x.clock .. " (day); beds only work at night", prio = 0}
		end
		if x.dim ~= "overworld" then
			return {ok = false, detail = "beds explode outside the overworld", prio = 0}
		end
		if x.bed and U.dist(x.pos, x.bed) < 64 then
			return {ok = true, prio = 88, detail = "walk to your bed " .. U.where(x.pos, x.bed) .. " and sleep until morning (skips the night)"}
		end
		if item then
			return {ok = true, prio = 88, detail = "place your " .. U.desc(item) .. " here and sleep until morning"}
		end
		return {ok = false, prio = 45, detail = "no bed: craft_bed needs 3 wool of one colour + 3 planks (have " ..
			x.n("group:wool") .. " wool)"}
	end,
	run = function(p)
		local bed = jev.mem.bed and minetest.string_to_pos(jev.mem.bed)
		if bed and minetest.get_item_group(minetest.get_node(bed).name, "bed") == 0 then
			bed = nil
		end
		if not bed or U.dist(p:get_pos(), bed) > 64 then
			local item = bed_item(p)
			if not item then
				return false, "no bed to sleep in"
			end
			bed = place_bed(p, item)
			if not bed then
				return false, "no flat 1x2 spot to place the bed"
			end
			jev.mem.bed = minetest.pos_to_string(bed)
			jev.save_mem()
		end
		local ok, why = A.approach(p, bed, 2.5)
		if not ok then
			return false, "could not reach the bed: " .. (why or "no path")
		end
		A.face(p, bed)
		mcl_beds.on_rightclick(bed, p, false)
		A.wait(1)
		local name = p:get_player_name()
		if not mcl_beds.player[name] then
			return false, "could not lie down (monsters nearby or not night yet)"
		end
		A.status("sleeping")
		for _ = 1, 40 do
			A.wait(1)
			if not mcl_beds.player[name] then
				break
			end
		end
		return not U.is_night(), "woke up at " .. U.clock()
	end,
})
