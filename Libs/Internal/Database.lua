local _, addon = ...
local Database = {}
addon.Database = Database

--[[
    Database — utilities for preparing a saved-variables table for use.

    The schema itself lives with its owner; this holds only the generic
    mechanics for working with that data.
]]

-- Writes any missing default keys into target, recursing into nested tables and
-- leaving existing values untouched. Returns target.
function Database:ApplyDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then
                target[key] = {}
            end
            self:ApplyDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
    return target
end
