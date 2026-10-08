---------------------------------------------------------------------------
-- A replay left looping: from the editor (RB, G or the Start menu) you get
-- off the board and walk about while the clip (its trimmed part, at its
-- speed) goes round and round as a ghost of you; getting back on removes it.
-- Whatever ghost you show - in the editor or looping - is sent to the other
-- players too (sv_replay_network.lua passes it on), so they see it skate.
-- H hides the HUD while a replay is open or looping (for clean shots).
--   skategm_replay_walk        leave the open replay looping and walk about
--   skategm_replay_stop_loop   stop the looping one
--   skategm_replay_hud         hide / show the HUD
---------------------------------------------------------------------------
local S = SkateGM
local R = S.replay
local UI = SKATEGM_UI
local function API() return S.API end

---------------------------------------------------------------------------
-- to the other players: the pose on show, 20 times a second
---------------------------------------------------------------------------
local writer = { float = net.WriteFloat, int = function(v) net.WriteInt(v, 16) end, u8 = function(v) net.WriteUInt(v, 8) end }
local reader = { float = net.ReadFloat, int = function() return net.ReadInt(16) end, u8 = function() return net.ReadUInt(8) end }
R.NET_RATE = 1 / 20

function R.NetworkFeed(P, state, now)
	if not (P and P.HIPS) or now < (R.nextNetwork or 0) then return end
	R.nextNetwork, R.networkActive = now + R.NET_RATE, true
	net.Start("skategm_replay_pose", true)
	net.WriteBool(true)
	S.Encode(P, writer, state)
	net.SendToServer()
end

function R.NetworkStop()
	if not R.networkActive then return end
	R.networkActive, R.nextNetwork = nil, nil
	net.Start("skategm_replay_pose")
	net.WriteBool(false)
	net.SendToServer()
end

-- the ghost in the editor goes out too
local feed = R.Feed
function R.Feed(now)
	feed(now)
	local v = R.on
	if v then R.NetworkFeed(v.P, v.frame and v.frame.state, now) end
end

local close = R.Close
function R.Close()
	if R.on and not R.leavingToLoop then
		R.NetworkStop()
		R.SetHUDHidden(false)
	end
	close()
end

---------------------------------------------------------------------------
-- the HUD hidden (H): the game's HUD and menus, and the editor's own
---------------------------------------------------------------------------
function R.SetHUDHidden(hidden)
	if hidden and not R.hudBackup then
		R.hudBackup = {}
		for _, name in ipairs({ "cl_drawhud", "r_drawvgui" }) do
			local cv = GetConVar(name)
			if cv then R.hudBackup[name] = cv:GetString() RunConsoleCommand(name, "0") end
		end
	elseif not hidden and R.hudBackup then
		for name, value in pairs(R.hudBackup) do RunConsoleCommand(name, value) end
		R.hudBackup = nil
	end
	R.hudHidden = hidden or nil
end

function R.ToggleHUD()
	if R.on or R.loop then R.SetHUDHidden(not R.hudHidden) end
end

local paint = R.Paint
function R.Paint(w, h)
	if R.hudHidden then return end
	paint(w, h)
end

hook.Add("ShutDown", "skategm_replay_restore_hud", function() R.SetHUDHidden(false) end)

---------------------------------------------------------------------------
-- other players' replay ghosts: each one a skater of its own
---------------------------------------------------------------------------
local remoteReplays = {}
local function Forget(ply)
	local r = remoteReplays[ply]
	if r then S.ForgetSkater(r.key) remoteReplays[ply] = nil end
end

net.Receive("skategm_replay_pose", function()
	local ply = net.ReadEntity()
	if not net.ReadBool() then Forget(ply) return end
	local P, state = S.Decode(reader)
	if not IsValid(ply) or ply == LocalPlayer() then return end
	local now = RealTime()
	local rec = remoteReplays[ply]
	if not rec then rec = { key = S.ClipProxy(ply) } remoteReplays[ply] = rec end
	rec.last = now
	local r = S.remote[rec.key] or { snaps = {} }
	local latest = r.snaps[#r.snaps]
	-- (a jump - the clip came round again - starts afresh, not a glide)
	if latest and (P.HIPS - latest.P.HIPS):LengthSqr() > 256 ^ 2 then r.snaps = {} end
	r.snaps[#r.snaps + 1] = { t = now, P = P }
	while #r.snaps > 4 do table.remove(r.snaps, 1) end
	r.last, r.state = now, state
	S.remote[rec.key] = r
end)

---------------------------------------------------------------------------
-- looping
---------------------------------------------------------------------------
-- leaves the open replay looping: you get off the board (Skater mode off)
-- and walk about; getting back on (skategm_toggle) removes the ghost. (Not
-- in the SkateGM gamemode, which keeps Skater mode on.)
function R.Detach()
	local v = R.on
	if not v then return end
	if S.locked then return R.Note("this gamemode keeps Skater mode on: leave a replay looping in Sandbox") end
	local a, b = R.Trim()
	if b - a < 0.2 then return R.Note("the trimmed part is too short to loop") end
	R.leavingToLoop = true
	R.Close()
	R.leavingToLoop = nil
	API().StopSkating()
	if S.phase ~= "off" then R.NetworkStop() R.SetHUDHidden(false) return end
	R.loop = { clip = v.clip, a = a, b = b, t = math.Clamp(v.t, a, b), speed = R.speeds[v.speed] or 1, key = S.ClipProxy(LocalPlayer()), last = RealTime() }
	API().Say("your replay is looping: getting back on the board removes it")
end

function R.StopLoop()
	local l = R.loop
	if not l then return end
	R.loop = nil
	R.NetworkStop()
	S.ForgetSkater(l.key)
	R.SetHUDHidden(false)
end

function R.LoopThink(now)
	local l = R.loop
	if not l then return end
	-- (back on the board, or a replay opened: the ghost goes)
	if S.phase == "on" or R.on then return R.StopLoop() end
	local dt = math.max(0, now - (l.last or now))
	l.last = now
	l.t = l.t + dt * l.speed
	if l.t > l.b then l.t = l.a + (l.t - l.b) % (l.b - l.a) end
	local P, frame = R.PoseAt(l.clip, l.t)
	if not P then return end
	S.remote[l.key] = { snaps = { { t = now - 1, P = P }, { t = now + 1, P = P } }, last = now, state = frame and frame.state }
	if frame and frame.rocket and S.RocketFlames then pcall(S.RocketFlames, P, now, l.key, true) end
	R.NetworkFeed(P, frame and frame.state, now)
end

hook.Add("Think", "skategm_replay_loop", function() R.LoopThink(RealTime()) end)

-- keys (the controller's buttons are all taken in the editor): G leaves the
-- open replay looping and gets you off the board, H hides / shows the HUD
local keyWas = {}
hook.Add("Think", "skategm_replay_loop_key", function()
	local free = not gui.IsGameUIVisible() and not vgui.CursorVisible() and (not system.HasFocus or system.HasFocus())
	for _, key in ipairs({ KEY_G, KEY_H }) do
		local down = input.IsKeyDown(key)
		if down and not keyWas[key] and free and not R.exporting then
			if key == KEY_H then R.ToggleHUD() elseif R.on then R.Detach() end
		end
		keyWas[key] = down
	end
end)

hook.Add("Think", "skategm_remote_replay_cleanup", function()
	local now = RealTime()
	for ply, r in pairs(remoteReplays) do
		if not IsValid(ply) or now - r.last > 2 then Forget(ply) end
	end
end)

concommand.Add("skategm_replay_walk", function() R.Detach() end, nil, "Leave the open replay looping as a ghost and walk about (back on the board removes it)")
concommand.Add("skategm_replay_stop_loop", function() R.StopLoop() end, nil, "Stop the looping replay")
concommand.Add("skategm_replay_hud", function() R.ToggleHUD() end, nil, "Hide / show the HUD while a replay is open or looping")

---------------------------------------------------------------------------
-- in the menus: the editor's Start menu, and the replay list
---------------------------------------------------------------------------
local menuPage = R.MenuPage
function R.MenuPage()
	local page = menuPage()
	local rows = page.rows
	page.rows = function()
		local list = type(rows) == "function" and rows() or rows
		list[#list + 1] = { label = "Leave it looping and walk (RB / G)", sub = S.locked and "not in the SkateGM gamemode" or "you get off the board; your ghost skates it on repeat, others see it",
			disabled = S.locked == true, run = function() R.Detach() end }
		list[#list + 1] = { label = R.hudHidden and "Show the HUD (H)" or "Hide the HUD (H)", run = function() R.ToggleHUD() end }
		return list
	end
	return page
end

local screen = R.Screen
function R.Screen()
	local page = screen()
	local rows = page.rows
	page.rows = function()
		local list = type(rows) == "function" and rows() or rows
		if R.loop then table.insert(list, 1, { label = "Stop the looping replay", sub = "your ghost stops skating", run = function() R.StopLoop() end }) end
		return list
	end
	return page
end
local menu = SKATEGM_MODES and SKATEGM_MODES.menu
if menu and menu.SCREENS then menu.SCREENS.replays = R.Screen end
