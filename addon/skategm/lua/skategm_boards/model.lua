-- A board drawn from a model (.mdl) instead of SkateGM's own geometry: pick a
-- preset or any model path (console: skategm_board_model_path), its skin, size,
-- height and turn. The model sits on the board's frame: its +Y along the
-- board, +Z up, its origin on the ground under the wheels.
local MODELS = {
	-- (addons/pf_skatepark_skateboard: under skategm_pfsk/, not pf_skatepark/, so the
	-- pf_skatepark map's own copy of it can't take its place)
	{ "PF Skatepark skateboard", "models/skategm_pfsk/skateboard/skateboard.mdl" },
	{ "Custom (skategm_board_model_path)" },
}
local CUSTOM = #MODELS

-- skin names for models that have them (in the model's skin order)
local SKIN_NAMES = {
	["models/skategm_pfsk/skateboard/skateboard.mdl"] = { "Plain", "Aries", "Ballboy", "Bonfire", "Buam", "Butterfly", "Cash", "Checker", "Chief", "Cloudy",
		"Collage", "Crab alien", "Dead knife", "Defuse", "Elephant", "Fracture", "GMod", "Goat", "Graffiti", "Inner world", "Jack-o'-lantern", "Jinx",
		"Knot", "Living tree", "Maze", "Mosaic", "Mountain", "No scope", "Reaper", "Rexer", "Smile", "Wire" },
}
local TURNS = { { "Along the board", 0 }, { "Turned 90 degrees", 90 }, { "Reversed", 180 }, { "Turned 270 degrees", 270 } }
local WHEEL_R = 1.1 -- the axles are this far above the ground

local MODEL = BOARD.RegisterType({
	id = "model", title = "Model", order = 2,
	fields = {
		{ key = "preset", kind = "choice", convar = "skategm_board_model_preset", choices = MODELS, default = 1, label = "Model", refresh = true },
		{ key = "path", kind = "model", convar = "skategm_board_model_path", default = MODELS[1][2], label = "Model path", hidden = true },
		{ key = "skin", kind = "number", convar = "skategm_board_model_skin", min = 0, max = 63, default = 0, label = "Skin", hidden = true },
		{ key = "scale", kind = "number", convar = "skategm_board_model_scale", min = 0.5, max = 1.5, default = 1, label = "Size" },
		{ key = "height", kind = "number", convar = "skategm_board_model_height", min = -3, max = 3, default = 0, decimals = 1, label = "Height" },
		{ key = "turn", kind = "choice", convar = "skategm_board_model_turn", choices = TURNS, default = 1, label = "Turn" },
		{ key = "trucks", kind = "bool", convar = "skategm_board_model_trucks", default = false, label = "SkateGM's trucks and wheels too" },
	},
})

function MODEL.Path(opts)
	local i = opts and opts.preset or 1
	if i == CUSTOM then return BOARD.ValidModel(opts.path) and opts.path or nil end
	return MODELS[i] and MODELS[i][2] or MODELS[1][2]
end

if not CLIENT then return end

MODEL.ents = MODEL.ents or {}
MODEL.skinCount = MODEL.skinCount or {}

local function Exists(path) return path and file.Exists(path, "GAME") end

-- one model per player (the settings preview shares the local player's)
function MODEL.Ent(ply, path)
	local e = MODEL.ents[ply]
	if IsValid(e) and e.Sk8Path == path then return e end
	if IsValid(e) then e:Remove() end
	MODEL.ents[ply] = nil
	if not Exists(path) then return nil end
	util.PrecacheModel(path)
	e = ClientsideModel(path, RENDERGROUP_OPAQUE)
	if not IsValid(e) then return nil end
	e:SetNoDraw(true)
	e:DrawShadow(false)
	e.Sk8Path = path
	MODEL.ents[ply] = e
	MODEL.skinCount[path] = e:SkinCount()
	return e
end

function MODEL.SkinNames(path)
	local names = SKIN_NAMES[path]
	local count = MODEL.skinCount[path]
	if not count and Exists(path) then
		local e = ClientsideModel(path, RENDERGROUP_OPAQUE)
		if IsValid(e) then count = e:SkinCount() e:Remove() end
		MODEL.skinCount[path] = count
	end
	local out = {}
	for i = 1, math.max(count or 1, 1) do out[i] = names and names[i] or ("Skin " .. i) end
	return out
end

local function MyPath()
	local cvPreset, cvPath = GetConVar("skategm_board_model_preset"), GetConVar("skategm_board_model_path")
	return MODEL.Path({ preset = cvPreset and cvPreset:GetInt() or 1, path = cvPath and cvPath:GetString() })
end

-- the skin as a named choice (the field itself is a number, hidden); read
-- each time, so it follows the model as soon as that changes
function MODEL.rows(List)
	local function skin()
		local cv = GetConVar("skategm_board_model_skin")
		return math.floor(cv and cv:GetFloat() or 0)
	end
	return { { label = "Skin",
		value = function()
			local path = MyPath()
			if not Exists(path) then return "model not found: " .. tostring(path) end
			local names = MODEL.SkinNames(path)
			return names[math.Clamp(skin() + 1, 1, #names)]
		end,
		change = function(dir)
			local path = MyPath()
			if not Exists(path) then return end
			local n = #MODEL.SkinNames(path)
			RunConsoleCommand("skategm_board_model_skin", tostring((math.Clamp(skin(), 0, n - 1) + dir) % n))
		end } }
end

function MODEL.draw(ctx)
	local opts, look = ctx.opts or {}, ctx.look or {}
	local path = MODEL.Path(opts)
	local e = path and MODEL.Ent(ctx.ply, path)
	if not e then return false end
	local B = BOARD.client.BoardFrame(ctx.P)
	if not B then return false end
	local scale = opts.scale or 1
	if e.Sk8Scale ~= scale then e:SetModelScale(scale, 0) e.Sk8Scale = scale end
	local skin = math.floor(opts.skin or 0)
	if e:GetSkin() ~= skin then e:SetSkin(skin) end
	-- model +Y along the board: an angle whose forward is the board's right
	-- has the board's forward as its left (+Y)
	local ang = B.right:AngleEx(B.up)
	local turn = TURNS[opts.turn or 1]
	if turn and turn[2] ~= 0 then ang:RotateAroundAxis(B.up, turn[2]) end
	local pos = B.centre + B.up * ((opts.height or 0) - WHEEL_R)
	e:SetPos(pos)
	e:SetAngles(ang)
	e:SetupBones()
	-- (only used where engine lighting is off, as in the settings preview)
	local c = render.GetLightColor(pos + B.up * 2)
	local l = math.Clamp(0.3 + (c.x + c.y + c.z) / 3 * 1.4, 0.45, 1.1)
	render.ResetModelLighting(l, l, l)
	e:DrawModel()
	if opts.trucks or ctx.rocket then
		ctx.DrawBoard(ctx.P, { deck = false, trucks = opts.trucks == true and not ctx.hover, rocket = ctx.rocket, wheel = look.wheels, graphic = ctx.graphic })
	end
	return true
end

hook.Add("Think", "skategm_board_model", function()
	if RealTime() < (MODEL.nextSweep or 0) then return end
	MODEL.nextSweep = RealTime() + 5
	for ply, e in pairs(MODEL.ents) do
		if not IsValid(ply) then
			if IsValid(e) then e:Remove() end
			MODEL.ents[ply] = nil
		end
	end
end)
