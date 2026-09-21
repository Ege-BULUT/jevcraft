-- Walk back to where Jev died and pick up the dropped items.
local U, A = jev.u, jev.a

jev.register_skill({
	id = "recover_items", label = "🎒 Recover dropped items", timeout = 90,
	offer = function(p, x)
		local d = jev.S.death
		if not d or d.recovered or os.time() - d.time > 280 then
			return nil
		end
		local dist = U.dist(x.pos, d.pos)
		if dist > 80 then
			return {ok = false, prio = 10, detail = "death spot " .. U.where(x.pos, d.pos) .. " is too far"}
		end
		return {ok = true, prio = 74, detail = string.format("walk to the death spot %s and pick up the dropped items (they vanish ~%d s from now)",
			U.where(x.pos, d.pos), 300 - (os.time() - d.time))}
	end,
	run = function(p)
		local d = jev.S.death
		A.status("walking back to " .. U.pos_text(d.pos))
		local ok, why = A.approach(p, vector.offset(d.pos, 0, 1, 0), 2)
		if not ok then
			return false, "could not reach the death spot: " .. (why or "no path")
		end
		local before = 0
		for _, c in pairs(U.counts(p)) do before = before + c end
		A.collect(p, d.pos, 8)
		d.recovered = true
		local after = 0
		for _, c in pairs(U.counts(p)) do after = after + c end
		return after > before, "picked up " .. (after - before) .. " items"
	end,
})
