local _, addon = ...
local ShareUtils = addon:NewObject("ShareUtils")

--[[
    ShareUtils — small shared helpers for the share subsystem.

    Both the wire format (ShareCodec) and the store (ImportStore) trim
    user-typed text and gate on real player classes; these are the single
    definitions they share.
]]

-- Trim surrounding whitespace from a pasted string.
function ShareUtils.Trim(text)
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- True when classID names a real player class.
function ShareUtils.IsValidClassID(classID)
    return type(classID) == "number" and C_CreatureInfo.GetClassInfo(classID) ~= nil
end
