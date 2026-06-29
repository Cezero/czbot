-- Global MA/MT fallback lists (cz_common.ma_list, cz_common.mt_list).

local botconfig = require('lib.config')
local state = require('lib.state')

local rolelists = {}

local _maListGen = 0
local _mtListGen = 0

local LIST_CONFIG = {
    ma = {
        commonKey = 'ma_list',
        runconfigKey = 'MaList',
    },
    mt = {
        commonKey = 'mt_list',
        runconfigKey = 'MtList',
    },
}

function rolelists.getMaListGen()
    return _maListGen
end

function rolelists.getMtListGen()
    return _mtListGen
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
    _maListGen = _maListGen + 1
    _mtListGen = _mtListGen + 1
    require('lib.tankrole').invalidateAll()
end

function rolelists.getMaList()
    return state.getRunconfig().MaList or {}
end

function rolelists.getMtList()
    return state.getRunconfig().MtList or {}
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
        _maListGen = _maListGen + 1
        require('lib.tankrole').invalidateMa()
    elseif listType == 'mt' then
        _mtListGen = _mtListGen + 1
        require('lib.tankrole').invalidateMt()
    end
end

return rolelists
