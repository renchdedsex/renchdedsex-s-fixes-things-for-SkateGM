local S = SkateGM

---------------------------------------------------------------------------
-- Replays: the last 15 s of your skating, always recorded (S.Record). LB +
-- RB opens the list (the last 15 s, then saved clips); the viewer
-- plays it back as a ghost of you while your skater waits.
--   A play / pause   D-pad left / right scrub   D-pad up / down speed
--   X camera (chase, orbit, free, tripod)   Y save   B back
--   orbit: right stick turns, triggers zoom; free: left stick moves, right
--   stick looks, triggers down / up
-- Saved clips: garrysmod/data/skategm/replays/*.txt
---------------------------------------------------------------------------
local R = { speeds = { 0.25, 0.5, 1 }, modes = { "chase", "orbit", "free", "tripod" } }
S.replay = R
R.DIR = "skategm/replays/"
R.MAX_LIST = 20
R.SCRUB = 1
R.MODE_NAMES = { chase = "Chase", orbit = "Orbit", free = "Free camera", tripod = "Tripod" }

-- (the shared controller UI: skategm_ui/cl_pad.lua)
if not (SKATEGM_UI and SKATEGM_UI.pad) then include("skategm_ui/cl_pad.lua") end
local UI = SKATEGM_UI
local PAD = UI.pad.B
R.PAD = PAD
local Dead = UI.pad.Dead

if file and file.CreateDir then
	file.CreateDir("skategm")
	file.CreateDir("skategm/replays")
end

---------------------------------------------------------------------------
-- a clip: { { t, P, state, trick }, ... }, t from 0
---------------------------------------------------------------------------
function R.Duration(clip) return clip and #clip > 0 and clip[#clip].t or 0 end

-- the pose at time t, blended between the two frames around it
function R.PoseAt(clip, t)
	local n = #clip
	if n == 0 then return nil end
	if t <= clip[1].t then return clip[1].P, clip[1] end
	if t >= clip[n].t then return clip[n].P, clip[n] end
	local lo, hi = 1, n
	while hi - lo > 1 do
		local mid = math.floor((lo + hi) / 2)
		if clip[mid].t <= t then lo = mid else hi = mid end
	end
	local a, b = clip[lo], clip[hi]
	local f = (t - a.t) / math.max(b.t - a.t, 1e-6)
	local P = {}
	for name, v in pairs(a.P) do
		local w = b.P[name]
		P[name] = w and (v + (w - v) * f) or v
	end
	return P, f < 0.5 and a or b
end

-- saved as text: a header, then one line a frame: t|state|trick|x,y,z,...
-- in S.BONES order, to a tenth of a unit
function R.Encode(clip, meta)
	local lines = { "skategm replay 1", "map " .. (meta and meta.map or "?"), "date " .. (meta and meta.date or "?") }
	for _, f in ipairs(clip) do
		local nums = {}
		for _, name in ipairs(S.BONES) do
			local v = f.P[name]
			if v then nums[#nums + 1] = string.format("%.1f,%.1f,%.1f", v.x, v.y, v.z) else nums[#nums + 1] = "" end
		end
		lines[#lines + 1] = string.format("%.3f|%s|%s|%s", f.t, f.state or "", (f.trick or ""):gsub("[|\n]", " "), table.concat(nums, ";"))
	end
	return table.concat(lines, "\n")
end

function R.Decode(text)
	if type(text) ~= "string" or text:sub(1, 16) ~= "skategm replay 1" then return nil end
	local clip, meta = {}, {}
	for line in text:gmatch("[^\n]+") do
		local k, v = line:match("^(%a+) (.*)$")
		if k == "map" or k == "date" then
			meta[k] = v
		else
			local t, state, trick, rest = line:match("^([%d%.%-]+)|([^|]*)|([^|]*)|(.*)$")
			if t then
				local P, i = {}, 0
				for part in (rest .. ";"):gmatch("([^;]*);") do
					i = i + 1
					local x, y, z = part:match("^([%d%.%-]+),([%d%.%-]+),([%d%.%-]+)$")
					local name = S.BONES[i]
					if x and name then P[name] = Vector(tonumber(x), tonumber(y), tonumber(z)) end
				end
				if P.HIPS then clip[#clip + 1] = { t = tonumber(t), P = P, state = state ~= "" and state or nil, trick = trick ~= "" and trick or nil } end
			end
		end
	end
	if #clip < 2 then return nil end
	return clip, meta
end

function R.MapName() return (game and game.GetMap and game.GetMap()) or "map" end

function R.Save(clip)
	if not (clip and #clip > 1 and file and file.Write) then return nil end
	local stamp = os.date("%Y-%m-%d_%H-%M-%S")
	local name = (R.MapName():gsub("[^%w_%-]", "_")) .. "_" .. stamp .. ".txt"
	file.Write(R.DIR .. name, R.Encode(clip, { map = R.MapName(), date = os.date("%Y-%m-%d %H:%M") }))
	return name
end

-- where saved clips are, as the player would find it on their PC
function R.FolderText()
	local full = util and util.RelativePathToFull and util.RelativePathToFull("data/" .. R.DIR)
	if full and full ~= "" then return (full:gsub("\\", "/")) end
	return "garrysmod/data/" .. R.DIR
end

function R.Saved()
	local files = file and file.Find and file.Find(R.DIR .. "*.txt", "DATA") or {}
	table.sort(files, function(a, b) return a > b end)
	local out = {}
	for i = 1, math.min(#files, R.MAX_LIST) do out[i] = files[i] end
	return out
end

function R.Load(name)
	if type(name) ~= "string" or name:find("..", 1, true) or name:find("[/\\]") then return nil end
	return R.Decode(file.Read(R.DIR .. name, "DATA"))
end

---------------------------------------------------------------------------
-- the viewer
---------------------------------------------------------------------------
local function API() return S.API end

function R.SetHUDHidden(hidden)
    if hidden and not R.hudBackup then
        R.hudBackup={}
        for _,name in ipairs({"cl_drawhud","r_drawvgui"}) do
            local cv=GetConVar(name)
            if cv then R.hudBackup[name]=cv:GetString() RunConsoleCommand(name,"0") end
        end
    elseif not hidden and R.hudBackup then
        for name,value in pairs(R.hudBackup) do RunConsoleCommand(name,value) end
        R.hudBackup=nil
    end
    R.hudHidden=hidden or nil
end
function R.ToggleHUD()
    if R.on or R.loop then R.SetHUDHidden(not R.hudHidden) end
end
function R.StopLoop()
    if R.loop then R.NetworkStop() end
    if R.loop then S.ForgetSkater(R.loop.key) R.loop=nil end
    R.SetHUDHidden(false)
end
function R.Detach()
    local v=R.on
    if not v then return end
    if S.locked then API().Say("This gamemode keeps Skater mode on. Use Sandbox for walking around a replay.",true) return end
    local hidden=R.hudHidden
    -- Give back camera/input and restore the real player, retaining the clip.
    R.on=nil R.cam=nil S.hideSelf=nil
    if S.SetHidden then S.SetHidden("replay",false) end
    UI.Give("replay")
    API().StopSkating()
    if S.phase~="off" then R.on=v R.Close() return end
    v.playing=true v.last=RealTime()
    R.loop=v
    R.SetHUDHidden(hidden)
end
function R.LoopThink(now)
    local v=R.loop
    if not v then return end
    if S.phase=="on" then R.StopLoop() return end
    local duration=R.Duration(v.clip)
    if duration<=0 then R.StopLoop() return end
    local dt=math.max(0,now-(v.last or now)) v.last=now
    v.t=(v.t+dt*R.speeds[v.speed])%duration
    R.Feed(now,v)
end
function R.Open(clip, title)
	if not (clip and #clip > 1) then
		S.API.Say("nothing to replay yet: skate for a few seconds first", true)
		return false
	end
	R.StopLoop()
	if R.on then R.Close() end
	local a = API()
	R.on = { clip = clip, title = title or "Last 15 seconds", t = 0, playing = true, speed = 3, mode = 1, key = S.ClipProxy(LocalPlayer()), prev = 0 }
	R.cam = nil
	S.hideSelf = true
	if S.SetHidden then S.SetHidden("replay", true) end
	UI.Take("replay", { press = R.Press, think = R.Think, close = R.Close }, function(_, _, fov) return R.View(fov) end)
	return true
end

function R.Close()
    if R.on then R.NetworkStop() end
    R.SetHUDHidden(false)
	local v = R.on
	if not v then return end
	R.on, R.cam = nil, nil
	S.ForgetSkater(v.key)
	S.hideSelf = nil
	if S.SetHidden then S.SetHidden("replay", false) end
	UI.Give("replay")
end

function R.Feed(now,v)
	v = v or R.on
	local P, frame = R.PoseAt(v.clip, v.t)
	if not P then return end
	S.remote[v.key] = { snaps = { { t = now - 1, P = P }, { t = now + 1, P = P } }, last = now, state = frame and frame.state }
	v.P, v.frame = P, frame
    R.NetworkFeed(P,frame and frame.state,now)
end

function R.Scrub(dt)
	local v = R.on
	v.t = math.Clamp(v.t + dt, 0, R.Duration(v.clip))
	if R.cam then R.cam.snap = true end
end

function R.Press(btn)
	local v = R.on
    if not v then return end
    if btn==PAD.LB then R.ToggleHUD() return end
    if btn==PAD.RB then R.Detach() return end
	if btn == PAD.A then
		if not v.playing and v.t >= R.Duration(v.clip) then v.t = 0 end
		v.playing = not v.playing
	elseif btn == PAD.B then R.Close()
	elseif btn == PAD.LEFT then R.Scrub(-R.SCRUB)
	elseif btn == PAD.RIGHT then R.Scrub(R.SCRUB)
	elseif btn == PAD.UP then v.speed = math.min(#R.speeds, v.speed + 1)
	elseif btn == PAD.DOWN then v.speed = math.max(1, v.speed - 1)
	elseif btn == PAD.X then
		v.mode = v.mode % #R.modes + 1
		R.cam = R.cam and { pos = R.cam.pos, ang = R.cam.ang, snap = false } or nil
	elseif btn == PAD.Y then
		local name = R.Save(v.clip)
		if name then
			S.API.Say("replay saved: " .. R.FolderText() .. name)
			v.saved, v.savedAt = name, RealTime and RealTime() or 0
		end
	end
end

-- (the shared controller loop feeds the presses; D-pad held repeats)
function R.Think(pad, now, dt)
	local v = R.on
	if not v then return end
	v.pad = pad
	if v.playing then
		v.t = v.t + dt * R.speeds[v.speed]
		if v.t >= R.Duration(v.clip) then v.t = R.Duration(v.clip) v.playing = false end
	end
	R.Feed(now)
	R.CameraThink(dt)
end

---------------------------------------------------------------------------
-- the cameras
---------------------------------------------------------------------------
function R.CameraThink(dt)
	local v = R.on
	local P = v.P
	if not (P and P.HIPS) then return end
	local target = P.HIPS + Vector(0, 0, 10)
	local cam = R.cam or { yaw = 180, pitch = 15, dist = 150 }
	R.cam = cam
	local mode = R.modes[v.mode]
	local pad = v.pad or {}
	if mode == "chase" then
		local moved = cam.last and (target - cam.last) or Vector(0, 0, 0)
		moved.z = 0
		if moved:LengthSqr() > 0.25 then cam.dir = cam.snap and moved:GetNormalized() or LerpVector(0.08, cam.dir or moved:GetNormalized(), moved:GetNormalized()) end
		local dir = (cam.dir or Vector(1, 0, 0)):GetNormalized()
		local want = target - dir * 160 + Vector(0, 0, 64)
		cam.pos = (cam.pos and not cam.snap) and LerpVector(math.min(1, 7 * dt), cam.pos, want) or want
		cam.ang = (target - cam.pos):Angle()
	elseif mode == "orbit" then
		cam.yaw = (cam.yaw or 180) - Dead(pad.rx) * 120 * dt
		cam.pitch = math.Clamp((cam.pitch or 15) + Dead(pad.ry) * 90 * dt, -10, 80)
		cam.dist = math.Clamp((cam.dist or 150) + ((pad.lt or 0) - (pad.rt or 0)) * 200 * dt, 40, 600)
		local ang = Angle(cam.pitch, cam.yaw, 0)
		cam.pos = target - ang:Forward() * cam.dist
		cam.ang = ang
	elseif mode == "free" then
		cam.pos = cam.pos or (target + Vector(-150, 0, 60))
		cam.ang = cam.ang or (target - cam.pos):Angle()
		cam.ang = Angle(math.Clamp(cam.ang.p - Dead(pad.ry) * 100 * dt, -89, 89), cam.ang.y - Dead(pad.rx) * 140 * dt, 0)
		local move = cam.ang:Forward() * Dead(pad.ly) + cam.ang:Right() * Dead(pad.lx) + Vector(0, 0, (pad.rt or 0) - (pad.lt or 0))
		cam.pos = cam.pos + move * 500 * dt
	else
		cam.pos = cam.pos or (target + Vector(-200, 0, 80))
		cam.ang = (target - cam.pos):Angle()
	end
	cam.last, cam.snap = target, false
end

function R.View(fov)
	local cam = R.cam
	if not (cam and cam.pos and cam.ang) then return nil end
	return { origin = cam.pos, angles = cam.ang, fov = fov }
end

---------------------------------------------------------------------------
-- on screen
---------------------------------------------------------------------------
function R.Paint(w, h)
    if R.hudHidden then return end
	local v = R.on
	if not v then return end
	if not R.fonts then
		R.fonts = true
		surface.CreateFont("skategm_replay_mid", { font = "Roboto", size = math.max(16, math.floor(h * 0.03)), weight = 700, antialias = true })
		surface.CreateFont("skategm_replay_small", { font = "Roboto", size = math.max(12, math.floor(h * 0.02)), weight = 600, antialias = true })
	end
	local dur = R.Duration(v.clip)
	local x0, x1, y = w * 0.2, w * 0.8, h * 0.9
	surface.SetDrawColor(0, 0, 0, 150)
	surface.DrawRect(x0, y, x1 - x0, 6)
	surface.SetDrawColor(255, 200, 70, 255)
	surface.DrawRect(x0, y, (x1 - x0) * (dur > 0 and v.t / dur or 0), 6)
	draw.SimpleText(string.format("%s   %.1f / %.1f s   %sx   %s%s", v.title, v.t, dur, tostring(R.speeds[v.speed]), R.MODE_NAMES[R.modes[v.mode]], v.playing and "" or "   (paused)"),
		"skategm_replay_mid", w / 2, y - h * 0.045, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
	UI.pad.Legend({
		{ keys = { "A" }, text = v.playing and "Pause" or "Play" },
		{ keys = { "LEFT", "RIGHT" }, text = "Scrub" },
		{ keys = { "UP", "DOWN" }, text = "Speed" },
		{ keys = { "X" }, text = "Camera" },
		{ keys = { "Y" }, text = "Save" },
		{ keys = { "B" }, text = "Back" },
        { keys = { "LB" }, text = "HUD (H)" },
        { keys = { "RB" }, text = "Walk + loop (G)" },
	}, w, h, { w / 2 - w * 0.2, y + h * 0.02 })
	if v.savedAt and (RealTime and RealTime() or 0) - v.savedAt < 6 then
		draw.SimpleText("Saved: " .. v.saved, "skategm_replay_mid", w / 2, h * 0.16, Color(120, 220, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
		draw.SimpleText("in " .. R.FolderText() .. "  -  " .. SKATEGM_UI.pad.T("watch it again from LB + RB > Replays"), "skategm_replay_small", w / 2, h * 0.16 + h * 0.035, Color(220, 220, 220), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
	end
	local trick = v.frame and v.frame.trick
	if trick then draw.SimpleText(trick, "skategm_replay_mid", w / 2, h * 0.08, Color(255, 200, 70), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP) end
end

hook.Add("HUDPaint", "skategm_replay", function() R.Paint(ScrW(), ScrH()) end)

---------------------------------------------------------------------------
-- the list (LB + RB), and the console
---------------------------------------------------------------------------
function R.Screen()
	return { title = "Replays", rows = function()
		local rows = { { label = "Last 15 seconds", sub = "watch what you just did", run = function() R.Open(S.RecentClip(), "Last 15 seconds") end } }
		for _, name in ipairs(R.Saved()) do
			rows[#rows + 1] = { label = name:gsub("%.txt$", ""), sub = "saved in " .. R.FolderText(), run = function()
				local clip = R.Load(name)
				if not clip then return S.API.Say("that replay couldn't be read", true) end
				R.Open(clip, name:gsub("%.txt$", ""))
			end }
		end
		return rows
	end }
end

local function Register()
	local menu = SKATEGM_MODES and SKATEGM_MODES.menu
	if not menu then return false end
	menu.SCREENS = menu.SCREENS or {}
	menu.SCREENS.replays = R.Screen
	return true
end
if not Register() and hook then hook.Add("Sk8ModesReady", "skategm_replay", Register) end

concommand.Add("skategm_replay", function(_, _, args)
	if args[1] and args[1] ~= "" then
		local clip = R.Load(args[1]) or R.Load(args[1] .. ".txt")
		if not clip then return S.API.Say("no saved replay called " .. args[1], true) end
		return R.Open(clip, args[1])
	end
	if R.on then R.Close() else R.Open(S.RecentClip(), "Last 15 seconds") end
end, nil, "Replay your last 15 seconds (or a saved replay: skategm_replay <name>)")

local keyWas={}
hook.Add("Think","skategm_replay_loop",function()
    R.LoopThink(RealTime())
    for _,key in ipairs({KEY_H,KEY_G}) do
        local down=input.IsKeyDown(key)
        local allowed=not gui.IsGameUIVisible() and not vgui.CursorVisible() and (not system.HasFocus or system.HasFocus())
        if down and not keyWas[key] and allowed then
            if key==KEY_H then R.ToggleHUD() elseif R.on then R.Detach() end
        end
        keyWas[key]=down
    end
end)
hook.Add("ShutDown","skategm_replay_restore_hud",function() R.SetHUDHidden(false) end)
concommand.Add("skategm_replay_hud",R.ToggleHUD)
concommand.Add("skategm_replay_walk",R.Detach)
concommand.Add("skategm_replay_stop_loop",R.StopLoop)

-- Broadcast the displayed pose, so pauses, scrubbing and loop timing agree.
local remoteReplays={}
local writer={float=net.WriteFloat,int=function(v) net.WriteInt(v,16) end,u8=function(v) net.WriteUInt(v,8) end}
local reader={float=net.ReadFloat,int=function() return net.ReadInt(16) end,u8=function() return net.ReadUInt(8) end}
function R.NetworkFeed(P,state,now)
    if now<(R.nextNetwork or 0) then return end
    R.nextNetwork=now+1/20 R.networkActive=true
    net.Start("skategm_replay_pose",true) net.WriteBool(true)
    S.Encode(P,writer,state) net.SendToServer()
end
function R.NetworkStop()
    if not R.networkActive then return end
    R.networkActive=nil R.nextNetwork=nil
    net.Start("skategm_replay_pose") net.WriteBool(false) net.SendToServer()
end
local function forget(ply)
    local r=remoteReplays[ply]
    if r then S.ForgetSkater(r.key) remoteReplays[ply]=nil end
end
net.Receive("skategm_replay_pose",function()
    local ply=net.ReadEntity()
    local on=net.ReadBool()
    if not on then forget(ply) return end
    local P,state=S.Decode(reader)
    if not IsValid(ply) or ply==LocalPlayer() then return end
    local now=RealTime()
    local record=remoteReplays[ply]
    if not record then record={key=S.ClipProxy(ply)} remoteReplays[ply]=record end
    record.last=now
    local r=S.remote[record.key] or {snaps={}}
    local latest=r.snaps[#r.snaps]
    if latest and (P.HIPS-latest.P.HIPS):LengthSqr()>256^2 then r.snaps={} end
    r.snaps[#r.snaps+1]={t=now,P=P}
    while #r.snaps>4 do table.remove(r.snaps,1) end
    r.last=now r.state=state S.remote[record.key]=r
end)
hook.Add("Think","skategm_remote_replay_cleanup",function()
    local now=RealTime()
    for ply,r in pairs(remoteReplays) do
        if not IsValid(ply) or now-r.last>2 then forget(ply) end
    end
end)
