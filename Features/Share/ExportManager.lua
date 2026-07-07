local _, addon = ...
local ExportManager = addon:NewObject("ExportManager")

--[[
    ExportManager — turns stored setups into portable shared strings.

    It reads a profile snapshot or a character's current live snapshot, optionally narrows
    it to a subset of modules, and hands it to ShareCodec to produce an
    anonymised shared string. It owns no state and stores nothing; exporting is a
    pure read.
]]

local C = addon.Contracts

local ProfileManager = addon:GetObject("ProfileManager")
local ShareCodec = addon:GetObject("ShareCodec")

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
function ExportManager:ExportSavedSnapshot(profileName, selector, opts)
    C:IsString(profileName, 2)
    opts = opts or {}

    local profile = ProfileManager:GetProfile(profileName)
    if not profile then
        return nil, "not-found"
    end

    local snapshot, reason
    if selector then
        snapshot, reason = ProfileManager:FindSnapshot(profile, selector)
    else
        snapshot = profile:GetLatestSnapshot()
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

-- Anonymised shared string for a character's current live snapshot. opts.modules
-- narrows the export to a { [name] = true } subset and opts.notes attaches a note.
-- Returns the string, or nil + a reason.
function ExportManager:ExportLiveSnapshot(charKey, opts)
    C:IsString(charKey, 2)
    opts = opts or {}

    local profile = ProfileManager:GetProfile(charKey)
    if not profile then
        return nil, "not-found"
    end

    local liveSnapshot = ProfileManager:GetLiveSnapshot(profile)
    if not liveSnapshot then
        return nil, "not-found"
    end

    local modules = FilterModules(liveSnapshot:Modules(), opts.modules)
    if next(modules) == nil then
        return nil, "no-modules"
    end
    return ShareCodec:Encode(modules, liveSnapshot:GetCharacterInfo().ClassID, liveSnapshot:GetTimestamp(), opts.notes)
end
