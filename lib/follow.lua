-- Follow logic: StartFollow(name) and registerEvents() for group/raid chat "follow".
-- Option C (chchain-style): module owns event registration and core behavior.
-- Used by lib/commands (cmd_follow) and botevents (follow.registerEvents only).

local mq = require('mq')
local state = require('lib.state')
local botmove = require('botmove')
local charinfo = require('plugin.charinfo')

local follow = {}

function follow.StartFollow(name)
    if not mq.TLO.Navigation.MeshLoaded then
        mq.cmd('/echo No Mesh for this zone, cannot use CZFollow+!!')
        return false
    end
    if not name or not mq.TLO.Spawn('=' .. name).ID() then
        return
    end
    local rc = state.getRunconfig()
    if rc.campstatus then botmove.MakeCamp('off') end
    rc.followid = mq.TLO.Spawn('=' .. name).ID()
    rc.followname = name
    rc.stucktimer = mq.gettime() + 60000
    printf('\ayCZBot:\ax\auFollowing\ax ON %s', mq.TLO.Spawn(rc.followid).CleanName())
end

local function event_FollowChat(line, speaker)
    if not charinfo.GetPeer(speaker) then return end
    follow.StartFollow(speaker)
end

function follow.registerEvents()
    mq.event('FollowChat', "#1# tells the #*#, 'follow#*#", event_FollowChat)
end

return follow
