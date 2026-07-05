-- Global MA/MT fallback lists (cz_common.ma_list, cz_common.mt_list).

local botconfig = require('lib.config')
local state = require('lib.state')
local auto_ma_mt = require('lib.auto_ma_mt')

local rolelists = {}

local _chListGen = 0

local LIST_CONFIG = {
    ma = {
        commonKey = 'ma_list',
        runconfigKey = 'MaList',
    },
    mt = {
        commonKey = 'mt_list',
        runconfigKey = 'MtList',
    },
    ch = {
        commonKey = 'ch_healers',
        runconfigKey = 'ChHealers',
    },
}

function rolelists.getChListGen()
    return _chListGen
end

local function saveList(listType, replace)
    local opts = LIST_CONFIG[listType]
    if not opts then return end
    local memList = botconfig.copyStringList(state.getRunconfig()[opts.runconfigKey])
    botconfig.mutateCommon(function(common)
        local diskList = common[opts.commonKey]
        if replace then
            common[opts.commonKey] = memList
        else
            common[opts.commonKey] = botconfig.unionStringList(diskList, memList)
        end
    end)
end

function rolelists.loadFromCommon()
    local common = botconfig.getCommon()
    local rc = state.getRunconfig()
    for _, opts in pairs(LIST_CONFIG) do
        rc[opts.runconfigKey] = botconfig.copyStringList(common[opts.commonKey])
    end
    auto_ma_mt.bumpMaListGen()
    auto_ma_mt.bumpMtListGen()
    _chListGen = _chListGen + 1
end

function rolelists.getMaList()
    return state.getRunconfig().MaList or {}
end

function rolelists.getMtList()
    return state.getRunconfig().MtList or {}
end

function rolelists.getChHealers()
    return state.getRunconfig().ChHealers or {}
end

function rolelists.process(listType, command)
    if command == 'save' then
        saveList(listType, false)
    elseif command == 'save_replace' then
        saveList(listType, true)
    else
        return
    end
    if listType == 'ma' then
        auto_ma_mt.bumpMaListGen()
    elseif listType == 'mt' then
        auto_ma_mt.bumpMtListGen()
    elseif listType == 'ch' then
        _chListGen = _chListGen + 1
    end
end

return rolelists
