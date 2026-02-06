local botmelee = require('botmelee')
local botlogic = require('botlogic')
local spellutils = require('lib.spellutils')

botlogic.StartUp(...)
spellutils.Init({
    AdvCombat = botmelee.AdvCombat,
})
botlogic.mainloop()
