-- Minimal GMod math mock with Source conventions (mathlib AngleMatrix / MatrixAngles)
local V = {} V.__index = V
function Vector(x, y, z) if type(x) == "table" then return setmetatable({ x = x.x, y = x.y, z = x.z }, V) end return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V) end
V.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
V.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
V.__mul = function(a, b) if type(a) == "number" then a, b = b, a end return Vector(a.x * b, a.y * b, a.z * b) end
V.__div = function(a, b) return Vector(a.x / b, a.y / b, a.z / b) end
V.__unm = function(a) return Vector(-a.x, -a.y, -a.z) end
function V:Dot(b) return self.x * b.x + self.y * b.y + self.z * b.z end
function V:Cross(b) return Vector(self.y * b.z - self.z * b.y, self.z * b.x - self.x * b.z, self.x * b.y - self.y * b.x) end
function V:Length() return math.sqrt(self:Dot(self)) end
function V:GetNormalized() local l = self:Length() return l > 0 and self / l or Vector() end
function V:DistToSqr(b) local d = self - b return d:Dot(d) end
function V:Div(s) self.x, self.y, self.z = self.x / s, self.y / s, self.z / s end

local A = {} A.__index = A
function Angle(p, y, r) return setmetatable({ p = p or 0, y = y or 0, r = r or 0 }, A) end
local function rad(d) return math.rad(d) end
local function AngleRot(a) -- 3x3 rows, columns = forward, left, up
	local sp, cp = math.sin(rad(a.p)), math.cos(rad(a.p))
	local sy, cy = math.sin(rad(a.y)), math.cos(rad(a.y))
	local sr, cr = math.sin(rad(a.r)), math.cos(rad(a.r))
	return {
		{ cp * cy, sr * sp * cy - cr * sy, cr * sp * cy + sr * sy },
		{ cp * sy, sr * sp * sy + cr * cy, cr * sp * sy - sr * cy },
		{ -sp, sr * cp, cr * cp },
	}
end
local function RotAngle(m)
	local fx, fy, fz = m[1][1], m[2][1], m[3][1]
	local lx, ly, lz = m[1][2], m[2][2], m[3][2]
	local uz = m[3][3]
	local xy = math.sqrt(fx * fx + fy * fy)
	if xy > 0.001 then
		return Angle(math.deg(math.atan2(-fz, xy)), math.deg(math.atan2(fy, fx)), math.deg(math.atan2(lz, uz)))
	end
	return Angle(math.deg(math.atan2(-fz, xy)), math.deg(math.atan2(-lx, ly)), 0)
end
-- right-handed rotation about a world axis (as Source's VMatrixBuildRotationAboutAxis)
function A:RotateAroundAxis(axis, deg)
	local m = AngleRot(self)
	local c, s = math.cos(rad(-deg)), math.sin(rad(-deg))
	local x, y, z = axis.x, axis.y, axis.z
	local R = {
		{ c + x * x * (1 - c), x * y * (1 - c) - z * s, x * z * (1 - c) + y * s },
		{ y * x * (1 - c) + z * s, c + y * y * (1 - c), y * z * (1 - c) - x * s },
		{ z * x * (1 - c) - y * s, z * y * (1 - c) + x * s, c + z * z * (1 - c) },
	}
	local o = {}
	for i = 1, 3 do o[i] = {} for j = 1, 3 do o[i][j] = R[i][1] * m[1][j] + R[i][2] * m[2][j] + R[i][3] * m[3][j] end end
	local a = RotAngle(o)
	self.p, self.y, self.r = a.p, a.y, a.r
end
function A:Forward() local m = AngleRot(self) return Vector(m[1][1], m[2][1], m[3][1]) end

local M = {} M.__index = M
function Matrix(t)
	local m = setmetatable({}, M)
	if getmetatable(t) == M then for i = 1, 4 do m[i] = { t[i][1], t[i][2], t[i][3], t[i][4] } end
	elseif t then for i = 1, 4 do m[i] = { t[i][1], t[i][2], t[i][3], t[i][4] } end
	else for i = 1, 4 do m[i] = { 0, 0, 0, 0 } m[i][i] = 1 end end
	return m
end
M.__mul = function(a, b)
	if getmetatable(b) == V then
		return Vector(a[1][1] * b.x + a[1][2] * b.y + a[1][3] * b.z + a[1][4], a[2][1] * b.x + a[2][2] * b.y + a[2][3] * b.z + a[2][4], a[3][1] * b.x + a[3][2] * b.y + a[3][3] * b.z + a[3][4])
	end
	local o = Matrix()
	for i = 1, 4 do for j = 1, 4 do local s = 0 for k = 1, 4 do s = s + a[i][k] * b[k][j] end o[i][j] = s end end
	return o
end
function M:GetTranslation() return Vector(self[1][4], self[2][4], self[3][4]) end
function M:SetTranslation(v) self[1][4], self[2][4], self[3][4] = v.x, v.y, v.z end
function M:GetAngles() return RotAngle(self) end
function M:SetAngles(a) local r = AngleRot(a) for i = 1, 3 do for j = 1, 3 do self[i][j] = r[i][j] end end end
function M:GetInverseTR()
	local o = Matrix()
	for i = 1, 3 do for j = 1, 3 do o[i][j] = self[j][i] end end
	local t = self:GetTranslation()
	for i = 1, 3 do o[i][4] = -(o[i][1] * t.x + o[i][2] * t.y + o[i][3] * t.z) end
	return o
end

-- stubs for everything else the client file touches at load time
local noop = setmetatable({}, { __index = function() return function() end end, __call = function() end })
hook, concommand, net, render, draw, surface, input, gameevent, chat, file = noop, noop, noop, noop, noop, noop, noop, noop, noop, noop
function CreateClientConVar() return { GetBool = function() return false end, GetFloat = function() return 1 end, GetString = function() return "" end } end
bit = require("bit")
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end
vector_origin = Vector()
COLLISION_GROUP_DEBRIS, COLLISION_GROUP_DEBRIS_TRIGGER, COLLISION_GROUP_WEAPON = 1, 2, 11
COLLISION_GROUP_IN_VEHICLE, COLLISION_GROUP_PASSABLE_DOOR, COLLISION_GROUP_WORLD = 10, 15, 20
function istable(x) return type(x) == "table" end
RunConsoleCommand = RunConsoleCommand or function() end

include = include or function(path) return dofile("../../addon/skategm/lua/" .. path) end
AddCSLuaFile = AddCSLuaFile or function() end
