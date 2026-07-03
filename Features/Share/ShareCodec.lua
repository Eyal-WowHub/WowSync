local _, addon = ...
local ShareCodec = addon:NewObject("ShareCodec")
local ShareUtils = addon:GetObject("ShareUtils")

local Time = addon.Time
local Codec = addon.Codec

--[[
    ShareCodec — the wire format for a shared string.

    A shared string is an envelope: ENVELOPE_PREFIX followed by a single
    Codec-encoded payload carrying the raw module data plus its class, capture
    time and note. It is anonymised — only the class, timestamp and note travel
    with the module data; character and realm names are dropped. Encoding turns a
    captured module set into the string; decoding validates the untrusted shape
    and normalises it back into plain { Modules, ClassID, Timestamp, Notes } data.
]]

local Trim = ShareUtils.Trim
local IsValidClassID = ShareUtils.IsValidClassID

-- Identifies a WowSync shared string; the rest is a Codec-encoded payload.
local ENVELOPE_PREFIX = "WSYNC1:"

-- Anonymise a captured module set into a shared string. Returns the string, or
-- nil + a reason ("no-class", "encode-failed").
function ShareCodec:Encode(modules, classID, timestamp, notes)
    if not IsValidClassID(classID) then
        return nil, "no-class"
    end

    local payload = {
        Timestamp = timestamp or Time:Now(),
        Source = { ClassID = classID },
        Notes = notes,
        Modules = modules,
    }

    local encoded, err = Codec:Encode(payload)
    if not encoded then
        return nil, err or "encode-failed"
    end
    return ENVELOPE_PREFIX .. encoded
end

-- Decode and validate an untrusted shared string. Returns a normalised
-- { Modules, ClassID, Timestamp, Notes } table, or nil + a reason
-- ("invalid-input", "bad-format", "invalid-class").
function ShareCodec:Decode(text)
    if type(text) ~= "string" then
        return nil, "invalid-input"
    end

    text = Trim(text)
    if text:sub(1, #ENVELOPE_PREFIX) ~= ENVELOPE_PREFIX then
        return nil, "bad-format"
    end

    local payload = Codec:Decode(text:sub(#ENVELOPE_PREFIX + 1))
    if type(payload) ~= "table" or type(payload.Modules) ~= "table" or next(payload.Modules) == nil then
        return nil, "bad-format"
    end
    for name in pairs(payload.Modules) do
        if type(name) ~= "string" then
            return nil, "bad-format"
        end
    end

    local classID = type(payload.Source) == "table" and payload.Source.ClassID or nil
    if not IsValidClassID(classID) then
        return nil, "invalid-class"
    end

    return {
        Modules = payload.Modules,
        ClassID = classID,
        Timestamp = type(payload.Timestamp) == "number" and payload.Timestamp or Time:Now(),
        Notes = type(payload.Notes) == "string" and payload.Notes or nil,
    }
end
