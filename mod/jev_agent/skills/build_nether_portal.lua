-- Build a 4x5 obsidian portal frame in front of the player, light it and step in.
local U, A = jev.u, jev.a

local function flint_ok(x)
	return x.n("mcl_fire:flint_and_steel") > 0 or (x.n("mcl_core:iron_ingot") > 0 and x.n("mcl_core:flint") > 0)
end

jev.register_skill({
	id = "build_nether_portal", label = "🌀 Build nether portal", timeout = 150,
	offer = function(p, x)
		if x.dim ~= "overworld" then
			return nil
		end
		local obs = x.n("mcl_core:obsidian")
		if obs < 10 or not flint_ok(x) then
			return {ok = false, prio = obs > 0 and 50 or (x.pick >= 5 and 40 or 2), detail = string.format(
				"need 10 obsidian (have %d; mine with a diamond pickaxe) and flint and steel (%s)", obs,
				x.n("mcl_fire:flint_and_steel") > 0 and "have it" or "1 iron ingot + 1 flint from gravel")}
		end
		return {ok = true, prio = 86, detail = "build a 4x5 obsidian frame 2 m ahead, light it and step into the Nether"}
	end,
	run = function(p)
		if not U.has(p, "mcl_fire:flint_and_steel") then
			local ok, why = A.craft(p, "mcl_fire:flint_and_steel")
			if not ok then return false, "flint and steel: " .. why end
		end
		local f = A.feet(p)
		local o = vector.offset(f, -1, 0, 2) -- frame corner; the frame spans x..x+3, y..y+4 in plane z+2
		local cells = {}
		for dx = 0, 3 do
			for dy = 0, 4 do
				local q = vector.offset(o, dx, dy, 0)
				local edge_x, edge_y = dx == 0 or dx == 3, dy == 0 or dy == 4
				local kind = (edge_x and edge_y) and "corner" or ((edge_x or edge_y) and "frame" or "inner")
				cells[#cells + 1] = {q = q, kind = kind, dy = dy}
			end
		end
		for _, c in ipairs(cells) do
			if c.kind == "inner" and A.solid(c.q) then A.dig(p, c.q) end
			if c.kind ~= "inner" and not A.buildable(c.q) and minetest.get_node(c.q).name ~= "mcl_core:obsidian" then
				A.dig(p, c.q)
			end
		end
		table.sort(cells, function(a, b) return a.dy < b.dy end)
		for _, c in ipairs(cells) do
			if c.kind == "frame" and minetest.get_node(c.q).name ~= "mcl_core:obsidian" then
				A.status("placing obsidian")
				if not A.place(p, c.q, "mcl_core:obsidian") then
					-- a temporary support block at the corner below helps side columns
					A.place_any_block(p, vector.offset(o, c.q.x == o.x and 0 or 3, 0, 0))
					if not A.place(p, c.q, "mcl_core:obsidian") then
						return false, "could not place obsidian at " .. U.pos_text(c.q)
					end
				end
			elseif c.kind == "corner" and A.buildable(c.q) then
				A.place_any_block(p, c.q)
			end
		end
		local bottom, inner = vector.offset(o, 1, 0, 0), vector.offset(o, 1, 1, 0)
		A.wield_item(p, "mcl_fire:flint_and_steel")
		local st = p:get_wielded_item()
		A.face(p, inner)
		local res = st:get_definition().on_place(st, p, {type = "node", under = bottom, above = inner})
		if res then p:set_wielded_item(res) end
		A.wait(1)
		if minetest.get_node(inner).name ~= "mcl_portals:portal" then
			mcl_portals.light_nether_portal(inner)
		end
		if minetest.get_node(inner).name ~= "mcl_portals:portal" then
			return false, "frame built but the portal did not light"
		end
		jev.mem.portal = minetest.pos_to_string(inner)
		jev.save_mem()
		A.status("stepping into the portal")
		A.approach(p, vector.offset(inner, 0, 0, -1), 1.5, {no_tunnel = true})
		A.glide(p, p:get_pos(), vector.offset(inner, 0, -0.5, 0))
		for _ = 1, 15 do
			A.wait(1)
			if U.dimension(p:get_pos()) == "nether" then
				jev.mem.nether_visited = true
				jev.save_mem()
				return true, "entered the Nether at " .. U.pos_text(p:get_pos())
			end
		end
		return true, "portal lit at " .. U.pos_text(inner) .. " but teleport did not happen yet"
	end,
})
