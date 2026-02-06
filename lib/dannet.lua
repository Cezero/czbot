local mq = require('mq')

local dannet = {}

function dannet.MakeObs(obsname, bot, query)
    if obsname and query and bot then
        if not mq.TLO.DanNet(bot).ObserveSet(query)() then
            mq.cmdf('/dobserve %s -q %s', bot, query)
            mq.delay(2000, function() return mq.TLO.DanNet(bot).Observe(query).Received() end)
        end
        _G[obsname] = mq.TLO.DanNet(bot).O(query)()
    end
end

function dannet.DropObs()
    local peercnt = mq.TLO.DanNet.PeerCount()
    for peeriter = 1, peercnt do
        local obscnt = mq.TLO.DanNet(mq.TLO.DanNet.Peers(peeriter)).ObserveCount() or 0
        if obscnt and obscnt > 0 then
            mq.cmdf('/dobs %s -drop', mq.TLO.DanNet.Peers(peeriter)())
        end
    end
end

return dannet
