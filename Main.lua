local addon = LibStub("Addon-1.0"):New(...)

local Colorizer = addon.Colorizer
local L = addon.L

local DB_DEFAULTS = {
    global = {
        Profiles = {},
        Characters = {},
        Settings = {
            MaxSnapshots = 20,
            MaxUndo = 20,
        },
    },
}

local function ToggleUI()
    if not C_AddOns.IsAddOnLoaded("WowSync_UI") and not C_AddOns.LoadAddOn("WowSync_UI") then
        addon:Print(L["WowSync_UI addon not found."])
        return
    end

    local ok = pcall(WowSyncUI_Toggle)
    if not ok then
        addon:Print(L["Could not open the WowSync window."])
    end
end

function WowSync_OnAddonCompartmentClick()
    ToggleUI()
end

function addon:OnInitialized()
    self.DB = LibStub("AceDB-3.0"):New("WowSyncDB", DB_DEFAULTS, true)

    SLASH_WOWSYNC1 = "/wowsync"
    SLASH_WOWSYNC2 = "/ws"
    SlashCmdList["WOWSYNC"] = function(input)
        local command, arg = strsplit(" ", strtrim(input or ""), 2)
        command = (command or ""):lower()
        arg = arg and strtrim(arg)

        if command == "" then
            ToggleUI()
            return
        end

        local ProfileManager = self:GetObject("ProfileManager")

        if command == "save" and arg and arg ~= "" then
            local snapshot, reason = ProfileManager:Save(arg)
            if snapshot then
                self:Print(L["Profile 'X' saved."]:format(arg))
            elseif reason == "unchanged" then
                self:Print(L["Nothing changed since the last save."])
            end
        elseif command == "apply" and arg and arg ~= "" then
            local profileName, mode = arg, nil
            local trailing = arg:match("%s(%S+)$")
            if trailing then
                local lower = trailing:lower()
                if lower == "merge" or lower == "replace" then
                    mode = lower
                    profileName = strtrim(arg:sub(1, #arg - #trailing))
                end
            end

            local lowerName = profileName:lower()
            if lowerName == "current" or lowerName == "latest" then
                self:Print(L["'current' and 'latest' are reserved; name a profile to apply."])
                return
            end

            if not ProfileManager:GetProfile(profileName) then
                self:Print(L["Profile 'X' not found."]:format(profileName))
                return
            end

            local results = ProfileManager:Apply(profileName, nil, { default = mode })
            if results then
                for name, result in pairs(results) do
                    if result.applied then
                        local msg = L["X: applied"]:format(name)
                        if result.warning then
                            msg = L["X (Y)"]:format(msg, result.warning)
                        end
                        self:Print(msg)
                    else
                        self:Print(L["X: skipped - Y"]:format(name, result.reason or L["unknown"]))
                    end
                end
            end
        elseif command == "undo" then
            if not ProfileManager:HasUndo() then
                self:Print(L["Nothing to undo."])
            else
                local results = ProfileManager:Undo()
                if results then
                    self:Print(L["Undid the last apply:"])
                    for name, result in pairs(results) do
                        if result.applied then
                            self:Print(L["  X: restored"]:format(name))
                        end
                    end
                end
            end
        elseif command == "delete" and arg and arg ~= "" then
            if ProfileManager:DeleteProfile(arg) then
                self:Print(L["Profile 'X' deleted."]:format(arg))
            else
                self:Print(L["Profile 'X' not found."]:format(arg))
            end
        elseif command == "list" then
            local profiles = ProfileManager:GetProfiles()
            if next(profiles) then
                local Snapshot = self:GetObject("Snapshot")
                self:Print(L["Saved profiles:"])
                for name, profile in pairs(profiles) do
                    local snapshots = profile.Snapshots
                    local latest = snapshots[#snapshots]
                    local subject = latest and Snapshot:GetSubject(latest) or L["empty"]
                    self:Print(L["  X (Y) - Z"]:format(name, #snapshots, subject))
                end
            else
                self:Print(L["No saved profiles."])
            end
        else
            self:Print(L["Usage:"])
            self:Print(L["  /ws save <name> - Save current setup to a profile"])
            self:Print(L["  /ws apply <name> [merge|replace] - Apply a profile's latest snapshot"])
            self:Print(L["  /ws undo - Undo the last apply"])
            self:Print(L["  /ws delete <name> - Delete a profile"])
            self:Print(L["  /ws list - List all saved profiles"])
        end
    end
end

function addon:Print(msg)
    local prefix = Colorizer:ToAccent(self:GetName()) .. ": "
    DEFAULT_CHAT_FRAME:AddMessage(prefix .. msg)
end