local addon = LibStub("Addon-1.0"):New(...)

local Colorizer = addon.Colorizer
local L = addon.L

local DB_DEFAULTS = {
    global = {
        Profiles = {},
        RevertPoints = {},
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
            if ProfileManager:Save(arg) then
                self:Print(L["Profile 'X' saved."]:format(arg))
            end
        elseif command == "apply" and arg and arg ~= "" then
            local results = ProfileManager:Apply(arg)
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
        elseif command == "delete" and arg and arg ~= "" then
            if ProfileManager:Delete(arg) then
                self:Print(L["Profile 'X' deleted."]:format(arg))
            else
                self:Print(L["Profile 'X' not found."]:format(arg))
            end
        elseif command == "list" then
            local profiles = ProfileManager:GetProfiles()
            if next(profiles) then
                self:Print(L["Saved profiles:"])
                for name, profile in pairs(profiles) do
                    local className = C_CreatureInfo.GetClassInfo(profile.Meta.ClassID)
                    local label = className and className.className or L["Unknown"]
                    self:Print(L["  X (Y) - Z"]:format(name, label, profile.Meta.LastCharacter))
                end
            else
                self:Print(L["No saved profiles."])
            end
        elseif command == "revert" then
            if not ProfileManager:HasRevertPoint() then
                self:Print(L["No revert point available for this character."])
            else
                local info = ProfileManager:GetRevertInfo()
                local results = ProfileManager:Revert()
                if results then
                    self:Print(L["Reverted changes from profile 'X':"]:format(info.ProfileName or L["Unknown"]))
                    for name, result in pairs(results) do
                        if result.applied then
                            self:Print(L["  X: reverted"]:format(name))
                        end
                    end
                end
            end
        else
            self:Print(L["Usage:"])
            self:Print(L["  /ws save <name> - Save current setup as a profile"])
            self:Print(L["  /ws apply <name> - Apply a profile to this character"])
            self:Print(L["  /ws delete <name> - Delete a profile"])
            self:Print(L["  /ws list - List all saved profiles"])
            self:Print(L["  /ws revert - Undo the last applied profile"])
        end
    end
end

function addon:Print(msg)
    local prefix = Colorizer:ToAccent(self:GetName()) .. ": "
    DEFAULT_CHAT_FRAME:AddMessage(prefix .. msg)
end