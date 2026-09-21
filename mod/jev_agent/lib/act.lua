-- Primitive actions for skills. Skills run as coroutines resumed once per
-- server step, so every function here that takes time yields instead of blocking.
local A = {}
jev.a = A
local U = jev.u

local WALK_SPEED = 4 -- m/s
local REACH = 4

-- Yield until the next server step; returns the elapsed dtime.
function A.tick()
	local dt = coroutine.yield()
	return dt or 0
end

function A.wait(t)
	local e = 0
	while e < t do
		e = e + A.tick()
	end
end

function A.status(text)
	jev.set_status(text)
end

-- Node position occupied by the player's feet.
function A.feet(p)
	return U.round_pos(vector.offset(p:get_pos(), 0, 0.1, 0))
end

function A.head(p)
	return vector.offset(p:get_pos(), 0, 1.5, 0)
end

function A.face(p, target)
	local pos = p:get_pos()
	local eye = pos.y + (p:get_properties().eye_height or 1.5)
	local dx, dz, dy = target.x - pos.x, target.z - pos.z, target.y - eye
	local h = math.sqrt(dx * dx + dz * dz)
	if h > 0.01 then
		p:set_look_horizontal(math.atan2(-dx, dz))
	end
	p:set_look_vertical(-math.atan2(dy, h))
end

-- Node classification ------------------------------------------------------

function A.solid(pos)
	local n = minetest.get_node(pos).name
	if n == "ignore" then
		return true
	end
	local d = minetest.registered_nodes[n]
	return not d or d.walkable ~= false
end

function A.dangerous(pos)
	local n = minetest.get_node(pos).name
	local d = minetest.registered_nodes[n]
	return d and ((d.damage_per_second or 0) > 0 or minetest.get_item_group(n, "lava") > 0
		or minetest.get_item_group(n, "fire") > 0)
end

function A.liquid(pos)
	local d = U.node_def(pos)
	return d and d.liquidtype and d.liquidtype ~= "none"
end

function A.passable(pos)
	return not A.solid(pos) and not A.dangerous(pos)
end

function A.standable(f)
	return A.passable(f) and A.passable(vector.offset(f, 0, 1, 0)) and A.solid(vector.offset(f, 0, -1, 0))
		and not A.dangerous(vector.offset(f, 0, -1, 0)) and minetest.get_node(vector.offset(f, 0, -1, 0)).name ~= "ignore"
end

function A.buildable(pos)
	local d = U.node_def(pos)
	return d and d.buildable_to and not A.dangerous(pos)
end

-- Movement -------------------------------------------------------------------

-- Moves the player from one feet position to another at walking speed, with a
-- small jump arc when climbing and a drop at the end when descending.
local function glide(p, from, to)
	local dur = math.max(vector.distance(from, to) / WALK_SPEED, 0.05)
	if U.hdist(from, to) > 0.1 then
		p:set_look_horizontal(math.atan2(-(to.x - from.x), to.z - from.z))
		p:set_look_vertical(0.2)
	end
	local t = 0
	while t < dur do
		t = t + A.tick()
		local f = math.min(t / dur, 1)
		local fy = to.y > from.y and math.min(1, f * 2) or math.max(0, f * 2 - 1)
		p:set_pos({x = from.x + (to.x - from.x) * f, y = from.y + (to.y - from.y) * fy, z = from.z + (to.z - from.z) * f})
	end
	p:set_pos(to)
end
A.glide = glide

local function stand_pos(f)
	return {x = f.x, y = f.y - 0.5, z = f.z}
end

-- Follows a find_path result; digs anything that has appeared in the way.
function A.follow(p, path, max_steps)
	local cur = p:get_pos()
	for i = 2, math.min(#path, (max_steps or 1e9) + 1) do
		local wp = path[i]
		for _, q in ipairs({wp, vector.offset(wp, 0, 1, 0)}) do
			if A.solid(q) then
				local ok = A.dig(p, q)
				if not ok then
					return false, "path blocked by " .. U.desc(minetest.get_node(q).name)
				end
			elseif A.dangerous(q) then
				return false, "path runs into " .. U.desc(minetest.get_node(q).name)
			end
		end
		local to = stand_pos(wp)
		glide(p, cur, to)
		cur = to
		if p:get_hp() <= 0 then
			return false, "died"
		end
	end
	return true
end

local function within(p, target, reach)
	return vector.distance(A.head(p), target) <= reach
end

-- Tunnels in a straight line toward target, digging and dropping as needed.
function A.tunnel(p, target, reach, max_steps)
	for _ = 1, max_steps or 48 do
		if within(p, target, reach) then
			return true
		end
		local f = A.feet(p)
		local dx, dy, dz = target.x - f.x, target.y - f.y, target.z - f.z
		local nx, nz = 0, 0
		if math.abs(dx) >= math.abs(dz) and dx ~= 0 then
			nx = dx > 0 and 1 or -1
		elseif dz ~= 0 then
			nz = dz > 0 and 1 or -1
		end
		if nx == 0 and nz == 0 then
			if dy < 0 then
				local below = vector.offset(f, 0, -1, 0)
				if A.dangerous(vector.offset(below, 0, -1, 0)) or not A.dig(p, below) then
					return false, "cannot dig down"
				end
				glide(p, p:get_pos(), stand_pos(below))
			else
				return false, "target is straight above"
			end
		else
			local ny = dy > 1 and 1 or (dy < -1 and -1 or 0)
			local nf = vector.offset(f, nx, ny, nz)
			local clear = {nf, vector.offset(nf, 0, 1, 0)}
			if ny == 1 then
				clear[#clear + 1] = vector.offset(f, 0, 2, 0)
			elseif ny == -1 then
				clear[#clear + 1] = vector.offset(nf, 0, 2, 0)
			end
			for _, q in ipairs(clear) do
				for _, o in ipairs({{0, 0, 0}, {1, 0, 0}, {-1, 0, 0}, {0, 0, 1}, {0, 0, -1}, {0, 1, 0}}) do
					if A.dangerous(vector.offset(q, o[1], o[2], o[3])) then
						return false, "lava or fire next to the way"
					end
				end
				if A.liquid(q) and not A.solid(q) then
					-- swimming through water is fine
				elseif A.solid(q) then
					local ok, why = A.dig(p, q)
					if not ok then
						return false, why or "cannot dig through"
					end
				end
			end
			-- Find ground under the next cell: fall up to 3, else bridge.
			local floor_y
			for k = 1, 4 do
				if A.solid(vector.offset(nf, 0, -k, 0)) then
					floor_y = nf.y - k + 1
					break
				end
			end
			if not floor_y then
				local ok = A.place_any_block(p, vector.offset(nf, 0, -1, 0))
				if not ok then
					return false, "gap ahead and no blocks to bridge"
				end
				floor_y = nf.y
			end
			local dest = {x = nf.x, y = floor_y, z = nf.z}
			glide(p, p:get_pos(), stand_pos(vector.new(nf.x, nf.y, nf.z)))
			if floor_y < nf.y then
				glide(p, p:get_pos(), stand_pos(dest))
			end
		end
		if p:get_hp() <= 0 then
			return false, "died"
		end
	end
	return within(p, target, reach), "too far to tunnel"
end

-- Standing spots within reach of target, nearest to the player first.
local function stand_spots(p, target, reach)
	local out, t, me = {}, vector.round(target), A.feet(p)
	local r = math.min(math.floor(reach), 3)
	for dx = -r, r do
		for dz = -r, r do
			for dy = -3, 2 do
				local f = vector.offset(t, dx, dy, dz)
				if A.standable(f) and vector.distance(vector.offset(f, 0, 1, 0), target) <= reach then
					out[#out + 1] = f
				end
			end
		end
	end
	table.sort(out, function(a, b) return vector.distance(a, me) < vector.distance(b, me) end)
	return out
end

-- Walks until the player's head is within `reach` of target. Uses the engine
-- pathfinder, falling back to tunnelling. opts.max_steps limits path steps
-- (for chasing moving targets), opts.no_tunnel disables digging a way.
function A.approach(p, target, reach, opts)
	opts = opts or {}
	reach = reach or REACH
	if within(p, target, reach) then
		return true
	end
	local start = A.feet(p)
	local spots = stand_spots(p, target, reach)
	local range = math.min(math.floor(vector.distance(start, target)) + 12, 64)
	for i = 1, math.min(#spots, 4) do
		local path = minetest.find_path(start, spots[i], range, 1, 3, "A*_noprefetch")
		if path then
			local ok, why = A.follow(p, path, opts.max_steps)
			if ok then
				return opts.max_steps and true or within(p, target, reach + 0.5)
			end
			if why == "died" then
				return false, why
			end
			start = A.feet(p)
		end
	end
	if opts.no_tunnel then
		return false, "no walkable path"
	end
	return A.tunnel(p, target, reach, opts.max_steps)
end

-- Inventory handling ---------------------------------------------------------

-- Puts main-list slot `idx` into the hand by swapping it with the wield slot.
function A.wield(p, idx)
	local inv, w = p:get_inventory(), p:get_wield_index()
	if idx and idx ~= w then
		local a, b = inv:get_stack("main", idx), inv:get_stack("main", w)
		inv:set_stack("main", w, a)
		inv:set_stack("main", idx, b)
	end
end

function A.wield_item(p, spec)
	local idx = U.slot(p, spec)
	if idx then
		A.wield(p, idx)
		return true
	end
	return false
end

local function caps(p, stack)
	if stack:is_empty() then
		local hand = p:get_inventory():get_stack("hand", 1)
		if not hand:is_empty() then
			return hand:get_tool_capabilities()
		end
	end
	return stack:get_tool_capabilities()
end

-- Seconds to dig `nodename` with `stack`, or nil when it cannot be dug.
function A.dig_time(p, nodename, stack)
	local def = minetest.registered_nodes[nodename]
	if not def then
		return nil
	end
	local dp = minetest.get_dig_params(def.groups, caps(p, stack))
	return dp.diggable and dp.time or nil
end

function A.can_harvest(p, nodename, stack)
	return mcl_autogroup.can_harvest(nodename, stack:get_name(), p)
end

-- Picks the fastest tool that still yields the node's drop (slot index or 0 for hand).
function A.best_tool(p, nodename)
	local best, bt, bh
	local list = p:get_inventory():get_list("main")
	local function consider(idx, st)
		local t = A.dig_time(p, nodename, st)
		if t then
			local h = A.can_harvest(p, nodename, st)
			if not best or (h and not bh) or (h == bh and t < bt) then
				best, bt, bh = idx, t, h
			end
		end
	end
	consider(0, ItemStack(""))
	for i, st in ipairs(list) do
		if minetest.registered_tools[st:get_name()] then
			consider(i, st)
		end
	end
	return best, bt, bh
end

-- Digs one node with the best tool, waiting its real dig time.
function A.dig(p, pos)
	local node = minetest.get_node(pos)
	if node.name == "air" or node.name == "ignore" then
		return node.name == "air"
	end
	local def = minetest.registered_nodes[node.name]
	if not def or def.diggable == false then
		return false, "cannot dig " .. U.desc(node.name)
	end
	if minetest.get_item_group(node.name, "door") > 0 then
		-- Open doors instead of breaking them; the way counts as clear.
		if minetest.get_meta(pos):get_int("is_open") == 0 and def.on_rightclick then
			A.face(p, pos)
			def.on_rightclick(pos, node, p, ItemStack(""))
			A.wait(0.3)
		end
		return true
	end
	if A.dangerous(pos) or (A.liquid(pos) and not def.walkable) then
		return false, "cannot dig a liquid"
	end
	local idx, t = A.best_tool(p, node.name)
	if not idx then
		return false, "no tool can dig " .. U.desc(node.name)
	end
	if idx == 0 then
		-- Empty hand: move whatever is wielded out of the way if possible.
		local inv = p:get_inventory()
		local w = p:get_wield_index()
		if not inv:get_stack("main", w):is_empty() then
			for i = 1, 9 do
				if inv:get_stack("main", i):is_empty() then
					A.wield(p, i)
					break
				end
			end
		end
	else
		A.wield(p, idx)
	end
	if t > 25 then
		return false, U.desc(node.name) .. " takes too long to dig (" .. math.floor(t) .. " s)"
	end
	A.face(p, pos)
	A.wait(math.max(t, 0.15))
	local now = minetest.get_node(pos)
	if now.name ~= node.name then
		return now.name == "air" or not A.solid(pos)
	end
	minetest.node_dig(pos, now, p)
	return minetest.get_node(pos).name ~= node.name
end

-- Walks over dropped items near `center` so the item magnet picks them up.
function A.collect(p, center, radius)
	for _ = 1, 8 do
		local items = {}
		for _, obj in ipairs(minetest.get_objects_inside_radius(center, radius or 6)) do
			local e = obj:get_luaentity()
			if e and e.name == "__builtin:item" then
				items[#items + 1] = obj
			end
		end
		if #items == 0 then
			return
		end
		local me = p:get_pos()
		table.sort(items, function(a, b) return vector.distance(a:get_pos(), me) < vector.distance(b:get_pos(), me) end)
		local ip = items[1]:get_pos()
		if vector.distance(me, ip) > 1.4 then
			if not A.approach(p, ip, 1.8, {max_steps = 12}) then
				return
			end
		end
		A.wait(0.7)
		if items[1]:get_pos() and vector.distance(p:get_pos(), items[1]:get_pos()) < 1.6 then
			A.wait(0.8)
			if items[1]:get_pos() then
				return -- cannot pick it up (inventory full?)
			end
		end
	end
end

-- Placing ----------------------------------------------------------------------

local SIDES = {{0, -1, 0}, {1, 0, 0}, {-1, 0, 0}, {0, 0, 1}, {0, 0, -1}, {0, 1, 0}}

-- Places a matching inventory item at pos, pointing at a solid neighbour.
function A.place(p, pos, spec, under)
	local idx = U.slot(p, spec)
	if not idx then
		return false, "no " .. spec
	end
	if not A.buildable(pos) then
		return false, "spot is occupied"
	end
	if not under then
		for _, o in ipairs(SIDES) do
			local q = vector.offset(pos, o[1], o[2], o[3])
			local d = U.node_def(q)
			if A.solid(q) and minetest.get_node(q).name ~= "ignore" and d and not d.on_rightclick then
				under = q
				break
			end
		end
	end
	if not under then
		return false, "nothing to place against"
	end
	A.wield(p, idx)
	A.face(p, pos)
	A.wait(0.2)
	local stack = p:get_wielded_item()
	local def = stack:get_definition()
	local before = minetest.get_node(pos).name
	local res = (def.on_place or minetest.item_place)(stack, p, {type = "node", under = under, above = pos})
	if res then
		p:set_wielded_item(res)
	end
	return minetest.get_node(pos).name ~= before
end

A.BLOCKS = {"group:cobble", "mcl_core:dirt", "group:wood", "mcl_core:stone", "mcl_core:andesite",
	"mcl_core:diorite", "mcl_core:granite", "mcl_deepslate:deepslate_cobbled", "mcl_core:sand"}

function A.block_count(p)
	local n = 0
	for _, b in ipairs(A.BLOCKS) do
		n = n + U.count(p, b)
	end
	return n
end

function A.place_any_block(p, pos)
	for _, b in ipairs(A.BLOCKS) do
		if U.has(p, b) then
			return A.place(p, pos, b)
		end
	end
	return false, "no building blocks"
end

-- A free spot next to the player (not where the player stands) to put a block.
function A.free_spot(p)
	local f = A.feet(p)
	for _, o in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}, {1, 1}, {-1, -1}, {1, -1}, {-1, 1}}) do
		local q = vector.offset(f, o[1], 0, o[2])
		if A.buildable(q) and A.solid(vector.offset(q, 0, -1, 0)) and not U.node_def(vector.offset(q, 0, -1, 0)).on_rightclick then
			return q
		end
	end
end

-- Crafting ---------------------------------------------------------------------

local function near_node(p, names, r)
	return minetest.find_node_near(p:get_pos(), r or REACH, names, true)
end
A.near_node = near_node

-- Resolves a recipe's inputs against the inventory.
-- Returns grid (concrete names), per-name counts, needs_3x3, or nil + missing text.
local function resolve(p, r)
	local have = U.counts(p)
	local used, grid, need = {}, {}, {}
	local maxi = 0
	for i in pairs(r.items) do
		maxi = math.max(maxi, i)
	end
	local w = r.width
	local needs3
	if w == 0 then
		needs3 = maxi > 4
	else
		needs3 = w > 2 or math.ceil(maxi / w) > 2
	end
	local missing = {}
	for i = 1, maxi do
		local spec = r.items[i]
		if spec and spec ~= "" then
			local pick
			for name, c in pairs(have) do
				if U.matches(name, spec) and c - (used[name] or 0) > 0 then
					pick = name
					break
				end
			end
			if pick then
				used[pick] = (used[pick] or 0) + 1
				grid[i] = pick
			else
				missing[spec] = (missing[spec] or 0) + 1
				grid[i] = ""
			end
		else
			grid[i] = ""
		end
	end
	for spec, n in pairs(missing) do
		need[#need + 1] = n .. " " .. spec:gsub("^group:", ""):gsub("^.-:", "")
	end
	if #need > 0 then
		return nil, table.concat(need, ", ")
	end
	return grid, used, needs3
end

-- Can `output` be crafted from the inventory right now? Returns recipe info or nil, reason.
function A.craftable(p, output)
	local recipes = minetest.get_all_craft_recipes(output) or {}
	local reason = "no recipe"
	for _, r in ipairs(recipes) do
		if (r.method or "normal") == "normal" and r.items then
			local grid, used, needs3 = resolve(p, r)
			if grid then
				return {recipe = r, grid = grid, used = used, needs3 = needs3}
			end
			reason = "need " .. used
		end
	end
	return nil, reason
end

-- Crafts `output` once. For 3x3 recipes a crafting table must be within reach.
function A.craft(p, output)
	local c, why = A.craftable(p, output)
	if not c then
		return false, why
	end
	if c.needs3 and not near_node(p, "mcl_crafting_table:crafting_table") then
		return false, "need a crafting table within reach"
	end
	local w = c.recipe.width
	local width = w == 0 and 3 or w
	local items = {}
	for i = 1, #c.grid do
		items[i] = c.grid[i]
	end
	local res = minetest.get_craft_result({method = "normal", width = width, items = items})
	if res.item:is_empty() or res.item:get_name() ~= ItemStack(output):get_name() then
		-- Shapeless recipes may need compact layout; try as given, else fail.
		return false, "recipe did not produce " .. U.desc(output)
	end
	for name, n in pairs(c.used) do
		U.take(p, name, n)
	end
	U.give(p, res.item)
	A.status("crafted " .. res.item:get_count() .. " " .. U.desc(res.item:get_name()))
	A.wait(0.4)
	return true, res.item:get_count()
end

-- Crafts until the inventory holds at least `want` of output (or recipes run out).
function A.craft_until(p, output, want)
	local made = 0
	for _ = 1, 64 do
		if U.count(p, output) >= want then
			break
		end
		local ok, n = A.craft(p, output)
		if not ok then
			return made > 0, made, n
		end
		made = made + n
	end
	return true, made
end

-- Makes sure a placed crafting table is within reach, placing or crafting one.
function A.ensure_station(p, node, item_spec, craft_item)
	local pos = near_node(p, node)
	if pos then
		return pos
	end
	local far = minetest.find_node_near(p:get_pos(), 16, node)
	if far and not U.has(p, item_spec) then
		local ok = A.approach(p, far, 3.5)
		if ok then
			return far
		end
	end
	if not U.has(p, item_spec) and craft_item then
		local ok, why = A.craft(p, craft_item)
		if not ok then
			return nil, why
		end
	end
	if not U.has(p, item_spec) then
		return nil, "no " .. U.desc(craft_item or item_spec)
	end
	local spot = A.free_spot(p)
	if not spot then
		return nil, "no free spot to place " .. U.desc(craft_item or item_spec)
	end
	if not A.place(p, spot, item_spec) then
		return nil, "placing failed"
	end
	return spot
end

function A.ensure_table(p)
	return A.ensure_station(p, "mcl_crafting_table:crafting_table", "mcl_crafting_table:crafting_table",
		"mcl_crafting_table:crafting_table")
end

function A.ensure_furnace(p)
	return A.ensure_station(p, {"mcl_furnaces:furnace", "mcl_furnaces:furnace_active"}, "mcl_furnaces:furnace",
		"mcl_furnaces:furnace")
end

-- Fuel and cooking -----------------------------------------------------------

function A.cook_result(name)
	local r = minetest.get_craft_result({method = "cooking", width = 1, items = {name}})
	return not r.item:is_empty() and r.item:get_name() or nil, r.time
end

function A.burn_time(name)
	return minetest.get_craft_result({method = "fuel", width = 1, items = {name}}).time
end

A.FUELS = {"mcl_core:coal_lump", "mcl_core:charcoal_lump", "group:wood", "group:tree", "mcl_core:stick"}

-- Combat -----------------------------------------------------------------------

local function damage_of(st)
	local c = st:get_tool_capabilities()
	return c and c.damage_groups and c.damage_groups.fleshy or 1
end

function A.wield_weapon(p)
	local best, bd = nil, 1
	for i, st in ipairs(p:get_inventory():get_list("main")) do
		if minetest.registered_tools[st:get_name()] and damage_of(st) > bd then
			best, bd = i, damage_of(st)
		end
	end
	if best then
		A.wield(p, best)
	end
	return bd
end

-- Chases and hits a mob until it dies, the time runs out or it gets away.
function A.attack(p, obj, max_time)
	A.wield_weapon(p)
	local t0 = minetest.get_us_time()
	local last_pos
	while (minetest.get_us_time() - t0) / 1e6 < (max_time or 40) do
		if not U.alive(obj) then
			return true, last_pos
		end
		if p:get_hp() <= 0 then
			return false, "died"
		end
		local op = obj:get_pos()
		last_pos = op
		local target = vector.offset(op, 0, 0.6, 0)
		if vector.distance(A.head(p), target) > 3 then
			if vector.distance(p:get_pos(), op) > 40 then
				return false, "it got away"
			end
			local ok = A.approach(p, target, 2.5, {max_steps = 3, no_tunnel = true})
			if not ok then
				-- step straight toward it if the pathfinder gives up
				local f = A.feet(p)
				local d = vector.direction(f, op)
				local nf = vector.round(vector.offset(f, d.x, 0, d.z))
				if A.standable(nf) then
					glide(p, p:get_pos(), stand_pos(nf))
				else
					A.wait(0.3)
				end
			end
		else
			A.face(p, target)
			local st = p:get_wielded_item()
			local c = caps(p, st)
			-- mcl_mobs wears the wielded weapon itself on punch
			obj:punch(p, c.full_punch_interval or 1, c, vector.direction(p:get_pos(), op))
			A.wait(math.max(c.full_punch_interval or 0.8, 0.6))
		end
	end
	return false, "timed out chasing it"
end

-- Eating ------------------------------------------------------------------------

function A.best_food(p, allow_risky)
	local best, bv
	for name in pairs(U.counts(p)) do
		local v = U.food_value(name)
		if v > 0 and (allow_risky or not U.RISKY_FOOD[name]) and (not bv or v > bv) then
			best, bv = name, v
		end
	end
	return best, bv
end

function A.eat(p, name)
	if not A.wield_item(p, name) then
		return false
	end
	A.status("eating " .. U.desc(name))
	A.face(p, vector.offset(p:get_pos(), 0, 0.5, 0))
	A.wait(1.6)
	local st = p:get_wielded_item()
	if st:get_name() ~= name then
		return false
	end
	local res = mcl_hunger.eat(U.food_value(name), nil, st, p, {type = "nothing"})
	p:set_wielded_item(res)
	return true
end
