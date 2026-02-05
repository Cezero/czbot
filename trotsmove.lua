local mq = require('mq')

local trotsmove = {}

function trotsmove.FollowCall()
    if MasterPause then return false end
    if not stucktimer then stucktimer = 0 end
    if stucktimer <= mq.gettime() then trotsmove.UnStuck() end
    if mq.TLO.Me.Sneaking() then mq.cmd('/doability sneak') end
    if not mq.TLO.Spawn('id ' .. runconfig['followid']).ID() or mq.TLO.Spawn('id ' .. runconfig['followid']).Type() == 'Corpse' then
        if mq.TLO.Spawn('=' .. runconfig['followname']).ID() then runconfig['followid'] = mq.TLO.Spawn('=' ..
            runconfig['followname']).ID() end
    end
    mq.cmdf('/nav id %s log=off', runconfig['followid'])
end

function trotsmove.UnStuck()
    local stuckdistance = mq.TLO.Spawn(runconfig['followid']).Distance3D() or 100
    local acleash = myconfig.settings.acleash
    local stuckdir = math.random(0, 360)
    local ransize = math.random(1, 12)
    local followdist = mq.TLO.Spawn(runconfig['followid']).Distance3D()
    if stuckdistance < acleash then return false end
    if (mq.TLO.Navigation.PathExists('id ' .. runconfig['followid'])()) then
        mq.cmdf('/nav id %s los=on dist=15 log=off', runconfig['followid'])
        mq.delay(5000)
        if mq.TLO.Spawn(runconfig['followid']).Distance3D() and stuckdistance >= mq.TLO.Spawn(runconfig['followid']).Distance3D() + 10 then
            stucktimer = mq.gettime() + 60000
            return
        end
    end
    mq.cmd('/echo I appear to be stuck, attempting to get unstuck')
    if mq.TLO.Navigation.Active() then
        if mq.TLO.Plugin("MQ2AutoSize").IsLoaded() then mq.cmd('/autosize sizeself 1') end
        mq.delay(2000)
        if stuckdistance < acleash then return false end
        if stuckdistance >= mq.TLO.Spawn(runconfig['followid']).Distance3D() + 10 then
            stucktimer = mq.gettime() + 60000
            return
        end
        if mq.TLO.Plugin("MQ2AutoSize").IsLoaded() then mq.cmd('/autosize sizeself 12') end
        mq.delay(2000)
        if stuckdistance < acleash then return false end
        if stuckdistance >= mq.TLO.Spawn(runconfig['followid']).Distance3D() + 10 then
            stucktimer = mq.gettime() + 60000
            return
        end
        if mq.TLO.Plugin("MQ2AutoSize").IsLoaded() then mq.cmd('/autosize sizeself 8') end
        mq.delay(2000)
        if stuckdistance < acleash then return false end
        if stuckdistance >= mq.TLO.Spawn(runconfig['followid']).Distance3D() + 10 then
            stucktimer = mq.gettime() + 60000
            return
        end
    end
    function Wiggle(heading, size)
        if MasterPause then return false end
        if stuckdistance < acleash then return false end
        mq.cmd('/nav stop')
        print('facing heading:', heading, ' sizing to:', size)
        if mq.TLO.Plugin("MQ2AutoSize").IsLoaded() then mq.cmdf(
            '/squelch /multiline ; /face fast heading %s ; /stand ; /autosize sizeself %s ; /keypress forward hold',
                heading, size) end
        mq.delay(2000)
        if stuckdistance < acleash then return false end
        mq.cmd('/squelch /multiline ; /keypress forward')
        mq.cmdf('/squelch /nav id %s log=off', runconfig['followid'])
        if mq.TLO.Navigation.Active() then mq.delay(1000) end
        if mq.TLO.Spawn(runconfig['followid']).Distance3D() and stuckdistance >= mq.TLO.Spawn(runconfig['followid']).Distance3D() + 10 then
            stucktimer = mq.gettime() + 60000
            return true
        end
        mq.delay(100)
        if stuckdistance < acleash then return false end
        mq.cmd('/squelch /keypress back hold')
        mq.delay(2000)
        if stuckdistance < acleash then return false end
        mq.cmd('/squelch /keypress back')
        mq.cmdf('/squelch /nav id %s log=off', runconfig['followid'])
        if mq.TLO.Navigation.Active() then mq.delay(1000) end
        if followdist and stuckdistance and stuckdistance >= followdist + 10 then
            stucktimer = mq.gettime() + 60000
            return true
        end
    end

    if Wiggle(0, 1) then return true end
    if stuckdistance < acleash then return false end
    if Wiggle(90, 1) then return true end
    if stuckdistance < acleash then return false end
    if Wiggle(180, 1) then return true end
    if stuckdistance < acleash then return false end
    if Wiggle(270, 1) then return true end
    if stuckdistance < acleash then return false end
    if Wiggle(0, 12) then return true end
    if stuckdistance < acleash then return false end
    if Wiggle(90, 12) then return true end
    if stuckdistance < acleash then return false end
    if Wiggle(180, 12) then return true end
    if stuckdistance < acleash then return false end
    if Wiggle(270, 12) then return true end
    if stuckdistance < acleash then return false end
    if Wiggle(stuckdir, ransize) then return true end
    if stuckdistance < acleash then return false end
    if followdist and stuckdistance >= followdist + 10 then
        stucktimer = mq.gettime() + 60000
        return
    end
    stucktimer = mq.gettime() + 3000
end

function trotsmove.MakeCamp(...)
    args = { ... }
    if args[1] == 'on' then
        if mq.TLO.Stick.Active() then mq.cmd('/stick off') end
        if mq.TLO.Navigation.Active() then mq.cmd('/nav stop log=off') end
        if not mq.TLO.Navigation.MeshLoaded() then
            mq.cmd('/dgt \ayTrotsbot:\axCannot use makecamp (no mesh loaded)')
            return false
        end
        runconfig['makecampx'] = mq.TLO.Me.X()
        runconfig['makecampy'] = mq.TLO.Me.Y()
        runconfig['makecampz'] = mq.TLO.Me.Z()
        runconfig['campstatus'] = true
        mq.cmd('/dgt \ayTrotsbot:\axhanging out using mq2nav')
        return true
    elseif args[1] == 'off' then
        if not myconfig.pull['hunter'] then runconfig['makecampx'] = nil end
        if not myconfig.pull['hunter'] then runconfig['makecampy'] = nil end
        if not myconfig.pull['hunter'] then runconfig['makecampz'] = nil end
        runconfig['campstatus'] = false
        mq.cmd('/dgt \ayTrotsbot:\axmakecamp \aroff\ax')
    elseif args[1] == 'return' then
        print('return called')
        local timer = mq.gettime() + 5000
        if (mq.TLO.Stick.Active()) then mq.cmd('/squelch /stick off') end
        if (mq.TLO.Me.Combat()) then mq.cmd('/squelch /attack off') end
        if (mq.TLO.Me.Pet.Aggressive) then
            mq.cmd('/squelch /pet back off')
            mq.cmd('/squelch /pet follow')
        end
        if (mq.TLO.Target.Type() == 'NPC') then mq.cmd('/squelch /target clear') end
        mq.cmdf('/nav locxyz %s %s %s log=off', runconfig['makecampx'], runconfig['makecampy'], runconfig['makecampz'])
        mq.delay(1000, function() if mq.TLO.Me.Moving() then return true end end)
        while (mq.TLO.Me.Moving() and timer >= mq.gettime()) do mq.delay(100) end
    end
end

return trotsmove
