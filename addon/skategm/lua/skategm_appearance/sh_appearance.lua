---------------------------------------------------------------------------
-- Character appearance from Z-City (homigrad new_appearance): its models,
-- clothes, faces, bodygroups and accessories, worn while skating.
--
-- Z-City's own data files are in zcity/ unchanged; they expect Z-City's
-- `hg` table, so a stand-in is set up first (its point shop only records
-- items: everything is free here). Only what is installed is offered.
--
-- An appearance: { on = bool, model = "Male 07", clothes = "normal",
--   face = "Default", bg = { [bodygroup name] = submodel }, acc = { ids } }
---------------------------------------------------------------------------
SKATEGM_APPEARANCE = SKATEGM_APPEARANCE or {}
local APP = SKATEGM_APPEARANCE
APP.NET = "skategm_appearance"
APP.MAX_JSON = 4096
APP.MAX_BODYGROUPS = 32
APP.MAX_ACCESSORIES = 8
APP.PLACEMENTS = { "head", "face", "ears", "torso", "spine" }
APP.PLACEMENT_NAMES = { head = "Head", face = "Face", ears = "Ears", torso = "Torso", spine = "Back" }
-- material slots besides the top ("main", which is `clothes`): each takes a
-- texture from the same clothes list, or keeps the model's own when unset
APP.EXTRA_SLOTS = { "pants", "boots" }

hg = hg or {}
hg.Appearance = hg.Appearance or {}
hg.PointShop = hg.PointShop or {}
hg.PointShop.Items = hg.PointShop.Items or {}
if not hg.PointShop.CreateItem then
	function hg.PointShop:CreateItem(uid, name, model, bodygroups, skin, vpos, price, donate, submats)
		self.Items[uid] = { ID = uid, NAME = name, MDL = model, BODYGROUPS = bodygroups, SKIN = skin, VPOS = vpos, PRICE = price, ISDONATE = donate, SUBMATERIALS = submats }
	end
end

local DATA = { "skategm_appearance/zcity/sh_names.lua", "skategm_appearance/zcity/sh_shared.lua", "skategm_appearance/zcity/sh_accessories.lua" }
APP.loadErr = nil
for _, f in ipairs(DATA) do
	if SERVER then AddCSLuaFile(f) end
	local ok, err = pcall(include, f)
	if not ok then
		APP.loadErr = APP.loadErr or (f .. ": " .. tostring(err))
		ErrorNoHalt("[SkateGM] appearance data: " .. tostring(err) .. "\n")
	end
end

-- the custom models, clothes and faces are added from game hooks; the
-- bodygroup names from the point shop's
APP.ready = false
local function Ready()
	if APP.ready then return end
	APP.ready = true
	hook.Run("ZPointshopLoaded")
	APP.cache = {}
end
hook.Add("InitPostEntity", "skategm_appearance", function() timer.Simple(0, Ready) end)
if game.GetWorld and IsValid(game.GetWorld()) and (CLIENT and IsValid(LocalPlayer()) or SERVER and #player.GetAll() > 0) then timer.Simple(0, Ready) end

APP.cache = APP.cache or {}
local function Cached(key, build)
	if not APP.ready then return build() end
	local v = APP.cache[key]
	if v == nil then v = build() APP.cache[key] = v end
	return v
end

local function Installed(path) return type(path) == "string" and path ~= "" and file.Exists(path, "GAME") end
APP.Installed = Installed

local function MaterialOk(path)
	if path == "" then return true end
	if not CLIENT then return true end
	local m = Material(path)
	return m and not m:IsError()
end

-- installed models: { name, mdl, sex (1 male, 2 female), slots }
function APP.Models()
	return Cached("models", function()
		local out = {}
		local pm = hg.Appearance.PlayerModels or {}
		for sex = 1, 2 do
			for name, t in pairs(pm[sex] or {}) do
				if type(t) == "table" and Installed(t.mdl) then out[#out + 1] = { name = name, mdl = t.mdl, sex = t.sex and 2 or 1, slots = t.submatSlots or {} } end
			end
		end
		table.sort(out, function(a, b) if a.sex ~= b.sex then return a.sex < b.sex end return a.name < b.name end)
		return out
	end)
end

function APP.Model(name)
	for _, m in ipairs(APP.Models()) do if m.name == name then return m end end
end

function APP.ModelByPath(path)
	path = string.lower(path or "")
	for _, m in ipairs(APP.Models()) do if string.lower(m.mdl) == path then return m end end
end

-- clothes for a sex: { id, path }, "normal" first
function APP.Clothes(sex)
	return Cached("clothes" .. sex, function()
		local out = {}
		for id, path in pairs((hg.Appearance.Clothes or {})[sex] or {}) do
			if type(path) == "string" and MaterialOk(path) then out[#out + 1] = { id = id, path = path } end
		end
		table.sort(out, function(a, b)
			if (a.id == "normal") ~= (b.id == "normal") then return a.id == "normal" end
			return a.id < b.id
		end)
		return out
	end)
end

function APP.ClothesPath(sex, id)
	local t = (hg.Appearance.Clothes or {})[sex]
	return t and t[id]
end

function APP.ClothesName(id)
	return (string.NiceName and string.NiceName(id:gsub("_cl$", " (colourable)"))) or id
end

-- the face names a model can take (from its materials), "Default" first
function APP.Faces(mats)
	local seen, out = {}, {}
	local slots = hg.Appearance.FacemapsSlots or {}
	for _, m in ipairs(mats or {}) do
		for name, path in pairs(slots[m] or {}) do
			if not seen[name] and MaterialOk(path) then seen[name] = true out[#out + 1] = name end
		end
	end
	table.sort(out, function(a, b)
		if (a == "Default") ~= (b == "Default") then return a == "Default" end
		local na, nb = tonumber(a:match("(%d+)")), tonumber(b:match("(%d+)"))
		if na and nb and na ~= nb then return na < nb end
		return a < b
	end)
	if not seen.Default then table.insert(out, 1, "Default") end
	return out
end

-- a bodygroup submodel's name in Z-City's lists, else its own
function APP.SubmodelName(sex, bgName, sub)
	local smd = tostring(sub or "")
	for _, group in pairs(hg.Appearance.Bodygroups or {}) do
		for name, t in pairs(type(group) == "table" and group[sex] or {}) do
			if type(t) == "table" and t[1] == smd then return name end
		end
	end
	smd = smd:gsub("%.smd$", "")
	return smd ~= "" and smd or "none"
end

-- installed accessories by placement: { id, name }
function APP.Accessories()
	return Cached("acc", function()
		local by = {}
		for id, a in pairs(hg.Accessories or {}) do
			if type(a) == "table" and a.model and not a.disallowinappearance and Installed(a.model) then
				local p = a.placement or "head"
				by[p] = by[p] or {}
				by[p][#by[p] + 1] = { id = id, name = a.name or id }
			end
		end
		for _, list in pairs(by) do table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end) end
		return by
	end)
end

function APP.Accessory(id)
	local a = hg.Accessories and hg.Accessories[id]
	return type(a) == "table" and a or nil
end

-- an appearance as received: everything checked, anything unknown dropped
function APP.Clean(t)
	if type(t) ~= "table" then return nil end
	local out = { on = t.on == true, bg = {}, acc = {} }
	local m = type(t.model) == "string" and APP.Model(t.model)
	if not m then out.on = false return out end
	out.model = m.name
	out.clothes = type(t.clothes) == "string" and APP.ClothesPath(m.sex, t.clothes) and t.clothes or "normal"
	for _, slot in ipairs(APP.EXTRA_SLOTS) do
		local id = t[slot]
		if type(id) == "string" and APP.ClothesPath(m.sex, id) then out[slot] = id end
	end
	out.face = type(t.face) == "string" and #t.face <= 64 and t.face or "Default"
	local n = 0
	for k, v in pairs(type(t.bg) == "table" and t.bg or {}) do
		v = tonumber(v)
		if type(k) == "string" and #k <= 64 and v and v >= 0 and v < 64 and n < APP.MAX_BODYGROUPS then
			out.bg[k] = math.floor(v)
			n = n + 1
		end
	end
	local used = {}
	for _, id in ipairs(type(t.acc) == "table" and t.acc or {}) do
		local a = type(id) == "string" and APP.Accessory(id)
		local p = a and (a.placement or "head")
		if a and not a.disallowinappearance and not used[p] and #out.acc < APP.MAX_ACCESSORIES then
			used[p] = true
			out.acc[#out.acc + 1] = id
		end
	end
	return out
end

-- Z-City's saved appearance (data/zcity/appearances/*.json) as ours
function APP.FromZCity(z)
	if type(z) ~= "table" then return nil end
	local m = APP.Model(z.AModel)
	local cl = type(z.AClothes) == "table" and z.AClothes or {}
	local t = { on = true, model = z.AModel, clothes = cl.main or "normal", pants = cl.pants, boots = cl.boots, face = z.AFacemap, bg = {}, acc = {} }
	for _, id in ipairs(type(z.AAttachments) == "table" and z.AAttachments or {}) do
		if id ~= "" and id ~= "none" then t.acc[#t.acc + 1] = id end
	end
	-- bodygroups there are Z-City names (a list entry -> its submodel name)
	t.zbg = type(z.ABodygroups) == "table" and z.ABodygroups or nil
	t.sex = m and m.sex
	return t
end

-- a random look from what's installed
function APP.Random()
	local models = APP.Models()
	if #models == 0 then return nil end
	local m = models[math.random(#models)]
	local clothes = APP.Clothes(m.sex)
	local function pick() return #clothes > 0 and clothes[math.random(#clothes)].id or "normal" end
	local t = { on = true, model = m.name, clothes = pick(), pants = pick(), boots = pick(), face = "Default", bg = {}, acc = {} }
	local by = APP.Accessories()
	for _, p in ipairs(APP.PLACEMENTS) do
		local list = by[p]
		if list and #list > 0 and math.random() < 0.35 then t.acc[#t.acc + 1] = list[math.random(#list)].id end
	end
	return t
end

-- female (for an accessory's female position and model)
function APP.IsFemale(ent)
	local m = APP.ModelByPath(ent:GetModel())
	if m then return m.sex == 2 end
	if ThatPlyIsFemale then
		local ok, fem = pcall(ThatPlyIsFemale, ent)
		return ok and fem or false
	end
	return false
end

local function SlotOf(mats, name)
	for i, m in ipairs(mats) do if m == name then return i - 1 end end
end

-- dresses an entity already on the model m: clothes, face, bodygroups
-- (the player on the server, the preview on the client)
function APP.Dress(ent, t, m)
	ent:SetSubMaterial()
	local mats = ent:GetMaterials() or {}
	local clothes = APP.ClothesPath(m.sex, t.clothes) or APP.ClothesPath(m.sex, "normal")
	local main = m.slots.main and SlotOf(mats, m.slots.main)
	if clothes and main then ent:SetSubMaterial(main, clothes) end
	for _, key in ipairs(APP.EXTRA_SLOTS) do
		local path = t[key] and APP.ClothesPath(m.sex, t[key])
		local slot = path and m.slots[key] and SlotOf(mats, m.slots[key])
		if slot then ent:SetSubMaterial(slot, path) end
	end
	local faces = hg.Appearance.FacemapsSlots or {}
	for i, mat in ipairs(mats) do
		local path = faces[mat] and faces[mat][t.face]
		if path and path ~= "" then ent:SetSubMaterial(i - 1, path) end
	end
	for i = 0, ent:GetNumBodyGroups() - 1 do ent:SetBodygroup(i, 0) end
	for name, sub in pairs(t.bg or {}) do
		local id = ent:FindBodygroupByName(name)
		if id and id >= 0 and sub < ent:GetBodygroupCount(id) then ent:SetBodygroup(id, sub) end
	end
end

if SERVER then
	include("skategm_appearance/sv_appearance.lua")
	AddCSLuaFile("skategm_appearance/cl_appearance.lua")
else
	include("skategm_appearance/cl_appearance.lua")
end
