-- Eat the best food in the inventory until the hunger bar is nearly full.
local U, A = jev.u, jev.a

jev.register_skill({
	id = "eat", label = "🍖 Eat", timeout = 30,
	offer = function(p, x)
		local food, v = A.best_food(p, x.hunger < 6)
		if not food then
			local hint = x.prey and ("; nearest animal: " .. x.prey.short .. " " .. U.where(x.pos, x.prey.pos)) or ""
			return {ok = false, detail = "no safe food in inventory" .. hint, prio = x.hunger < 12 and 55 or 5}
		end
		if x.hunger >= 16 then
			return {ok = false, detail = "hunger " .. x.hunger .. "/20 is not low enough (eat below 16)", prio = 0}
		end
		return {ok = true, prio = x.hunger < 8 and 100 or (x.hunger < 12 and 88 or 70),
			detail = string.format("eat %s: +%d food (%d -> %d/20); %d food items left", U.desc(food), v, x.hunger,
				math.min(20, x.hunger + v), x.food - 1)}
	end,
	run = function(p)
		local eaten = 0
		for _ = 1, 4 do
			if mcl_hunger.get_hunger(p) >= 18 then
				break
			end
			local food = A.best_food(p, mcl_hunger.get_hunger(p) < 6)
			if not food or not A.eat(p, food) then
				break
			end
			eaten = eaten + 1
			A.wait(0.6)
		end
		if eaten == 0 then
			return false, "nothing eaten"
		end
		return true, "ate " .. eaten .. " item(s); food now " .. mcl_hunger.get_hunger(p) .. "/20"
	end,
})
