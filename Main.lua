local addon = LibStub("Addon-1.0"):New(...)

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
}

function addon:OnInitialized()
    WowSyncDB = addon.Database:ApplyDefaults(WowSyncDB or {}, DB_DEFAULTS)
    self.DB = WowSyncDB
end

-- Prints a chat message prefixed with the accent-coloured addon name.
function addon:Print(msg)
    local prefix = addon.Colorizer:ToAccent(addon:GetName()) .. ": "
    DEFAULT_CHAT_FRAME:AddMessage(prefix .. msg)
end