local addon = LibStub("Addon-1.0"):New(...)

local DB_DEFAULTS = {
    global = {
        Profiles = {},
        Characters = {},
        Settings = {
            MaxSnapshots = 20,
            MaxUndo = 20,
            Watcher = true,
        },
    },
}

function addon:OnInitialized()
    self.DB = LibStub("AceDB-3.0"):New("WowSyncDB", DB_DEFAULTS, true)
end