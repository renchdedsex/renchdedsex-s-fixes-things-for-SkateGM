local APP = SKATEGM_APPEARANCE
APP.FILE = "skategm/character.json"
APP.ZCITY_DIR = "zcity/appearances/"

---------------------------------------------------------------------------
-- my appearance: kept in data/skategm/character.json, sent to the server
---------------------------------------------------------------------------
local function Default() return { on = false, model = "Male 07", clothes = "normal", face = "Default", bg = {}, acc = {} } end

function APP.Load()
	local t = file.Exists(APP.FILE, "DATA") and util.JSONToTable(file.Read(APP.FILE, "DATA") or "") or nil
	local d = Default()
	if type(t) == "table" then
		d.on = t.on == true
		if type(t.model) == "string" then d.model = t.model end
		if type(t.clothes) == "string" then d.clothes = t.clothes end
		for _, slot in ipairs(APP.EXTRA_SLOTS) do if type(t[slot]) == "string" then d[slot] = t[slot] end end
		if type(t.face) == "string" then d.face = t.face end
		if type(t.bg) == "table" then d.bg = t.bg end
		if type(t.acc) == "table" then d.acc = t.acc end
	end
	APP.my = d
	return d
end

function APP.Save()
	file.CreateDir("skategm")
	file.Write(APP.FILE, util.TableToJSON(APP.my, true))
end

function APP.Send()
	if not APP.my then APP.Load() end
	net.Start(APP.NET)
	net.WriteString(util.TableToJSON(APP.my))
	net.SendToServer()
end

-- saved, sent shortly, and the preview dressed again
function APP.Changed()
	APP.Save()
	timer.Create("skategm_appearance_send", 0.5, 1, APP.Send)
	local p, m = APP.preview, APP.MyModel()
	if p and IsValid(p.ent) and m and p.mdl == m.mdl then APP.Dress(p.ent, APP.my, m) end
end

function APP.Set(key, value)
	if not APP.my then APP.Load() end
	APP.my[key] = value
	APP.Changed()
end

-- my model (the first installed one if mine isn't)
function APP.MyModel()
	if not APP.my then APP.Load() end
	return APP.Model(APP.my.model) or APP.Models()[1]
end

function APP.SetModel(name)
	local m = APP.Model(name)
	if not m then return end
	APP.my.model = m.name
	if not APP.ClothesPath(m.sex, APP.my.clothes) then APP.my.clothes = "normal" end
	for _, slot in ipairs(APP.EXTRA_SLOTS) do
		if APP.my[slot] and not APP.ClothesPath(m.sex, APP.my[slot]) then APP.my[slot] = nil end
	end
	APP.my.face = "Default"
	APP.my.bg = {}
	APP.Changed()
end

-- one accessory per placement
function APP.MyAccessory(placement)
	for _, id in ipairs(APP.my.acc or {}) do
		local a = APP.Accessory(id)
		if a and (a.placement or "head") == placement then return id end
	end
end

function APP.SetAccessory(placement, id)
	local out = {}
	for _, cur in ipairs(APP.my.acc or {}) do
		local a = APP.Accessory(cur)
		if a and (a.placement or "head") ~= placement then out[#out + 1] = cur end
	end
	if id then out[#out + 1] = id end
	APP.Set("acc", out)
end

---------------------------------------------------------------------------
-- the preview: a model dressed as my appearance is set right now
---------------------------------------------------------------------------
function APP.Preview()
	local m = APP.MyModel()
	if not m then return nil end
	local p = APP.preview
	if p and IsValid(p.ent) and p.mdl == m.mdl then return p.ent, m end
	if p and IsValid(p.ent) and p.mdl ~= m.mdl then p.ent:Remove() end
	local e = ClientsideModel(m.mdl, RENDERGROUP_OPAQUE)
	if not IsValid(e) then return nil end
	e:SetNoDraw(true)
	local seq = e:LookupSequence("idle_all_01")
	if seq and seq >= 0 then e:ResetSequence(seq) end
	e.GetPlayerColor = function() return IsValid(LocalPlayer()) and LocalPlayer():GetPlayerColor() or Vector(1, 1, 1) end
	APP.Dress(e, APP.my, m)
	APP.preview = { ent = e, mdl = m.mdl }
	return e, m
end

-- the bodygroups a model has with something to choose: { id, name, subs }
function APP.BodygroupsOf(ent)
	local out = {}
	for _, bg in ipairs(IsValid(ent) and ent:GetBodyGroups() or {}) do
		if bg.num and bg.num > 1 then out[#out + 1] = { id = bg.id, name = bg.name, subs = bg.submodels, num = bg.num } end
	end
	return out
end

---------------------------------------------------------------------------
-- accessories: drawn on the player, or on their skater while skating
---------------------------------------------------------------------------
APP.worn = APP.worn or setmetatable({}, { __mode = "k" }) -- target -> { [id] = model }
local lists = {}

local function ListOf(ply)
	local s = ply:GetNW2String("skategm_acc", "")
	local l = lists[s]
	if not l then
		l = {}
		for id in string.gmatch(s, "[^,]+") do l[#l + 1] = id end
		lists[s] = l
	end
	return l, s
end

local function Drop(target, keep)
	local set = APP.worn[target]
	if not set then return end
	for id, model in pairs(set) do
		if not (keep and keep[id]) then
			if IsValid(model) then model:Remove() end
			set[id] = nil
		end
	end
end

local function Worn(target, id, a, fem)
	APP.worn[target] = APP.worn[target] or {}
	local set = APP.worn[target]
	local mdl = fem and a.femmodel or a.model
	local model = set[id]
	if IsValid(model) and model.Sk8Mdl == mdl then return model end
	if IsValid(model) then model:Remove() end
	if not APP.Installed(mdl) then return nil end
	model = ClientsideModel(mdl, RENDERGROUP_OPAQUE)
	if not IsValid(model) then return nil end
	model.Sk8Mdl = mdl
	model:SetNoDraw(true)
	model:DrawShadow(false)
	local p = a[fem and "fempos" or "malepos"] or a.malepos
	model:SetModelScale(p and p[3] or 1, 0)
	model:SetBodyGroups(a.bodygroups or "")
	if a.SubMat then model:SetSubMaterial(0, a.SubMat) end
	if a.bonemerge then
		model:SetParent(target)
		model:AddEffects(EF_BONEMERGE)
	end
	-- (some fit each body by a flex named after its model)
	local flex = model:GetFlexIDByName(string.GetFileFromFilename(string.StripExtension(target:GetModel() or "")))
	if flex then model:SetFlexWeight(flex, 1) end
	set[id] = model
	return model
end

function APP.DrawAccessories(target, owner, list)
	if not (IsValid(target) and list) then return end
	local keep = {}
	for _, id in ipairs(list) do keep[id] = true end
	Drop(target, keep)
	if #list == 0 then return end
	local fem = APP.IsFemale(target)
	for _, id in ipairs(list) do
		local a = APP.Accessory(id)
		local model = a and Worn(target, id, a, fem)
		if model then
			local skin = isfunction(a.skin) and a.skin(target) or a.skin or 0
			if model:GetSkin() ~= skin then model:SetSkin(skin) end
			local drawn = true
			if not a.bonemerge then
				local bone = target:LookupBone(a.bone or "ValveBiped.Bip01_Head1")
				local matrix = bone and target:GetBoneMatrix(bone)
				local p = a[fem and "fempos" or "malepos"] or a.malepos
				if matrix and p and p[1] and p[2] then
					local pos, ang = LocalToWorld(p[1], p[2], matrix:GetTranslation(), matrix:GetAngles())
					model:SetPos(pos)
					model:SetAngles(ang)
					model:SetRenderOrigin(pos)
					model:SetRenderAngles(ang)
					model:SetupBones()
				else
					drawn = false
				end
			end
			if drawn then
				local c = a.bSetColor and (a.vecColorOveride or (IsValid(owner) and owner.GetPlayerColor and owner:GetPlayerColor()) or Vector(1, 1, 1))
				if c then render.SetColorModulation(c[1], c[2], c[3]) end
				model:DrawModel()
				if c then render.SetColorModulation(1, 1, 1) end
			end
		end
	end
end

-- on the skater (SkateGM draws it, the player itself is hidden)
hook.Add("SkateGMDrawSkater", "skategm_appearance", function(e, ply)
	if not IsValid(ply) then return end
	APP.DrawAccessories(e, ply, (ListOf(ply)))
end)

-- on the player, when not skating (an accessory merged onto the player's
-- bones draws the player again, which calls this hook again: once is enough)
local drawing = false
hook.Add("PostPlayerDraw", "skategm_appearance", function(ply)
	if drawing or not ply:Alive() then return end
	drawing = true
	local ok, err = pcall(APP.DrawAccessories, ply, ply, (ListOf(ply)))
	drawing = false
	if not ok then ErrorNoHalt("[SkateGM] accessories: " .. tostring(err) .. "\n") end
end)

timer.Create("skategm_appearance_sweep", 5, 0, function()
	for target in pairs(APP.worn) do
		if not IsValid(target) then
			for _, model in pairs(APP.worn[target] or {}) do if IsValid(model) then model:Remove() end end
			APP.worn[target] = nil
		end
	end
end)

---------------------------------------------------------------------------
-- Z-City's saved appearances (data/zcity/appearances/*.json) and its
-- presets (data/zcity/appearances/presets/*.json, listed as "presets/<name>")
---------------------------------------------------------------------------
function APP.ZCityFiles()
	local list = file.Find(APP.ZCITY_DIR .. "*.json", "DATA") or {}
	table.sort(list)
	local presets = file.Find(APP.ZCITY_DIR .. "presets/*.json", "DATA") or {}
	table.sort(presets)
	for _, f in ipairs(presets) do list[#list + 1] = "presets/" .. f end
	return list
end

function APP.ImportZCity(name)
	local raw = file.Read(APP.ZCITY_DIR .. name, "DATA")
	local ok, z = pcall(util.JSONToTable, raw or "")
	local t = ok and APP.FromZCity(z)
	if not t then return false, "can't read " .. name end
	local m = APP.Model(t.model)
	if not m then return false, tostring(t.model) .. " isn't installed" end
	APP.my = { on = true, model = m.name, clothes = t.clothes or "normal", pants = t.pants, boots = t.boots, face = t.face or "Default", bg = {}, acc = t.acc }
	-- Z-City names its bodygroup choices: find their submodels on the model
	if t.zbg then
		local e = ClientsideModel(m.mdl, RENDERGROUP_OPAQUE)
		if IsValid(e) then
			for bgName, choice in pairs(t.zbg) do
				local entry = hg.Appearance.Bodygroups[bgName] and hg.Appearance.Bodygroups[bgName][m.sex] and hg.Appearance.Bodygroups[bgName][m.sex][choice]
				local id = entry and e:FindBodygroupByName(bgName)
				if id and id >= 0 then
					for _, bg in ipairs(e:GetBodyGroups()) do
						if bg.id == id then
							for i = 0, bg.num - 1 do if bg.submodels[i] == entry[1] then APP.my.bg[bgName] = i end end
						end
					end
				end
			end
			e:Remove()
		end
	end
	if type(z.AColor) == "table" and z.AColor.r then
		RunConsoleCommand("cl_playercolor", string.format("%.3f %.3f %.3f", z.AColor.r / 255, z.AColor.g / 255, z.AColor.b / 255))
	end
	APP.Changed()
	return true
end

concommand.Add("skategm_character", function(_, _, args)
	if not APP.my then APP.Load() end
	local v = args[1]
	if v == "1" or v == "0" then APP.Set("on", v == "1") end
	print("[SkateGM] Z-City character: " .. (APP.my.on and "on" or "off") .. ", " .. tostring(APP.my.model) .. (APP.loadErr and (" (data error: " .. APP.loadErr .. ")") or ""))
end, nil, "Wear your Z-City character: 1 on, 0 off")

APP.Load()
hook.Add("InitPostEntity", "skategm_appearance_send", function() timer.Simple(4, APP.Send) end)
if IsValid(LocalPlayer()) then timer.Simple(1, APP.Send) end
