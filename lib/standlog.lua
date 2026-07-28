-- Stand/memorization debug logging. Isolated here so callers avoid spellutils<->botmove cycles.
local mq = require('mq')
local log = require('lib.log')

local standlog = {}

local function isMemorizing()
    local premem = require('lib.premem')
    if premem.isPending() then return true end
    local casting = require('lib.casting')
    return casting.isMemorizing()
end

function standlog.logStand(reason, ctx)
    ctx = ctx or {}
    local casting = require('lib.casting')
    local state = require('lib.state')
    local mem = isMemorizing()
    local castingMem = casting.isMemorizing()
    local rc = state.getRunconfig()
    local cs = rc.CurSpell
    local parts = {
        'reason=' .. tostring(reason),
        'isMemorizing=' .. tostring(mem),
        'castingMem=' .. tostring(castingMem),
        'runState=' .. tostring(state.getRunState()),
        'sitting=' .. tostring(mq.TLO.Me.Sitting()),
    }
    if cs and cs.sub then
        parts[#parts + 1] = 'curSpell=' .. tostring(cs.sub) .. '/' .. tostring(cs.phase)
    end
    for k, v in pairs(ctx) do
        parts[#parts + 1] = tostring(k) .. '=' .. tostring(v)
    end
    local tag = (mem or castingMem) and '\ar[stand:INTERRUPTS-MEM]\ax' or '[stand]'
    log.say('%s %s', tag, table.concat(parts, ' '))
end

function standlog.cmdStand(reason, ctx)
    standlog.logStand(reason, ctx)
    mq.cmd('/stand')
end

function standlog.logMemStart(slot, spellName, inGem)
    log.say('[mem] start gem=%s spell="%s" inGem="%s"', tostring(slot), tostring(spellName), tostring(inGem))
end

function standlog.logMemWait(slot, spellName)
    log.say('[mem] wait gem=%s spell="%s" (in gem, not ready)', tostring(slot), tostring(spellName))
end

function standlog.isMemorizing()
    return isMemorizing()
end

return standlog
