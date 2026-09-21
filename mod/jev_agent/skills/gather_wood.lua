-- Walk to the nearest tree and chop its trunk (and nearby trunk blocks within reach).
local U, A = jev.u, jev.a

local function chop_tree(p, start)
	-- Find the trunk base.
	local base = vector.new(start)
	while minetest.get_item_group(minetest.get_node(vector.offset(base, 0, -1, 0)).name, "tree") > 0 do
		base.y = base.y - 1
	end
	A.status("walking to a tree " .. U.where(p:get_pos(), base))
	local ok, why = A.approach(p, base, 3.5)
	if not ok then
		return 0, why
	end
	local n = 0
	for _ = 1, 12 do
		local head = A.head(p)
		local list = minetest.find_nodes_in_area(vector.offset(head, -4, -3, -4), vector.offset(head, 4, 4, 4), {"group:tree"})
		table.sort(list, function(a, b) return a.y < b.y or (a.y == b.y and U.dist(a, head) < U.dist(b, head)) end)
		local target
		for _, q in ipairs(list) do
			if vector.distance(head, q) <= 4.4 then
				target = q
				break
			end
		end
		if not target then
			break
		end
		A.status("chopping " .. U.desc(minetest.get_node(target).name))
		if not A.dig(p, target) then
			break
		end
		n = n + 1
	end
	A.collect(p, base, 7)
	return n
end

jev.register_skill({
	id = "gather_wood", label = "🪓 Gather wood", timeout = 100,
	offer = function(p, x)
		local wood = x.logs * 4 + x.planks
		if not x.tree then
			return {ok = false, prio = wood < 8 and 45 or 5, detail = "no trees within 32 m; explore to find some (you have " ..
				x.logs .. " logs, " .. x.planks .. " planks)"}
		end
		local prio = wood < 12 and 80 or (wood < 28 and 52 or 12)
		return {ok = true, prio = prio, detail = string.format("nearest tree %s; you have %d logs, %d planks; %s",
			U.where(x.pos, x.tree), x.logs, x.planks, x.axe > 0 and "your axe chops faster" or "no axe, ~3 s per log by hand")}
	end,
	run = function(p)
		local before = U.count(p, "group:tree")
		for _ = 1, 3 do
			local tree = U.nearest_node(p:get_pos(), {"group:tree"}, 32, 8, 12)
			if not tree then
				break
			end
			local n, why = chop_tree(p, tree)
			if n == 0 and why then
				return U.count(p, "group:tree") > before, "could not reach the tree: " .. why
			end
			if U.count(p, "group:tree") - before >= 5 then
				break
			end
		end
		local got = U.count(p, "group:tree") - before
		return got > 0, got > 0 and ("+" .. got .. " logs") or "no logs collected"
	end,
})
