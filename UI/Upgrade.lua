local _, addon = ...
local Upgrade = addon:NewObject("Upgrade")

--[[
    Upgrade — the one-time database reset gate for the current overhaul.

    This release reshaped the saved data incompatibly, so a database written by
    an older schema must be reset once before the addon can be used. A database
    whose SchemaVersion is below RESET_BELOW_SCHEMA is "pending": the UI toggle
    and the slash handler call ShowIfPending, which raises the WOWSYNC_UPGRADE
    prompt instead of proceeding, until the player accepts the reset. Accepting
    clears every profile and import, stamps the current schema so the prompt
    never returns, and reloads.
]]

local ProfileManager = addon:GetObject("ProfileManager")
local ImportManager = addon:GetObject("ImportManager")

-- Databases older than this schema must be reset once before use. Kept separate
-- from the current schema version so a later, non-destructive schema bump does
-- not re-trigger this prompt.
local RESET_BELOW_SCHEMA = 2

-- Whether the stored database predates the overhaul and still needs its one-time
-- reset.
function Upgrade:IsPending()
    local db = addon.DB or WowSyncDB
    if type(db) ~= "table" then
        return false
    end
    return (db.SchemaVersion or 0) < RESET_BELOW_SCHEMA
end

-- Wipe the incompatible saved data, stamp the current schema so the prompt never
-- returns, and reload so every view reinitialises from the clean database.
function Upgrade:PerformReset()
    ProfileManager:ResetDatabase()
    ImportManager:ResetDatabase()
    addon.DB.SchemaVersion = addon.SchemaVersion
    C_UI.Reload()
end

-- Raise the upgrade prompt when a reset is still pending, returning whether it
-- did so callers can stop before opening the UI or running a command.
function Upgrade:ShowIfPending()
    if not self:IsPending() then
        return false
    end
    StaticPopup_Show("WOWSYNC_UPGRADE")
    return true
end
