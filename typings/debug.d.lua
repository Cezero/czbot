--- Lua 5.1 debug library (minimal stub for linter).
--- Only include if removing "debug" from diagnostics.globals.

--- Table returned by debug.getinfo (Lua 5.1).
---@class DebugInfo
---@field source string
---@field short_src string
---@field linedefined number
---@field lastlinedefined number
---@field what string
---@field currentline number
---@field name string|nil
---@field namewhat string
---@field nups number

---@class DebugLib
---@field getinfo fun(thread: any, level: number|string, what?: string): DebugInfo|nil
---@field getlocal fun(thread: any, level: number, index: number): string?, any
---@field setlocal fun(thread: any, level: number, index: number, value: any): string|nil
---@field getupvalue fun(f: function, index: number): string?, any
---@field setupvalue fun(f: function, index: number, value: any): string|nil
---@field traceback fun(thread?: any, message?: string, level?: number): string
---@field getmetatable fun(object: any): table|nil
---@field setmetatable fun(object: any, metatable: table|nil): any

---@type DebugLib
---@diagnostic disable-next-line: assign-type-mismatch
debug = debug or {}
