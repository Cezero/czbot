local Util = {}

function Util.concat(...)
    local input = {...}
    local parts = {}

    -- If a single table was passed, use its elements instead
    if #input == 1 and type(input[1]) == 'table' then
        input = input[1]
    end

    for _, v in ipairs(input) do
        if type(v) == 'table' then
            -- Flatten simple array-like tables
            for _, w in ipairs(v) do
                table.insert(parts, tostring(w))
            end
        else
            table.insert(parts, tostring(v))
        end
    end

    return table.concat(parts, ' ')
end

return Util
