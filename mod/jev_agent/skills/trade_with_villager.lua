-- Minimal villager interaction: walk up to a villager and report its profession
-- (trading proper needs emeralds, which this agent does not collect yet).
local U, A = jev.u, jev.a

jev.register_skill({
	id = "trade_with_villager", label = "🤝 Visit villager", timeout = 60,
	offer = function(p, x)
		if not x.villager then
			return nil
		end
		local em = x.n("mcl_core:emerald")
		return {ok = true, prio = 18, detail = "walk to the villager " .. U.where(x.pos, x.villager.pos) ..
			" and check its trades (you have " .. em .. " emeralds)"}
	end,
	run = function(p)
		local v = U.first(U.mobs(p:get_pos(), 32), function(m) return m.kind == "villager" end)
		if not v then
			return false, "villager gone"
		end
		for _ = 1, 10 do
			if not v.obj:get_pos() then break end
			if vector.distance(p:get_pos(), v.obj:get_pos()) < 3 then break end
			A.approach(p, vector.offset(v.obj:get_pos(), 0, 1, 0), 2.5, {max_steps = 6, no_tunnel = true})
		end
		if not v.obj:get_pos() or vector.distance(p:get_pos(), v.obj:get_pos()) > 4 then
			return false, "could not catch up with the villager"
		end
		A.face(p, vector.offset(v.obj:get_pos(), 0, 1.5, 0))
		local e = v.obj:get_luaentity()
		local prof = e and e._profession or "unknown"
		jev.mem.village = minetest.pos_to_string(vector.round(v.obj:get_pos()))
		jev.save_mem()
		A.wait(1)
		return true, "met a " .. prof .. " villager at " .. U.pos_text(v.obj:get_pos()) .. "; trading needs emeralds"
	end,
})
