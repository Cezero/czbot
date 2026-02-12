--- bit32 library (Lua 5.2+). Provided by MacroQuest at runtime for Lua 5.1 compatibility.
--- Standard bit32 API: https://www.lua.org/manual/5.2/manual.html#6.7

---@class bit32
---@field band fun(...: number): number
---@field bnot fun(x: number): number
---@field bor fun(...: number): number
---@field btest fun(...: number): boolean
---@field bxor fun(...: number): number
---@field extract fun(n: number, field: number, width?: number): number
---@field replace fun(n: number, v: number, field: number, width?: number): number
---@field lshift fun(x: number, disp: number): number
---@field rshift fun(x: number, disp: number): number
---@field arshift fun(x: number, disp: number): number
---@field rol fun(x: number, disp: number): number
---@field ror fun(x: number, disp: number): number
---@field setflag fun(value: number, flag: number, set: boolean): number
---@field clearflag fun(value: number, flag: number): number

---@type bit32
bit32 = bit32 or {}
