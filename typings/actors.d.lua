--- MacroQuest actors namespace (inter-script messaging).
--- Source: LuaActor.cpp RegisterLua

--- Callback invoked when send completes; err is a ResponseStatus value (number) if delivery failed.
---@alias ActorSendCallback fun(err?: number, response?: any): nil

---@class dropbox
---@field send fun(self: dropbox, obj: any): nil
---@field send fun(self: dropbox, obj: any, callback: ActorSendCallback): nil
---@field send fun(self: dropbox, recipients: table, obj: any): nil
---@field send fun(self: dropbox, recipients: table, obj: any, callback: ActorSendCallback): nil
---@field unregister fun(self: dropbox): nil

---@class message
---@field content any
---@field sender string
---@field reply fun(self: message, obj?: any): nil
---@field reply fun(self: message, code: number, obj: any): nil
---@field send fun(self: message, ...: any): nil

---@class ResponseStatusEnum
---@field ConnectionClosed number
---@field NoConnection number
---@field RoutingFailed number
---@field AmbiguousRecipient number

---@class ActorsNamespace
---@field ResponseStatus ResponseStatusEnum
---@field register fun(name?: string): dropbox
---@field iter fun(): function, nil, nil
---@field send fun(recipient: any, content: any, callback?: ActorSendCallback): nil
---@field send fun(recipients: table, content: any, callback?: ActorSendCallback): nil

---@type ActorsNamespace
actors = actors or {}
