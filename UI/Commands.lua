local _, addon = ...
local Commands = addon:NewObject("Commands")

local L = addon.L

local CharacterManager = addon:GetObject("CharacterManager")
local Debugger = addon:GetObject("Debugger")
local GameWatcher = addon:GetObject("GameWatcher")
local ProfileManager = addon:GetObject("ProfileManager")
local SaveTask = addon:GetObject("SaveTask")
local SnapshotManager = addon:GetObject("SnapshotManager")
local UndoManager = addon:GetObject("UndoManager")

--[[
    Slash command interface ("/wowsync", "/ws").

    Parses the player's input and routes it to the snapshot and profile
    managers, printing feedback through addon:Print. With no arguments it
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

-- "<7-char hash>#<index>" short display selector for a saved snapshot.
local function ShortSelector(snapshot)
    local hash, index = snapshot:GetSelector():match("^(%w+)#(%d+)$")
    return ("%s#%s"):format(hash:sub(1, 7), index)
end

-- Prints feedback for a snapshot selector that could not be resolved.
local function PrintSnapshotError(selector, reason, candidates)
    if reason == "ambiguous" then
        addon:Print(L["Multiple snapshots match 'X'. Use the full snapshot selector:"]:format(selector))
        for _, snapshot in ipairs(candidates or {}) do
            addon:Print(L["  X - Y"]:format(snapshot:GetSelector(), snapshot:GetSubject()))
        end
    else
        addon:Print(L["No snapshot matches 'X'."]:format(selector))
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
        addon:Print(L["Multiple characters match 'X'. Add a realm to disambiguate (e.g. Name-Realm):"]:format(token))
        for _, candidate in ipairs(candidates or {}) do
            addon:Print(L["  X"]:format(candidate))
        end
    else
        addon:Print(L["No character matches 'X'."]:format(token))
    end
end

--[[ Status helpers ]]

-- Identity stanza: addon version, database schema revision, and the active
-- character key.
local function PrintAddonStatus()
    local version = C_AddOns.GetAddOnMetadata(addon:GetName(), "Version")
    -- The token is left unsubstituted on unpackaged (source) builds; the
    -- packager fills it in for a real release.
    if not version or version == "" or version == "@project-version@" then
        version = L["Prerelease"]
    end
    local schema = (addon.DB and addon.DB.SchemaVersion) or L["unknown"]
    addon:Print(L["[Addon]"])
    addon:PrintLine(L["  Version: X"]:format(version))
    addon:PrintLine(L["  Database schema: X"]:format(tostring(schema)))
    addon:PrintLine(L["  Character: X"]:format(SnapshotManager:GetCurrentCharKey()))
end

-- Profile stanza: stored snapshot count, latest snapshot summary, in-sync flag
-- against the live snapshot, and the undo stack depth. Fingerprints the live
-- snapshot to compute the in-sync flag, so this is the heaviest status stanza.
local function PrintProfileStatus()
    local charKey = SnapshotManager:GetCurrentCharKey()
    local profile = ProfileManager:GetProfile(charKey)
    local latest = profile and profile:GetLatestSnapshot()
    local liveSnapshot = profile and ProfileManager:GetLiveSnapshot(profile)
    local historyCount = profile and #profile:GetHistory() or 0

    addon:Print(L["[Profile]"])
    addon:PrintLine(L["  Snapshots: X / Y"]:format(historyCount, SnapshotManager:GetSnapshotLimit()))

    if latest then
        addon:PrintLine(L["  Latest: X - Y"]:format(ShortSelector(latest), latest:GetSubject()))
    else
        addon:PrintLine(L["  Latest: none"])
    end

    if not liveSnapshot then
        addon:PrintLine(L["  In sync: no captured state"])
    elseif latest and liveSnapshot:CompareTo(latest) then
        addon:PrintLine(L["  In sync: yes"])
    else
        addon:PrintLine(L["  In sync: no"])
    end

    local undoPoints = UndoManager:GetUndoPoints()
    if #undoPoints == 0 then
        addon:PrintLine(L["  Undo points: 0"])
    else
        addon:PrintLine(L["  Undo points: X (top: Y)"]:format(#undoPoints, undoPoints[1].Subject or L["Unknown"]))
    end
end

-- Watcher stanza: configured tracking mode (qualified active/idle for lazy)
-- and the save task's current state.
local function PrintWatcherStatus()
    local mode = GameWatcher:GetTrackingMode()
    local modeText
    if mode == "off" then
        modeText = L["off"]
    elseif GameWatcher:HasAttachments() then
        modeText = L["lazy (active)"]
    else
        modeText = L["lazy (idle)"]
    end

    addon:Print(L["[Watcher]"])
    addon:PrintLine(L["  Mode: X"]:format(modeText))
    addon:PrintLine(L["  Save task: X"]:format(SaveTask:IsRunning() and L["running"] or L["idle"]))
end

-- Debug stanza: logging on/off and recorded event count.
local function PrintDebugStatus()
    addon:Print(L["[Debug]"])
    if Debugger:IsEnabled() then
        addon:PrintLine(L["  Logging: on (X events)"]:format(Debugger:GetEventCount()))
    else
        addon:PrintLine(L["  Logging: off"])
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
            WowSync:Import("UI"):ToggleUI()
            return
        end

        -- Trace every command except the debug toggle itself, and attribute any
        -- apply/undo it triggers to the command line.
        if command ~= "debug" and Debugger:IsEnabled() then
            Debugger:RecordCommand({ Command = strtrim(input or "") })
        end

        -- Changing any saved setup is off-limits in combat, matching the core
        -- guards that no-op save/apply/undo while locked.
        if (command == "save" or command == "apply" or command == "undo" or command == "delete")
            and SnapshotManager:IsCombatLocked() then
            addon:Print(L["You can't do that while in combat."])
            return
        end

        if command == "save" then
            local note = (arg and arg ~= "") and arg or nil
            local evicted = SnapshotManager:PreviewSaveSnapshotByCharKey(nil)
            SnapshotManager:SaveCurrentSnapshot(note, nil, function(snapshot, reason)
                if snapshot then
                    addon:Print(L["Snapshot saved."])
                    if evicted then
                        addon:Print(L["Reached the snapshot limit — removed the oldest (X)."]:format(
                            evicted:GetSubject()))
                    end
                elseif reason == "busy" then
                    addon:Print(L["A save is already in progress."])
                else
                    addon:Print(L["Could not save. Try again."])
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
                addon:Print(L["'current' and 'latest' are reserved; name a profile to apply."])
                return
            end

            local resolvedProfileName = GetResolvedCharacter(profileName)

            if not resolvedProfileName then
                return
            end

            profileName = resolvedProfileName

            local profile = ProfileManager:GetProfile(profileName)
            if not profile then
                addon:Print(L["Profile 'X' has no snapshots."]:format(profileName))
                return
            end

            local snapshot
            if selector then
                local reason, candidates
                snapshot, reason, candidates = ProfileManager:FindSnapshot(profile, selector)
                if not snapshot then
                    PrintSnapshotError(selector, reason, candidates)
                    return
                end
            else
                snapshot = profile:GetLatestSnapshot()
                if not snapshot then
                    addon:Print(L["Profile 'X' has no snapshots."]:format(profileName))
                    return
                end
            end

            local applyResult = SnapshotManager:Apply(snapshot, { default = mode })
            for _, moduleName in ipairs(applyResult:Applied()) do
                local outcome = applyResult:Get(moduleName)
                local message = L["X: applied"]:format(moduleName)
                if outcome.warning then
                    message = L["X (Y)"]:format(message, outcome.warning)
                end
                addon:Print(message)
            end
            for _, moduleName in ipairs(applyResult:Skipped()) do
                addon:Print(L["X: skipped - Y"]:format(moduleName, applyResult:Get(moduleName).reason or L["unknown"]))
            end
        elseif command == "undo" then
            if not UndoManager:CanUndo() then
                addon:Print(L["Nothing to undo."])
            else
                local undoResult = UndoManager:UndoLastApply()
                if undoResult then
                    addon:Print(L["Undid the last apply:"])
                    for _, moduleName in ipairs(undoResult:Applied()) do
                        addon:Print(L["  X: restored"]:format(moduleName))
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
                local profile = ProfileManager:GetProfile(profileName)
                if not profile then
                    PrintSnapshotError(selector, "not-found")
                    return
                end

                local snapshot, reason, candidates = ProfileManager:FindSnapshot(profile, selector)
                if not snapshot then
                    PrintSnapshotError(selector, reason, candidates)
                    return
                end

                local resolvedSelector = snapshot:GetSelector()
                if ProfileManager:Remove(snapshot) then
                    addon:Print(L["Snapshot 'X' deleted."]:format(resolvedSelector))
                end
            elseif ProfileManager:DeleteProfile(profileName) then
                addon:Print(L["Profile 'X' deleted."]:format(profileName))
            end
        elseif command == "list" then
            if arg and arg ~= "" then
                local profileName = GetResolvedCharacter(arg)

                if not profileName then
                    return
                end

                local profile = ProfileManager:GetProfile(profileName)
                local history = profile and profile:GetHistory() or {}
                if #history == 0 then
                    addon:Print(L["Profile 'X' has no snapshots."]:format(profileName))
                    return
                end

                addon:Print(L["Snapshots for 'X':"]:format(profileName))
                for _, snapshot in ipairs(history) do
                    local selector = ShortSelector(snapshot)
                    local subject = snapshot:GetSubject()
                    if snapshot:IsPinned() then
                        addon:Print(L["  X - Y (pinned)"]:format(selector, subject))
                    else
                        addon:Print(L["  X - Y"]:format(selector, subject))
                    end
                end
            else
                local profiles = ProfileManager:GetProfiles()
                if #profiles > 0 then
                    addon:Print(L["Saved profiles:"])
                    for _, profile in ipairs(profiles) do
                        local profileName = profile:Key()
                        local latest = profile:GetLatestSnapshot()
                        local subject = latest and latest:GetSubject() or L["empty"]
                        addon:Print(L["  X (Y) - Z"]:format(profileName, #profile:Snapshots(), subject))
                    end
                else
                    addon:Print(L["No saved profiles."])
                end
            end
        elseif command == "export" then
            WowSync:Import("UI"):OpenShareDialog("export")
        elseif command == "import" then
            WowSync:Import("UI"):OpenShareDialog("import")
        elseif command == "watcher" then
            local watcherMode = (arg or ""):lower()
            if watcherMode == "lazy" then
                GameWatcher:SetTrackingMode("lazy")
                addon:Print(L["Live tracking is on demand."])
            elseif watcherMode == "off" then
                GameWatcher:SetTrackingMode("off")
                addon:Print(L["Live tracking is off."])
            else
                addon:Print(L["Usage: X"]:format("/ws watcher off|lazy"))
            end
        elseif command == "reset" then
            local resetTarget = (arg or ""):lower()
            if resetTarget == "database" or resetTarget == "db" then
                StaticPopup_Show("WOWSYNC_RESET_DB")
            else
                addon:Print(L["Usage: X"]:format("/ws reset database|db"))
            end
        elseif command == "status" then
            local group = (arg or ""):lower()
            if group == "" then
                PrintAddonStatus()
                PrintProfileStatus()
                PrintWatcherStatus()
                PrintDebugStatus()
            elseif group == "addon" then
                PrintAddonStatus()
            elseif group == "profile" then
                PrintProfileStatus()
            elseif group == "watcher" then
                PrintWatcherStatus()
            elseif group == "debug" then
                PrintDebugStatus()
            else
                addon:Print(L["Usage: X"]:format("/ws status [addon|profile|watcher|debug]"))
            end
        elseif command == "debug" then
            local debugMode = (arg or ""):lower()
            if debugMode == "on" then
                Debugger:SetEnabled(true)
                addon:Print(L["Debug logging is on. It persists across sessions until you turn it off."])
            elseif debugMode == "off" then
                Debugger:SetEnabled(false)
                addon:Print(L["Debug logging is off. The debug log has been cleared."])
            elseif debugMode == "" or debugMode == "status" then
                if Debugger:IsEnabled() then
                    addon:Print(L["Debug logging is on (X events recorded)."]:format(Debugger:GetEventCount()))
                else
                    addon:Print(L["Debug logging is off."])
                end
            else
                addon:Print(L["Usage: X"]:format("/ws debug on|off"))
            end
        elseif command == "help" then
            addon:Print(L["Usage: (X and Y are interchangeable)"]:format("/ws", "/wowsync"))
            addon:Print(L["  X - Y"]:format("/ws", L["Open or close the WowSync UI window"]))
            addon:Print(L["  X - Y"]:format("/ws save [note]", L["Save a snapshot of your current setup, optionally with a short note"]))
            addon:Print(L["  X - Y"]:format("/ws apply <name>[@hash[#index]] [--merge|--exact]", L["Apply a profile's latest snapshot, or a specific snapshot by hash (merge by default)"]))
            addon:Print(L["  X - Y"]:format("/ws undo", L["Undo the last applied snapshot"]))
            addon:Print(L["  X - Y"]:format("/ws delete <name>[@hash[#index]]", L["Delete a profile, or delete a specific snapshot by hash"]))
            addon:Print(L["  X - Y"]:format("/ws list [name]", L["List all saved profiles, or list one profile's snapshots"]))
            addon:Print(L["  X - Y"]:format("/ws export", L["Open the WowSync_UI window to export a snapshot you can share"]))
            addon:Print(L["  X - Y"]:format("/ws import", L["Open the WowSync_UI window to import a snapshot from a string"]))
            addon:Print(L["  X - Y"]:format("/ws status [addon|profile|watcher|debug]", L["Show what WowSync is currently doing"]))
            addon:Print(L["  X - Y"]:format("/ws watcher off|lazy", L["Track your setup live on demand, or turn tracking off entirely (lazy by default)"]))
            addon:Print(L["  X - Y"]:format("/ws reset database|db", L["Delete all saved profiles and snapshots, while keeping your settings"]))
            addon:Print(L["  X - Y"]:format("/ws debug on|off", L["Record detailed debug data to WowSyncDebugDB (off clears it)"]))
            addon:Print(L["  X - Y"]:format("/ws help", L["Show the command list"]))
        else
            addon:Print(L["Unknown command. Type X."]:format("/ws help"))
        end
    end
end
