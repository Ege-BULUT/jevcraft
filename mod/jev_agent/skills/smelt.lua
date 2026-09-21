-- Smelt raw ores / cook raw food in a furnace: load input and fuel, wait, collect.
local U, A = jev.u, jev.a

local SKIP = {tree = true, wood = true, cobble = true, sand = true}

-- Most valuable smeltable stack in the inventory: name, output, count.
local function pick_input(p)
	local best
	for name, c in pairs(U.counts(p)) do
		local out = A.cook_result(name)
		local skip = false
		for g in pairs(SKIP) do
			if minetest.get_item_group(name, g) > 0 then skip = true end
		end
		if minetest.registered_tools[name] or minetest.get_item_group(name, "armor") > 0 then
			skip = true -- never melt down gear
		end
		if out and not skip then
			local score = name:find("raw_ores") and 3 or (U.food_value(out) > 0 and 2 or 1)
			if not best or score > best.score then
				best = {name = name, out = out, count = math.min(c, 8), score = score}
			end
		end
	end
	return best
end

local function fuel_seconds(p)
	local t = 0
	for name, c in pairs(U.counts(p)) do
		for _, f in ipairs(A.FUELS) do
			if U.matches(name, f) then
				t = t + A.burn_time(name) * c
				break
			end
		end
	end
	return t
end

jev.register_skill({
	id = "smelt", label = "♨ Smelt / cook", timeout = 150,
	offer = function(p, x)
		local inp = pick_input(p)
		if not inp then
			return {ok = false, prio = 0, detail = "nothing to smelt (raw iron, raw meat ...)"}
		end
		local need = inp.count * 10
		local fuel = fuel_seconds(p)
		local furnace = x.furnace and ("furnace " .. U.where(x.pos, x.furnace)) or
			(x.n("mcl_furnaces:furnace") > 0 and "will place your furnace") or (x.cobble >= 8 and "will craft a furnace (8 cobble)")
		if not furnace then
			return {ok = false, prio = 40, detail = "no furnace and only " .. x.cobble .. "/8 cobblestone to make one"}
		end
		if fuel < 10 then
			return {ok = false, prio = 40, detail = "no fuel (coal, planks, logs or sticks)"}
		end
		return {ok = true, prio = inp.score == 3 and 69 or 48, detail = string.format("%d %s -> %s (~%d s); %s; fuel for ~%d s",
			inp.count, U.desc(inp.name), U.desc(inp.out), need, furnace, fuel)}
	end,
	run = function(p)
		local inp = pick_input(p)
		if not inp then
			return false, "nothing to smelt"
		end
		if not A.near_node(p, {"mcl_furnaces:furnace", "mcl_furnaces:furnace_active"}) and not U.has(p, "mcl_furnaces:furnace") then
			A.ensure_table(p)
		end
		local fpos, why = A.ensure_furnace(p)
		if not fpos then
			return false, why
		end
		A.approach(p, fpos, 3.5)
		A.face(p, fpos)
		local inv = minetest.get_meta(fpos):get_inventory()
		local n = U.take(p, inp.name, inp.count)
		local left = inv:add_item("src", ItemStack(inp.name .. " " .. n))
		if not left:is_empty() then
			U.give(p, left)
			n = n - left:get_count()
		end
		-- Fuel: add until the burn time covers the batch.
		local need = n * 10
		for _, f in ipairs(A.FUELS) do
			while need > 0 do
				local slot, st = U.slot(p, f)
				if not slot then break end
				local name = st:get_name()
				local burn = A.burn_time(name)
				if burn <= 0 then break end
				local k = math.min(st:get_count(), math.ceil(need / burn))
				local fl = inv:add_item("fuel", ItemStack(name .. " " .. k))
				U.take(p, name, k - fl:get_count())
				need = need - burn * (k - fl:get_count())
				if not fl:is_empty() then break end
			end
		end
		minetest.get_node_timer(fpos):start(1.0)
		local t = 0
		while t < n * 10 + 15 do
			A.wait(1)
			t = t + 1
			local done = inv:get_stack("dst", 1):get_count()
			A.status(string.format("smelting %s: %d/%d done", U.desc(inp.name), done, n))
			if inv:is_empty("src") then
				break
			end
		end
		local got = 0
		for _, st in ipairs(inv:get_list("dst")) do
			got = got + st:get_count()
			U.give(p, st)
		end
		inv:set_list("dst", {})
		for _, st in ipairs(inv:get_list("fuel")) do
			U.give(p, st)
		end
		inv:set_list("fuel", {})
		if got == 0 then
			return false, "furnace produced nothing"
		end
		return true, "+" .. got .. " " .. U.desc(inp.out)
	end,
})
