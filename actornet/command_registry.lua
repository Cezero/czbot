local mq = require('mq')

local Registry = {}

-- Unbind everything (safe to call multiple times)
function Registry.clear()
  -- Collect command keys first to avoid modifying the table while iterating
  local to_remove = {}
  for cmd, _ in pairs(Registry) do
    if type(cmd) == 'string' and cmd:sub(1,1) == '/' then
      table.insert(to_remove, cmd)
    end
  end

  for _, cmd in ipairs(to_remove) do
    mq.unbind(cmd)
    Registry[cmd] = nil
  end
end

-- Register a command safely
function Registry.bind(cmd, fn)
  mq.unbind(cmd)
  mq.bind(cmd, fn)
  Registry[cmd] = fn
end

return Registry
