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
local SnapshotInfo = addon.SnapshotInfo

local ProfileManager = addon:GetObject("ProfileManager")
local ShareCodec = addon:GetObject("ShareCodec")

-- Encode a module set to a shared string, paired with the export's
-- hash-of-hashes fingerprint over that same subset. Returns the string, nil,
-- and the fingerprint, or nil and a reason when encoding fails.
local function EncodeWithFingerprint(modules, classID, timestamp, notes)
    local share, reason = ShareCodec:Encode(modules, classID, timestamp, notes)
    if not share then
        return nil, reason
    end
    return share, nil, (SnapshotInfo:Fingerprint(modules))
end

-- Anonymised shared string for a profile snapshot (latest when selector is
-- nil). opts.modules narrows the export to a { [name] = true } subset and
-- opts.notes sets the travelling note (falling back to the snapshot's own).
-- Returns the string and its content fingerprint, or nil + a reason.
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

    local modules = snapshot:Modules(opts.modules)
    if next(modules) == nil then
        return nil, "no-modules"
    end

    local classID = snapshot:GetCharacterInfo().ClassID
    local notes = opts.notes ~= nil and opts.notes or snapshot:GetNotes()
    return EncodeWithFingerprint(modules, classID, snapshot:GetTimestamp(), notes)
end

-- Anonymised shared string for a character's current live snapshot. opts.modules
-- narrows the export to a { [name] = true } subset and opts.notes attaches a note.
-- Returns the string and its content fingerprint, or nil + a reason.
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

    local modules = liveSnapshot:Modules(opts.modules)
    if next(modules) == nil then
        return nil, "no-modules"
    end
    return EncodeWithFingerprint(modules, liveSnapshot:GetCharacterInfo().ClassID, liveSnapshot:GetTimestamp(), opts.notes)
end
