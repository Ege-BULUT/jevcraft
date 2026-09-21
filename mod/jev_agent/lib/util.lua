-- Read-only helpers: inventory, node and mob queries, and text formatting.
local U = {}
jev.u = U

local floor, sqrt, abs = math.floor, math.sqrt, math.abs

function U.dist(a, b)
	return vector.distance(a, b)
end

function U.hdist(a, b)
	local dx, dz = a.x - b.x, a.z - b.z
	return sqrt(dx * dx + dz * dz)
end

local COMPASS = {"east", "north-east", "north", "north-west", "west", "south-west", "south", "south-east"}

-- "14 m north-east, 3 below"; +Z is north and +X is east in Luanti.
function U.where(from, to)
	local d = U.dist(from, to)
	local s = string.format("%d m", floor(d + 0.5))
	if U.hdist(from, to) >= 1.5 then
		local ang = math.atan2(to.z - from.z, to.x - from.x)
		s = s .. " " .. COMPASS[(floor(ang / (math.pi / 4) + 0.5) % 8) + 1]
	end
	local dy = floor(to.y - from.y + 0.5)
	if dy >= 2 then
		s = s .. ", " .. dy .. " up"
	elseif dy <= -2 then
		s = s .. ", " .. -dy .. " down"
	end
	return s
end

function U.desc(name)
	local def = minetest.registered_items[name]
	local d = def and def.description or name
	d = minetest.get_translated_string("en", d):match("^[^\n]*")
	return minetest.strip_colors(d):lower()
end

function U.matches(name, spec)
	if name == "" then
		return false
	end
	if spec:sub(1, 6) ~= "group:" then
		return name == spec
	end
	for g in spec:sub(7):gmatch("[^,]+") do
		if minetest.get_item_group(name, g) == 0 then
			return false
		end
	end
	return true
end

-- Item counts of the main inventory list, by item name.
function U.counts(p)
	local c = {}
	for _, st in ipairs(p:get_inventory():get_list("main")) do
		if not st:is_empty() then
			c[st:get_name()] = (c[st:get_name()] or 0) + st:get_count()
		end
	end
	return c
end

-- Count items matching a name or "group:x" spec.
function U.count(p, spec)
	local n = 0
	for name, c in pairs(U.counts(p)) do
		if U.matches(name, spec) then
			n = n + c
		end
	end
	return n
end

function U.has(p, spec, n)
	return U.count(p, spec) >= (n or 1)
end

-- First main-list slot holding a matching item.
function U.slot(p, spec)
	for i, st in ipairs(p:get_inventory():get_list("main")) do
		if U.matches(st:get_name(), spec) then
			return i, st
		end
	end
end

function U.take(p, spec, n)
	local inv, left = p:get_inventory(), n
	for i, st in ipairs(inv:get_list("main")) do
		if left <= 0 then
			break
		end
		if U.matches(st:get_name(), spec) then
			local t = st:take_item(left)
			left = left - t:get_count()
			inv:set_stack("main", i, st)
		end
	end
	return n - left
end

-- Adds items to the inventory; drops what does not fit at the player's feet.
function U.give(p, stack)
	local left = p:get_inventory():add_item("main", stack)
	if not left:is_empty() then
		minetest.add_item(p:get_pos(), left)
	end
end

-- Best tool material the player holds for a tool kind ("pick", "sword", "axe", "shovel").
local TIERS = {"wood", "stone", "gold", "iron", "diamond", "netherite"}
function U.tool_tier(p, kind)
	local best = 0
	for name in pairs(U.counts(p)) do
		for i, t in ipairs(TIERS) do
			if name == "mcl_tools:" .. kind .. "_" .. t and i > best then
				best = i
			end
		end
	end
	return best, TIERS[best]
end

function U.node_def(pos)
	return minetest.registered_nodes[minetest.get_node(pos).name]
end

-- Nearest node matching `names` in a box around pos, or nil.
function U.nearest_node(pos, names, r, ydown, yup, filter)
	local c = vector.round(pos)
	local list = minetest.find_nodes_in_area(vector.offset(c, -r, -(ydown or r), -r), vector.offset(c, r, yup or r, r), names)
	local best, bd
	for _, q in ipairs(list) do
		local d = U.dist(c, q)
		if (not bd or d < bd) and (not filter or filter(q)) then
			best, bd = q, d
		end
	end
	return best, bd, #list
end

function U.nearest_exposed(pos, names, r)
	local c = vector.round(pos)
	local list = minetest.find_nodes_in_area_under_air(vector.offset(c, -r, -r, -r), vector.offset(c, r, r, r), names)
	local best, bd
	for _, q in ipairs(list) do
		local d = U.dist(c, q)
		if not bd or d < bd then
			best, bd = q, d
		end
	end
	return best, bd
end

U.FOOD_MOBS = {
	["mobs_mc:cow"] = true, ["mobs_mc:pig"] = true, ["mobs_mc:sheep"] = true,
	["mobs_mc:chicken"] = true, ["mobs_mc:rabbit"] = true, ["mobs_mc:mooshroom"] = true,
}

-- Mobs near pos, nearest first: {obj, name, short, kind, dist, pos}.
function U.mobs(pos, r)
	local out = {}
	for _, obj in ipairs(minetest.get_objects_inside_radius(pos, r)) do
		local e = obj:get_luaentity()
		if e and e.is_mob and (e.health or 1) > 0 then
			local kind = "other"
			if U.FOOD_MOBS[e.name] then
				kind = "food"
			elseif e.type == "monster" then
				kind = "hostile"
			elseif e.name == "mobs_mc:villager" then
				kind = "villager"
			end
			local op = obj:get_pos()
			out[#out + 1] = {obj = obj, name = e.name, short = e.name:gsub("^.*:", ""), kind = kind,
				dist = U.dist(pos, op), pos = op}
		end
	end
	table.sort(out, function(a, b) return a.dist < b.dist end)
	return out
end

function U.first(list, pred)
	for _, v in ipairs(list) do
		if pred(v) then
			return v
		end
	end
end

function U.alive(obj)
	local e = obj and obj:get_pos() and obj:get_luaentity()
	return e ~= nil and (e.health or 1) > 0 and not e.dead
end

function U.is_night()
	local t = minetest.get_timeofday()
	return t < 0.23 or t > 0.77
end

function U.clock()
	local m = floor(minetest.get_timeofday() * 24 * 60)
	return string.format("%02d:%02d", floor(m / 60), m % 60)
end

-- Food value of an item (VoxeLibre stores it in the "eatable" group).
function U.food_value(name)
	return minetest.get_item_group(name, "eatable")
end

U.RISKY_FOOD = {
	["mcl_mobitems:chicken"] = true, ["mcl_mobitems:rotten_flesh"] = true,
	["mcl_mobitems:spider_eye"] = true, ["mcl_fishing:pufferfish_raw"] = true,
	["mcl_potatoes:potato_item_poison"] = true,
}

function U.food_total(p)
	local n = 0
	for name, c in pairs(U.counts(p)) do
		if U.food_value(name) > 0 then
			n = n + c
		end
	end
	return n
end

-- Short inventory summary, biggest stacks first.
function U.inv_text(p, max)
	local list = {}
	for name, c in pairs(U.counts(p)) do
		list[#list + 1] = {name, c}
	end
	if #list == 0 then
		return "empty"
	end
	table.sort(list, function(a, b) return a[2] > b[2] end)
	local parts = {}
	for i = 1, math.min(#list, max or 20) do
		parts[#parts + 1] = list[i][2] .. " " .. U.desc(list[i][1])
	end
	if #list > (max or 20) then
		parts[#parts + 1] = "+" .. (#list - (max or 20)) .. " more kinds"
	end
	return table.concat(parts, ", ")
end

function U.round_pos(pos)
	return {x = floor(pos.x + 0.5), y = floor(pos.y + 0.5), z = floor(pos.z + 0.5)}
end

function U.pos_text(pos)
	local r = U.round_pos(pos)
	return string.format("(%d,%d,%d)", r.x, r.y, r.z)
end

function U.dimension(pos)
	return mcl_worlds.pos_to_dimension(pos)
end

U.abs = abs
