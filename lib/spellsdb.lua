local mq = require('mq')
local botconfig = require('lib.config')
local myconfig = botconfig.config

local spellsdb = {}

local DB_PATH = nil

local CLASS_COL = {
    brd = 'brdlevel',
    ber = 'berlevel',
    bst = 'bstlevel',
    clr = 'clrlevel',
    dru = 'drulevel',
    enc = 'enclevel',
    mag = 'maglevel',
    mnk = 'mnklevel',
    nec = 'neclevel',
    pal = 'pallevel',
    rng = 'rnglevel',
    rog = 'roglevel',
    shd = 'shdlevel',
    shm = 'shmlevel',
    war = 'warlevel',
    wiz = 'wizlevel'
}

local function trim(s)
    if not s then return s end
    return s:match('^%s*(.-)%s*$')
end

local function escape_sql(s)
    return tostring(s):gsub("'", "''")
end

local has_sqlite, sqlite3 = pcall(require, 'lsqlite3')
local db = nil

-- directory of this script (e.g. .../bumsbot/lib/)
local function get_script_dir()
    local src = debug and debug.getinfo and debug.getinfo(1, 'S') and debug.getinfo(1, 'S').source or ''
    if src then
        local m = src:match('@(.+)[/\\][^/\\]+$')
        if m then return m .. '\\' end
    end
    return ''
end

-- project root: parent of lib/ when script is in lib/, else script dir
local function get_project_root()
    local script_dir = get_script_dir()
    if script_dir == '' then return '' end
    local norm = script_dir:gsub('/', '\\')
    if norm:match('\\lib\\?$') then
        local parent = norm:match('^(.+)\\[^\\]+\\?$')
        return parent and (parent .. '\\') or script_dir
    end
    return script_dir
end

local function ensure_sqlite()
    if has_sqlite and sqlite3 then return true end
    local root = get_project_root()
    if root ~= '' then
        package.cpath = package.cpath .. ';' .. root .. '?.dll'
    end
    local ok, lib = pcall(require, 'lsqlite3')
    if ok then
        has_sqlite = true
        sqlite3 = lib
        return true
    end
    return false
end

local function init_db()
    if not ensure_sqlite() then return false end
    if not db then
        if not DB_PATH then return false end
        db = sqlite3.open(DB_PATH)
    end
    return db ~= nil
end

local function set_default_db_path()
    if DB_PATH then return end
    if myconfig and myconfig.settings and myconfig.settings.spelldb then
        DB_PATH = myconfig.settings.spelldb
    else
        local root = get_project_root()
        DB_PATH = (root ~= '' and (root .. 'spells.db')) or 'spells.db'
    end
end

function spellsdb.set_db(path)
    if db then
        pcall(function() db:close() end)
        db = nil
    end
    DB_PATH = path
end

local function sqlite_query(sql)
    set_default_db_path()
    if not DB_PATH then return nil end
    if ensure_sqlite() and init_db() then
        -- return first column of first row
        for row in db:nrows(sql) do
            return row.name or nil
        end
        return nil
    end
    -- fallback to CLI (may spawn windows)
    local cmd = string.format('sqlite3 "%s" "%s"', DB_PATH, sql:gsub('"', '\\"'))
    local pipe = io.popen(cmd, 'r')
    if not pipe then return nil end
    local out = pipe:read('*a')
    pipe:close()
    if not out then return nil end
    out = out:gsub('\r\n', '\n')
    out = out:gsub('\n$', '')
    return out
end

local function sqlite_query_all(sql)
    set_default_db_path()
    if not DB_PATH then return {} end
    local results = {}
    if ensure_sqlite() and init_db() then
        for row in db:nrows(sql) do
            if row.name and row.name ~= '' then table.insert(results, row.name) end
        end
        return results
    end
    local cmd = string.format('sqlite3 "%s" "%s"', DB_PATH, sql:gsub('"', '\\"'))
    local pipe = io.popen(cmd, 'r')
    if not pipe then return results end
    local out = pipe:read('*a') or ''
    pipe:close()
    out = out:gsub('\r\n', '\n')
    for name in out:gmatch("([^\n]+)") do
        table.insert(results, name)
    end
    return results
end

local function section_category(section)
    if section == 'heal' then return 'HEAL' end
    if section == 'buff' then return 'BUFF' end
    if section == 'cure' then return 'CURE' end
    -- debuff/event categories vary; no filter
    return nil
end

function spellsdb.resolve_line(line, sub, gem)
    if not line or line == '' then return nil end
    set_default_db_path()
    local class = mq.TLO.Me.Class.ShortName()
    if not class then return nil end
    class = string.lower(class)
    local col = CLASS_COL[class]
    if not col then return nil end
    local lvl = tonumber(mq.TLO.Me.Level()) or 1
    local cat = section_category(sub)
    local catFilter = ''
    if cat then catFilter = string.format(" AND category='%s'", escape_sql(cat)) end
    local sql = string.format(
        "SELECT name FROM spells WHERE line='%s' AND COALESCE(%s,255) <> 255 AND COALESCE(%s,255) <= %d%s ORDER BY COALESCE(%s,255) DESC, priority DESC LIMIT 50;",
        escape_sql(line), col, col, lvl, catFilter, col
    )
    local names = sqlite_query_all(sql)
    for _, name in ipairs(names) do
        -- Check for disciplines if gem type is 'disc'
        if gem == 'disc' then
            if mq.TLO.Me.CombatAbility(name)() then return name end
        else
            if mq.TLO.Me.Book(name)() then return name end
        end
    end
    if cat then
        local sql2 = string.format(
            "SELECT name FROM spells WHERE line='%s' AND COALESCE(%s,255) <> 255 AND COALESCE(%s,255) <= %d ORDER BY COALESCE(%s,255) DESC, priority DESC LIMIT 50;",
            escape_sql(line), col, col, lvl, col
        )
        local names2 = sqlite_query_all(sql2)
        for _, name in ipairs(names2) do
            if gem == 'disc' then
                if mq.TLO.Me.CombatAbility(name)() then return name end
            else
                if mq.TLO.Me.Book(name)() then return name end
            end
        end
    end
    return nil
end

local function resolve_from_alias(alias_str, sub, gem)
    if not alias_str or alias_str == '' then return nil end
    for value in tostring(alias_str):gmatch("[^|]+") do
        local token = trim(value)
        if token and token ~= '' then
            local name = spellsdb.resolve_line(token, sub, gem)
            if name then return name end
        end
    end
    return nil
end

function spellsdb.resolve_entry(section, index, force)
    if true then return false end
    if not botconfig or not section or not index then return nil end
    local entry = botconfig.getSpellEntry(section, index)
    if not entry then return nil end
    -- simple cache: don't re-resolve if same alias at same level unless forced
    local curlevel = tonumber(mq.TLO.Me.Level()) or 1
    if not force then
        if type(entry.spell) == 'string' and entry.spell ~= '' and entry.spell ~= '0' then
            if entry._resolved_level == curlevel and entry._resolved_alias == entry.alias then
                return nil
            end
        end
    end
    local resolved = nil
    if type(entry.alias) == 'string' and entry.alias ~= '' then
        resolved = resolve_from_alias(entry.alias, section, entry.gem)
    end
    if resolved and resolved ~= entry.spell then
        entry.spell = resolved
        entry._resolved_level = curlevel
        entry._resolved_alias = entry.alias
        return resolved
    else
        entry._resolved_level = curlevel
        entry._resolved_alias = entry.alias
    end
    return nil
end

return spellsdb
