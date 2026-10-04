local S = SkateGM
local R = S.replay

R.EXPORT_FPS = { 30, 60 }
R.EXPORT_QUALITY = { { "Normal", 70, 8000 }, { "High", 90, 20000 } }
R.EXPORT_WAIT = 3

function R.ExportName()
	return "skategm_" .. (R.MapName():gsub("[^%w_%-]", "_")) .. "_" .. os.date("%Y-%m-%d_%H-%M-%S")
end

function R.CanExport() return video ~= nil and video.Record ~= nil end

function R.Export(fps, quality)
	local v = R.on
	if not v or R.exporting then return false end
	if not R.CanExport() then
		S.API.Say("this copy of Garry's Mod can't record video", true)
		return false
	end
	fps = fps or R.EXPORT_FPS[1]
	local q = R.EXPORT_QUALITY[quality or 1] or R.EXPORT_QUALITY[1]
	local name = R.ExportName()
	local writer, err = video.Record({
		name = name, container = "webm", video = "vp8", audio = "vorbis",
		quality = q[2], bitrate = q[3], fps = fps, lockfps = true,
		width = ScrW(), height = ScrH(),
	})
	if not writer then
		S.API.Say("couldn't start the video: " .. tostring(err), true)
		return false
	end
	if writer.SetRecordSound then writer:SetRecordSound(false) end
	v.playing = false
	v.menu = nil
	local a, b = R.Trim()
	R.exporting = { writer = writer, fps = fps, frame = 0, from = a, to = b, frames = math.max(1, math.ceil((b - a) * fps) + 1), name = name, wait = R.EXPORT_WAIT }
	return true
end

function R.ExportThink()
	local e, v = R.exporting, R.on
	if not (e and v) then return end
	v.t = math.min(e.from + e.frame / e.fps, e.to)
	e.ready = e.wait <= 0
	if e.wait > 0 then e.wait = e.wait - 1 end
end

function R.ExportCapture()
	local e = R.exporting
	if not (e and e.ready) then return end
	e.ready = false
	e.writer:AddFrame(1 / e.fps, true)
	e.frame = e.frame + 1
	if e.frame >= e.frames then R.ExportFinish(true) end
end

function R.ExportFinish(done)
	local e = R.exporting
	if not e then return end
	R.exporting = nil
	pcall(function() e.writer:Finish() end)
	if done then
		R.ShowDone(e.name)
	else
		S.API.Say("video export cancelled (the part recorded so far is in garrysmod/videos)")
	end
end

hook.Add("PreDrawHUD", "skategm_replay_export", function() R.ExportCapture() end)

function R.VideoFile(name) return "videos/" .. name .. ".webm" end

function R.ShowDone(name)
	R.done = { name = name }
	if not (vgui and vgui.Create) then return end
	local w, h = ScrW(), ScrH()
	local pw, ph = math.floor(w * 0.5), math.floor(w * 0.5 * 9 / 16)
	local html = vgui.Create("DHTML")
	if not IsValid(html) then return end
	html:SetPos((w - pw) / 2, h * 0.2)
	html:SetSize(pw, ph)
	html:SetHTML(([[<html><body style="margin:0;background:#000;overflow:hidden">
<video src="asset://garrysmod/%s" autoplay loop muted style="width:100%%;height:100%%;object-fit:contain"></video>
</body></html>]]):format(R.VideoFile(name)))
	R.done.html = html
	R.done.box = { x = (w - pw) / 2, y = h * 0.2, w = pw, h = ph }
end

function R.CloseDone()
	local d = R.done
	if not d then return end
	R.done = nil
	if d.html and IsValid(d.html) then d.html:Remove() end
end

function R.OpenVideos()
	if skategm and skategm.OpenFolder and skategm.OpenFolder("videos") then return true end
	S.API.Say("your video is in garrysmod/videos")
	return false
end

function R.ExportPress(btn)
	local B = R.PAD
	if R.exporting then
		if btn == B.B then R.ExportFinish(false) end
		return true
	end
	if R.done then
		if btn == B.A or btn == B.B then R.CloseDone()
		elseif btn == B.X then R.OpenVideos() end
		return true
	end
	return false
end

function R.PaintExport(w, h)
	local UI = SKATEGM_UI
	local e, d = R.exporting, R.done
	if not (e or d) then return false end
	surface.SetDrawColor(0, 0, 0, e and 235 or 200)
	surface.DrawRect(0, 0, w, h)
	if e then
		local f = e.frames > 0 and e.frame / e.frames or 0
		draw.SimpleText("Exporting video...", "skategm_replay_big", w / 2, h * 0.38, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		local bw, bh = w * 0.5, math.max(10, h * 0.018)
		local bx, by = (w - bw) / 2, h * 0.46
		surface.SetDrawColor(60, 60, 60, 255)
		surface.DrawRect(bx, by, bw, bh)
		surface.SetDrawColor(255, 200, 70, 255)
		surface.DrawRect(bx, by, bw * f, bh)
		draw.SimpleText(string.format("%d%%   frame %d of %d", math.floor(f * 100), e.frame, e.frames), "skategm_replay_small", w / 2, by + bh * 2.2, Color(220, 220, 220), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
		UI.pad.Legend({ { keys = { "B" }, text = "Cancel" } }, w, h, "bottom")
	else
		draw.SimpleText("Video saved", "skategm_replay_big", w / 2, h * 0.12, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		draw.SimpleText("garrysmod/" .. R.VideoFile(d.name), "skategm_replay_small", w / 2, h * 0.16, Color(220, 220, 220), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
		if d.box then
			surface.SetDrawColor(255, 200, 70, 255)
			surface.DrawOutlinedRect(d.box.x - 2, d.box.y - 2, d.box.w + 4, d.box.h + 4, 2)
		end
		UI.pad.Legend({ { keys = { "A" }, text = "OK" }, { keys = { "X" }, text = "Open folder" } }, w, h, "bottom")
	end
	return true
end
