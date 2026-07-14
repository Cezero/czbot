-- CH Chain (Complete Heal chain): absolute slot clock + czactor start/stop control.
-- Healers: cz_common ch_healers. Tanks: mt_list via lib/auto_ma_mt.
-- Each participating cleric schedules casts locally (no baton messaging).

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
local log = require('lib.log')

local chchain = {}

local CH_TARGET_WAIT_MS = 200
local EVENT_PUMP_MS = 50
local MANA_SKIP_BUFFER = 400
local FIRE_WINDOW_MS = 250

local DEFAULT_CH_CHAIN = {
    enabled = true,
    delayMs = 2500,
    startCountdownMs = 3000,
    preCastHpCheckMs = 9500,
    healthThreshold = 98,
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

--- Migrate legacy baton-era keys into slot-clock settings.
local function migrateLegacy(settings)
    settings = settings or {}
    if settings.delayMs == nil and settings.broadcastDelayMs ~= nil then
        settings.delayMs = settings.broadcastDelayMs
    end
    -- cancelWindowMs has no 1:1 mapping; preCastHpCheckMs uses the new default.
    return settings
end

local function mergeDefaults(settings)
    settings = migrateLegacy(settings)
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
        -- Drop legacy keys when writing new values.
        if partial.delayMs ~= nil then
            common.ch_chain.broadcastDelayMs = nil
        end
        if partial.preCastHpCheckMs ~= nil then
            common.ch_chain.cancelWindowMs = nil
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

local function findCompleteHealGem()
    for i = 1, 12 do
        local g = mq.TLO.Me.Gem(i)
        if g and g.Name() and g.Name():lower():find('complete heal', 1, true) then
            return i
        end
    end
    return nil
end

--- Start Complete Heal via lib.casting (/cast gem), not MQ2Cast /casting.
---@param tankid number
---@return boolean started
local function startCompleteHealCast(tankid)
    local gem = findCompleteHealGem()
    if not gem then return false end
    spellutils.AutoinvIfCursorBlockingCast()
    return casting.start({
        spellName = 'Complete Heal',
        gemType = gem,
        targetId = tankid,
        maxTries = 1,
    }) == true
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

function chchain.isMeInHealerList()
    local me = meName()
    if not me then return false end
    for _, name in ipairs(state.getRunconfig().ChHealers or {}) do
        if namesEqual(name, me) then return true end
    end
    return false
end

--- Assign slot from ch_healers order (1-based). Nil if not in list.
function chchain.refreshMySlot()
    local rc = state.getRunconfig()
    rc.chchainMySlot = nil
    local me = meName()
    if not me then return nil end
    for i, name in ipairs(rc.ChHealers or {}) do
        if namesEqual(name, me) then
            rc.chchainMySlot = i
            return i
        end
    end
    return nil
end

--- First name in ch_healers (validation for remote start).
function chchain.getFirstHealer()
    local list = state.getRunconfig().ChHealers or {}
    local name = list[1]
    if not name or name == '' then return nil end
    return name
end

--- ms until this bot's next slot fire; countdown leftover if before chainStart.
function chchain.timeUntilMyCH()
    local rc = state.getRunconfig()
    local settings = chchain.getSettings()
    local healers = rc.ChHealers or {}
    if not rc.chainActive or not rc.chchainMySlot or #healers == 0 then return 999999 end
    local chainStart = rc.chchainStart or 0
    local elapsed = mq.gettime() - chainStart
    if elapsed < 0 then return -elapsed end
    local delayMs = settings.delayMs or DEFAULT_CH_CHAIN.delayMs
    local fullCycleMs = delayMs * #healers
    if fullCycleMs <= 0 then return 999999 end
    local slotTime = (rc.chchainMySlot - 1) * delayMs
    local timeIntoCycle = elapsed % fullCycleMs
    local untilMyCast = slotTime - timeIntoCycle
    if untilMyCast < 0 then untilMyCast = untilMyCast + fullCycleMs end
    return untilMyCast
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
    chchain.refreshMySlot()
    rc.chchainCurtank = 1
    if rc.MtList and rc.MtList[1] then
        rc.chchainTank = rc.MtList[1]
    end
    if rc.chainActive then
        suppressNormalActivity()
    end
    return true
end

local function disarmLocal()
    local rc = state.getRunconfig()
    rc.doChchain = false
    rc.chainActive = false
    rc.chchainStart = nil
    rc.chchainLastCastCycle = -1
    rc.chchainPendingCheck = nil
    rc.chchainMySlot = nil
    restorePreCH()
    state.clearRunState()
end

--- Feature flag: this cleric participates when the chain runs. Does not suppress heals until active.
function chchain.enable()
    if not armLocal(false) then return false end
    persistDoChchain(true)
    log.say('CHChain enabled (slot: %s)', tostring(state.getRunconfig().chchainMySlot))
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
        rc.chchainStart = nil
        rc.chchainLastCastCycle = -1
        rc.chchainPendingCheck = nil
        restorePreCH()
        state.clearRunState()
    end
end

--- Arm shared slot clock (local). Call on start/kickoff for participating bots.
function chchain.beginSchedule()
    local rc = state.getRunconfig()
    if not rc.doChchain then return false end
    local settings = chchain.getSettings()
    chchain.setChainActive(true)
    chchain.refreshMySlot()
    rc.chchainStart = mq.gettime() + (settings.startCountdownMs or DEFAULT_CH_CHAIN.startCountdownMs)
    rc.chchainLastCastCycle = -1
    rc.chchainPendingCheck = nil
    rc.chchainCurtank = 1
    rc.chchainArmedAt = mq.gettime()
    if rc.MtList and rc.MtList[1] then
        rc.chchainTank = rc.MtList[1]
    end
    if rc.chchainMySlot then
        log.say('CHChain starting in %dms (slot %d)', settings.startCountdownMs or DEFAULT_CH_CHAIN.startCountdownMs, rc.chchainMySlot)
    else
        log.say('CHChain starting (not in ch_healers)')
    end
    return true
end

--- Local stop: interrupt if casting in chain, clear schedule.
function chchain.endSchedule()
    local rc = state.getRunconfig()
    if rc.chchainMySlot and (mq.TLO.Me.Casting() or state.getRunState() == state.STATES.chchain) then
        casting.interrupt()
    end
    chchain.setChainActive(false)
end

--- Raid-wide stop from any bot.
function chchain.requestStop()
    chchain.endSchedule()
    chchain.publishControl('stop')
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
        else
            chchain.refreshMySlot()
        end
    elseif rc.doChchain or rc.PreCH then
        disarmLocal()
    end
end

local function beginCastState(tankName, castStartMs, tankid)
    local rc = state.getRunconfig()
    local now = castStartMs or mq.gettime()
    rc.chchainPendingCheck = {
        tank = tankName,
        targetId = tankid,
        castStart = now,
        checked = false,
    }
    state.setRunState(state.STATES.chchain, {
        tank = tankName,
        castStart = now,
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
        return false
    end

    if mq.TLO.Target.ID() ~= tankid then
        targeting.TargetAndWait(tankid, CH_TARGET_WAIT_MS)
    end
    if mq.TLO.Target.ID() ~= tankid then
        log.say('CHChain: failed to target %s', tankName)
        return false
    end

    if (mq.TLO.Me.CurrentMana() - (mq.TLO.Me.ManaRegen() * 2)) < MANA_SKIP_BUFFER then
        log.say('CHChain: skip (out of mana)')
        chchain.mirrorSay('skip (out of mana)')
        return false
    end

    local gem = findCompleteHealGem()
    if not gem then
        log.say('CHChain: Complete Heal not memorized')
        chchain.mirrorSay('Complete Heal not memorized - cannot chain!')
        return false
    end

    if not startCompleteHealCast(tankid) then
        log.say('CHChain: cast failed to start')
        return false
    end

    local waited = 0
    while waited < settings.castStartTimeoutMs do
        casting.tick()
        mq.doevents()
        local status = casting.status() or ''
        if mq.TLO.Me.Casting() or status:find('C', 1, true) then
            break
        end
        mq.delay(EVENT_PUMP_MS)
        waited = waited + EVENT_PUMP_MS
    end
    casting.tick()
    local status = casting.status() or ''
    if not mq.TLO.Me.Casting() and not status:find('C', 1, true) then
        log.say('CHChain: cast failed to start')
        return false
    end

    if settings.mirrorCasts then
        chchain.mirrorSay('Casting CH on %s', tankName)
    end

    beginCastState(tankName, mq.gettime(), tankid)
    return true
end

--- Raid-wide start: local participants arm first; publish for peers (onControl debounces self-echo).
function chchain.requestKickoff()
    if not chchain.getFirstHealer() then
        log.say('CHChain: ch_healers is empty')
        return false
    end

    local rc = state.getRunconfig()
    if rc.doChchain then
        chchain.beginSchedule()
    else
        log.say('CHChain start published (slot clock)')
    end
    chchain.publishControl('kickoff')
    return true
end

local function onControl(content)
    local action = content.action
    local rc = state.getRunconfig()
    if action == 'start' or action == 'kickoff' then
        if not rc.doChchain then return end
        -- Skip if we already armed locally in the last second (self-echo of our publish).
        if rc.chchainArmedAt and (mq.gettime() - rc.chchainArmedAt) < 1000 then
            return
        end
        chchain.beginSchedule()
    elseif action == 'stop' then
        chchain.endSchedule()
    end
end

function chchain.registerEvents()
    -- CH chain control is czactor-only; no chat events.
end

function chchain.registerActorHandlers()
    czactor_dispatch.RegisterHandler('chchain_curtank', applyCurtank)
    czactor_dispatch.RegisterHandler('chchain_control', onControl)
end

local function preLandHpCheck()
    local rc = state.getRunconfig()
    local pending = rc.chchainPendingCheck
    if not pending then return end

    if not mq.TLO.Me.Casting() then
        rc.chchainPendingCheck = nil
        return
    end
    if pending.checked then return end

    local settings = chchain.getSettings()
    local elapsed = mq.gettime() - (pending.castStart or mq.gettime())
    if elapsed < (settings.preCastHpCheckMs or DEFAULT_CH_CHAIN.preCastHpCheckMs) then return end

    pending.checked = true
    local tank = pending.tank
    local hp = safeTankHp(tank)
    if hp >= (settings.healthThreshold or DEFAULT_CH_CHAIN.healthThreshold) then
        casting.interrupt()
        chchain.mirrorSay('Stopped CH - %s at %d%%', tank or '?', hp)
        local p = state.getRunStatePayload()
        if p then p.cancelled = true end
        rc.chchainPendingCheck = nil
        state.clearRunState()
    else
        rc.chchainPendingCheck = nil
    end
end

local function slotScheduleTick()
    local rc = state.getRunconfig()
    if not rc.chainActive or not rc.doChchain then return end
    if not rc.chchainMySlot then return end

    local healers = rc.ChHealers or {}
    local tanks = rc.MtList or {}
    if #healers == 0 or #tanks == 0 then return end
    if not rc.chchainStart then return end

    local elapsed = mq.gettime() - rc.chchainStart
    if elapsed < 0 then return end

    local settings = chchain.getSettings()
    local delayMs = settings.delayMs or DEFAULT_CH_CHAIN.delayMs
    local fullCycleMs = delayMs * #healers
    if fullCycleMs <= 0 then return end

    local cycle = math.floor(elapsed / fullCycleMs)
    local slotTime = (rc.chchainMySlot - 1) * delayMs
    local timeIntoCycle = elapsed % fullCycleMs

    if cycle == (rc.chchainLastCastCycle or -1) then return end

    if timeIntoCycle >= slotTime and timeIntoCycle < slotTime + FIRE_WINDOW_MS then
        -- Consume cycle even if cast fails (mana/tank) so we don't spam the fire window.
        rc.chchainLastCastCycle = cycle
        if state.getRunState() ~= state.STATES.chchain then
            chchain.startCast(false)
        end
    end
end

local function castPollTick()
    if state.getRunState() ~= state.STATES.chchain then return end

    casting.tick()

    local p = state.getRunStatePayload()
    if not p or not p.tank then
        state.clearRunState()
        return
    end

    local rc = state.getRunconfig()
    local tank = p.tank

    if casting.result() == 'CAST_FIZZLE' then
        casting.clear()
        local tankid = mq.TLO.Spawn('pc =' .. tank).ID() or 0
        if tankid <= 0 then
            tankid = selectHealTank(rc)
        end
        if tankid and tankid > 0 and startCompleteHealCast(tankid) then
            local now = mq.gettime()
            p.castStart = now
            if rc.chchainPendingCheck then
                rc.chchainPendingCheck.castStart = now
                rc.chchainPendingCheck.checked = false
            end
        end
        return
    end

    if mq.TLO.Me.CastTimeLeft() and mq.TLO.Me.CastTimeLeft() > 0 and mq.TLO.Target.Type() == 'Corpse' then
        casting.interrupt()
        chchain.mirrorSay('target died')
        rc.chchainPendingCheck = nil
        state.clearRunState()
        return
    end

    if mq.TLO.Me.Casting() and (mq.TLO.Me.CastTimeLeft() or 0) > 0 then
        preLandHpCheck()
        return
    end

    -- Cast finished.
    if not p.cancelled then
        useClickyIfEnabled()
    end
    rc.chchainPendingCheck = nil
    state.clearRunState()
end

function chchain.Tick()
    slotScheduleTick()
    castPollTick()
    -- preLand also runs while casting via castPollTick; run once more if pending outside runState race.
    if state.getRunconfig().chchainPendingCheck then
        preLandHpCheck()
    end
end

function chchain.getHookFn(name)
    if name == 'chchainTick' then
        return function(_hookName)
            local rc = state.getRunconfig()
            if rc.doChchain and rc.chainActive then
                chchain.Tick()
                return
            end
            if state.getRunState() == state.STATES.chchain then
                castPollTick()
            end
        end
    end
    return nil
end

chchain.MIRROR_CHANNELS = MIRROR_CHANNELS
chchain.DEFAULT_CH_CHAIN = DEFAULT_CH_CHAIN

botconfig.RegisterConfigLoader(chchain.applyFromSettings)
czactor.setMtNameChangedHook(chchain.syncCurtankFromMtName)

return chchain
