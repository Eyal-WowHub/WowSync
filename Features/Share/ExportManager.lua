local _, addon = ...
local ExportManager = addon:NewObject("ExportManager")

--[[
    ExportManager — turns stored setups into portable shared strings.

    It reads a profile snapshot or a character's current head, optionally narrows
    it to a subset of modules, and hands it to ShareCodec to produce an
    anonymised shared string. It owns no state and stores nothing; exporting is a
    pure read.
]]

local ShareCodec = addon:GetObject("ShareCodec")
local ProfileManager = addon:GetObject("ProfileManager")

-- Keep only the modules named in `allowed` (a { [name] = true } set). With no
-- set the full { [name] = data } table passes through unchanged.
local function FilterModules(modules, allowed)
    if not allowed then
        return modules
    end
    local filtered = {}
    for name, data in pairs(modules) do
        if allowed[name] then
            filtered[name] = data
        end
    end
    return filtered
end

-- Anonymised shared string for a profile snapshot (latest when selector is
-- nil). opts.modules narrows the export to a { [name] = true } subset and
-- opts.notes sets the travelling note (falling back to the snapshot's own).
-- Returns the string, or nil + a reason.
function ExportManager:ExportSnapshot(profileName, selector, opts)
    opts = opts or {}

    local snapshot, reason
    if selector then
        snapshot, reason = ProfileManager:FindSnapshot(profileName, selector)
    else
        snapshot = ProfileManager:Latest(profileName)
    end
    if not snapshot then
        return nil, reason or "not-found"
    end

    local modules = FilterModules(snapshot:Modules(), opts.modules)
    if next(modules) == nil then
        return nil, "no-modules"
    end

    local classID = snapshot:GetCharacterInfo().ClassID
    local notes = opts.notes ~= nil and opts.notes or snapshot:GetNotes()
    return ShareCodec:Encode(modules, classID, snapshot:GetTimestamp(), notes)
end

-- Anonymised shared string for a character's current head. opts.modules narrows
-- the export to a { [name] = true } subset and opts.notes attaches a note.
-- Returns the string, or nil + a reason.
function ExportManager:ExportHead(charKey, opts)
    opts = opts or {}

    local head = ProfileManager:GetHead(charKey)
    if not head then
        return nil, "not-found"
    end

    local modules = FilterModules(head:Modules(), opts.modules)
    if next(modules) == nil then
        return nil, "no-modules"
    end
    return ShareCodec:Encode(modules, head:GetCharacterInfo().ClassID, head:GetTimestamp(), opts.notes)
end
