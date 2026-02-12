-- Comprehensive mq.TLO.Spell proxy test for MacroQuest Lua.
-- Run in-game: /lua run D:\git\czbot\scripts\test_spell_tlo.lua
-- Or from czbot: /lua run scripts/test_spell_tlo.lua (if CWD is czbot)
--
-- Tests which patterns work vs break/hang:
-- 1. Direct chain: mq.TLO.Spell(name).Method() or mq.TLO.Spell(name)()
-- 2. Stored proxy: local sp = mq.TLO.Spell(name) then sp.Method() / sp()
-- 3. By name vs by ID
-- 4. Multiple methods used in sequence (simulating buff flow)

local mq = require('mq')

local function log(msg)
    print('\at[SpellTLO]\ax ' .. tostring(msg))
end

local function ok(val)
    return val ~= nil and (type(val) ~= 'number' or not (val ~= val)) -- not NaN
end

-- Pick a spell to test: first spell in book, or fallback name
local function getTestSpellName()
    for i = 1, 12 do
        local name = mq.TLO.Me.Book(i)()
        if name and name ~= '' then return name end
    end
    return 'Minor Healing' -- fallback; change if your class doesn't have it
end

local spellName = getTestSpellName()
local spellId = mq.TLO.Spell(spellName).ID()
if not spellId or spellId == 0 then
    spellId = mq.TLO.Me.Book(1) and mq.TLO.Spell(mq.TLO.Me.Book(1)()).ID() or nil
end

log('Testing spell: ' .. tostring(spellName) .. ' (ID ' .. tostring(spellId) .. ')')
log('')

local results = {}

-- Test 1: Direct chain - invoke ()
local function test_direct_invoke(name)
    local r = mq.TLO.Spell(spellName)()
    results[name] = ok(r)
    return results[name]
end

-- Test 2: Direct chain - .ID()
local function test_direct_id(name)
    local r = mq.TLO.Spell(spellName).ID()
    results[name] = ok(r)
    return results[name]
end

-- Test 3: Direct chain - .MyRange() .AERange() .Mana() .MyCastTime()
local function test_direct_props(name)
    local a = mq.TLO.Spell(spellName).MyRange()
    local b = mq.TLO.Spell(spellName).AERange()
    local c = mq.TLO.Spell(spellName).Mana()
    local d = mq.TLO.Spell(spellName).MyCastTime()
    results[name] = ok(a) or ok(b) or ok(c) or ok(d)
    return results[name]
end

-- Test 4: Direct chain - .ReagentID(slot)() .ReagentCount(slot)()
local function test_direct_reagents(name)
    local r1 = mq.TLO.Spell(spellName).ReagentID(1)()
    local r2 = mq.TLO.Spell(spellName).ReagentCount(1)()
    results[name] = true -- don't fail if spell has no reagents
    return true
end

-- Test 5: Stored proxy - store then invoke ()
local function test_stored_invoke(name)
    local sp = mq.TLO.Spell(spellName)
    local r = sp and sp()
    results[name] = ok(r)
    return results[name]
end

-- Test 6: Stored proxy - store then .ID()
local function test_stored_id(name)
    local sp = mq.TLO.Spell(spellName)
    local r = sp and sp.ID and sp.ID()
    results[name] = ok(r)
    return results[name]
end

-- Test 7: Stored proxy - store then .MyRange() .AERange()
local function test_stored_range(name)
    local sp = mq.TLO.Spell(spellName)
    local a = sp and sp.MyRange and sp.MyRange()
    local b = sp and sp.AERange and sp.AERange()
    results[name] = ok(a) or ok(b)
    return results[name]
end

-- Test 8: Stored proxy - store then .ReagentID(1)() .ReagentCount(1)()
local function test_stored_reagents(name)
    local sp = mq.TLO.Spell(spellName)
    local r1 = sp and sp.ReagentID and sp.ReagentID(1) and sp.ReagentID(1)()
    local r2 = sp and sp.ReagentCount and sp.ReagentCount(1) and sp.ReagentCount(1)()
    results[name] = true
    return true
end

-- Test 9: Stored proxy - multiple method calls in sequence (like buff flow)
local function test_stored_sequence(name)
    local sp = mq.TLO.Spell(spellName)
    if not sp then results[name] = false; return false end
    local a = sp.MyRange and sp.MyRange()
    local b = sp.AERange and sp.AERange()
    local c = sp.Mana and sp.Mana()
    local d = sp.MyCastTime and sp.MyCastTime()
    local e = sp.Stacks and sp.Stacks()
    local f = sp.TargetType and sp.TargetType()
    results[name] = ok(a) or ok(b) or ok(c) or ok(d) or ok(e) or ok(f)
    return results[name]
end

-- Test 10: Spell by ID (e.g. mq.TLO.Spell(123).Name())
local function test_by_id(name)
    if not spellId or spellId == 0 then results[name] = nil; return end
    local n = mq.TLO.Spell(spellId).Name()
    results[name] = n and n ~= ''
    return results[name]
end

-- Test 11: Stored proxy then call from a different spell (Bone Walk style - spell with reagents)
local function test_stored_second_spell(name)
    local other = 'Bone Walk'
    local sp = mq.TLO.Spell(other)
    if not sp then results[name] = nil; return end
    local r = sp()
    local rid = sp.ReagentID and sp.ReagentID(1) and sp.ReagentID(1)()
    local rcnt = sp.ReagentCount and sp.ReagentCount(1) and sp.ReagentCount(1)()
    results[name] = ok(r)
    return results[name]
end

local tests = {
    { name = 'Direct: Spell(name)()', fn = test_direct_invoke },
    { name = 'Direct: Spell(name).ID()', fn = test_direct_id },
    { name = 'Direct: Spell(name).MyRange/AERange/Mana/MyCastTime', fn = test_direct_props },
    { name = 'Direct: Spell(name).ReagentID/Count(1)()', fn = test_direct_reagents },
    { name = 'Stored: sp = Spell(name); sp()', fn = test_stored_invoke },
    { name = 'Stored: sp = Spell(name); sp.ID()', fn = test_stored_id },
    { name = 'Stored: sp = Spell(name); sp.MyRange/AERange()', fn = test_stored_range },
    { name = 'Stored: sp = Spell(name); sp.ReagentID/Count(1)()', fn = test_stored_reagents },
    { name = 'Stored: sp then multiple (MyRange, Mana, Stacks, TargetType)', fn = test_stored_sequence },
    { name = 'By ID: Spell(id).Name()', fn = test_by_id },
    { name = 'Stored: Bone Walk proxy then sp() / ReagentID', fn = test_stored_second_spell },
}

log('Running tests (any test may hang if MQ blocks on stored proxy)...')
log('')

for _, t in ipairs(tests) do
    local ok_result, err = pcall(function() t.fn(t.name) end)
    if not ok_result then
        results[t.name] = false
        log('\arFAIL\ax ' .. t.name .. ': ' .. tostring(err))
    else
        local r = results[t.name]
        if r == true then
            log('\agPASS\ax ' .. t.name)
        elseif r == false then
            log('\arFAIL\ax ' .. t.name .. ' (returned false/nil)')
        else
            log('\aySKIP\ax ' .. t.name)
        end
    end
end

log('')
log('Summary: use DIRECT chains (mq.TLO.Spell(name).Method()) everywhere; avoid storing the Spell proxy.')
log('Done.')
