local _, addon = ...
local Settings = addon:NewObject("Settings")

local ProfileManager = addon:GetObject("ProfileManager")

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

function Settings:CanApply(meta)
    return true
end

--[[ Registration ]]

function Settings:OnInitialized()
    ProfileManager:RegisterModule(self)
end
