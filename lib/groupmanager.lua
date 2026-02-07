-- Raid/group formation: save/load raid config, group invites.
-- Uses globals debug and printf. LoadRaid uses state/timers (no mq.delay).

local mq = require('mq')
local botconfig = require('lib.config')
local state = require('lib.state')

local M = {}

-- Do a single invite (one member). Used by AdvanceLoadRaid; delay between invites is enforced by state timer.
local function doOneInvite(groupldr, raidmember, grptype)
    local myid = mq.TLO.Me.ID() or 0
    local groupldrspawnid = mq.TLO.Spawn('pc =' .. groupldr).ID() or 0
    local spawnid = mq.TLO.Spawn('pc =' .. raidmember).ID() or 0
    if debug then printf('%s inviting: %s', groupldr, raidmember) end
    if (grptype == 'group' or spawnid > 0) and groupldrspawnid ~= myid then
        mq.cmdf('/rc %s /inv %s', groupldr, raidmember)
    elseif spawnid > 0 and groupldrspawnid == myid then
        mq.cmdf('/inv %s', raidmember)
    elseif grptype == 'raid' then
        printf("\ayCZBot:\ax\ar%s's\ax group member \ar%s\ax is not in the zone, skipping", groupldr, raidmember)
    end
end

function M.GroupInvite(groupldr, groupmembers, grptype)
    if debug then printf('groupldr: %s', groupldr) end
    local myid = mq.TLO.Me.ID() or 0
    local groupldrspawnid = mq.TLO.Spawn('pc =' .. groupldr).ID() or 0
    for raidmember, _ in pairs(groupmembers) do
        doOneInvite(groupldr, raidmember, grptype)
    end
end

function M.SaveRaid(raidname)
    local raidmembers = mq.TLO.Raid.Members() or 0
    if raidmembers == 0 then
        printf('\ayCZBot:\ax Not in a raid, no raid to save')
        return
    end
    if not raidname or raidname == '' then
        printf('\ayCZBot:\ax Noname given, cant save raid (/cz raid save raidname)')
        return
    end
    local comkeytable = botconfig.getCommon()
    if not comkeytable.raidlist then comkeytable.raidlist = {} end
    printf('\ayCZBot:\ax saving raidconfig \ag%s\ax', raidname)
    comkeytable.raidlist[raidname] = {}
    comkeytable.raidlist[raidname].leaders = {}
    comkeytable.raidlist[raidname].groups = {}
    for i = 1, raidmembers do
        local raidmember = mq.TLO.Raid.Member(i)() or false
        local groupldr = mq.TLO.Raid.Member(i).GroupLeader() or false
        local groupnum = mq.TLO.Raid.Member(i).Group() or false
        if groupldr and raidmember and groupnum then
            comkeytable.raidlist[raidname].leaders[groupnum] = raidmember
            if debug then printf('saving leader of group %s as %s', groupnum,
                    comkeytable.raidlist[raidname].leaders[groupnum]) end
        elseif raidmember and groupnum then
            if not comkeytable.raidlist[raidname].groups[groupnum] then
                comkeytable.raidlist[raidname].groups[groupnum] = {}
                if not comkeytable.raidlist[raidname].leaders[groupnum] then
                    comkeytable.raidlist[raidname].leaders[groupnum] = raidmember
                end
            end
            comkeytable.raidlist[raidname].groups[groupnum][raidmember] = raidmember
            if debug then printf('saving member of group %s as %s', groupnum,
                    comkeytable.raidlist[raidname].groups[groupnum][raidmember]) end
        end
    end
    botconfig.saveCommon()
end

function M.LoadRaid(raidname)
    local comkeytable = botconfig.getCommon()
    if not comkeytable.raidlist or not comkeytable.raidlist[raidname] then
        printf('no raid named %s found on this pc', raidname)
        return
    end
    printf('\ayCZBot:\ax Loading raid setup \ag%s\ax', raidname)
    local raidmembers = mq.TLO.Raid.Members() or 0
    local myid = mq.TLO.Me.ID() or 0
    if raidmembers and raidmembers > 0 then mq.cmd('/raiddisband') end
    for disbanditer = 1, 12 do
        local groupldr = comkeytable.raidlist[raidname].leaders[disbanditer] or false
        if groupldr then
            mq.cmdf('/rc %s /squelch /multiline ; /disband ; /raiddisband', groupldr)
        end
        if comkeytable.raidlist[raidname].groups[disbanditer] then
            for raidmember, _ in pairs(comkeytable.raidlist[raidname].groups[disbanditer]) do
                mq.cmdf('/rc %s /squelch /multiline ; /disband ; /raiddisband', raidmember)
            end
        end
    end
    state.setRunState('load_raid', {
        phase = 'after_disband',
        deadline = mq.gettime() + 500,
        raidname = raidname,
    })
end

-- Advance the load_raid state machine. Called from mainloop hook; no mq.delay.
function M.AdvanceLoadRaid()
    if state.getRunState() ~= 'load_raid' then return end
    local p = state.getRunStatePayload()
    if not p or not p.deadline or mq.gettime() < p.deadline then return end

    local raidname = p.raidname
    local comkeytable = botconfig.getCommon()
    local myid = mq.TLO.Me.ID() or 0

    if p.phase == 'after_disband' then
        -- Build flat list of actions: one invite per member, then raidinv per group.
        local actions = {}
        for i = 1, 12 do
            local groupldr = comkeytable.raidlist[raidname].leaders[i] or false
            local groups = comkeytable.raidlist[raidname].groups[i] or {}
            if groupldr then
                if debug then printf('groupldr: %s', groupldr) end
                for raidmember, _ in pairs(groups) do
                    actions[#actions + 1] = { type = 'invite', groupldr = groupldr, raidmember = raidmember, grptype = 'raid' }
                end
                actions[#actions + 1] = { type = 'raidinv', groupldr = groupldr }
            end
        end
        state.setRunState('load_raid', {
            phase = 'inviting',
            raidname = raidname,
            deadline = mq.gettime() + 50,
            actions = actions,
            index = 1,
        })
        return
    end

    if p.phase == 'inviting' then
        local actions = p.actions
        local idx = p.index or 1
        if idx <= #actions then
            local a = actions[idx]
            if a.type == 'invite' then
                doOneInvite(a.groupldr, a.raidmember, a.grptype)
            elseif a.type == 'raidinv' then
                local groupldrspawnid = mq.TLO.Spawn('pc =' .. a.groupldr).ID() or 0
                if groupldrspawnid > 0 and groupldrspawnid ~= myid then
                    mq.cmdf('/raidinv %s', a.groupldr)
                elseif groupldrspawnid ~= myid then
                    printf('\ayCZBot:\axGroup Leader \ar%s is not in zone, skipping group', a.groupldr)
                end
            end
            state.setRunState('load_raid', {
                phase = 'inviting',
                raidname = raidname,
                deadline = mq.gettime() + 50,
                actions = actions,
                index = idx + 1,
            })
            return
        end
        -- All invites done; plugin handles accepting group/raid invites
        state.clearRunState()
        return
    end
end

-- Register mainloop hook so AdvanceLoadRaid runs every tick when state is load_raid.
local hookregistry = require('lib.hookregistry')
hookregistry.registerMainloopHook('groupmanager_advance', function()
    M.AdvanceLoadRaid()
end, 100, true)

return M
