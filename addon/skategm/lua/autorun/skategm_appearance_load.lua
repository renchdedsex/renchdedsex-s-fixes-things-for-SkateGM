-- the Z-City character appearance (not under Z-City itself, which has its own)
if engine.ActiveGamemode() == "zcity" then return end
if SERVER then AddCSLuaFile("skategm_appearance/sh_appearance.lua") end
include("skategm_appearance/sh_appearance.lua")
