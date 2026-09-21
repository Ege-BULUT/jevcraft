-- Builds the per-decision scan (ctx), the state text and the snapshot JSON.
local U = jev.u

local ORES = {
	coal = {"mcl_core:stone_with_coal", "mcl_deepslate:deepslate_with_coal"},
	iron = {"mcl_core:stone_with_iron", "mcl_deepslate:deepslate_with_iron"},
	gold = {"mcl_core:stone_with_gold", "mcl_deepslate:deepslate_with_gold"},
	diamond = {"mcl_core:stone_with_diamond", "mcl_deepslate:deepslate_with_diamond"},
	obsidian = {"mcl_core:obsidian"},
}
jev.ORES = ORES
local ORE_OF = {}
local ORE_NAMES = {}
for kind, names in pairs(ORES) do
	for _, n in ipairs(names) do
		ORE_OF[n] = kind
		ORE_NAMES[#ORE_NAMES + 1] = n
	end
end

jev.STONE = {"mcl_core:stone", "mcl_core:andesite", "mcl_core:diorite", "mcl_core:granite", "mcl_deepslate:deepslate"}

-- One scan of the surroundings per decision; skills read it for their details.
function jev.scan(p)
	local pos = p:get_pos()
	local ctx = {p = p, pos = pos, dim = U.dimension(pos), hp = p:get_hp(), hunger = mcl_hunger.get_hunger(p),
		night = U.is_night(), clock = U.clock(), tod = minetest.get_timeofday(), c = U.counts(p)}
	function ctx.n(spec)
		return U.count(p, spec)
	end
	ctx.logs = ctx.n("group:tree")
	ctx.planks = ctx.n("group:wood")
	ctx.sticks = ctx.n("mcl_core:stick")
	ctx.cobble = ctx.n("group:cobble")
	ctx.pick = U.tool_tier(p, "pick")
	ctx.sword = U.tool_tier(p, "sword")
	ctx.axe = U.tool_tier(p, "axe")
	ctx.food = U.food_total(p)
	ctx.blocks = jev.a.block_count(p)

	ctx.tree, ctx.tree_d = U.nearest_node(pos, {"group:tree"}, 32, 8, 12)
	ctx.stone, ctx.stone_d = U.nearest_exposed(pos, jev.STONE, 16)
	ctx.ores = {}
	local c = vector.round(pos)
	for _, q in ipairs(minetest.find_nodes_in_area(vector.offset(c, -24, -24, -24), vector.offset(c, 24, 24, 24), ORE_NAMES)) do
		local kind = ORE_OF[minetest.get_node(q).name]
		local d = U.dist(pos, q)
		if not ctx.ores[kind] or d < ctx.ores[kind].d then
			ctx.ores[kind] = {pos = q, d = d}
		end
	end
	ctx.table = minetest.find_node_near(pos, 16, "mcl_crafting_table:crafting_table", true)
	ctx.furnace = minetest.find_node_near(pos, 16, {"mcl_furnaces:furnace", "mcl_furnaces:furnace_active"}, true)
	ctx.mobs = U.mobs(pos, 32)
	ctx.hostile = U.first(ctx.mobs, function(m) return m.kind == "hostile" end)
	ctx.fightable = U.first(ctx.mobs, function(m) return m.kind == "hostile" and not m.avoid end)
	local eye = vector.offset(pos, 0, 1.5, 0)
	ctx.danger = U.first(ctx.mobs, function(m)
		return m.avoid and m.dist <= 12 and minetest.line_of_sight(eye, vector.offset(m.pos, 0, 1, 0))
	end)
	ctx.outdoors = jev.a.outdoors(pos)
	ctx.prey = U.first(ctx.mobs, function(m) return m.kind == "food" end)
	ctx.sheep = U.first(ctx.mobs, function(m) return m.name == "mobs_mc:sheep" end)
	ctx.villager = U.first(ctx.mobs, function(m) return m.kind == "villager" end)
	ctx.shelter = jev.mem.shelter and minetest.string_to_pos(jev.mem.shelter)
	ctx.sheltered = (ctx.shelter and U.dist(pos, ctx.shelter) < 1.5) or false
	ctx.bed = jev.mem.bed and minetest.string_to_pos(jev.mem.bed)
	if ctx.bed and minetest.get_item_group(minetest.get_node(ctx.bed).name, "bed") == 0
			and minetest.get_node(ctx.bed).name ~= "ignore" then
		ctx.bed = nil
		jev.mem.bed = nil
	end
	return ctx
end

-- Progression chain toward the Nether; the first unmet step is the goal.
jev.GOALS = {
	{"gather logs", function(x) return x.logs > 0 or x.planks >= 4 or x.pick >= 1 end},
	{"crafting table", function(x) return x.n("mcl_crafting_table:crafting_table") > 0 or x.table or x.pick >= 1 end},
	{"wooden pickaxe", function(x) return x.pick >= 1 end},
	{"stone pickaxe", function(x) return x.pick >= 2 end},
	{"furnace", function(x) return x.n("mcl_furnaces:furnace") > 0 or x.furnace or x.pick >= 4 end},
	{"3 iron ingots", function(x) return x.n("mcl_core:iron_ingot") >= 3 or x.pick >= 4 end},
	{"iron pickaxe", function(x) return x.pick >= 4 end},
	{"bed", function(x) return x.n("group:bed") > 0 or x.bed ~= nil end},
	{"3 diamonds", function(x) return x.n("mcl_core:diamond") >= 3 or x.pick >= 5 end},
	{"diamond pickaxe", function(x) return x.pick >= 5 end},
	{"10 obsidian", function(x) return x.n("mcl_core:obsidian") >= 10 or jev.mem.portal ~= nil end},
	{"nether portal", function(x) return jev.mem.portal ~= nil end},
	{"enter the Nether", function(x) return x.dim == "nether" or jev.mem.nether_visited end},
}

function jev.goal(ctx)
	for i, g in ipairs(jev.GOALS) do
		if not g[2](ctx) then
			return g[1], i, #jev.GOALS
		end
	end
	return "all goals done (the End is next)", #jev.GOALS + 1, #jev.GOALS
end

local function mobs_text(ctx)
	local groups, order = {}, {}
	for _, m in ipairs(ctx.mobs) do
		if not groups[m.short] then
			groups[m.short] = {n = 0, first = m}
			order[#order + 1] = m.short
		end
		groups[m.short].n = groups[m.short].n + 1
	end
	local parts = {}
	for i = 1, math.min(#order, 5) do
		local g = groups[order[i]]
		parts[#parts + 1] = g.n .. " " .. order[i] .. (g.first.kind == "hostile" and " (hostile)" or "") ..
			" nearest " .. U.where(ctx.pos, g.first.pos)
	end
	return #parts > 0 and table.concat(parts, "; ") or "no mobs within 32 m"
end

function jev.state_text(ctx, notes)
	local p = ctx.p
	local lines = {}
	local phase
	if ctx.tod > 0.77 or ctx.tod < 0.23 then
		phase = "night"
	elseif ctx.tod > 0.70 then
		phase = "dusk (night soon)"
	else
		phase = "day"
	end
	lines[#lines + 1] = string.format("Jev in the %s at %s, %s %s. HP %d/20, food %d/20.",
		ctx.dim, U.pos_text(ctx.pos), ctx.clock, phase, ctx.hp, ctx.hunger)
	local w = p:get_wielded_item()
	lines[#lines + 1] = "Holding: " .. (w:is_empty() and "nothing" or U.desc(w:get_name())) ..
		". Inventory: " .. U.inv_text(p, 18) .. "."
	local near = {}
	if ctx.tree then near[#near + 1] = "tree " .. U.where(ctx.pos, ctx.tree) end
	if ctx.stone then near[#near + 1] = "exposed stone " .. U.where(ctx.pos, ctx.stone) end
	for _, kind in ipairs({"coal", "iron", "gold", "diamond", "obsidian"}) do
		local o = ctx.ores[kind]
		if o then near[#near + 1] = kind .. (kind == "obsidian" and "" or " ore") .. " " .. U.where(ctx.pos, o.pos) end
	end
	if ctx.table then near[#near + 1] = "crafting table " .. U.where(ctx.pos, ctx.table) end
	if ctx.furnace then near[#near + 1] = "furnace " .. U.where(ctx.pos, ctx.furnace) end
	if ctx.shelter then near[#near + 1] = "your shelter " .. U.where(ctx.pos, ctx.shelter) end
	if ctx.bed then near[#near + 1] = "your bed " .. U.where(ctx.pos, ctx.bed) end
	lines[#lines + 1] = "Around: " .. (#near > 0 and table.concat(near, "; ") or "nothing notable in range") .. "."
	lines[#lines + 1] = "Mobs: " .. mobs_text(ctx) .. "."
	local g, i, n = jev.goal(ctx)
	lines[#lines + 1] = string.format("Goal: %s (step %d/%d toward the Nether).", g, math.min(i, n), n)
	for _, note in ipairs(notes or {}) do
		lines[#lines + 1] = note
	end
	return table.concat(lines, "\n")
end

function jev.snapshot(ctx, last)
	local inv = {}
	for name, c in pairs(ctx.c) do
		inv[name] = c
	end
	local g, i, n = jev.goal(ctx)
	local r = U.round_pos(ctx.pos)
	return {
		health = ctx.hp, hunger = ctx.hunger,
		pos = {x = r.x, y = r.y, z = r.z}, dimension = ctx.dim,
		time_of_day = math.floor(ctx.tod * 1000) / 1000, night = ctx.night,
		inventory = inv,
		goal = {name = g, step = math.min(i, n), of = n},
		last = last,
	}
end
