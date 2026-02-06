-- Resolves Main Tank (MT) vs Main Assist (MA) for the bot.
-- MT = who gets heals and who may pick from MobList when they are a bot.
-- MA = who DPS and offtank follow (whose target to attack).
-- "automatic" uses Group/Raid window roles: Group.MainTank, Group.MainAssist, Group.Puller.
-- Raid has MainAssist only; MainTank and Puller always come from Group.

local mq = require('mq')
local state = require('lib.state')
local charinfo = require('actornet.charinfo')

local tankrole = {}

--- Return the Main Assist's character name (who DPS/offtank follow). Reads AssistName from runconfig; if nil/empty, uses TankName for backward compat.
---@return string|nil
function tankrole.GetAssistTargetName()
    local rc = state.getRunconfig()
    local name = rc.AssistName
    if name == nil or name == '' then
        name = rc.TankName
    end
    if name == nil or name == '' then return nil end
    if name == 'automatic' then
        if mq.TLO.Raid.Members() and mq.TLO.Raid.Members() > 0 then
            local ma = mq.TLO.Raid.MainAssist
            if ma and ma.Name then return ma.Name() end
        end
        local gma = mq.TLO.Group.MainAssist
        if gma and gma.Name then return gma.Name() end
        return nil
    end
    return name
end

--- Return the Main Tank's character name (who gets heals; who may pick from MobList). Reads TankName from runconfig.
---@return string|nil
function tankrole.GetMainTankName()
    local name = state.getRunconfig().TankName
    if name == nil or name == '' then return nil end
    if name == 'automatic' then
        local gmt = mq.TLO.Group.MainTank
        if gmt and gmt.Name then return gmt.Name() end
        return nil
    end
    return name
end

--- Return the Puller's current target ID when this toon is the MT (for puller priority in selectTankTarget). Group only; Raid has no Puller.
---@return number|nil
function tankrole.GetPullerTargetID()
    if tankrole.GetMainTankName() ~= mq.TLO.Me.Name() then return nil end
    local puller = mq.TLO.Group.Puller
    if not puller or not puller.Name then return nil end
    local pullerName = puller.Name()
    if not pullerName or pullerName == '' then return nil end
    local info = charinfo.GetInfo(pullerName)
    if info and info.Target and info.Target.ID then return info.Target.ID end
    return nil
end

--- True when this character is the Main Tank (resolved from TankName / Group.MainTank).
---@return boolean
function tankrole.AmIMainTank()
    return tankrole.GetMainTankName() == mq.TLO.Me.Name()
end

--- True when this character is the Main Assist (resolved from AssistName / Group or Raid MainAssist). Used so the MA bot runs selectMATarget.
---@return boolean
function tankrole.AmIMainAssist()
    return tankrole.GetAssistTargetName() == mq.TLO.Me.Name()
end

return tankrole
