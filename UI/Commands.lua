local _, addon = ...
local Commands = addon:NewObject("Commands")

local L = addon.L

local CharacterManager = addon:GetObject("CharacterManager")
local Debugger = addon:GetObject("Debugger")
local GameWatcher = addon:GetObject("GameWatcher")
local MinimapButton = addon:GetObject("MinimapButton")
local ProfileManager = addon:GetObject("ProfileManager")
local SaveTask = addon:GetObject("SaveTask")
local UndoManager = addon:GetObject("UndoManager")
local Upgrade = addon:GetObject("Upgrade")

--[[
    Slash command interface ("/wowsync", "/ws").

    Parses the player's input and routes it to the snapshot and profile
    managers, printing feedback through addon:Print. With no arguments it
    simply toggles the companion UI.
]]

-- "<7-char hash>#<index>" short display selector for a saved snapshot.
local function ShortSelector(snapshot)
    local hash, index = snapshot:GetSelector():match("^(%w+)#(%d+)$")
    return ("%s#%s"):format(hash:sub(1, 7), index)
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
    addon:PrintLine(L["  Character: X"]:format(CharacterManager:GetConnectedCharacterKey()))
end

-- Profile stanza: stored snapshot count, latest snapshot summary, in-sync flag
-- against the live snapshot, and the undo stack depth. Fingerprints the live
-- snapshot to compute the in-sync flag, so this is the heaviest status stanza.
local function PrintProfileStatus()
    local charKey = CharacterManager:GetConnectedCharacterKey()
    local profile = ProfileManager:GetProfile(charKey)
    local latest = profile and profile:GetLatestSnapshot()
    local liveSnapshot = profile and ProfileManager:GetLiveSnapshot(profile)
    local historyCount = profile and #profile:GetHistory() or 0

    addon:Print(L["[Profile]"])
    addon:PrintLine(L["  Snapshots: X / Y"]:format(historyCount, ProfileManager:GetMaxSnapshots()))

    if latest then
        addon:PrintLine(L["  Latest: X - Y"]:format(ShortSelector(latest), latest:GetSubject()))
    else
        addon:PrintLine(L["  Latest: none"])
    end

    if not liveSnapshot then
        addon:PrintLine(L["  In sync: no captured state"])
    elseif latest and liveSnapshot:Equals(latest) then
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
        -- A pending one-time upgrade reset intercepts every command, raising the
        -- reset prompt until the player accepts it.
        if Upgrade:ShowIfPending() then
            return
        end

        local command, arg = strsplit(" ", strtrim(input or ""), 2)
        command = (command or ""):lower()
        arg = arg and strtrim(arg)

        if command == "" then
            WowSync:Import("UI"):ToggleUI()
            return
        end

        -- Trace every command except the debug toggle itself so the debug log
        -- captures what the player ran.
        if command ~= "debug" and Debugger:IsEnabled() then
            Debugger:RecordCommand({ Command = strtrim(input or "") })
        end

        if command == "watcher" then
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
        elseif command == "button" then
            local buttonMode = (arg or ""):lower()
            if buttonMode == "show" then
                if MinimapButton:Show() then
                    addon:Print(L["Minimap button shown."])
                else
                    addon:Print(L["The minimap button needs the WowSync_UI companion installed and enabled."])
                end
            elseif buttonMode == "hide" then
                if MinimapButton:Hide() then
                    addon:Print(L["Minimap button hidden."])
                else
                    addon:Print(L["The minimap button needs the WowSync_UI companion installed and enabled."])
                end
            else
                addon:Print(L["Usage: X"]:format("/ws button hide|show"))
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
            addon:Print(L["  X - Y"]:format("/ws status [addon|profile|watcher|debug]", L["Show what WowSync is currently doing"]))
            addon:Print(L["  X - Y"]:format("/ws watcher off|lazy", L["Track your setup live on demand, or turn tracking off entirely (lazy by default)"]))
            addon:Print(L["  X - Y"]:format("/ws button hide|show", L["Show or hide the WowSync minimap button"]))
            addon:Print(L["  X - Y"]:format("/ws reset database|db", L["Delete all saved profiles, snapshots, and imports, while keeping your settings"]))
            addon:Print(L["  X - Y"]:format("/ws debug on|off", L["Record detailed debug data to WowSyncDebugDB (off clears it)"]))
            addon:Print(L["  X - Y"]:format("/ws help", L["Show the command list"]))
        else
            addon:Print(L["Unknown command. Type X."]:format("/ws help"))
        end
    end
end
