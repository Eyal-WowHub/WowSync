local _, addon = ...
local Commands = addon:NewObject("Commands")

local ProfileManager = addon:GetObject("ProfileManager")
local GameWatcher = addon:GetObject("GameWatcher")
local L = addon.L

--[[
    Slash command interface ("/wowsync", "/ws").

    Parses the player's input and routes it to the ProfileManager facade,
    printing feedback through WowSync:Print. With no arguments it simply toggles
    the companion UI (see WowSync:ToggleUI in Core/API.lua).
]]

-- Splits a "<name>@<hash>" selector. Returns the profile name plus the hash
-- (lowercased) when present, or just the name with nil when there is no "@".
local function ParseSelector(text)
    local hash = text:match("^.-@(%w+)$")
    if hash then
        return (text:gsub("@%w+$", "")), hash:lower()
    end
    return text, nil
end

-- Prints feedback for a snapshot selector that could not be resolved.
local function PrintSnapshotError(hash, reason)
    if reason == "ambiguous" then
        WowSync:Print(L["Snapshot 'X' is ambiguous."]:format(hash))
    else
        WowSync:Print(L["No snapshot matches 'X'."]:format(hash))
    end
end

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
            local trailing = arg:match("%s(%-%-%S+)$")
            if trailing then
                local lower = trailing:lower()
                if lower == "--merge" or lower == "--exact" then
                    mode = lower:sub(3)
                    profileName = strtrim(arg:sub(1, #arg - #trailing))
                end
            end

            local hash
            profileName, hash = ParseSelector(profileName)

            local lowerName = profileName:lower()
            if lowerName == "current" or lowerName == "latest" then
                WowSync:Print(L["'current' and 'latest' are reserved; name a profile to apply."])
                return
            end

            if not ProfileManager:GetProfile(profileName) then
                WowSync:Print(L["Profile 'X' not found."]:format(profileName))
                return
            end

            if hash then
                local snapshot, reason = ProfileManager:GetSnapshot(profileName, hash)
                if not snapshot then
                    PrintSnapshotError(hash, reason)
                    return
                end
                hash = snapshot.Hash
            end

            local result = ProfileManager:Apply(profileName, hash, { default = mode })
            for _, name in ipairs(result:Applied()) do
                local outcome = result:Get(name)
                local msg = L["X: applied"]:format(name)
                if outcome.warning then
                    msg = L["X (Y)"]:format(msg, outcome.warning)
                end
                WowSync:Print(msg)
            end
            for _, name in ipairs(result:Skipped()) do
                WowSync:Print(L["X: skipped - Y"]:format(name, result:Get(name).reason or L["unknown"]))
            end
        elseif command == "undo" then
            if not ProfileManager:HasUndo() then
                WowSync:Print(L["Nothing to undo."])
            else
                local result = ProfileManager:Undo()
                if result then
                    WowSync:Print(L["Undid the last apply:"])
                    for _, name in ipairs(result:Applied()) do
                        WowSync:Print(L["  X: restored"]:format(name))
                    end
                end
            end
        elseif command == "delete" and arg and arg ~= "" then
            local profileName, hash = ParseSelector(arg)

            if hash then
                if not ProfileManager:GetProfile(profileName) then
                    WowSync:Print(L["Profile 'X' not found."]:format(profileName))
                    return
                end

                local snapshot, reason = ProfileManager:GetSnapshot(profileName, hash)
                if not snapshot then
                    PrintSnapshotError(hash, reason)
                    return
                end

                if ProfileManager:DeleteSnapshot(profileName, snapshot.Hash) then
                    WowSync:Print(L["Snapshot 'X' deleted."]:format(snapshot.Hash:sub(1, 7)))
                end
            elseif ProfileManager:DeleteProfile(profileName) then
                WowSync:Print(L["Profile 'X' deleted."]:format(profileName))
            else
                WowSync:Print(L["Profile 'X' not found."]:format(profileName))
            end
        elseif command == "list" then
            if arg and arg ~= "" then
                local profile = ProfileManager:GetProfile(arg)
                if not profile then
                    WowSync:Print(L["Profile 'X' not found."]:format(arg))
                    return
                end

                local snapshots = profile.Snapshots
                if #snapshots == 0 then
                    WowSync:Print(L["Profile 'X' has no snapshots."]:format(arg))
                    return
                end

                local Snapshot = addon:GetObject("Snapshot")
                WowSync:Print(L["Snapshots for 'X':"]:format(arg))
                for index = #snapshots, 1, -1 do
                    local snapshot = snapshots[index]
                    local shortHash = snapshot.Hash:sub(1, 7)
                    local subject = Snapshot:GetSubject(snapshot)
                    if snapshot.Pinned then
                        WowSync:Print(L["  X - Y (pinned)"]:format(shortHash, subject))
                    else
                        WowSync:Print(L["  X - Y"]:format(shortHash, subject))
                    end
                end
            else
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
            end
        elseif command == "watcher" then
            local state = (arg or ""):lower()
            if state == "on" then
                GameWatcher:SetEnabled(true)
                WowSync:Print(L["Live tracking is on."])
            elseif state == "off" then
                GameWatcher:SetEnabled(false)
                WowSync:Print(L["Live tracking is off."])
            else
                WowSync:Print(L["Usage: /ws watcher on|off."])
            end
        elseif command == "help" then
            WowSync:Print(L["Usage: (/ws and /wowsync are interchangeable)"])
            WowSync:Print(L["  /ws - Toggle the UI"])
            WowSync:Print(L["  /ws save <name> - Save current setup to a profile"])
            WowSync:Print(L["  /ws apply <name>[@hash] [--merge|--exact] - Apply latest or a specific snapshot"])
            WowSync:Print(L["  /ws undo - Undo the last apply"])
            WowSync:Print(L["  /ws delete <name>[@hash] - Delete a profile or one of its snapshots"])
            WowSync:Print(L["  /ws list [name] - List profiles, or a profile's snapshots"])
            WowSync:Print(L["  /ws watcher on|off - Mirror your changes live"])
        else
            WowSync:Print(L["Unknown command. Type /ws help."])
        end
    end
end
