dofile("gmock_left.lua")
dofile("../../addon/skategm/lua/autorun/client/skategm_cl.lua")
local S = SkateGM
local T = S.test

-- fake skeleton (ValveBiped-like): bone -> {parent, world position in a bind/idle pose}
local names = { "ValveBiped.Bip01_Pelvis", "ValveBiped.Bip01_Spine", "ValveBiped.Bip01_R_Thigh", "ValveBiped.Bip01_R_Calf",
	"ValveBiped.Bip01_R_Foot", "ValveBiped.Bip01_L_Thigh", "ValveBiped.Bip01_L_Calf", "ValveBiped.Bip01_Spine1" }
local parent = { [0] = -1, 0, 0, 2, 3, 0, 5, 1 }
-- idle pose facing +x: right is -y
local pos = { [0] = Vector(0, 0, 40), Vector(0, 0, 44), Vector(0, -4, 38), Vector(0, -4, 20), Vector(0, -4, 3), Vector(0, 4, 38), Vector(0, 4, 20), Vector(0, 0, 50) }
local W = {}
for i = 0, 7 do
	local m = Matrix()
	m:SetAngles(Angle(math.random(-30, 30), math.random(-30, 30), math.random(-30, 30))) -- arbitrary bone frames
	m:SetTranslation(pos[i])
	W[i] = m
end
local set = {}
local ent = {
	GetBoneParent = function(_, i) return parent[i] end,
	GetBoneCount = function() return 8 end,
	GetBoneMatrix = function(_, i) return Matrix(W[i]) end,
	SetBoneMatrix = function(_, i, m) set[i] = m end,
}
local R = { parent = parent, swing = {} }
R.pelvis, R.spine, R.rthigh, R.lthigh = 0, 1, 2, 5
R.swing[2] = { a = "RIGHTUPLEG", b = "RIGHTLEG", child = 3 }
R.swing[3] = { a = "RIGHTLEG", b = "RIGHTFOOT", child = 4 }
R.swing[1] = { a = "SPINE", b = "SPINE1", child = 7 }
ent.Sk8Rig = R

-- skate target pose: turned 90 degrees (facing +y, so right is +x), crouched, right knee forward
local P = {
	HIPS = Vector(100, 200, 30), SPINE = Vector(100, 201, 35), SPINE1 = Vector(100, 203, 44),
	RIGHTUPLEG = Vector(104, 200, 28), LEFTUPLEG = Vector(96, 200, 28),
	RIGHTLEG = Vector(104, 212, 16), RIGHTFOOT = Vector(104, 204, 2),
}
S.P = P
ent.Sk8P = P
T.Retarget(ent)

local function dir(a, b) return (b - a):GetNormalized() end
local function report(label, got, want)
	local d = got:Dot(want)
	print(string.format("%-28s alignment %.4f  %s", label, d, d > 0.999 and "OK" or "<-- WRONG"))
end
local g = function(i) return set[i]:GetTranslation() end
report("pelvis at skate hips", Vector(1, 0, 0) * (1 - math.min(1, (g(0) - P.HIPS):Length())), Vector(1, 0, 0))
report("hips right axis", dir(g(5), g(2)), dir(P.LEFTUPLEG, P.RIGHTUPLEG))
report("thigh -> knee", dir(g(2), g(3)), dir(P.RIGHTUPLEG, P.RIGHTLEG))
report("shin -> ankle", dir(g(3), g(4)), dir(P.RIGHTLEG, P.RIGHTFOOT))
report("spine -> spine1", dir(g(1), g(7)), dir(P.SPINE, P.SPINE1))
-- bone lengths must be the model's own, not the skater's
print(string.format("thigh length kept: model %.2f -> posed %.2f", (pos[3] - pos[2]):Length(), (g(3) - g(2)):Length()))
-- unmapped child (left calf) must follow its parent rigidly
local lw = W[5]:GetInverseTR() * W[6]
local ln = set[5]:GetInverseTR() * set[6]
local drift = (lw:GetTranslation() - ln:GetTranslation()):Length()
print(string.format("unmapped left calf keeps its local offset: drift %.5f %s", drift, drift < 1e-3 and "OK" or "<-- WRONG"))
