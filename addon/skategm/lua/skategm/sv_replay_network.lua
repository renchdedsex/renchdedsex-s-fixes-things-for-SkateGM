-- Replay ghosts have their own channel and never replace the live player pose.
util.AddNetworkString("skategm_replay_pose")
local active={}
local function stop(ply)
    if not active[ply] then return end
    active[ply]=nil
    net.Start("skategm_replay_pose") net.WriteEntity(ply) net.WriteBool(false) net.SendOmit(ply)
end
net.Receive("skategm_replay_pose",function(len,ply)
    if not IsValid(ply) or len<1 then return end
    if not net.ReadBool() then stop(ply) return end
    if len<1833 then return end -- active bit + 3 floats + 108 int16 offsets + state
    if SkateGM and SkateGM.API and not SkateGM.API.Allowed(ply) then return end
    local now=SysTime()
    if now-(ply.SkateGMReplayAt or -100)<1/25 then return end
    local x,y,z=net.ReadFloat(),net.ReadFloat(),net.ReadFloat()
    for _,v in ipairs({x,y,z}) do if v~=v or math.abs(v)>2^31 then return end end
    local offsets={}
    for i=1,108 do offsets[i]=net.ReadInt(16) end
    local state=net.ReadUInt(8)
    if state>26 then return end
    ply.SkateGMReplayAt=now active[ply]=now
    net.Start("skategm_replay_pose",true)
    net.WriteEntity(ply) net.WriteBool(true)
    net.WriteFloat(x) net.WriteFloat(y) net.WriteFloat(z)
    for i=1,108 do net.WriteInt(offsets[i],16) end
    net.WriteUInt(state,8) net.SendOmit(ply)
end)
hook.Add("PlayerDisconnected","skategm_replay_network",stop)
hook.Add("Think","skategm_replay_network_timeout",function()
    local now=SysTime()
    for ply,last in pairs(active) do if now-last>2 then stop(ply) end end
end)
