local mq = require('mq')
local botconfig = require('lib.config')
local spellutils = require('lib.spellutils')
local state = require('lib.state')
local charinfo = require('plugin.charinfo')
local bothooks = require('lib.bothooks')
local castutils = require('lib.castutils')
local botmove = require('botmove')
local pcphasethrottle = require('lib.pcphasethrottle')
local charinfowatchers = require('lib.charinfowatchers')
local tickprof = require('lib.tickprof')

local botcure = {}
local CureClass = {}
local CureType = {}

local function defaultCureEntry()
    return botconfig.getDefaultSpellEntry('cure')
end

function botcure.LoadCureConfig()
    castutils.LoadSpellSectionConfig('cure', {
        defaultEntry = defaultCureEntry,
        bandsKey = 'cure',
        storeIn = CureClass,
        perEntryAfterBands = function(entry, i)
            CureType[i] = {}
            local list = entry.curetype
            if not list or #list == 0 then list = { 'all' } end
            for _, word in ipairs(list) do
                CureType[i][word] = word
            end
        end,
    })
    charinfowatchers.registerCureWatchers()
end

castutils.RegisterSectionLoader('cure', 'docure', botcure.LoadCureConfig)

local function CureTypeList(index)
    local list = {}
    for k in pairs(CureType[index] or {}) do list[#list + 1] = k end
    return list
end

--- Self / non-peer need check. Peers: watchlist already applied; only range.
local function CureEvalForTarget(index, botname, botid, botclass, targethit, spelltartype, resumePhase, resumeGroupIndex)
    local cureindex = CureClass[index]
    if not cureindex then return nil, nil end
    if not botname then
        if spellutils.MeDetrimentalsForCure(CureTypeList(index)) and targethit == 'self' then
            return mq.TLO.Me.ID(), 'self'
        end
        return nil, nil
    end
    if not botid or botid <= 0 then return nil, nil end

    if charinfo.GetInfo(botname) then
        if not spellutils.DistanceCheck('cure', index, botid) then return nil, nil end
        if targethit == 'tank' or targethit == 'offtank' or targethit == 'groupmember' or targethit == 'pc' then
            return botid, targethit
        end
        if type(targethit) == 'string' and cureindex[targethit] then
            return botid, targethit
        end
        return nil, nil
    end

    -- Non-peer: Spawn buff walk (only when nonPeerGroupMembers flag is set by caller).
    if not spellutils.EnsureSpawnBuffsPopulated(botid, 'cure', index, targethit, CureTypeList(index), resumePhase, resumeGroupIndex) then
        return nil, nil
    end
    if not spellutils.SpawnDetrimentalsForCure(botid, CureTypeList(index)) then return nil, nil end
    if not spellutils.DistanceCheck('cure', index, botid) then return nil, nil end
    if targethit == 'tank' or targethit == 'offtank' or targethit == 'groupmember' or targethit == 'pc' then
        return botid, targethit
    end
    return nil, nil
end

local function nonPeerCureNeeds(index)
    if not charinfowatchers.hasNonPeerGroupMembers() then return 0 end
    local typelist = CureTypeList(index)
    local n = 0
    for _, m in ipairs(charinfowatchers.getNonPeerGroupMembers()) do
        if m.id and m.id > 0
            and spellutils.EnsureSpawnBuffsPopulated(m.id, 'cure', index, 'groupcure', typelist, nil, nil)
            and spellutils.SpawnDetrimentalsForCure(m.id, typelist) then
            n = n + 1
        end
    end
    return n
end

local function CureEvalGroupCure(index, entry)
    local spellId = spellutils.GetSpellId(entry)
    if not spellId then return nil, nil end
    local typelist = CureTypeList(index)
    local function selfPasses()
        return spellutils.MeDetrimentalsForCure(typelist)
    end
    if not charinfowatchers.grpAggShouldCast('CURE', spellId, entry.tarcnt, selfPasses, nonPeerCureNeeds(index)) then
        return nil, nil
    end
    return mq.TLO.Me.ID(), 'groupcure'
end

local CURE_PHASE_ORDER = { 'self', 'tank', 'offtank', 'groupcure', 'groupmember', 'pc' }
local CURE_PHASE_ORDER_PRIORITY = { 'priority' }
local CURE_PHASE_ORDER_LOCAL = { 'self' }
local CURE_PHASE_ORDER_LOCAL_LIST = { 'self', 'tank', 'offtank' }

--- Tank only — peer targets come from CharInfo watch unions.
local function cureBuildContext()
    local tank, tankid = spellutils.GetTankInfo(false)
    return { tank = tank, tankid = tankid }
end

local function cureBandHasPhase(spellIndex, phase)
    return CureClass[spellIndex] and CureClass[spellIndex][phase] and true or false
end

local function curePhaseOrderForPass(requested)
    if requested and requested ~= CURE_PHASE_ORDER then
        return requested
    end
    local listIds = charinfowatchers.spellIdsForPhases('cure', { 'tank', 'offtank' }, cureBandHasPhase)
    local otherIds = charinfowatchers.spellIdsForPhases(
        'cure', { 'groupcure', 'groupmember', 'pc' }, cureBandHasPhase)
    local hasList = charinfowatchers.anyWatchNonEmpty('CURE', { 'LIST' }, listIds)
    local hasOther = charinfowatchers.anyWatchNonEmpty(
        'CURE', { 'INGROUP', 'ALL', 'GRPAGG' }, otherIds)
        or charinfowatchers.hasNonPeerGroupMembers()
    if hasOther then return CURE_PHASE_ORDER end
    if hasList then return CURE_PHASE_ORDER_LOCAL_LIST end
    return CURE_PHASE_ORDER_LOCAL
end

local function cureGetTargetsForPhase(phase, context, pcAllowed)
    if phase == 'priority' then
        local count = botconfig.getSpellCount('cure')
        if count <= 0 then return {} end
        local priorityIndices = spellutils.getSpellIndicesForPhase(count, 'priority', CureClass)
        if not priorityIndices or #priorityIndices == 0 then return {} end
        local needTypes = {}
        for _, i in ipairs(priorityIndices) do
            local band = CureClass[i]
            if band then
                for _, targetType in ipairs(CURE_PHASE_ORDER) do
                    if band[targetType] then needTypes[targetType] = true end
                end
            end
        end
        local out = {}
        for _, targetType in ipairs(CURE_PHASE_ORDER) do
            if needTypes[targetType] then
                if targetType == 'pc' and not pcAllowed then
                    -- skip throttled pc peer scan
                else
                    local list = cureGetTargetsForPhase(targetType, context, pcAllowed)
                    for _, t in ipairs(list) do out[#out + 1] = t end
                end
            end
        end
        return out
    end
    if phase == 'self' then return castutils.getTargetsSelf() end
    if phase == 'tank' or phase == 'offtank' or phase == 'groupmember' or phase == 'pc' then
        if phase == 'pc' and not pcAllowed then return {} end
        local count = botconfig.getSpellCount('cure')
        local out = charinfowatchers.unionTargetsForPhase('cure', phase, count, cureBandHasPhase)
        if phase == 'groupmember' and charinfowatchers.hasNonPeerGroupMembers() then
            local seen = {}
            for i = 1, #out do
                if out[i].id then seen[out[i].id] = true end
            end
            for _, m in ipairs(charinfowatchers.getNonPeerGroupMembers()) do
                if m.id and m.id > 0 and not seen[m.id] then
                    seen[m.id] = true
                    out[#out + 1] = { id = m.id, targethit = 'groupmember', name = m.name, nonPeer = true }
                end
            end
        end
        return out
    end
    if phase == 'groupcure' then return castutils.getTargetsGroupCaster('groupcure') end
    return {}
end

local function cureTargetNeedsSpell(spellIndex, targetId, targethit, context)
    return tickprof.span('needs', function()
        local entry = botconfig.getSpellEntry('cure', spellIndex)
        if not entry or not CureClass[spellIndex] then return nil, nil end
        local spell, _, spelltartype = spellutils.GetSpellInfo(entry)
        if not spell then return nil, nil end
        local botname = (targethit ~= 'self') and mq.TLO.Spawn(targetId).CleanName() or nil
        if targethit == 'self' then
            return CureEvalForTarget(spellIndex, nil, nil, nil, 'self', spelltartype)
        end
        if targethit == 'groupcure' then
            return CureEvalGroupCure(spellIndex, entry)
        end

        local watchScope = charinfowatchers.phaseToScope(targethit)
        if watchScope and watchScope ~= 'GRPAGG' then
            local spellId = spellutils.GetSpellId(entry)
            local onWatch = spellId and charinfowatchers.watchListHas('CURE', watchScope, spellId, targetId)
            if onWatch then
                if targethit == 'tank' then
                    local id, hit = CureEvalForTarget(spellIndex, context.tank, context.tankid, nil, 'tank', spelltartype, nil, nil)
                    if id == targetId then return id, hit end
                    return nil, nil
                end
                local id, hit = CureEvalForTarget(spellIndex, botname, targetId, nil, targethit, spelltartype, nil, nil)
                if id == targetId then return id, hit end
                return nil, nil
            end
            -- Non-peer groupmember merge: Spawn detrimentals when flag is set.
            if targethit == 'groupmember' and charinfowatchers.hasNonPeerGroupMembers() then
                local id, hit = CureEvalForTarget(spellIndex, botname, targetId, nil, 'groupmember', spelltartype, nil, nil)
                if id == targetId then return id, hit end
            end
            return nil, nil
        end

        local id, hit = CureEvalForTarget(spellIndex, botname, targetId, targethit, targethit, spelltartype, nil, nil)
        if id == targetId then return id, hit end
        return nil, nil
    end)
end

function botcure.CureCheck(runPriority, phaseOrder, hookName)
    phaseOrder = curePhaseOrderForPass(phaseOrder)
    hookName = hookName or 'doCure'
    local myconfig = botconfig.config
    if state.getRunconfig().SpellTimer > mq.gettime() then return false end
    local count = botconfig.getSpellCount('cure')
    if count <= 0 then return false end
    local ctx = tickprof.span('context', function()
        return cureBuildContext()
    end)
    spellutils.setMeDetrimentalsCureCache(spellutils.buildMeDetrimentalsCureCache())
    local options = {
        skipInterruptForBRD = true,
        runPriority = runPriority,
        entryValid = function(i)
            local entry = botconfig.getSpellEntry('cure', i)
            if not entry then return false end
            local gem = entry.gem
            return (entry.enabled ~= false) and ((type(gem) == 'number' and gem ~= 0) or type(gem) == 'string')
        end,
    }
    local function getSpellIndices(phase, _target)
        return spellutils.getSpellIndicesForPhase(count, phase, CureClass)
    end
    local cursor = spellutils.getResumeCursor(hookName)
    local pcAllowed = pcphasethrottle.allow('cure', cursor)
    local function getTargets(phase, context)
        return tickprof.span('targets', function()
            return cureGetTargetsForPhase(phase, context, pcAllowed)
        end)
    end
    local result = tickprof.span('spellcheck', function()
        return spellutils.RunPhaseFirstSpellCheck('cure', hookName, phaseOrder, getTargets, getSpellIndices,
            cureTargetNeedsSpell, ctx, options)
    end)
    spellutils.clearMeDetrimentalsCureCache()
    return result
end

function botcure.getHookFn(name)
    if name == 'priorityCure' then
        return function(hookName)
            local myconfig = botconfig.config
            if state.isTravelMode() and not state.isTravelAttackOverriding() then return end
            if botmove.isBeyondFollowDistance() then return end
            if not (myconfig.settings.docure or state.isTravelAttackOverriding()) or not (myconfig.cure.spells and #myconfig.cure.spells > 0) then return end
            local count = botconfig.getSpellCount('cure')
            if count <= 0 then return end
            local priorityIndices = spellutils.getSpellIndicesForPhase(count, 'priority', CureClass)
            if not priorityIndices or #priorityIndices == 0 then return end
            if state.getRunState() == state.STATES.idle then state.getRunconfig().statusMessage = 'Cure Check' end
            botcure.CureCheck(bothooks.getPriority(hookName), CURE_PHASE_ORDER_PRIORITY, 'priorityCure')
        end
    end
    if name == 'doCure' then
        return function(hookName)
            local myconfig = botconfig.config
            if state.isTravelMode() and not state.isTravelAttackOverriding() then return end
            if botmove.isBeyondFollowDistance() then return end
            if not (myconfig.settings.docure or state.isTravelAttackOverriding()) or not (myconfig.cure.spells and #myconfig.cure.spells > 0) then return end
            if state.getRunState() == state.STATES.idle then state.getRunconfig().statusMessage = 'Cure Check' end
            botcure.CureCheck(bothooks.getPriority(hookName), CURE_PHASE_ORDER, 'doCure')
        end
    end
    return nil
end

return botcure
