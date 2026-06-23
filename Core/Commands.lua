local _, addon = ...
local Commands = addon:NewObject("Commands")

local ProfileManager = addon:GetObject("ProfileManager")
local L = addon.L

--[[
    Slash command interface ("/wowsync", "/ws").

    Parses the player's input and routes it to the ProfileManager facade,
    printing feedback through WowSync:Print. With no arguments it simply toggles
    the companion UI (see WowSync:ToggleUI in Core/API.lua).
]]

function Commands:OnInitialized()
    SLASH_WOWSYNC1 = "/wowsync"
    SLASH_WOWSYNC2 = "/ws"
    SlashCmdList["WOWSYNC"] = function(input)
        local command, arg = strsplit(" ", strtrim(input or ""), 2)
        command = (command or ""):lower()
        arg = arg and strtrim(arg)

        if command == "" then
            WowSync:ToggleUI()
            return
        end

        if command == "save" and arg and arg ~= "" then
            local snapshot, reason = ProfileManager:Save(arg)
            if snapshot then
                WowSync:Print(L["Profile 'X' saved."]:format(arg))
            elseif reason == "unchanged" then
                WowSync:Print(L["Nothing changed since the last save."])
            end
        elseif command == "apply" and arg and arg ~= "" then
            local profileName, mode = arg, nil
            local trailing = arg:match("%s(%S+)$")
            if trailing then
                local lower = trailing:lower()
                if lower == "merge" or lower == "exact" then
                    mode = lower
                    profileName = strtrim(arg:sub(1, #arg - #trailing))
                end
            end

            local lowerName = profileName:lower()
            if lowerName == "current" or lowerName == "latest" then
                WowSync:Print(L["'current' and 'latest' are reserved; name a profile to apply."])
                return
            end

            if not ProfileManager:GetProfile(profileName) then
                WowSync:Print(L["Profile 'X' not found."]:format(profileName))
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
                        WowSync:Print(msg)
                    else
                        WowSync:Print(L["X: skipped - Y"]:format(name, result.reason or L["unknown"]))
                    end
                end
            end
        elseif command == "undo" then
            if not ProfileManager:HasUndo() then
                WowSync:Print(L["Nothing to undo."])
            else
                local results = ProfileManager:Undo()
                if results then
                    WowSync:Print(L["Undid the last apply:"])
                    for name, result in pairs(results) do
                        if result.applied then
                            WowSync:Print(L["  X: restored"]:format(name))
                        end
                    end
                end
            end
        elseif command == "delete" and arg and arg ~= "" then
            if ProfileManager:DeleteProfile(arg) then
                WowSync:Print(L["Profile 'X' deleted."]:format(arg))
            else
                WowSync:Print(L["Profile 'X' not found."]:format(arg))
            end
        elseif command == "list" then
            local profiles = ProfileManager:GetProfiles()
            if next(profiles) then
                local Snapshot = addon:GetObject("Snapshot")
                WowSync:Print(L["Saved profiles:"])
                for name, profile in pairs(profiles) do
                    local snapshots = profile.Snapshots
                    local latest = snapshots[#snapshots]
                    local subject = latest and Snapshot:GetSubject(latest) or L["empty"]
                    WowSync:Print(L["  X (Y) - Z"]:format(name, #snapshots, subject))
                end
            else
                WowSync:Print(L["No saved profiles."])
            end
        else
            WowSync:Print(L["Usage:"])
            WowSync:Print(L["  /ws save <name> - Save current setup to a profile"])
            WowSync:Print(L["  /ws apply <name> [merge|exact] - Apply a profile's latest snapshot"])
            WowSync:Print(L["  /ws undo - Undo the last apply"])
            WowSync:Print(L["  /ws delete <name> - Delete a profile"])
            WowSync:Print(L["  /ws list - List all saved profiles"])
        end
    end
end
