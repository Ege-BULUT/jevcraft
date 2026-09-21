-- A light that travels with Jev, so the recording is never pitch black: in a cave, at night or
-- with a block in front of its face, the surroundings stay visible. It is an invisible,
-- non-solid node at head height that follows the player; each copy removes itself a moment after
-- the player has moved on, so none are left behind, even after a crash.
local NAME = "jev_agent:glow"
local PLAYER = minetest.settings:get("jev_agent.player") or "Jev"

minetest.register_node(NAME, {
	description = "Jev's light",
	drawtype = "airlike",
	paramtype = "light",
	light_source = 11, -- a little under a torch (14)
	sunlight_propagates = true,
	walkable = false,
	pointable = false,
	diggable = false,
	buildable_to = true, -- anything placed here simply replaces it
	floodable = true,
	drop = "",
	groups = { not_in_creative_inventory = 1 },
	on_timer = function(pos)
		local p = minetest.get_player_by_name(PLAYER)
		if p and vector.distance(vector.round(vector.offset(p:get_pos(), 0, 1, 0)), pos) < 1 then
			return true -- still here: keep glowing
		end
		minetest.remove_node(pos)
	end,
})

local last, acc = nil, 0
minetest.register_globalstep(function(dtime)
	acc = acc + dtime
	if acc < 0.25 then return end
	acc = 0
	local p = minetest.get_player_by_name(PLAYER)
	if not p then return end
	local head = vector.round(vector.offset(p:get_pos(), 0, 1, 0))
	if last and vector.equals(last, head) then return end
	local node = minetest.get_node(head).name
	if node == "air" then
		minetest.swap_node(head, { name = NAME })
		minetest.get_node_timer(head):start(1.5)
		last = head
	elseif node ~= NAME then
		last = nil -- head in water or a block: nothing to light from here
	end
end)
