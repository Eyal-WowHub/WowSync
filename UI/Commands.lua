local _, addon = ...
local Commands = addon:NewObject("Commands")
local ProfileManager = addon:GetObject("ProfileManager")
local SnapshotManager = addon:GetObject("SnapshotManager")
local CharacterManager = addon:GetObject("CharacterManager")
local GameWatcher = addon:GetObject("GameWatcher")
local Snapshot = addon:GetObject("Snapshot")

local L = addon.L

--[[
    Slash command interface ("/wowsync", "/ws").

    Parses the player's input and routes it to the snapshot and profile
    managers, printing feedback through WowSync:Print. With no arguments it
    simply toggles the companion UI.
]]

-- Splits a "<name>@<hash[#index]>" selector. Returns the profile name plus
-- the selector (lowercased) when present, or just the name with nil.
local function ParseSelector(text)
    local selector = text:match("^.-@([^%s]+)$")
    if selector then
        return (text:gsub("@[^%s]+$", "")), selector:lower()
    end
    return text, nil
end

-- Prints feedback for a snapshot selector that could not be resolved.
local function PrintSnapshotError(selector, reason, candidates)
    if reason == "ambiguous" then
        WowSync:Print(L["Multiple snapshots match 'X'. Use the full snapshot selector:"]:format(selector))
        for _, snapshot in ipairs(candidates or {}) do
            WowSync:Print(L["  X - Y"]:format(Snapshot:GetSelector(snapshot), Snapshot:GetSubject(snapshot)))
        end
    else
        WowSync:Print(L["No snapshot matches 'X'."]:format(selector))
    end
end

-- Resolves a user-typed character token to a stored profile key, printing the
-- not-found or ambiguous-match feedback itself. Returns the key, or nil.
local function GetResolvedCharacter(token)
    local profileName, reason, candidates = CharacterManager:ResolveCharacterName(token)

    if profileName then
        return profileName
    end

    if reason == "ambiguous" then
        WowSync:Print(L["Multiple characters match 'X'. Add a realm to disambiguate (e.g. Name-Realm):"]:format(token))
        for _, candidate in ipairs(candidates or {}) do
            WowSync:Print(L["  X"]:format(candidate))
        end
    else
        WowSync:Print(L["No character matches 'X'."]:format(token))
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

        if command == "save" then
            local note = (arg and arg ~= "") and arg or nil
            local evicted = SnapshotManager:PreviewSaveSnapshotByCharKey(nil)
            SnapshotManager:SaveCurrentSnapshot(note, nil, function(snapshot, reason)
                if snapshot then
                    WowSync:Print(L["Snapshot saved."])
                    if evicted then
                        WowSync:Print(L["Reached the snapshot limit — removed the oldest (X)."]:format(
                            Snapshot:GetSubject(evicted)))
                    end
                elseif reason == "busy" then
                    WowSync:Print(L["A save is already in progress."])
                else
                    WowSync:Print(L["Could not save. Try again."])
                end
            end)
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

            local selector
            profileName, selector = ParseSelector(profileName)

            local lowerName = profileName:lower()
            if lowerName == "current" or lowerName == "latest" then
                WowSync:Print(L["'current' and 'latest' are reserved; name a profile to apply."])
                return
            end

            local resolvedProfileName = GetResolvedCharacter(profileName)

            if not resolvedProfileName then
                return
            end

            profileName = resolvedProfileName

            if selector then
                local snapshot, reason, candidates = SnapshotManager:GetSnapshot(profileName, selector)
                if not snapshot then
                    PrintSnapshotError(selector, reason, candidates)
                    return
                end
                selector = Snapshot:GetSelector(snapshot)
            end

            local applyResult = SnapshotManager:ApplySnapshot(profileName, selector, { default = mode })
            for _, moduleName in ipairs(applyResult:Applied()) do
                local outcome = applyResult:Get(moduleName)
                local message = L["X: applied"]:format(moduleName)
                if outcome.warning then
                    message = L["X (Y)"]:format(message, outcome.warning)
                end
                WowSync:Print(message)
            end
            for _, moduleName in ipairs(applyResult:Skipped()) do
                WowSync:Print(L["X: skipped - Y"]:format(moduleName, applyResult:Get(moduleName).reason or L["unknown"]))
            end
        elseif command == "undo" then
            if not SnapshotManager:CanUndo() then
                WowSync:Print(L["Nothing to undo."])
            else
                local undoResult = SnapshotManager:UndoLastApply()
                if undoResult then
                    WowSync:Print(L["Undid the last apply:"])
                    for _, moduleName in ipairs(undoResult:Applied()) do
                        WowSync:Print(L["  X: restored"]:format(moduleName))
                    end
                end
            end
        elseif command == "delete" and arg and arg ~= "" then
            local profileName, selector = ParseSelector(arg)

            local resolvedProfileName = GetResolvedCharacter(profileName)

            if not resolvedProfileName then
                return
            end

            profileName = resolvedProfileName

            if selector then
                local snapshot, reason, candidates = SnapshotManager:GetSnapshot(profileName, selector)
                if not snapshot then
                    PrintSnapshotError(selector, reason, candidates)
                    return
                end

                selector = Snapshot:GetSelector(snapshot)
                if SnapshotManager:DeleteSnapshot(profileName, selector) then
                    WowSync:Print(L["Snapshot 'X' deleted."]:format(selector))
                end
            elseif ProfileManager:DeleteProfile(profileName) then
                WowSync:Print(L["Profile 'X' deleted."]:format(profileName))
            end
        elseif command == "list" then
            if arg and arg ~= "" then
                local profileName = GetResolvedCharacter(arg)

                if not profileName then
                    return
                end

                local profile = ProfileManager:GetProfile(profileName)
                local snapshots = profile.Snapshots
                if not snapshots or #snapshots == 0 then
                    WowSync:Print(L["Profile 'X' has no snapshots."]:format(profileName))
                    return
                end

                WowSync:Print(L["Snapshots for 'X':"]:format(profileName))
                for index = #snapshots, 1, -1 do
                    local snapshot = snapshots[index]
                    local selector = ("%s#%s"):format(snapshot.Hash:sub(1, 7), snapshot.Index)
                    local subject = Snapshot:GetSubject(snapshot)
                    if snapshot.Pinned then
                        WowSync:Print(L["  X - Y (pinned)"]:format(selector, subject))
                    else
                        WowSync:Print(L["  X - Y"]:format(selector, subject))
                    end
                end
            else
                local profiles = ProfileManager:GetProfiles()
                if next(profiles) then
                    WowSync:Print(L["Saved profiles:"])
                    for profileName, profile in pairs(profiles) do
                        local snapshots = profile.Snapshots
                        local latestSnapshot = snapshots[#snapshots]
                        local subject = latestSnapshot and Snapshot:GetSubject(latestSnapshot) or L["empty"]
                        WowSync:Print(L["  X (Y) - Z"]:format(profileName, #snapshots, subject))
                    end
                else
                    WowSync:Print(L["No saved profiles."])
                end
            end
        elseif command == "watcher" then
            local watcherMode = (arg or ""):lower()
            if watcherMode == "lazy" then
                GameWatcher:SetTrackingMode("lazy")
                WowSync:Print(L["Live tracking is on demand."])
            elseif watcherMode == "off" then
                GameWatcher:SetTrackingMode("off")
                WowSync:Print(L["Live tracking is off."])
            else
                WowSync:Print(L["Usage: X"]:format("/ws watcher off|lazy"))
            end
        elseif command == "reset" then
            local resetTarget = (arg or ""):lower()
            if resetTarget == "database" or resetTarget == "db" then
                StaticPopup_Show("WOWSYNC_RESET_DB")
            else
                WowSync:Print(L["Usage: X"]:format("/ws reset database|db"))
            end
        elseif command == "help" then
            WowSync:Print(L["Usage: (X and Y are interchangeable)"]:format("/ws", "/wowsync"))
            WowSync:Print(L["  X - Y"]:format("/ws", L["Open or close the WowSync UI window"]))
            WowSync:Print(L["  X - Y"]:format("/ws save [note]", L["Save a snapshot of your current setup, optionally with a short note"]))
            WowSync:Print(L["  X - Y"]:format("/ws apply <name>[@hash[#index]] [--merge|--exact]", L["Apply a profile's latest snapshot, or a specific snapshot by hash (merge by default)"]))
            WowSync:Print(L["  X - Y"]:format("/ws undo", L["Undo the last applied snapshot"]))
            WowSync:Print(L["  X - Y"]:format("/ws delete <name>[@hash[#index]]", L["Delete a profile, or delete a specific snapshot by hash"]))
            WowSync:Print(L["  X - Y"]:format("/ws list [name]", L["List all saved profiles, or list one profile's snapshots"]))
            WowSync:Print(L["  X - Y"]:format("/ws watcher off|lazy", L["Track your setup live on demand, or turn tracking off entirely (lazy by default)"]))
            WowSync:Print(L["  X - Y"]:format("/ws reset database|db", L["Delete all saved profiles and snapshots, while keeping your settings"]))
            WowSync:Print(L["  X - Y"]:format("/ws help", L["Show the command list"]))
        else
            WowSync:Print(L["Unknown command. Type X."]:format("/ws help"))
        end
    end
end
