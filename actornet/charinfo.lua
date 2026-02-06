local actors = require('actors')
local mq = require('mq')
local state = require('actornet.state')

local Charinfo = {}

-- message handler for character info
local cmdActor = actors.register('charinfo', function (message)
    if message.content.id == 'publish' then
        state.Peers[message.content.sender] = message.content
    elseif message.content.id == 'remove' then
        state.Peers[message.content.sender] = nil
    end
end)

local function buffEntry(buff)
    if not buff or not buff.Spell then return nil end
    return {
        Duration = buff.Duration and buff.Duration() or nil,
        Spell = {Name = buff.Spell.Name(), ID = buff.Spell.ID(), Category = buff.Spell.Category(), Level = buff.Spell.Level()}
    }
end

local function getBuffs()
    local buffs = {}
    local maxSlots = mq.TLO.Me.MaxBuffSlots() or 40
    for i = 1, maxSlots do
        local buff = mq.TLO.Me.Buff(i)
        local entry = buffEntry(buff)
        buffs[#buffs + 1] = entry or {}
    end
    return buffs
end

local function getShortBuffs()
    local buffs = {}
    for i = 1, 15 do
        local buff = mq.TLO.Me.ShortBuff(i)
        if buff and buff.Spell then
            local entry = buffEntry(buff)
            if entry then buffs[#buffs + 1] = entry end
        end
    end
    return buffs
end

local function getPetBuffs()
    local buffs = {}
    if not mq.TLO.Me.Pet.ID or mq.TLO.Me.Pet.ID() == 0 then return buffs end
    for i = 1, 15 do
        local buff = mq.TLO.Me.Pet.Buff(i)
        if buff and buff.Spell then
            local entry = buffEntry(buff)
            if entry then buffs[#buffs + 1] = entry end
        end
    end
    return buffs
end

-- Detrimentals = count of buffs/shortbuffs that are detrimental. Counter fields = sum of remaining
-- counters on each buff (per MQ2NetBots: only available on client from current buff state).
local function getDetrimentalsAndCounters()
    local detrimentals = 0
    local countPoison, countDisease, countCurse, countCorruption = 0, 0, 0, 0
    local function processBuff(buff)
        if not buff or not buff.Spell then return end
        local st = buff.Spell.SpellType and buff.Spell.SpellType()
        if st and st == 'Detrimental' then
            detrimentals = detrimentals + 1
        end
        countPoison = countPoison + (buff.CountersPoison and buff.CountersPoison() or 0)
        countDisease = countDisease + (buff.CountersDisease and buff.CountersDisease() or 0)
        countCurse = countCurse + (buff.CountersCurse and buff.CountersCurse() or 0)
        countCorruption = countCorruption + (buff.CountersCorruption and buff.CountersCorruption() or 0)
    end
    local maxSlots = mq.TLO.Me.MaxBuffSlots() or 40
    for i = 1, maxSlots do
        processBuff(mq.TLO.Me.Buff(i))
    end
    for i = 1, 15 do
        processBuff(mq.TLO.Me.ShortBuff(i))
    end
    return detrimentals, countPoison, countDisease, countCurse, countCorruption
end

function Charinfo.publish()
    local targetId = mq.TLO.Target.ID()
    local targetHP = (targetId and targetId > 0) and mq.TLO.Target.PctHPs() or nil
    local cinfo = {
        id = 'publish',
        sender = mq.TLO.Me.Name(),
        Name = mq.TLO.Me.Name(),
        ID = mq.TLO.Me.ID(),
        Level = mq.TLO.Me.Level(),
        Class = {Name = mq.TLO.Me.Class(), ShortName = mq.TLO.Me.Class.ShortName(), ID = mq.TLO.Me.Class.ID()},
        PctHPs = mq.TLO.Me.PctHPs(),
        PctMana = mq.TLO.Me.PctMana(),
        Target = {Name = mq.TLO.Target.Name(), ID = targetId},
        TargetHP = targetHP,
        Zone = {Name = mq.TLO.Zone.Name(), ShortName = mq.TLO.Zone.ShortName(), ID = mq.TLO.Zone.ID()},
        Buff = getBuffs(),
        ShortBuff = getShortBuffs(),
        FreeBuffSlots = mq.TLO.Me.FreeBuffSlots(),
        PetBuff = getPetBuffs(),
    }
    do
        local det, cp, cd, cc, ccor = getDetrimentalsAndCounters()
        cinfo.Detrimentals = det
        cinfo.CountPoison = cp
        cinfo.CountDisease = cd
        cinfo.CountCurse = cc
        cinfo.CountCorruption = ccor
    end
    cinfo.PetHP = (mq.TLO.Me.Pet.ID and mq.TLO.Me.Pet.ID() and mq.TLO.Me.Pet.ID() > 0) and (mq.TLO.Me.Pet.PctHPs and mq.TLO.Me.Pet.PctHPs() or nil) or nil
    cinfo.MaxEndurance = mq.TLO.Me.MaxEndurance and mq.TLO.Me.MaxEndurance() or nil
    cmdActor:send({mailbox='charinfo'}, cinfo)
end

function Charinfo.remove()
    cmdActor:send({mailbox='charinfo'}, {id = 'remove', sender = mq.TLO.Me.Name()})
end

function Charinfo.GetInfo(name)
    return state.Peers[name]
end

function Charinfo.GetPeers(...)
    local keys = {}
    for k in pairs(state.Peers) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    return keys
end

function Charinfo.GetPeerCnt(...)
    local n = 0
    for _ in pairs(state.Peers) do
        n = n + 1
    end
    return n
end

-- Peer view: returns peer data with .Stacks(spell) and .StacksPet(spell) methods (WillStack checks).
-- Spell.WillStack[name]: "Does the selected spell stack with the specific SPELL name" (docs: https://docs.macroquest.org/reference/top-level-objects/tlo-spell/#WillStack[name]). Prefer spell Name.
local function otherSpellFromEntry(b)
    if not b or not b.Spell then return nil end
    local s = b.Spell
    -- Peer data stores Spell as table {Name=..., ID=...}. WillStack takes spell name.
    if type(s.Name) == 'string' and s.Name ~= '' then return s.Name end
    if type(s.ID) == 'number' then return s.ID end
    return nil
end

local function stacksForBuffs(peerInfo, spell)
    if not peerInfo then return false end
    local function check(list)
        if not list then return true end
        for _, b in ipairs(list) do
            local other = otherSpellFromEntry(b)
            if other then
                local ok = mq.TLO.Spell(spell).WillStack and mq.TLO.Spell(spell).WillStack(other)
                if not ok or ok == 'FALSE' or ok == false then return false end
            end
        end
        return true
    end
    if not check(peerInfo.Buff) then return false end
    if not check(peerInfo.ShortBuff) then return false end
    return true
end

local function stacksPet(peerInfo, spell)
    if not peerInfo or not peerInfo.PetBuff then return true end
    for _, b in ipairs(peerInfo.PetBuff) do
        local other = otherSpellFromEntry(b)
        if other then
            local ok = mq.TLO.Spell(spell).WillStack and mq.TLO.Spell(spell).WillStack(other)
            if not ok or ok == 'FALSE' or ok == false then return false end
        end
    end
    return true
end

function Charinfo.GetPeer(name)
    local info = state.Peers[name]
    if not info then return nil end
    local proxy = {}
    setmetatable(proxy, { __index = info })
    function proxy.Stacks(spell)
        return stacksForBuffs(info, spell)
    end
    function proxy.StacksPet(spell)
        return stacksPet(info, spell)
    end
    return proxy
end

-- Callable: Charinfo(peer) returns peer view (same shape as NetBots(peer)).
setmetatable(Charinfo, {
    __call = function(_, name) return Charinfo.GetPeer(name) end
})

return Charinfo
