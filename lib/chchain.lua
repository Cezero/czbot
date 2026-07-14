-- CH Chain (Complete Heal chain): czactor control plane, chV2 poll-based cast logic.
-- Healers: cz_common ch_healers. Tanks: mt_list via lib/auto_ma_mt.

local mq = require('mq')
local botconfig = require('lib.config')
local state = require('lib.state')
local bothooks = require('lib.bothooks')
local targeting = require('lib.targeting')
local spellutils = require('lib.spellutils')
local casting = require('lib.casting')
local utils = require('lib.utils')
local czactor = require('lib.czactor')
local czactor_dispatch = require('lib.czactor_dispatch')
local auto_ma_mt = require('lib.auto_ma_mt')
local tankrole = require('lib.tankrole')
local log = require('lib.log')

local chchain = {}

local CH_TARGET_WAIT_MS = 200
local EVENT_PUMP_MS = 50
local MANA_SKIP_BUFFER = 400

local DEFAULT_CH_CHAIN = {
    enabled = true,
    broadcastDelayMs = 5000,
    cancelWindowMs = 500,
    healthThreshold = 95,
    castStartTimeoutMs = 1500,
    mirrorEnabled = false,
    mirrorChannel = 'rsay',
    mirrorCasts = false,
    clickyEnabled = false,
    clickyItem = 'None',
}

local MIRROR_CHANNELS = { 'rsay', 'shout', 'gsay', 'ooc', 'say' }

local function meName()
    return mq.TLO.Me.CleanName() or mq.TLO.Me.Name()
end

local function namesEqual(a, b)
    if not a or not b then return false end
    return string.lower(a) == string.lower(b)
end

local function nextBatonSeq(rc)
    rc.chchainBatonSeq = (rc.chchainBatonSeq or 0) + 1
    return rc.chchainBatonSeq
end

local function mergeDefaults(settings)
    settings = settings or {}
    local out = {}
    for k, v in pairs(DEFAULT_CH_CHAIN) do
        out[k] = settings[k]
        if out[k] == nil then out[k] = v end
    end
    return out
end

function chchain.getSettings()
    local common = botconfig.getCommon()
    return mergeDefaults(common.ch_chain)
end

function chchain.ensureDefaultsInCommon()
    local common = botconfig.getCommon()
    if type(common.ch_chain) ~= 'table' then
        botconfig.mutateCommon(function(c)
            if type(c.ch_chain) ~= 'table' then
                c.ch_chain = mergeDefaults(nil)
            end
        end)
    end
end

function chchain.saveSettings(partial)
    if type(partial) ~= 'table' then return end
    botconfig.mutateCommon(function(common)
        common.ch_chain = mergeDefaults(common.ch_chain)
        for k, v in pairs(partial) do
            common.ch_chain[k] = v
        end
    end)
end

function chchain.mirrorSay(fmt, ...)
    local settings = chchain.getSettings()
    if not settings.mirrorEnabled then return end
    local channel = settings.mirrorChannel or 'rsay'
    local msg = string.format(fmt, ...)
    mq.cmdf('/%s %s', channel, msg)
end

function chchain.publishBaton(healerName, tankName)
    local rc = state.getRunconfig()
    local seq = nextBatonSeq(rc)
    czactor.publish('chchain_baton', {
        healer = healerName,
        seq = seq,
        tank = tankName or rc.chchainTank,
    })
    chchain.mirrorSay('your next %s', healerName or '?')
end

function chchain.publishControl(action, healerName)
    czactor.publish('chchain_control', {
        action = action,
        healer = healerName,
    })
end

local function isTankInCHRange(tankid)
    local spellRange = mq.TLO.Spell('Complete Heal').MyRange()
    if not spellRange or spellRange <= 0 then return true end
    local sp = mq.TLO.Spawn(tankid)
    if not sp or not sp.ID() or sp.ID() == 0 then return false end
    local distSq = utils.getDistanceSquared3D(mq.TLO.Me.X(), mq.TLO.Me.Y(), mq.TLO.Me.Z(), sp.X(), sp.Y(), sp.Z())
    return distSq and distSq <= (spellRange * spellRange)
end

local function safeTankHp(name)
    if not name or name == '' then return 0 end
    local sp = mq.TLO.Spawn('pc =' .. name)
    if sp and sp.ID() and sp.ID() > 0 then
        local hp = sp.PctHPs()
        if type(hp) == 'number' then return hp end
    end
    return 0
end

local function advanceCurtank(rc, index, tankName)
    if not rc.doChchain then return false end
    if not index or not tankName or tankName == '' then return false end
    local cur = rc.chchainCurtank or 1
    if index < cur then return false end
    rc.chchainCurtank = index
    rc.chchainTank = tankName
    return true
end

--- Local curtank index sync when MT changes (im_mt / mt_update). Does not broadcast.
function chchain.syncCurtankFromMtName(name, reason)
    if not name or name == '' then return end
    local rc = state.getRunconfig()
    if not rc.doChchain then return end
    local curtank = auto_ma_mt.handleMtOverride(name, reason)
    if curtank and curtank.index and curtank.tank then
        advanceCurtank(rc, curtank.index, curtank.tank)
    end
end

local function applyCurtank(content, sender)
    local rc = state.getRunconfig()
    if not rc.doChchain then return end
    local idx = tonumber(content.index)
    local name = content.tank
    if not idx or not name or name == '' then return end
    local prev = rc.chchainCurtank or 1
    if idx < prev then
        printf('CHChain curtank ignored (stale) from %s: index=%s tank=%s', tostring(sender), tostring(idx), tostring(name))
        return
    end
    advanceCurtank(rc, idx, name)
end

local function selectHealTank(rc)
    local list = rc.MtList
    if not list or #list == 0 then return nil end
    local startIdx = rc.chchainCurtank or 1
    local tid, idx, name = auto_ma_mt.firstAliveMtFromIndex(list, startIdx, isTankInCHRange)
    if tid and idx and name then
        local prev = rc.chchainCurtank or 1
        if advanceCurtank(rc, idx, name) and idx > prev then
            czactor.publish('chchain_curtank', { index = idx, tank = name })
        end
        return tid, name
    end
    return nil
end

local function getMyHealerIndex()
    local my = meName()
    if not my then return 1 end
    local list = state.getRunconfig().ChHealers or {}
    for i, name in ipairs(list) do
        if namesEqual(name, my) then return i end
    end
    return 1
end

local function getNextHealerName()
    local list = state.getRunconfig().ChHealers or {}
    if #list < 2 then return list[1] end
    local idx = getMyHealerIndex()
    return list[(idx % #list) + 1]
end

local function computeNextClr(me)
    local list = state.getRunconfig().ChHealers or {}
    if #list == 0 then return nil end
    for i, name in ipairs(list) do
        if namesEqual(name, me) then
            if i < #list then return list[i + 1] end
            return list[1]
        end
    end
    return list[1]
end

local function findCompleteHealGem()
    for i = 1, 12 do
        local g = mq.TLO.Me.Gem(i)
        if g and g.Name() and g.Name():lower():find('complete heal', 1, true) then
            return i
        end
    end
    return nil
end

local function useClickyIfEnabled()
    local settings = chchain.getSettings()
    if not settings.clickyEnabled or settings.clickyItem == 'None' or settings.clickyItem == '' then return end
    if mq.TLO.Me.Casting() then return end
    if not mq.TLO.FindItem(settings.clickyItem)() then return end
    mq.cmd('/useitem "' .. settings.clickyItem .. '"')
end

local function suppressNormalActivity()
    local rc = state.getRunconfig()
    if rc.PreCH then return end
    rc.PreCH = {
        dodebuff = botconfig.config.settings.dodebuff,
        dobuff = botconfig.config.settings.dobuff,
        domelee = botconfig.config.settings.domelee,
        doheal = botconfig.config.settings.doheal,
        docure = botconfig.config.settings.docure,
        dopull = rc.dopull,
    }
    botconfig.config.settings.dodebuff = false
    botconfig.config.settings.dobuff = false
    botconfig.config.settings.domelee = false
    botconfig.config.settings.doheal = false
    botconfig.config.settings.docure = false
    rc.dopull = false
end

local function restorePreCH()
    local rc = state.getRunconfig()
    local pre = rc.PreCH
    if not pre then return end
    if pre.dodebuff ~= nil then botconfig.config.settings.dodebuff = pre.dodebuff end
    if pre.dobuff ~= nil then botconfig.config.settings.dobuff = pre.dobuff end
    if pre.domelee ~= nil then botconfig.config.settings.domelee = pre.domelee end
    if pre.doheal ~= nil then botconfig.config.settings.doheal = pre.doheal end
    if pre.docure ~= nil then botconfig.config.settings.docure = pre.docure end
    if pre.dopull ~= nil then rc.dopull = pre.dopull end
    rc.PreCH = nil
end

local function persistDoChchain(value)
    local s = botconfig.config.settings
    if s.doChchain == value then return end
    s.doChchain = value
    botconfig.ApplyAndPersist()
end

--- Arm/disarm local participation without touching settings persist.
local function armLocal(quiet)
    if not chchain.isMeInHealerList() then
        if not quiet then
            log.say('CHChain: %s not in ch_healers', meName() or '?')
        end
        return false
    end
    if not mq.TLO.Me.Book('complete heal')() then
        if not quiet then
            log.say('CHChain: Complete Heal not in book')
        end
        return false
    end
    local rc = state.getRunconfig()
    rc.doChchain = true
    rc.chnextClr = computeNextClr(meName())
    rc.chchainCurtank = 1
    if rc.MtList and rc.MtList[1] then
        rc.chchainTank = rc.MtList[1]
    end
    rc.chchainBatonSeq = 0
    -- Late join while an active chain is already running.
    if rc.chainActive then
        suppressNormalActivity()
    end
    return true
end

local function disarmLocal()
    local rc = state.getRunconfig()
    rc.doChchain = false
    rc.chainActive = false
    restorePreCH()
    state.clearRunState()
end

function chchain.isMeInHealerList()
    local me = meName()
    if not me then return false end
    for _, name in ipairs(state.getRunconfig().ChHealers or {}) do
        if namesEqual(name, me) then return true end
    end
    return false
end

--- First name in ch_healers (kickoff target for remote start).
function chchain.getFirstHealer()
    local list = state.getRunconfig().ChHealers or {}
    local name = list[1]
    if not name or name == '' then return nil end
    return name
end

--- Feature flag: this cleric participates when the chain runs. Does not suppress heals until active.
function chchain.enable()
    if not armLocal(false) then return false end
    persistDoChchain(true)
    log.say('CHChain enabled (next: %s)', tostring(state.getRunconfig().chnextClr))
    return true
end

function chchain.disable()
    disarmLocal()
    persistDoChchain(false)
    log.say('CHChain disabled')
end

--- Start/stop the live rotation. Suppresses normal activity only for enabled clerics.
function chchain.setChainActive(active)
    local rc = state.getRunconfig()
    if active then
        rc.chainActive = true
        if rc.doChchain then
            suppressNormalActivity()
        end
    else
        rc.chainActive = false
        restorePreCH()
        state.clearRunState()
    end
end

--- Mirror persisted settings.doChchain into runconfig (no suppress unless chain already active).
function chchain.applyFromSettings()
    local settings = botconfig.config and botconfig.config.settings
    if not settings then return end
    local want = settings.doChchain == true
    local rc = state.getRunconfig()
    if want then
        if not chchain.isMeInHealerList() then
            if rc.doChchain or rc.PreCH then
                rc.doChchain = false
                restorePreCH()
                state.clearRunState()
            end
            return
        end
        if not rc.doChchain then
            armLocal(true)
        end
    elseif rc.doChchain or rc.PreCH then
        disarmLocal()
    end
end

local function passBaton(rc)
    local nextName = getNextHealerName()
    if not nextName then return end
    chchain.publishBaton(nextName, rc.chchainTank)
end

local function beginCastState(tankName, castStartMs)
    local settings = chchain.getSettings()
    state.setRunState(state.STATES.chchain, {
        tank = tankName,
        castStart = castStartMs or mq.gettime(),
        broadcasted = false,
        cancelled = false,
        priority = bothooks.getPriority('chchainTick'),
    })
end

function chchain.startCast(testOnly)
    local rc = state.getRunconfig()
    local settings = chchain.getSettings()
    if not rc.doChchain then return false end
    if not testOnly and not rc.chainActive then return false end
    if state.getRunState() == state.STATES.chchain then return false end

    local tankid, tankName = selectHealTank(rc)
    if not tankid or not tankName then
        log.say('CHChain: no alive tank in mt_list')
        chchain.mirrorSay('No alive tank!')
        if not testOnly then passBaton(rc) end
        return false
    end

    if mq.TLO.Target.ID() ~= tankid then
        targeting.TargetAndWait(tankid, CH_TARGET_WAIT_MS)
    end
    if mq.TLO.Target.ID() ~= tankid then
        log.say('CHChain: failed to target %s', tankName)
        if not testOnly then passBaton(rc) end
        return false
    end

    if (mq.TLO.Me.CurrentMana() - (mq.TLO.Me.ManaRegen() * 2)) < MANA_SKIP_BUFFER then
        log.say('CHChain: skip (out of mana)')
        chchain.mirrorSay('skip (out of mana)')
        if not testOnly then passBaton(rc) end
        return false
    end

    local gem = findCompleteHealGem()
    if not gem then
        log.say('CHChain: Complete Heal not memorized')
        chchain.mirrorSay('Complete Heal not memorized - cannot chain!')
        return false
    end

    spellutils.AutoinvIfCursorBlockingCast()
    mq.cmdf('/casting "Complete Heal|gem%d"', gem)

    local waited = 0
    while not mq.TLO.Me.Casting() and waited < settings.castStartTimeoutMs do
        mq.doevents()
        mq.delay(EVENT_PUMP_MS)
        waited = waited + EVENT_PUMP_MS
    end
    if not mq.TLO.Me.Casting() then
        log.say('CHChain: cast failed to start')
        return false
    end

    if settings.mirrorCasts then
        chchain.mirrorSay('Casting CH on %s', tankName)
    end

    beginCastState(tankName, mq.gettime())
    return true
end

--- Raid-wide kickoff: publish first ch_healers entry. Safe from any bot (driver hotkey).
function chchain.requestKickoff()
    local firstHealer = chchain.getFirstHealer()
    if not firstHealer then
        log.say('CHChain: ch_healers is empty')
        return false
    end

    chchain.publishControl('kickoff', firstHealer)

    local rc = state.getRunconfig()
    local me = meName()
    local amKickoff = me and namesEqual(firstHealer, me)

    if amKickoff then
        if not rc.doChchain then
            if not chchain.enable() then return false end
            rc = state.getRunconfig()
        end
        chchain.setChainActive(true)
        rc.chchainBatonSeq = 0
        chchain.startCast(false)
        return true
    end

    if rc.doChchain then
        chchain.setChainActive(true)
    else
        log.say('CHChain kickoff -> %s', firstHealer)
    end
    return true
end

local function onBaton(content)
    local rc = state.getRunconfig()
    if not rc.doChchain or not rc.chainActive then return end
    local healer = content.healer
    if not healer or not namesEqual(healer, meName()) then return end
    local seq = tonumber(content.seq) or 0
    if seq > 0 and seq <= (rc.chchainBatonSeq or 0) then return end
    if seq > 0 then rc.chchainBatonSeq = seq end
    if content.tank and content.tank ~= '' then
        local idx = auto_ma_mt.indexInList(rc.MtList, content.tank)
        if idx then advanceCurtank(rc, idx, content.tank) end
    end
    chchain.startCast(false)
end

local function onControl(content)
    local action = content.action
    local rc = state.getRunconfig()
    if action == 'start' then
        if not rc.doChchain then return end
        chchain.setChainActive(true)
    elseif action == 'stop' then
        chchain.setChainActive(false)
    elseif action == 'kickoff' then
        if not rc.doChchain then return end
        chchain.setChainActive(true)
        local healer = content.healer
        if healer and namesEqual(healer, meName()) then
            rc.chchainBatonSeq = 0
            chchain.startCast(false)
        end
    end
end

function chchain.registerEvents()
    -- CH chain control is czactor-only; no chat events.
end

function chchain.registerActorHandlers()
    czactor_dispatch.RegisterHandler('chchain_curtank', applyCurtank)
    czactor_dispatch.RegisterHandler('chchain_baton', onBaton)
    czactor_dispatch.RegisterHandler('chchain_control', onControl)
end

function chchain.Tick()
    local p = state.getRunStatePayload()
    if not p or not p.tank then
        state.clearRunState()
        return
    end

    local rc = state.getRunconfig()
    local settings = chchain.getSettings()
    local tank = p.tank

    if casting.result() == 'CAST_FIZZLE' then
        spellutils.AutoinvIfCursorBlockingCast()
        casting.clear()
        local gem = findCompleteHealGem()
        if gem then mq.cmdf('/casting "Complete Heal|gem%d"', gem) end
        p.castStart = mq.gettime()
        p.broadcasted = false
        return
    end

    if mq.TLO.Me.CastTimeLeft() and mq.TLO.Me.CastTimeLeft() > 0 and mq.TLO.Target.Type() == 'Corpse' then
        casting.interrupt()
        chchain.mirrorSay('target died, passing baton')
        passBaton(rc)
        state.clearRunState()
        return
    end

    if mq.TLO.Me.Casting() and (mq.TLO.Me.CastTimeLeft() or 0) > 0 then
        local elapsed = mq.gettime() - (p.castStart or mq.gettime())
        if not p.broadcasted and elapsed >= settings.broadcastDelayMs then
            passBaton(rc)
            p.broadcasted = true
        end
        if (mq.TLO.Me.CastTimeLeft() or 0) <= settings.cancelWindowMs then
            local hp = safeTankHp(tank)
            if hp >= settings.healthThreshold then
                mq.cmd('/stopcast')
                p.cancelled = true
                chchain.mirrorSay('Stopped CH - %s at %d%%', tank, hp)
                state.clearRunState()
                return
            end
        end
        return
    end

    if not p.broadcasted then
        passBaton(rc)
    end

    if not p.cancelled then
        useClickyIfEnabled()
    end
    state.clearRunState()
end

function chchain.getHookFn(name)
    if name == 'chchainTick' then
        return function(_hookName)
            if state.getRunState() ~= state.STATES.chchain then return end
            chchain.Tick()
        end
    end
    return nil
end

chchain.MIRROR_CHANNELS = MIRROR_CHANNELS
chchain.DEFAULT_CH_CHAIN = DEFAULT_CH_CHAIN

botconfig.RegisterConfigLoader(chchain.applyFromSettings)
czactor.setMtNameChangedHook(chchain.syncCurtankFromMtName)

return chchain
