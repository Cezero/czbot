--- MQ Lua global overrides: print and printf write to MQ chat.
--- Source: lua_Globals.cpp

--- Print to MQ chat (concatenates args with no separator).
---@param ... any
---@return nil
function print(...) end

--- Print to MQ chat using string.format(fmt, ...).
---@param fmt string
---@param ... any
---@return nil
function printf(fmt, ...) end
