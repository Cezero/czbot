local mq = require('mq')

local RemovedAugs = {}

local function EquipGear(geartoequip)
    local myitem = mq.TLO.FindItem(geartoequip)()
    if not myitem then return false end
    local canuse          = mq.TLO.FindItem(geartoequip).CanUse()
    local toequipitemlink = mq.TLO.FindItem(geartoequip).ItemLink('CLICKABLE')()
    local wornslot        = mq.TLO.FindItem(geartoequip).WornSlot(1)()
    local slotname        = mq.TLO.InvSlot(wornslot).Name()
    local curitemlink     = mq.TLO.Me.Inventory(wornslot).ItemLink('CLICKABLE')() or 'EMPTY'
    if canuse and wornslot then
        printf('\ayCZBot:\ax\ayattempting to replace \ar%s\ax with \ag%s\ax in slot %s', curitemlink,
            toequipitemlink, slotname)
    else
        printf('\ayCZBot:\ax\ar%s is not equipable by my class/race\ax', toequipitemlink)
        return false
    end

    local function findaugslot(slot)
        local augslots = tonumber(mq.TLO.InvSlot(slot).Item.Augs())
        if tonumber(augslots) then
            for i = 1, augslots do
                local a
                if mq.TLO.InvSlot(slot).Item["AugSlot" .. i]() == augtype then
                    return i
                end
            end
        else
            mq.cmdf('%s has no augslots')
        end
    end

    local augslot = findaugslot(wornslot)

    local function invsearch(itemname)
        if not itemname then return false end
        for packcntr = 1, 10 do
            local packname = mq.TLO.InvSlot("pack" .. packcntr).Item.Name()
            if packname and string.lower(packname) == string.lower(itemname) then return packcntr end
            if mq.TLO.InvSlot("pack" .. packcntr).Item.Container() then
                local packslots = mq.TLO.InvSlot("pack" .. packcntr).Item.Container()
                for slotcntr = 1, packslots do
                    local slotname = mq.TLO.InvSlot("pack" .. packcntr).Item.Item(slotcntr)()
                    if slotname and string.lower(slotname) == string.lower(itemname) then return packcntr, slotcntr end
                end
            end
        end
        return false
    end

    local function equipaugs(slot)
        if mq.TLO.InvSlot(slot).Item.ID() then
            mq.TLO.InvSlot(slot).Item.Inspect()
            local augslots = mq.TLO.InvSlot(slot).Item.Augs()
            mq.delay(100)
            for i = 1, augslots do
                local itemslot, packslot = invsearch(RemovedAugs[i])
                if itemslot then
                    if packslot then
                        mq.cmdf('/itemnotify in pack%s %s leftmouseup', itemslot, packslot)
                    else
                        mq.cmdf('/itemnotify pack%s  leftmouseup', itemslot, packslot)
                    end
                    mq.delay(3000, function() if mq.TLO.Cursor.ID() then return true end end)
                    mq.cmdf('/notify ItemDisplayWindow IDW_Socket_Slot_%s_Item leftmouseup', i)
                    mq.delay(3000, function() if mq.TLO.Window("ConfirmationDialogBox") then return true end end)
                    mq.cmd('/yes')
                    mq.delay(2000, function() if mq.TLO.InvSlot(slot).Item.AugSlot(i)() then return true end end)
                    if mq.TLO.InvSlot(slot).Item.AugSlot(i)() then
                        printf("\ayCZBot:\axI've equiped %s in my %s succesfully", RemovedAugs[i], geartoequip)
                    else
                        printf("\ayCZBot:\axSomething went wrong equiping %s", RemovedAugs[i])
                    end
                end
            end
        else
            printf('\ayCZBot:\axInvalid slot or missing item')
        end
    end

    local function removeaugs(slot)
        local augslots = mq.TLO.InvSlot(slot).Item.Augs()
        local curitem = mq.TLO.InvSlot(slot).Item()
        RemovedAugs = {}
        if augslots and curitem then
            for i = 1, augslots do
                if mq.TLO.InvSlot(slot).Item.AugSlot(i)() then
                    local aug = mq.TLO.InvSlot(slot).Item.AugSlot(i)()
                    if aug then
                        table.insert(RemovedAugs, aug)
                        printf("\ayCZBot:\axI have an augment in %s, removing it", curitem)
                        mq.cmdf('/removeaug "%s" "%s"', aug, mq.TLO.InvSlot(slot).Item())
                        mq.delay(3000, function() if mq.TLO.Window("ConfirmationDialogBox") then return true end end)
                        if mq.TLO.Window("ConfirmationDialogBox") then
                            mq.cmd('/yes')
                            mq.delay(3000,
                                function() if (not mq.TLO.InvSlot(slot).Item.AugSlot(augslot)()) and mq.TLO.Cursor.ID() then return true end end)
                            mq.delay(100)
                            mq.cmd('/autoinv')
                        end
                        mq.delay(2000, function() if mq.TLO.InvSlot(slot).Item.AugSlot(i)() then return true end end)
                        if not mq.TLO.InvSlot(slot).Item.AugSlot(i)() then
                            printf("\ayCZBot:\axI've removed \ag%s\ax in \ag%s\ax succesfully", RemovedAugs[i],
                                curitem)
                        else
                            printf("\ayCZBot:\ax\arSomething went wrong removing %s from %s most likely need distillers",
                                RemovedAugs[i], curitem)
                        end
                    end
                end
            end
        end
        return augslots
    end

    -- remove augments from existing item

    if wornslot then removeaugs(wornslot) end


    --equip the item

    mq.cmdf('/itemnotify "%s" leftmouseup', geartoequip)
    mq.cmdf('/itemnotify "%s" leftmouseup', wornslot)
    mq.delay(300)
    if mq.TLO.Window("ConfirmationDialogBox")() then mq.cmdf('/yes') end
    mq.cmd('/autoinv')

    --equip the augs back

    equipaugs(wornslot)

    if mq.TLO.Me.Inventory(wornslot)() == geartoequip then
        printf('\ayCZBot:\ax\agSuccesfully equiped\ax %s in slot %s', geartoequip, slotname)
    else
        printf('\ayCZBot:\ax\arSomething went wrong\ax equiping %s in slot %s', geartoequip, slotname)
    end
end

return { EquipGear = EquipGear }
