---------------------------------------------------------------------------
-- Settings > Character: the Z-City appearance (model, clothes, face,
-- bodygroups, accessories, colour), shown on the right as you change it.
-- Its rows are built each time they're read, so they follow the model.
---------------------------------------------------------------------------
local UI = SKATEGM_UI
local SET = UI and UI.settings
local APP = SKATEGM_APPEARANCE
if not (SET and APP) then return end
local List = UI.List
local TURN = { { keys = { "RS" }, text = "Turn the preview" } }

local function Nice(s) return string.NiceName and string.NiceName(s) or s end

function APP.PaintPreview(x, y, w, h)
	draw.RoundedBox(10, x, y, w, h, Color(0, 0, 0, 120))
	local e = APP.Preview()
	if not IsValid(e) then
		draw.SimpleText("no Z-City models installed", "DermaDefault", x + w / 2, y + h / 2, Color(255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		return
	end
	e:SetAngles(Angle(0, SET.spin or 0, 0))
	e:FrameAdvance(FrameTime())
	local lo, hi = e:GetRenderBounds()
	local height = math.max(hi.z - lo.z, 40)
	local ang = Angle(math.Clamp((SET.tilt or 20) * 0.4, -20, 35), 180, 0)
	cam.Start3D(Vector(0, 0, (lo.z + hi.z) / 2) - ang:Forward() * height * 1.7, ang, 40, x, y, w, h, 1, 4000)
	render.ClearDepth()
	render.SuppressEngineLighting(true)
	render.ResetModelLighting(0.75, 0.75, 0.75)
	render.SetModelLighting(0, 1, 1, 1)
	e:SetupBones()
	e:DrawModel()
	APP.DrawAccessories(e, LocalPlayer(), APP.my.acc or {})
	render.SuppressEngineLighting(false)
	cam.End3D()
end

local function Preview(_, x, y, w, h) APP.PaintPreview(x, y, w, h) end

-- a value row that cycles a list (get / set work in the list's indexes)
local function Cycle(label, names, get, set)
	return { label = label, value = function() local n = names() return n[get(n)] or "?" end,
		change = function(dir)
			local n = names()
			if #n == 0 then return end
			set((get(n) - 1 + dir) % #n + 1, n)
		end }
end

function SET.CharacterModelPage()
	local page = { title = "Choose a character", preview = Preview, hints = TURN, rows = {} }
	local cur = APP.MyModel()
	for i, m in ipairs(APP.Models()) do
		page.rows[i] = { label = m.name, sub = m.sex == 2 and "female" or "male", mark = function() local now = APP.MyModel() return now and now.name == m.name end,
			run = function() APP.SetModel(m.name) SET.stack[#SET.stack] = nil end }
		if cur and cur.name == m.name then page.sel = i end
	end
	if #page.rows == 0 then page.rows[1] = { label = "No Z-City models installed" } end
	return page
end

function SET.AccessoryListPage(placement)
	local list = APP.Accessories()[placement] or {}
	local page = { title = APP.PLACEMENT_NAMES[placement] or Nice(placement), preview = Preview, hints = TURN, rows = {} }
	local cur = APP.MyAccessory(placement)
	page.rows[1] = { label = "None", mark = function() return APP.MyAccessory(placement) == nil end, run = function() APP.SetAccessory(placement, nil) SET.stack[#SET.stack] = nil end }
	for i, a in ipairs(list) do
		page.rows[i + 1] = { label = a.name, mark = function() return APP.MyAccessory(placement) == a.id end,
			run = function() APP.SetAccessory(placement, a.id) SET.stack[#SET.stack] = nil end }
		if cur == a.id then page.sel = i + 1 end
	end
	return page
end

function SET.AccessoriesPage()
	local rows = {}
	local by = APP.Accessories()
	for _, p in ipairs(APP.PLACEMENTS) do
		local list = by[p]
		if list and #list > 0 then
			local row = Cycle(APP.PLACEMENT_NAMES[p] or Nice(p), function()
				local n = { "None" }
				for i, a in ipairs(list) do n[i + 1] = a.name end
				return n
			end, function()
				local cur = APP.MyAccessory(p)
				for i, a in ipairs(list) do if a.id == cur then return i + 1 end end
				return 1
			end, function(i) APP.SetAccessory(p, i > 1 and list[i - 1].id or nil) end)
			row.page = function() return SET.AccessoryListPage(p) end
			row.aText = "Pick from the list"
			rows[#rows + 1] = row
		end
	end
	if #rows == 0 then rows[1] = { label = "No Z-City accessories installed" } end
	rows[#rows + 1] = { label = "Take everything off", run = function() APP.Set("acc", {}) end }
	return { title = "Accessories", preview = Preview, hints = TURN, rows = rows }
end

function SET.ImportPage()
	local rows = {}
	for _, f in ipairs(APP.ZCityFiles()) do
		local name = f:gsub("%.json$", "")
		local preset = name:match("^presets/(.+)$")
		rows[#rows + 1] = { label = preset or name, sub = preset and "preset" or nil, run = function()
			local ok, err = APP.ImportZCity(f)
			SET.Say(ok and ("wearing " .. f) or ("couldn't: " .. tostring(err)))
			if ok then SET.stack[#SET.stack] = nil end
		end }
	end
	if #rows == 0 then rows[1] = { label = "None in data/zcity/appearances" } end
	return { title = "Z-City appearances", preview = Preview, hints = TURN, rows = rows }
end

local function CharacterRows()
	local my = APP.my
	local rows = {
		List.Bool("Wear the Z-City character", function() return APP.my.on end, function(v) APP.Set("on", v) end),
	}
	local m = APP.MyModel()
	if not m then
		rows[#rows + 1] = { label = "No Z-City models installed", sub = APP.loadErr or "subscribe to the Z-City content" }
		return rows
	end
	rows[#rows + 1] = { label = "Model", page = SET.CharacterModelPage, value = function() return m.name end }
	rows[#rows + 1] = Cycle("Jacket texture", function()
		local n = {}
		for i, c in ipairs(APP.Clothes(m.sex)) do n[i] = APP.ClothesName(c.id) end
		return n
	end, function()
		for i, c in ipairs(APP.Clothes(m.sex)) do if c.id == my.clothes then return i end end
		return 1
	end, function(i) local c = APP.Clothes(m.sex)[i] if c then APP.Set("clothes", c.id) end end)
	local e = APP.Preview()
	-- pants and boots: the same textures on their own material slots, when
	-- the model has them (first choice: the model's own)
	local mats = IsValid(e) and e:GetMaterials() or {}
	local has = {}
	for _, mat in ipairs(mats) do has[mat] = true end
	for _, slot in ipairs(APP.EXTRA_SLOTS) do
		if m.slots[slot] and has[m.slots[slot]] then
			rows[#rows + 1] = Cycle(Nice(slot) .. " texture", function()
				local n = { "Model's own" }
				for i, c in ipairs(APP.Clothes(m.sex)) do n[i + 1] = APP.ClothesName(c.id) end
				return n
			end, function()
				for i, c in ipairs(APP.Clothes(m.sex)) do if c.id == my[slot] then return i + 1 end end
				return 1
			end, function(i) local c = APP.Clothes(m.sex)[i - 1] APP.Set(slot, c and c.id or nil) end)
		end
	end
	local faces = APP.Faces(IsValid(e) and e:GetMaterials() or {})
	if #faces > 1 then
		rows[#rows + 1] = Cycle("Face", function() return faces end, function(n)
			for i, f in ipairs(n) do if f == my.face then return i end end
			return 1
		end, function(i, n) APP.Set("face", n[i]) end)
	end
	for _, bg in ipairs(APP.BodygroupsOf(e)) do
		rows[#rows + 1] = Cycle(Nice(bg.name), function()
			local n = {}
			for i = 0, bg.num - 1 do n[i + 1] = APP.SubmodelName(m.sex, bg.name, bg.subs[i]) end
			return n
		end, function() return math.Clamp((my.bg[bg.name] or 0) + 1, 1, bg.num) end, function(i)
			my.bg[bg.name] = i - 1
			APP.Changed()
		end)
	end
	rows[#rows + 1] = { label = "Accessories", page = SET.AccessoriesPage, value = function() return #(my.acc or {}) .. " worn" end }
	rows[#rows + 1] = List.Colour("Colour", SET.COLOURS, function()
		local v = Vector(GetConVar("cl_playercolor"):GetString())
		return string.format("%d %d %d", v.x * 255, v.y * 255, v.z * 255)
	end, function(s)
		local c = List.Parse(s)
		RunConsoleCommand("cl_playercolor", string.format("%.3f %.3f %.3f", c.r / 255, c.g / 255, c.b / 255))
	end)
	rows[#rows + 1] = { label = "Random look", run = function()
		local t = APP.Random()
		if t then t.on = APP.my.on APP.my = t APP.Changed() end
	end }
	if #APP.ZCityFiles() > 0 then rows[#rows + 1] = { label = "Wear a saved Z-City appearance", page = SET.ImportPage } end
	return rows
end

function SET.CharacterPage()
	if not APP.my then APP.Load() end
	return { title = "Character", preview = Preview, hints = TURN, rows = CharacterRows }
end
