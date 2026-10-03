dofile("gmock.lua")
local function check(label, ok) print(string.format("%-72s %s", label, ok and "OK" or "<-- WRONG")) end
local files = {}
file = {
	CreateDir = function() end,
	Write = function(p, d) files[p] = d end,
	Read = function(p) return files[p] end,
	Find = function(pat)
		local out = {}
		for p in pairs(files) do local name = p:match("^skategm/replays/(.+%.txt)$") if name then out[#out + 1] = name end end
		return out
	end,
}
local hooks, cmds = {}, {}
hook = { Add = function(n, id, f) hooks[n .. "/" .. id] = f end }
concommand = { Add = function(n, f) cmds[n] = f end }
game = { GetMap = function() return "tl_skatepark" end }
function LerpVector(f, a, b) return a + (b - a) * f end
function IsValid(x) return x ~= nil end
local ME = {}
function LocalPlayer() return ME end
local said = {}
local api = { frozen = false, blocked = false, pad = { buttons = 0 } }
SKATEGM_MODES = { menu = { open = false, Close = function(self) end } }
SkateGM = {
	phase = "on", remote = {}, BONES = { "TRAJECTORY", "HIPS", "SPINE", "HEAD" },
	ClipProxy = function(ply) return { ghost = true, of = ply } end,
	ForgetSkater = function(key) SkateGM.remote[key] = nil SkateGM.forgot = key end,
	API = {
		Freeze = function(on) api.frozen = on end,
		BlockInput = function(on) api.blocked = on end,
		SetView = function(fn) api.view = fn end,
		Pad = function() return api.pad end,
		Say = function(t) said[#said + 1] = t end,
	},
}
local S = SkateGM
local clock = 0
RealTime = function() return clock end
function ScrW() return 1600 end
function ScrH() return 900 end
dofile("../../addon/skategm/lua/skategm/cl_replay.lua")
local UI = SKATEGM_UI
local function Think(t, dt) clock = t UI.Think(t, dt) end
local R = S.replay

local clip = {}
for i = 0, 30 do clip[#clip + 1] = { t = i * 0.05, P = { HIPS = Vector(i * 10, 0, 40), HEAD = Vector(i * 10, 0, 70) }, state = i < 20 and "PhysicsGround" or "PhysicsAir", trick = i == 25 and "Kickflip" or nil } end
local P = R.PoseAt(clip, 0.125)
check("the pose between two frames is blended", math.abs(P.HIPS.x - 25) < 1e-6)
check("before the start / after the end: the first / last frame", R.PoseAt(clip, -1).HIPS.x == 0 and R.PoseAt(clip, 99).HIPS.x == 300)

check("nothing recorded yet: says so", R.Open(nil) == false and said[#said]:find("nothing to replay"))
check("open: the clip plays back", R.Open(clip, "Last 15 seconds") and R.on and R.on.playing)
check("... my skater waits, the pad drives the viewer, my live skater is hidden", api.frozen and api.blocked and S.hideSelf and UI.IsOpen("replay"))
local think = hooks["Think/skategm_replay"]
Think(1, 0.5)
check("playing: time runs at full speed, a ghost of me in the pose", math.abs(R.on.t - 0.5) < 1e-6 and S.remote[R.on.key] ~= nil and math.abs(R.on.P.HIPS.x - 100) < 1e-6)
check("... and a camera on it", api.view and api.view(nil, nil, 90) and api.view(nil, nil, 90).origin ~= nil)
local function press(b) api.pad = { buttons = b } Think(2, 0) api.pad = { buttons = 0 } Think(2.01, 0) end
press(R.PAD.A)
check("A pauses", not R.on.playing)
Think(3, 1)
check("paused: time stands still", math.abs(R.on.t - 0.5) < 1e-6)
press(R.PAD.RIGHT)
check("D-pad right scrubs forward a second (not past the end)", math.abs(R.on.t - R.Duration(clip)) < 1e-6)
press(R.PAD.LEFT)
check("D-pad left scrubs back", math.abs(R.on.t - 0.5) < 1e-6)
press(R.PAD.DOWN) press(R.PAD.DOWN)
check("D-pad down: slow motion, down to a quarter", R.speeds[R.on.speed] == 0.25)
press(R.PAD.A)
Think(4, 1)
check("... a second of play moves a quarter second", math.abs(R.on.t - 0.75) < 1e-6)
for _, mode in ipairs({ "orbit", "free", "tripod", "chase" }) do
	press(R.PAD.X)
	Think(5, 0.016)
	check("X: camera " .. mode, R.modes[R.on.mode] == mode and R.cam and R.cam.pos ~= nil)
end
R.on.t = 1.26
Think(6, 0)
check("the trick name shows at its moment", R.on.frame and R.on.frame.trick == "Kickflip")
press(R.PAD.Y)
local saved = R.Saved()
check("Y saves it to data/skategm/replays", #saved == 1 and saved[1]:find("^tl_skatepark_") and said[#said]:find("replay saved"))
check("... and says where on the PC", said[#said]:find("garrysmod/data/skategm/replays/", 1, true) and R.on.savedAt ~= nil)
local loaded, meta = R.Load(saved[1])
check("... and it loads back the same", loaded and #loaded == #clip and math.abs(loaded[11].P.HIPS.x - 100) < 0.06 and loaded[26].trick == "Kickflip" and meta.map == "tl_skatepark")
check("saved files can't be read from outside the folder", R.Load("../../cfg/config.cfg") == nil)
local key = R.on.key
press(R.PAD.B)
check("B: back to skating, everything as it was", R.on == nil and not api.frozen and not api.blocked and not S.hideSelf and api.view == nil and S.forgot == key and not UI.Busy())
local screen = SKATEGM_MODES.menu.SCREENS.replays()
local rows = screen.rows()
check("the Replays list: the last 15 seconds, then saved ones", rows[1].label == "Last 15 seconds" and #rows == 2)
check("... each saying which folder it's in", rows[2].sub:find("skategm/replays", 1, true) ~= nil)
S.RecentClip = function() return clip end
rows[2].run()
check("picking a saved one plays it", R.on and #R.on.clip == #clip)
S.phase = "off"
api.pad = nil
Think(7, 0)
check("leaving Skater mode closes the viewer", R.on == nil)
