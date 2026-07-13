local mq = require('mq')
local botconfig = require('lib.config')
local spellbands = require('lib.spellbands')
local state = require('lib.state')
local utils = require('lib.utils')
local charinfo = require('plugin.charinfo')
local myconfig = botconfig.config

local castutils = {}

-- Count mobs in mobList within aeRange 3D distance of spawnId. Used for targeted AE tarcnt (mobs in AE of candidate).
-- aeRange is spell-derived (passed per call from debuff/heal/buff context); we square once here per invocation.
function castutils.CountMobsWithinAERangeOfSpawn(mobList, spawnId, aeRange)
    if not mobList or not spawnId or not aeRange or aeRange <= 0 then return 0 end
    local aeRangeSq = aeRange * aeRange
    local sp = mq.TLO.Spawn(spawnId)
    local cx, cy, cz = sp.X(), sp.Y(), sp.Z()
    if not cx or not cy or not cz then return 0 end
    local count = 0
    for _, v in ipairs(mobList) do
        local vid = (v.ID and v.ID()) or v
        if vid and vid ~= 0 then
            local s = mq.TLO.Spawn(vid)
            local x, y, z = s.X(), s.Y(), s.Z()
            if x and y and z then
                local dSq = utils.getDistanceSquared3D(cx, cy, cz, x, y, z)
                if dSq and dSq <= aeRangeSq then count = count + 1 end
            end
        end
    end
    return count
end

-- Normalize spell entry: script gem handling and enabled default. Used by LoadSpellSectionConfig.
function castutils.normalizeSpellEntry(entry)
    if entry.gem == 'script' then
        if not myconfig.script[entry.spell] then
            print('making script ', entry.spell)
            myconfig.script[entry.spell] = "test"
        end
        table.insert(state.getRunconfig().ScriptList, entry.spell)
    end
    if entry.enabled == nil then entry.enabled = true end
end

-- Generic spell-section config loader. opts: defaultEntry(), bandsKey, storeIn, preLoad?, postLoad?, perEntryNormalize?(entry), perEntryAfterBands?(entry, i).
function castutils.LoadSpellSectionConfig(section, opts)
    if opts.preLoad then opts.preLoad() end
    local spells = myconfig[section].spells
    if not spells then
        myconfig[section].spells = {}
        spells = myconfig[section].spells
    end
    for i = 1, #spells do
        local entry = spells[i]
        if not entry then
            spells[i] = opts.defaultEntry()
            entry = spells[i]
        end
        if opts.perEntryNormalize then opts.perEntryNormalize(entry) end
        castutils.normalizeSpellEntry(entry)
        opts.storeIn[i] = spellbands.applyBands(opts.bandsKey, entry, i)
        if opts.perEntryAfterBands then opts.perEntryAfterBands(entry, i) end
    end
    if opts.postLoad then opts.postLoad() end
end

-- Group AE count-and-threshold: count members where needMemberFn(grpmember, grpid, grpname, peer) is true;
-- if count >= entry.tarcnt return (Group v1 -> 1 else Me.ID()), targethit. opts.aeRangeSq: when set, only count PC within squared range.
-- opts.includeMemberZero: when true, loop from 0 (Group.Member(0) is self); otherwise 1 to Members().
function castutils.evalGroupAECount(entry, targethit, index, bandTable, phaseKey, needMemberFn, opts)
    if not bandTable[index] or not bandTable[index][phaseKey] then return nil, nil end
    local tartype = mq.TLO.Spell(entry.spell).TargetType()
    if tartype ~= 'Group v1' and tartype ~= 'Group v2' then return nil, nil end
    opts = opts or {}
    local aeRangeSq = opts.aeRangeSq
    local startIdx = (opts.includeMemberZero and 0) or 1
    local needCount = 0
    for i = startIdx, mq.TLO.Group.Members() do
        local grpmember = mq.TLO.Group.Member(i)
        if grpmember then
            local grpspawn = grpmember.Spawn
            local grpname = grpmember.Name()
            local grpid = grpmember.ID()
            if grpid and grpid > 0 then
                if aeRangeSq then
                    local grpdistSq = grpspawn and
                    utils.getDistanceSquared2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), grpspawn.X(), grpspawn.Y()) or nil
                    if mq.TLO.Spawn(grpid).Type() ~= 'PC' or not grpdistSq or grpdistSq > aeRangeSq then
                        -- skip
                    else
                        local peer = charinfo.GetInfo(grpname)
                        if needMemberFn(grpmember, grpid, grpname, peer) then needCount = needCount + 1 end
                    end
                else
                    local peer = charinfo.GetInfo(grpname)
                    if needMemberFn(grpmember, grpid, grpname, peer) then needCount = needCount + 1 end
                end
            end
        end
    end
    if needCount >= (entry.tarcnt or 1) then
        if tartype == 'Group v1' then return mq.TLO.Me.ID(), targethit end
        return mq.TLO.Me.ID(), targethit
    end
    return nil, nil
end

-- Peer group key for dedup (remote Group v2 pc anchors). Multi-group dedup requires raid when not in anchor's EQ group.
function castutils.getPeerGroupKey(peerName)
    if not peerName or peerName == '' then return 'solo_unknown' end
    if mq.TLO.Group.Member(peerName).Index() then return 'mine' end
    local raidMembers = mq.TLO.Raid.Members()
    if raidMembers and raidMembers > 0 then
        for i = 1, raidMembers do
            if mq.TLO.Raid.Member(i)() == peerName then
                local gn = mq.TLO.Raid.Member(i).Group()
                if gn and gn > 0 then return 'raid_' .. tostring(gn) end
                break
            end
        end
    end
    return 'solo_' .. peerName
end

local function forEachGroupMemberOfAnchor(anchorName, fn)
    if mq.TLO.Group.Member(anchorName).Index() then
        for i = 0, mq.TLO.Group.Members() do
            local grpmember = mq.TLO.Group.Member(i)
            if grpmember then
                local grpname = grpmember.Name()
                local grpid = grpmember.ID()
                if grpid and grpid > 0 and grpname then
                    fn(grpname, grpid, grpmember, charinfo.GetInfo(grpname))
                end
            end
        end
        return
    end
    local anchorGroupNum = nil
    local raidMembers = mq.TLO.Raid.Members()
    if raidMembers and raidMembers > 0 then
        for i = 1, raidMembers do
            if mq.TLO.Raid.Member(i)() == anchorName then
                anchorGroupNum = mq.TLO.Raid.Member(i).Group()
                break
            end
        end
        if anchorGroupNum and anchorGroupNum > 0 then
            for i = 1, raidMembers do
                if mq.TLO.Raid.Member(i).Group() == anchorGroupNum then
                    local grpname = mq.TLO.Raid.Member(i)()
                    local peer = grpname and charinfo.GetInfo(grpname)
                    local grpid = peer and peer.ID
                    if (not grpid or grpid <= 0) and grpname then
                        grpid = mq.TLO.Spawn('pc =' .. grpname).ID()
                    end
                    if grpname and grpid and grpid > 0 then
                        fn(grpname, grpid, nil, peer or charinfo.GetInfo(grpname))
                    end
                end
            end
            return
        end
    end
    local peer = charinfo.GetInfo(anchorName)
    local grpid = peer and peer.ID
    if not grpid or grpid <= 0 then
        grpid = mq.TLO.Spawn('pc =' .. anchorName).ID()
    end
    if grpid and grpid > 0 then
        fn(anchorName, grpid, nil, peer or charinfo.GetInfo(anchorName))
    end
end

-- Group v2 AE on a peer anchor: count anchor's group members in AE range; return anchorId when count >= tarcnt.
function castutils.evalGroupV2OnPeer(entry, anchorId, anchorName, needMemberFn, opts)
    if not entry or not entry.spell then return nil end
    local tartype = mq.TLO.Spell(entry.spell).TargetType()
    if tartype ~= 'Group v2' then return nil end
    opts = opts or {}
    local aeRangeSq = opts.aeRangeSq
    local myRangeSq = opts.myRangeSq
    if not aeRangeSq or not myRangeSq then return nil end
    local anchorSpawn = mq.TLO.Spawn(anchorId)
    if not anchorSpawn or not anchorSpawn.ID() or anchorSpawn.ID() == 0 then return nil end
    local anchorDistSq = utils.getDistanceSquared2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), anchorSpawn.X(), anchorSpawn.Y())
    if not anchorDistSq or anchorDistSq > myRangeSq then return nil end
    local needCount = 0
    forEachGroupMemberOfAnchor(anchorName, function(grpname, grpid, grpmember, peer)
        local grpspawn = mq.TLO.Spawn(grpid)
        if not grpspawn or grpspawn.Type() ~= 'PC' then return end
        local grpdistSq = utils.getDistanceSquared2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), grpspawn.X(), grpspawn.Y())
        if not grpdistSq or grpdistSq > aeRangeSq then return end
        local memberRef = grpmember or grpspawn
        if needMemberFn(memberRef, grpid, grpname, peer) then needCount = needCount + 1 end
    end)
    if needCount >= (entry.tarcnt or 1) then return anchorId end
    return nil
end

-- Shared get-targets helpers for buff/cure/heal GetTargetsForPhase.
-- opts for getTargetsGroupMember: botsFirst (add bots in group first), excludeBotsFromGroup (in group loop skip names that have charinfo), excludeSelfAndTank (heal/buff: skip tank in group loop).
local function addPcEntries(out, names, count, filterFn, context)
    if not names then return end
    count = count or #names
    local byName = context and context.peerByName
    for i = 1, count do
        local name = names[i]
        local peer = (byName and byName[name]) or (name and charinfo.GetInfo(name))
        if peer and (not filterFn or filterFn(name)) then
            local id = peer.ID
            if id and id > 0 then
                local class = peer.Class and peer.Class.ShortName
                if type(class) == 'string' and class ~= '' then
                    out[#out + 1] = { id = id, targethit = class:lower(), name = name }
                end
            end
        end
    end
end

function castutils.getTargetsSelf()
    local out = {}
    local myid = mq.TLO.Me.ID()
    if myid and myid > 0 then out[#out + 1] = { id = myid, targethit = 'self' } end
    return out
end

function castutils.getTargetsOfftank(_context)
    local out = {}
    local czactor = require('lib.czactor')
    for _, ot in ipairs(czactor.getActiveOfftanks()) do
        local peer = charinfo.GetInfo(ot.name)
        local id = peer and peer.ID
        if (not id or id <= 0) then
            local sp = mq.TLO.Spawn('pc =' .. ot.name)
            id = sp and sp.ID()
        end
        if id and id > 0 then
            out[#out + 1] = { id = id, targethit = 'offtank', name = ot.name }
        end
    end
    return out
end

function castutils.getTargetsTank(context)
    local out = {}
    if context.tankid and context.tankid > 0 then
        out[#out + 1] = { id = context.tankid, targethit = 'tank' }
    end
    return out
end

function castutils.getTargetsGroupCaster(targethit)
    local out = {}
    local meid = mq.TLO.Me.ID()
    if meid then out[#out + 1] = { id = meid, targethit = targethit } end
    return out
end

function castutils.getTargetsGroupMember(context, opts)
    local out = {}
    opts = opts or {}
    if opts.botsFirst and context.bots then
        addPcEntries(out, context.bots, #context.bots, function(name) return mq.TLO.Group.Member(name).ID() end, context)
    end
    if mq.TLO.Group.Members() and mq.TLO.Group.Members() > 0 then
        for i = 1, mq.TLO.Group.Members() do
            local grpmember = mq.TLO.Group.Member(i)
            if grpmember and grpmember.Class then
                local grpname = grpmember.Name()
                local grpid = grpmember.ID()
                local grpclass = grpmember.Class.ShortName()
                if grpid and grpid > 0 and grpclass then
                    if opts.excludeBotsFromGroup and charinfo.GetInfo(grpname) then
                        -- skip (already added in botsFirst or is a bot)
                    elseif opts.excludeSelfAndTank and context and (grpid == context.tankid or grpid == mq.TLO.Me.ID()) then
                        -- skip tank and self (heal/buff: tank only in tank phase; groupmember = not self, not tank)
                    else
                        out[#out + 1] = { id = grpid, targethit = grpclass:lower(), name = grpname }
                    end
                end
            end
        end
    end
    return out
end

function castutils.getTargetsPc(context, opts)
    local out = {}
    local bots = context.bots
    if not bots then return out end
    local filterFn = nil
    if opts and opts.excludeTank and context and context.tank then
        filterFn = function(name) return name ~= context.tank end
    end
    addPcEntries(out, bots, context.botcount, filterFn, context)
    return out
end

function castutils.getTargetsMypet()
    local out = {}
    local mypetid = mq.TLO.Me.Pet.ID()
    if mypetid and mypetid > 0 then out[#out + 1] = { id = mypetid, targethit = 'mypet' } end
    return out
end

function castutils.getTargetsPet(context)
    local out = {}
    if not context.bots then return out end
    local n = context.botcount or #context.bots
    local byName = context.peerByName
    for i = 1, n do
        local name = context.bots[i]
        local peer = (byName and byName[name]) or (name and charinfo.GetInfo(name))
        local petid = peer and peer.PetID
        if (not petid or petid <= 0) and name then
            petid = mq.TLO.Spawn('pc =' .. name).Pet.ID()
        end
        if petid and petid > 0 then out[#out + 1] = { id = petid, targethit = 'pet' } end
    end
    return out
end

function castutils.bandHasPhaseSimple(bandTable, spellIndex, phase)
    return bandTable[spellIndex] and bandTable[spellIndex][phase] and true or false
end

-- Get spawn HP and check band. spawnIdOrSpawn: spawn ID (number) or spawn-like object with PctHPs(). band: { min, max }.
function castutils.hpEvalSpawn(spawnIdOrSpawn, band)
    local pct
    if type(spawnIdOrSpawn) == 'number' then
        pct = mq.TLO.Spawn(spawnIdOrSpawn).PctHPs()
    else
        pct = spawnIdOrSpawn.PctHPs and spawnIdOrSpawn.PctHPs()
    end
    return pct and spellbands.hpInBand(pct, band)
end

function castutils.RegisterSectionLoader(section, settingsKey, loadFn)
    botconfig.RegisterConfigLoader(function()
        if botconfig.config.settings[settingsKey] then loadFn() end
    end)
end

return castutils
