local util = require('actornet.util')
local actors = require('actors')
local mq = require('mq')
local state = require('lib.state')

-- Basic remote command execution
local function execCommand(command)
    mq.cmd(command)
end

-- message handler for remote commands
local cmdActor = actors.register('rexec', function (message)
    local rc = state.getRunconfig()
    rc.rexecSender = message.content.sender
    local function run()
        if message.content.id == 'direct' or (message.content.id == 'global' and mq.TLO.Me.Name() ~= message.content.sender) then
            execCommand(message.content.command)
        elseif message.content.id == 'zone' and mq.TLO.Zone.ShortName() == message.content.zone then
            execCommand(message.content.command)
        elseif message.content.id == 'group' and mq.TLO.Group.Member(message.content.sender).Index() then
            execCommand(message.content.command)
        elseif message.content.id == 'raid' and mq.TLO.Raid.Member(message.content.sender).Name() ~= nil then
            execCommand(message.content.command)
        end
    end
    pcall(run)
    rc.rexecSender = nil
end)

local function sendCommand(includeSelf, target, ...)
    local targets = {
        zone = true,
        group = true,
        raid = true,
        global = true
    }
    local cmd = util.concat(...)
    if includeSelf then
        execCommand(cmd)
    end
    if not targets[target] then
        cmdActor:send({character=target, mailbox='rexec'}, {sender = mq.TLO.Me.Name(), id = 'direct', command = cmd})
    else
        cmdActor:send({mailbox='rexec'}, {sender = mq.TLO.Me.Name(), id = target, command = cmd, zone = mq.TLO.Zone.ShortName()})
    end
end

local Rexec = {}

function Rexec.sendDirectCommand(target, ...)
    sendCommand(false, target, ...)
end

function Rexec.sendGlobalCommand(...)
    sendCommand(false, 'global', ...)
end

function Rexec.sendSelfAndGlobalCommand(...)
    sendCommand(true, 'global', ...)
end

function Rexec.sendZoneCommand(...)
    sendCommand(false, 'zone', ...)
end

function Rexec.sendSelfAndZoneCommand(...)
    sendCommand(true, 'zone', ...)
end

function Rexec.sendGroupCommand(...)
    sendCommand(false, 'group', ...)
end

function Rexec.sendSelfAndGroupCommand(...)
    sendCommand(true, 'group', ...)
end

function Rexec.sendRaidCommand(...)
    sendCommand(false, 'raid', ...)
end

function Rexec.sendSelfAndRaidCommand(...)
    sendCommand(true, 'raid', ...)
end

return Rexec
