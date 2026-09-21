-- Walk 30-60 m toward the least visited area (32 m grid cells), in ~10 m hops.
local U, A = jev.u, jev.a

local DIRS = {{0, 1, "north"}, {1, 1, "north-east"}, {1, 0, "east"}, {1, -1, "south-east"},
	{0, -1, "south"}, {-1, -1, "south-west"}, {-1, 0, "west"}, {-1, 1, "north-west"}}

local function cell(pos)
	return math.floor(pos.x / 32) .. "," .. math.floor(pos.z / 32)
end

local function mark(pos)
	jev.mem.visited = jev.mem.visited or {}
	jev.mem.visited[cell(pos)] = true
end

-- Direction whose cell 48 m away is unvisited, rotating to keep variety.
local function pick_dir(pos)
	local v = jev.mem.visited or {}
	local start = (jev.mem.explore_i or 0)
	for k = 0, 7 do
		local i = (start + k) % 8 + 1
		local d = DIRS[i]
		local len = math.sqrt(d[1] * d[1] + d[2] * d[2])
		local t = vector.offset(pos, d[1] / len * 48, 0, d[2] / len * 48)
		if not v[cell(t)] then
			return i
		end
	end
	return (start % 8) + 1
end

local function surface(near)
	local c = vector.round(near)
	for dy = 8, -12, -1 do
		local f = vector.offset(c, 0, dy, 0)
		if A.standable(f) then
			return f
		end
	end
end

jev.register_skill({
	id = "explore", label = "🧭 Explore", timeout = 200,
	offer = function(p, x)
		local i = pick_dir(x.pos)
		local prio = (not x.tree) and 60 or ((x.pick >= 2 and not x.ores.iron) and 44 or 25)
		local vil = x.villager and ("; a villager is " .. U.where(x.pos, x.villager.pos) .. " (village near)") or ""
		local up = A.outdoors(x.pos) and "" or " (first digs a staircase up to the surface)"
		return {ok = true, prio = prio, detail = "walk ~50 m " .. DIRS[i][3] .. " into unvisited land" .. up .. vil}
	end,
	run = function(p)
		if not A.outdoors(p:get_pos()) then
			local ok, why = A.to_surface(p)
			if not ok then
				return false, why
			end
		end
		local start = p:get_pos()
		mark(start)
		local i = pick_dir(start)
		jev.mem.explore_i = i
		local walked, fails = 0, 0
		while U.hdist(start, p:get_pos()) < 50 and fails < 4 do
			local d = DIRS[i]
			local len = math.sqrt(d[1] * d[1] + d[2] * d[2])
			local target = surface(vector.offset(p:get_pos(), d[1] / len * 10, 0, d[2] / len * 10))
			A.status("exploring " .. d[3] .. ", " .. math.floor(U.hdist(start, p:get_pos())) .. " m so far")
			local ok = target and A.approach(p, vector.offset(target, 0, 1, 0), 1.5, {no_tunnel = fails < 2})
			if ok then
				walked = walked + 1
				mark(p:get_pos())
			else
				fails = fails + 1
				i = (i + (fails % 2 == 1 and 1 or -2) - 1) % 8 + 1 -- veer right, then left
			end
			if p:get_hp() <= 0 then
				return false, "died"
			end
		end
		jev.save_mem()
		local dist = math.floor(U.hdist(start, p:get_pos()))
		local vil = U.first(U.mobs(p:get_pos(), 48), function(m) return m.kind == "villager" end)
		return dist >= 10, "moved " .. dist .. " m " .. DIRS[i][3] .. " to " .. U.pos_text(p:get_pos()) ..
			(vil and "; spotted a villager" or "")
	end,
})
