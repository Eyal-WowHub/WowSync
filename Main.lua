local addon = LibStub("Addon-1.0"):New(...)

-- Whether this is an unpackaged developer build. The X-WowSync-DevMode flag is
-- wrapped in a #@debug@ block, so the packager strips it from every release.
-- Developer builds run every contract check; releases skip the expensive ones.
local DEV_MODE = C_AddOns.GetAddOnMetadata(addon:GetName(), "X-WowSync-DevMode") == "1"

-- The contract checker shared by every WowSync file.
addon.Contracts = LibStub("Contracts-1.0"):New(DEV_MODE and "none" or "expensive")

-- On-disk schema revision.
local SCHEMA_VERSION = 1

-- The complete saved-variables shape. Every field is written to disk on load so
-- the file is fully self-describing for external tools that parse it directly.
-- Each character owns a single record under Profiles, holding its live Current,
-- its undo stack and its saved snapshot history.
local DB_DEFAULTS = {
    SchemaVersion = SCHEMA_VERSION,
    Settings = {
        MaxSnapshots = 20,
        MaxUndo = 10,
        Watcher = "lazy",
    },
    Profiles = {},
    Imports = {},
    ImportSequence = 0,
}

function addon:OnInitialized()
    WowSyncDB = addon.Database:ApplyDefaults(WowSyncDB or {}, DB_DEFAULTS)
    self.DB = WowSyncDB
    if DEV_MODE then
        self:Print(addon.L["Developer mode is active — contract checks are fully enabled."])
    end
end

-- Prints a chat message prefixed with the accent-coloured addon name.
function addon:Print(msg)
    local prefix = addon.Colorizer:Wrap(addon.ACCENT_COLOR, addon:GetName()) .. ": "
    DEFAULT_CHAT_FRAME:AddMessage(prefix .. msg)
end

-- Prints a chat message with no addon-name prefix, for continuation lines that
-- belong under a preceding prefixed line.
function addon:PrintLine(msg)
    DEFAULT_CHAT_FRAME:AddMessage(msg)
end