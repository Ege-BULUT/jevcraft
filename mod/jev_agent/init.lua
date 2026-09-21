-- jev_agent: an external decision service plays VoxeLibre as one player
-- through high-level skills (skills/*.lua), driven by a decision HTTP endpoint.
jev = {}
local MP = minetest.get_modpath(minetest.get_current_modname())
local http = minetest.request_http_api()
local storage = minetest.get_mod_storage()
local settings = minetest.settings

local PLAYER = settings:get("jev_agent.player") or "Jev"
local URL = settings:get("jev_agent.decide_url") or "http://127.0.0.1:8787/decide"
local KEY = settings:get("jev_agent.key") or ""
local TIMEOUT = tonumber(settings:get("jev_agent.decide_timeout")) or 60
local RETRY_OFFLINE = 10
local REC_FILE = minetest.get_worldpath() .. "/jev_recording"

local function log(msg)
	minetest.log("action", "[jev_agent] " .. msg)
end
jev.log = log

-- Small persistent memory (shelter, bed, portal positions ...).
jev.mem = minetest.deserialize(storage:get_string("mem")) or {}
function jev.save_mem()
	storage:set_string("mem", minetest.serialize(jev.mem))
end

dofile(MP .. "/lib/util.lua")
dofile(MP .. "/lib/act.lua")
dofile(MP .. "/lib/state.lua")
dofile(MP .. "/lib/hud.lua")

-- Skill registry ---------------------------------------------------------------
jev.skills, jev.skill_order = {}, {}
function jev.register_skill(def)
	def.timeout = def.timeout or 90
	jev.skills[def.id] = def
	jev.skill_order[#jev.skill_order + 1] = def.id
end

for _, id in ipairs({
	"eat", "fight_hostile", "flee_to_shelter", "sleep", "gather_wood", "craft_planks", "craft_sticks",
	"craft_crafting_table", "craft_wooden_tools", "mine_stone", "craft_stone_tools", "craft_furnace",
	"mine_ores", "smelt", "craft_iron_tools", "hunt_food", "build_shelter", "craft_bed", "farm",
	"explore", "trade_with_villager", "build_nether_portal",
}) do
	dofile(MP .. "/skills/" .. id .. ".lua")
end

-- Agent state -------------------------------------------------------------------
-- mode: "idle" (needs a decision), "deciding" (request in flight), "running",
-- "waiting" (endpoint asked us to wait), "paused" (endpoint offline), "over", "dead"
local S = {mode = "idle", notes = {}, retry_at = 0}
jev.S = S

local function now()
	return minetest.get_us_time() / 1e6
end

local function note(text)
	S.notes[#S.notes + 1] = text
end
jev.note = note

-- Recording flag file: present only while the agent is PLAYING.
local function set_recording(on)
	if on then
		if not S.recording then
			minetest.safe_file_write(REC_FILE, "playing\n")
			S.recording = true
		end
	else
		os.remove(REC_FILE)
		S.recording = false
	end
end
os.remove(REC_FILE)

-- Pause / resume ------------------------------------------------------------------
local function enter_pause(p, why, permanent)
	S.retry_at = now() + RETRY_OFFLINE
	if permanent then
		S.mode = "over"
	else
		S.mode = "paused"
	end
	set_recording(false)
	if not S.paused then
		S.paused = true
		S.saved_time_speed = settings:get("time_speed") or "72"
		settings:set("time_speed", "0")
		if p then
			local g = p:get_armor_groups()
			S.saved_armor = table.copy(g)
			g.immortal = 1
			p:set_armor_groups(g)
		end
		S.pause_tod = minetest.get_timeofday()
		log(string.format("PAUSED: %s (time_speed %s -> 0, immortal=%s, recording file removed)", why,
			S.saved_time_speed, p and tostring(p:get_armor_groups().immortal) or "?"))
	end
	jev.hud_set(p, "⏸ PAUSED", why .. (permanent and "" or " - retrying every 10 s"))
end

local function leave_pause(p)
	if not S.paused then
		return
	end
	S.paused = false
	settings:set("time_speed", S.saved_time_speed or "72")
	if p and S.saved_armor then
		p:set_armor_groups(S.saved_armor)
	end
	S.saved_armor = nil
	log(string.format("RESUMED: decision endpoint answered (time of day %.4f -> %.4f while paused)",
		S.pause_tod or -1, minetest.get_timeofday()))
	note("Resumed after the decision service was offline; the world was frozen meanwhile.")
end

minetest.register_on_player_hpchange(function(player, change, reason)
	if player:get_player_name() ~= PLAYER then
		return change
	end
	if S.paused and change < 0 then
		return 0
	end
	if change < 0 then
		S.last_damage = reason
	end
	return change
end, true)

minetest.register_on_shutdown(function()
	set_recording(false)
	if S.paused then
		settings:set("time_speed", S.saved_time_speed or "72")
	end
end)

-- Skill execution ----------------------------------------------------------------
local function finish(ok, msg)
	local sk = S.skill
	msg = msg or (ok and "done" or "failed")
	local gained = {}
	local after = jev.u.counts(S.player)
	for name, c in pairs(after) do
		local d = c - (S.inv_before[name] or 0)
		if d > 0 then
			gained[#gained + 1] = "+" .. d .. " " .. jev.u.desc(name)
		end
	end
	for name, c in pairs(S.inv_before) do
		local d = (after[name] or 0) - c
		if d < 0 then
			gained[#gained + 1] = d .. " " .. jev.u.desc(name)
		end
	end
	local delta = #gained > 0 and (" [" .. table.concat(gained, ", ", 1, math.min(#gained, 8)) .. "]") or ""
	S.last = {skill = sk.id, ok = ok, message = msg}
	note(string.format("Last: %s %s after %d s: %s%s", sk.id, ok and "succeeded" or "FAILED",
		math.floor(now() - S.started), msg, delta))
	log(string.format("skill %s %s: %s%s", sk.id, ok and "succeeded" or "failed", msg, delta))
	S.skill, S.co = nil, nil
	S.mode = "idle"
	S.retry_at = now() + 0.3
end

local function start_skill(p, id, label)
	local sk = jev.skills[id]
	S.skill, S.player, S.started = sk, p, now()
	S.inv_before = jev.u.counts(p)
	S.mode = "running"
	S.last_hp = p:get_hp()
	local ctx = jev.scan(p)
	S.co = coroutine.create(function()
		return sk.run(p, ctx)
	end)
	jev.hud_set(p, (sk.label or id), "starting", label)
	log("start skill " .. id)
end

-- Decision request ----------------------------------------------------------------
local function build_request(p)
	local ctx = jev.scan(p)
	local opts = {}
	for _, id in ipairs(jev.skill_order) do
		local sk = jev.skills[id]
		local ok, o = pcall(sk.offer, p, ctx)
		if not ok then
			minetest.log("error", "[jev_agent] offer " .. id .. ": " .. tostring(o))
		elseif o then
			opts[#opts + 1] = {id = id, label = sk.label, detail = (o.ok and "" or "Not possible now: ") .. o.detail,
				ok = o.ok, prio = o.prio or 0}
		end
	end
	-- Feasible options first (by relevance), then explanations of blocked ones; 6-14 total.
	table.sort(opts, function(a, b)
		if a.ok ~= b.ok then
			return a.ok
		end
		return a.prio > b.prio
	end)
	local out = {}
	for _, o in ipairs(opts) do
		if #out < 14 and (o.ok or #out < 6 or o.prio >= 50) then
			out[#out + 1] = {id = o.id, label = o.label, detail = o.detail}
		end
	end
	local body = {
		state = jev.state_text(ctx, S.notes),
		options = out,
		snapshot = jev.snapshot(ctx, S.last),
	}
	return body, out
end

local function handle_response(p, res, offered)
	if not res.succeeded or res.code == 0 then
		return enter_pause(p, res.timeout and "decision request timed out" or "decision endpoint unreachable")
	end
	if res.code == 410 then
		return enter_pause(p, "run is over (HTTP 410); paused until restart", true)
	end
	if res.code == 401 or res.code == 400 then
		minetest.log("error", "[jev_agent] decision endpoint rejected the request (HTTP " .. res.code .. "): "
			.. tostring(res.data):sub(1, 300))
		return enter_pause(p, "endpoint rejected request (HTTP " .. res.code .. ")")
	end
	if res.code < 200 or res.code > 299 then
		return enter_pause(p, "decision endpoint returned HTTP " .. res.code)
	end
	local data = minetest.parse_json(res.data or "", nil)
	leave_pause(p)
	if type(data) ~= "table" then
		log("unparseable decision: " .. tostring(res.data):sub(1, 200))
		note("Last decision could not be parsed; answer with {\"action\": \"<option id>\"}.")
		S.mode, S.retry_at = "idle", now() + 2
		return
	end
	if data.wait then
		local ms = math.max(100, math.min(tonumber(data.retryMs) or 2000, 120000))
		S.mode, S.retry_at = "waiting", now() + ms / 1000
		set_recording(true)
		jev.hud_set(p, "⏳ waiting", "decision service asked to wait " .. math.floor(ms / 100) / 10 .. " s")
		return
	end
	local id = data.action
	local label
	for _, o in ipairs(offered) do
		if o.id == id then
			label = o.label
		end
	end
	if not label then
		log("invalid action: " .. tostring(id))
		note("Last answer '" .. tostring(id) .. "' was not one of the offered option ids.")
		S.mode, S.retry_at = "idle", now() + 2
		return
	end
	set_recording(true)
	S.notes = {}
	log("decision: " .. id)
	start_skill(p, id, label)
end

local function request_decision(p)
	if not http then
		return enter_pause(p, "HTTP API unavailable: add jev_agent to secure.http_mods")
	end
	local body, offered = build_request(p)
	local ids = {}
	for _, o in ipairs(offered) do
		ids[#ids + 1] = o.id
	end
	log("request decision; options: " .. table.concat(ids, ","))
	S.mode = "deciding"
	local headers = {"Content-Type: application/json"}
	if KEY ~= "" then
		headers[#headers + 1] = "x-jevcraft-key: " .. KEY
	end
	http.fetch({url = URL, method = "POST", data = minetest.write_json(body), extra_headers = headers,
		timeout = TIMEOUT}, function(res)
		local pl = minetest.get_player_by_name(PLAYER)
		if not pl or S.mode ~= "deciding" then
			return
		end
		if pl:get_hp() <= 0 then
			S.mode = "dead"
			return
		end
		handle_response(pl, res, offered)
	end)
end

-- Death and respawn ---------------------------------------------------------------
local function death_cause(reason)
	local r = S.last_damage or reason or {}
	local m = r._mcl_reason
	local t = (m and m.type) or r._mcl_type or r.type or "unknown"
	local src = (m and (m.source or m.direct)) or r.object
	if src and src.get_luaentity and src:get_luaentity() then
		return t .. " (" .. (src:get_luaentity().name or "?"):gsub("^.*:", "") .. ")"
	end
	return t
end

minetest.register_on_dieplayer(function(player, reason)
	if player:get_player_name() ~= PLAYER then
		return
	end
	local pos = player:get_pos()
	local cause = death_cause(reason)
	if S.skill then
		note("Died during " .. S.skill.id .. ".")
		log("skill " .. S.skill.id .. " aborted: died")
		S.skill, S.co = nil, nil
	end
	S.mode = "dead"
	S.death = {cause = cause, pos = pos}
	jev.mem.deaths = (jev.mem.deaths or 0) + 1
	jev.save_mem()
	log("died: " .. cause .. " at " .. minetest.pos_to_string(vector.round(pos)))
	jev.hud_set(player, "☠ died", cause)
	minetest.after(3, function()
		local pl = minetest.get_player_by_name(PLAYER)
		if pl and pl:get_hp() <= 0 then
			minetest.close_formspec(PLAYER, "__builtin:death")
			pl:respawn()
		end
	end)
end)

minetest.register_on_respawnplayer(function(player)
	if player:get_player_name() ~= PLAYER then
		return
	end
	minetest.after(0.5, function()
		minetest.close_formspec(PLAYER, "__builtin:death")
		local pl = minetest.get_player_by_name(PLAYER)
		if not pl then
			return
		end
		local d = S.death or {cause = "unknown", pos = pl:get_pos()}
		local empty = next(jev.u.counts(pl)) == nil
		note(string.format("Died: %s at %s; respawned at %s%s. Death count %d.", d.cause, jev.u.pos_text(d.pos),
			jev.u.pos_text(pl:get_pos()), empty and ", inventory lost (items dropped where you died, they despawn in ~5 min)" or "",
			jev.mem.deaths or 1))
		log("respawned at " .. minetest.pos_to_string(vector.round(pl:get_pos())))
		S.mode, S.retry_at = "idle", now() + 1
	end)
end)

-- Main loop --------------------------------------------------------------------------
minetest.register_on_joinplayer(function(player)
	if player:get_player_name() == PLAYER then
		jev.hud_init(player)
		S.mode, S.retry_at = "idle", now() + 3
		if player:get_hp() <= 0 then
			S.mode = "dead"
			minetest.after(2, function()
				if player:get_hp() <= 0 then
					player:respawn()
				end
			end)
		end
	end
end)

minetest.register_on_leaveplayer(function(player)
	if player:get_player_name() == PLAYER then
		if S.paused and S.saved_armor then
			player:set_armor_groups(S.saved_armor)
		end
		S.skill, S.co = nil, nil
		S.mode = "idle"
		set_recording(false)
	end
end)

local INTERRUPTIBLE = {fight_hostile = false, flee_to_shelter = false, eat = false, sleep = false}

minetest.register_globalstep(function(dtime)
	local p = minetest.get_player_by_name(PLAYER)
	if not p then
		return
	end
	local t = now()
	if S.mode == "running" then
		if p:get_hp() <= 0 then
			return
		end
		if t - S.started > S.skill.timeout then
			return finish(false, "timed out after " .. S.skill.timeout .. " s")
		end
		-- Being hurt by a hostile interrupts non-combat skills so the model can react.
		local hp = p:get_hp()
		if hp < (S.last_hp or hp) and INTERRUPTIBLE[S.skill.id] ~= false then
			local m = jev.u.first(jev.u.mobs(p:get_pos(), 6), function(x) return x.kind == "hostile" end)
			if m then
				S.last_hp = hp
				return finish(false, "interrupted: attacked by " .. m.short .. " (HP " .. hp .. ")")
			end
		end
		S.last_hp = hp
		local ok, a, b = coroutine.resume(S.co, dtime)
		if not ok then
			minetest.log("error", "[jev_agent] skill " .. S.skill.id .. " crashed: " .. tostring(a))
			return finish(false, "internal error")
		end
		if coroutine.status(S.co) == "dead" then
			return finish(a and true or false, b)
		end
	elseif S.mode == "paused" then
		local g = p:get_armor_groups()
		if not g.immortal then
			S.saved_armor = table.copy(g)
			g.immortal = 1
			p:set_armor_groups(g)
		end
		if t >= S.retry_at then
			request_decision(p)
		end
	elseif S.mode == "idle" or S.mode == "waiting" then
		if t >= S.retry_at and p:get_hp() > 0 then
			request_decision(p)
		end
	end
end)

function jev.set_status(text)
	local p = minetest.get_player_by_name(PLAYER)
	if p and S.skill then
		jev.hud_set(p, S.skill.label or S.skill.id, text)
	end
end
