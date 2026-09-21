-- Mine cobblestone: nearby exposed stone first, otherwise a staircase down.
local U, A = jev.u, jev.a

local function dig_stone_near(p, center)
	local head = A.head(p)
	local list = minetest.find_nodes_in_area(vector.offset(center, -2, -2, -2), vector.offset(center, 2, 2, 2), jev.STONE)
	table.sort(list, function(a, b) return U.dist(a, head) < U.dist(b, head) end)
	local n = 0
	for _, q in ipairs(list) do
		if n >= 4 then
			break
		end
		-- Do not dig out the block we stand on.
		if U.dist(q, A.head(p)) <= 4.3 and not vector.equals(q, vector.offset(A.feet(p), 0, -1, 0)) then
			A.status("mining " .. U.desc(minetest.get_node(q).name))
			if A.dig(p, q) then
				n = n + 1
			end
		end
	end
	return n
end

jev.register_skill({
	id = "mine_stone", label = "🪨 Mine stone", timeout = 110,
	offer = function(p, x)
		if x.pick == 0 then
			return {ok = false, prio = 55, detail = "stone needs a pickaxe to drop cobblestone (craft_wooden_tools first)"}
		end
		local prio = x.cobble < 11 and 72 or (x.cobble < 24 and 48 or 15)
		local where = x.stone and ("exposed stone " .. U.where(x.pos, x.stone)) or "no exposed stone near: dig a staircase down"
		return {ok = true, prio = prio, detail = where .. "; you have " .. x.cobble .. " cobblestone, aiming for +10"}
	end,
	run = function(p)
		local before = U.count(p, "group:cobble")
		local function got()
			return U.count(p, "group:cobble") - before
		end
		for _ = 1, 4 do
			if got() >= 10 then
				break
			end
			local stone = U.nearest_exposed(p:get_pos(), jev.STONE, 16)
			if not stone then
				break
			end
			A.status("walking to stone " .. U.where(p:get_pos(), stone))
			if not A.approach(p, stone, 4) then
				break
			end
			dig_stone_near(p, stone)
			A.collect(p, stone, 5)
		end
		-- Staircase down in the direction the player faces.
		local steps = 0
		while got() < 10 and steps < 10 and A.feet(p).y > -30 do
			local f = A.feet(p)
			local yaw = p:get_look_horizontal()
			local dx, dz = -math.sin(yaw), math.cos(yaw)
			if math.abs(dx) > math.abs(dz) then dx, dz = dx > 0 and 1 or -1, 0 else dx, dz = 0, dz > 0 and 1 or -1 end
			A.status("staircase down, y " .. f.y)
			local ok, why = A.tunnel(p, vector.offset(f, dx * 3, -3, dz * 3), 1.2, 1)
			if not ok and why and why ~= "too far to tunnel" then
				if steps == 0 or why:find("lava") then
					if got() == 0 then
						return false, "staircase blocked: " .. why
					end
					break
				end
				p:set_look_horizontal(yaw + math.pi / 2)
			end
			steps = steps + 1
			A.collect(p, p:get_pos(), 3)
		end
		return got() > 0, "+" .. got() .. " cobblestone (now at y " .. A.feet(p).y .. ")"
	end,
})
