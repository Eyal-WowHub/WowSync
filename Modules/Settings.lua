local _, addon = ...
local Settings = addon:NewObject("Settings")

local ProfileManager = addon:GetObject("ProfileManager")
local HashSet = addon.HashSet
local SnapshotApplyMode = addon.SnapshotApplyMode

Settings.Config = {
    SnapshotApplyMode = SnapshotApplyMode.Merge,
}

local TRACKED_CVARS = addon.TRACKED_CVARS

--[[ Helpers ]]

local function SetTrackedCVar(cvar, value)
    -- GetCVarInfo returns: value, defaultValue, isStoredServerAccount,
    --   isStoredServerCharacter, isLockedFromUser, isSecure, isReadOnly
    local _, _, _, _, isLockedFromUser, isSecure, isReadOnly = C_CVar.GetCVarInfo(cvar)
    if isLockedFromUser or isSecure or isReadOnly then
        return
    end

    -- Isolate each SetCVar: a protected or erroring CVar must not abort the
    -- rest of the batch (the whole module Apply runs under a single pcall).
    pcall(C_CVar.SetCVar, cvar, value)
end

--[[ Module API ]]

function Settings:Capture()
    local account, character = {}, {}

    for _, cvar in ipairs(TRACKED_CVARS) do
        local value = C_CVar.GetCVar(cvar)
        if value then
            -- GetCVarInfo returns: value, defaultValue, isStoredServerAccount,
            --   isStoredServerCharacter, isLockedFromUser, isSecure, isReadOnly
            local _, _, _, isStoredServerCharacter = C_CVar.GetCVarInfo(cvar)

            if isStoredServerCharacter then
                character[cvar] = value
            else
                account[cvar] = value
            end
        end
    end

    return {
        Account = account,
        Character = character,
    }
end

function Settings:Apply(data, meta)
    if data.Account then
        for cvar, value in pairs(data.Account) do
            SetTrackedCVar(cvar, value)
        end
    end

    if data.Character then
        for cvar, value in pairs(data.Character) do
            SetTrackedCVar(cvar, value)
        end
    end
end

-- Each tracked CVar as a keyed list entry, hashed by name + value.
local function CVarEntries(data)
    local list = {}
    if not data then
        return list
    end
    for _, scope in ipairs({ "Account", "Character" }) do
        local map = data[scope]
        if map then
            for cvar, value in pairs(map) do
                tinsert(list, { Name = cvar, Value = value })
            end
        end
    end
    return list
end

local function CVarKey(entry)
    return entry.Name
end

-- Preview of which CVars applying this profile would change.
function Settings:Diff(current, snapshot)
    local currentSet = HashSet:From(CVarEntries(current), CVarKey, CVarKey)
    local snapshotSet = HashSet:From(CVarEntries(snapshot), CVarKey, CVarKey)

    return {
        added = currentSet:Added(snapshotSet),
        changed = currentSet:Changed(snapshotSet),
        removed = currentSet:Removed(snapshotSet),
    }
end

function Settings:CanApply(meta)
    return true
end

-- Events that mean this module's live state may have changed, so the GameWatcher
-- can re-mirror it into Current (debounced). CVAR_UPDATE is chatty, but the
-- watcher debounces and only this module re-captures.
function Settings:GetWatchedEvents()
    return { "CVAR_UPDATE" }
end

--[[ Registration ]]

function Settings:OnInitialized()
    ProfileManager:RegisterModule(self)
end
