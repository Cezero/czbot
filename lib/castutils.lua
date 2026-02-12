local mq = require('mq') ---@cast mq mq
local botconfig = require('lib.config')
local spellbands = require('lib.spellbands')
local state = require('lib.state')
local utils = require('lib.utils')
local charinfo = require('mqcharinfo')
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
    while #spells < 2 do
        table.insert(spells, opts.defaultEntry())
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
        if tartype == 'Group v1' then return 1, targethit end
        return mq.TLO.Me.ID(), targethit
    end
    return nil, nil
end

-- Shared get-targets helpers for buff/cure/heal GetTargetsForPhase.
-- opts for getTargetsGroupMember: botsFirst (add bots in group first), excludeBotsFromGroup (in group loop skip names that have charinfo).
local function addPcEntries(out, names, count, filterFn)
    if not names then return end
    count = count or #names
    for i = 1, count do
        local name = names[i]
        if name and (not filterFn or filterFn(name)) then
            local id = mq.TLO.Spawn('pc =' .. name).ID()
            local class = mq.TLO.Spawn('pc =' .. name).Class.ShortName()
            if id and id > 0 and class then out[#out + 1] = { id = id, targethit = class:lower() } end
        end
    end
end

function castutils.getTargetsSelf()
    local out = {}
    local myid = mq.TLO.Me.ID()
    if myid and myid > 0 then out[#out + 1] = { id = myid, targethit = 'self' } end
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
        addPcEntries(out, context.bots, #context.bots, function(name) return mq.TLO.Group.Member(name).ID() end)
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
                    else
                        out[#out + 1] = { id = grpid, targethit = grpclass:lower() }
                    end
                end
            end
        end
    end
    return out
end

function castutils.getTargetsPc(context)
    local out = {}
    local bots = context.bots
    if not bots then return out end
    addPcEntries(out, bots, context.botcount, nil)
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
    for i = 1, n do
        local petid = mq.TLO.Spawn('pc =' .. context.bots[i]).Pet.ID()
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
