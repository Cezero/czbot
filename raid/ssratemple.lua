-- Zone 162: ssratemple (Vyzh`dra the Cursed, Vyzh`dra the Exiled, Glyph Covered Serpent)
local mq = require('mq')
local botconfig = require('lib.config')
local tankrole = require('lib.tankrole')
local myconfig = botconfig.config

local M = {}

local ZONE_ID = 162
local FIGHT_LOC = '56.88, 141.24, -256.50'
local SAFE_LOC = '34.40, 173.45, -256.50'

-- nil | 'fight' | 'safe'. File-local so leaving the zone cannot stick botraid's raidsactive fallback.
local phase = nil
local fightUntil = 0

local function inZone()
    return mq.TLO.Zone.ID() == ZONE_ID
end

local function stopNavStick()
    if mq.TLO.Navigation.Active() then mq.cmd('/nav stop log=off') end
    if mq.TLO.Stick.Active() then mq.cmd('/squelch /stick off') end
end

-- Melee or debuff bots joust. The main tank stays on the mob.
local function eligible()
    if not myconfig.settings.doraid or not inZone() then return false end
    if not myconfig.settings.domelee and not myconfig.settings.dodebuff then return false end
    if tankrole.AmIMainTank() then return false end
    return true
end

local function clearPhase()
    phase = nil
    fightUntil = 0
end

local function beginFight(durationMs)
    if not eligible() then return end
    stopNavStick()
    phase = 'fight'
    fightUntil = mq.gettime() + durationMs
    mq.cmdf('/warp loc %s', FIGHT_LOC)
end

mq.event('SsraCausticMist', '#*#Vyzh`dra the Cursed begins casting Caustic Mist.#*#', function()
    beginFight(20000)
end)
mq.event('SsraPyroHallucinations', '#*#Vyzh`dra the Exiled begins casting Pyrokinetic Hallucinations.#*#', function()
    beginFight(10000)
end)
mq.event('SsraWaveOfDeath', '#*#A Glyph Covered Serpent begins casting Wave of Death.#*#', function()
    beginFight(20000)
end)

function M.reset()
    clearPhase()
end

function M.raid_check()
    if not inZone() then return false end
    if phase ~= nil and not eligible() then
        clearPhase()
        return false
    end
    if phase == 'fight' then
        if mq.gettime() >= fightUntil then
            stopNavStick()
            mq.cmdf('/warp loc %s', SAFE_LOC)
            phase = 'safe'
            return true
        end
        return false
    end
    if phase == 'safe' then
        stopNavStick()
        return true
    end
    return false
end

return M
