-- Combat state reset: stick off, attack off, optional pet back, optional target clear.
-- Used by botmelee, botmove, and botpull to avoid duplicated logic.

local mq = require('mq')

local combat = {}

--- Reset combat state (stick, attack, optionally pet and target).
--- @param opts table|nil Optional: clearTarget (boolean, default true), clearPet (boolean, default true)
function combat.ResetCombatState(opts)
    opts = opts or {}
    local clearTarget = opts.clearTarget ~= false
    local clearPet = opts.clearPet ~= false

    if mq.TLO.Stick.Active() then mq.cmd('/squelch /stick off') end
    if mq.TLO.Me.Combat() then mq.cmd('/squelch /attack off') end
    if clearPet and mq.TLO.Me.Pet.Aggressive() then
        mq.cmd('/squelch /pet back off')
        mq.cmd('/squelch /pet follow')
    end
    if clearTarget and mq.TLO.Target.Type() == 'NPC' then mq.cmd('/squelch /target clear') end
end

return combat
