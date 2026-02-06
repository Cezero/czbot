local mq = require('mq')
local botgui = require('botgui')
local trotslib = {}
local commands = require('lib.commands')
local state = require('lib.state')
local charinfo = require('actornet.charinfo')

--build variables for trotslib
debug = false

function BotCheck()
    state.getRunconfig().BotList = charinfo.GetPeers()
end

function trotslib.IgnoreCheck()
    --print('build check for doyell array')
    return true
end

function trotslib.DoYell()
    if state.getRunconfig().YellTimer < mq.gettime() then
        mq.cmd('/yell')
        state.getRunconfig().YellTimer = mq.gettime() + 3000
    end
end

mq.bind('/tb', commands.Parse)
mq.bind('/tbshow', botgui.UIEnable)

return trotslib
