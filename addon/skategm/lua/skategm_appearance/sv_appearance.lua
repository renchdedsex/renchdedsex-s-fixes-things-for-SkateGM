local APP = SKATEGM_APPEARANCE
util.AddNetworkString(APP.NET)

-- puts the player's appearance on them (after whatever set their playermodel)
function APP.Apply(ply)
	if not IsValid(ply) then return false end
	local t = ply.Sk8Appearance
	local m = t and t.on and APP.Model(t.model)
	if not m then return false end
	if string.lower(ply:GetModel() or "") ~= string.lower(m.mdl) then ply:SetModel(m.mdl) end
	APP.Dress(ply, t, m)
	ply:SetNW2String("skategm_acc", table.concat(t.acc, ","))
	ply.Sk8AppearanceOn = true
	return true
end

-- back to the plain playermodel
function APP.Remove(ply)
	if not IsValid(ply) or not ply.Sk8AppearanceOn then return end
	ply.Sk8AppearanceOn = nil
	ply:SetSubMaterial()
	ply:SetNW2String("skategm_acc", "")
	local ok = player_manager and player_manager.RunClass and pcall(player_manager.RunClass, ply, "SetModel")
	if not ok and GAMEMODE then hook.Call("PlayerSetModel", GAMEMODE, ply) end
	local bg = ply:GetInfo("cl_playerbodygroups")
	if bg and bg ~= "" then ply:SetBodyGroups(bg) end
	ply:SetSkin(ply:GetInfoNum("cl_playerskin", 0))
end

net.Receive(APP.NET, function(len, ply)
	if len > APP.MAX_JSON * 8 then return end
	local now = CurTime()
	if now - (ply.Sk8AppearanceAt or -10) < 0.5 then return end
	ply.Sk8AppearanceAt = now
	local raw = net.ReadString()
	if #raw > APP.MAX_JSON then return end
	local ok, t = pcall(util.JSONToTable, raw)
	t = ok and APP.Clean(t) or nil
	if not t then return end
	ply.Sk8Appearance = t
	if not ply:Alive() then return end
	if t.on then APP.Apply(ply) else APP.Remove(ply) end
end)

-- spawning, and SkateGM setting the playermodel again, both undo it
hook.Add("PlayerSpawn", "skategm_appearance", function(ply)
	timer.Simple(0.1, function() if IsValid(ply) then APP.Apply(ply) end end)
end)
hook.Add("SkateGMPlayerModel", "skategm_appearance", function(ply) APP.Apply(ply) end)
