-- Wheat farming: harvest ripe wheat, bake bread, plant seeds, or collect seeds from grass.
local U, A = jev.u, jev.a

local RIPE, GRASS = "mcl_farming:wheat", {"mcl_flowers:tallgrass", "mcl_flowers:double_grass"}

local function plan(p, x)
	local ripe = U.nearest_node(x.pos, {RIPE}, 24, 6, 6)
	if ripe then
		return "harvest", 58, "harvest ripe wheat " .. U.where(x.pos, ripe) .. " and replant", ripe
	end
	local wheat = x.n("mcl_farming:wheat_item")
	if wheat >= 3 then
		return "bread", 60, "bake " .. math.floor(wheat / 3) .. " bread from " .. wheat .. " wheat (needs a crafting table)"
	end
	local seeds = x.n("mcl_farming:wheat_seeds")
	local hoe = x.n("group:hoe") > 0
	if seeds > 0 and (hoe or x.planks + x.sticks >= 4) then
		return "plant", 30, string.format("till soil and plant %d wheat seeds%s; ripens in ~20-40 min", math.min(seeds, 6),
			hoe and "" or " (crafts a wooden hoe first)")
	end
	local grass = U.nearest_node(x.pos, GRASS, 16, 4, 4)
	if grass then
		return "seeds", 22, "break tall grass " .. U.where(x.pos, grass) .. " for wheat seeds (about 1 in 8 drops one)", grass
	end
end

local function dig_around(p, names, max, radius)
	local n = 0
	for _ = 1, max do
		local q = U.nearest_node(p:get_pos(), names, radius, 4, 4)
		if not q then break end
		if not A.approach(p, q, 4, {no_tunnel = true}) or not A.dig(p, q) then break end
		n = n + 1
		A.collect(p, q, 3)
	end
	return n
end

local function plant(p)
	if not U.has(p, "group:hoe") then
		A.ensure_table(p)
		if U.count(p, "mcl_core:stick") < 2 then A.craft(p, "mcl_core:stick") end
		local ok, why = A.craft(p, "mcl_farming:hoe_wood")
		if not ok then return 0, "no hoe: " .. why end
	end
	local planted = 0
	for _ = 1, 6 do
		if not U.has(p, "mcl_farming:wheat_seeds") then break end
		local pos = p:get_pos()
		local water = minetest.find_node_near(pos, 12, {"group:water"})
		local center = water or pos
		local c = vector.round(center)
		local soil = minetest.find_nodes_in_area_under_air(vector.offset(c, -4, -2, -4), vector.offset(c, 4, 2, 4),
			{"mcl_core:dirt_with_grass", "mcl_core:dirt", "mcl_farming:soil", "mcl_farming:soil_wet"})
		local spot
		for _, q in ipairs(soil) do
			local above = vector.offset(q, 0, 1, 0)
			if (minetest.get_node(above).name == "air" or minetest.get_node(above).name == "jev_agent:glow") and not vector.equals(above, A.feet(p)) then
				spot = q
				break
			end
		end
		if not spot then break end
		if not A.approach(p, spot, 4, {no_tunnel = true}) then break end
		if minetest.get_item_group(minetest.get_node(spot).name, "soil") < 2 and not minetest.get_node(spot).name:find("soil") then
			A.wield_item(p, "group:hoe")
			local st = p:get_wielded_item()
			local def = st:get_definition()
			A.face(p, spot)
			local res = def.on_place(st, p, {type = "node", under = spot, above = vector.offset(spot, 0, 1, 0)})
			if res then p:set_wielded_item(res) end
			A.wait(0.4)
		end
		if A.place(p, vector.offset(spot, 0, 1, 0), "mcl_farming:wheat_seeds", spot) then
			planted = planted + 1
		else
			break
		end
	end
	return planted
end

jev.register_skill({
	id = "farm", label = "🌾 Farm wheat", timeout = 110,
	offer = function(p, x)
		local what, prio, detail = plan(p, x)
		if not what then
			return {ok = false, prio = 10, detail = "no seeds, no wheat and no tall grass within 16 m"}
		end
		return {ok = true, prio = prio, detail = detail}
	end,
	run = function(p, x)
		local what = plan(p, x)
		if what == "harvest" then
			local n = dig_around(p, {RIPE}, 10, 24)
			local replanted = plant(p)
			return n > 0, "harvested " .. n .. " wheat, replanted " .. replanted
		elseif what == "bread" then
			local ok, why = A.ensure_table(p)
			if not ok then return false, why end
			local made = 0
			while U.count(p, "mcl_farming:wheat_item") >= 3 and A.craft(p, "mcl_farming:bread") do
				made = made + 1
			end
			return made > 0, "baked " .. made .. " bread"
		elseif what == "plant" then
			local n, why = plant(p)
			return n > 0, n > 0 and ("planted " .. n .. " wheat seeds") or (why or "no place to plant")
		elseif what == "seeds" then
			local before = U.count(p, "mcl_farming:wheat_seeds")
			local n = dig_around(p, GRASS, 12, 16)
			local got = U.count(p, "mcl_farming:wheat_seeds") - before
			return n > 0, "broke " .. n .. " grass, +" .. got .. " seeds"
		end
		return false, "nothing to do on the farm"
	end,
})
