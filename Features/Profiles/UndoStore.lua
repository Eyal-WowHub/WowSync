local _, addon = ...
local UndoStore = addon:NewObject("UndoStore")
local ProfileStore = addon:GetObject("ProfileStore")

local CharacterInfo = LibStub("CharacterInfo-1.0")
local BoundedList = addon.BoundedList

--[[
    UndoStore — a per-character stack of rollback snapshots.

    Before any apply, the current live setup is captured and pushed here so the
    change can be undone. Entries share the Snapshot shape and live on the
    character's record under DB.Profiles[charKey].Undo (owned by ProfileStore).
    The stack is capped at Settings.MaxUndo; the oldest entry is dropped when the
    cap is exceeded.
]]

local profiles

function UndoStore:OnInitialized()
    profiles = addon.DB.Profiles
end

function UndoStore:Push(profileName, rollbackSnapshot)
    profileName = profileName or CharacterInfo:GetFullName()
    local rollbackStack = ProfileStore:CreateProfile(profileName).Undo
    BoundedList:Wrap(rollbackStack, {
        max = function() return addon.DB.Settings.MaxUndo or 10 end,
    }):Push(rollbackSnapshot)
end

function UndoStore:Peek(profileName)
    profileName = profileName or CharacterInfo:GetFullName()
    local profile = profiles[profileName]
    local rollbackStack = profile and profile.Undo
    return rollbackStack and rollbackStack[#rollbackStack]
end

function UndoStore:Pop(profileName)
    profileName = profileName or CharacterInfo:GetFullName()
    local profile = profiles[profileName]
    local rollbackStack = profile and profile.Undo
    if rollbackStack and #rollbackStack > 0 then
        return tremove(rollbackStack)
    end
end

function UndoStore:List(profileName)
    profileName = profileName or CharacterInfo:GetFullName()
    local profile = profiles[profileName]
    return (profile and profile.Undo) or {}
end

function UndoStore:Has(profileName)
    profileName = profileName or CharacterInfo:GetFullName()
    local profile = profiles[profileName]
    local rollbackStack = profile and profile.Undo
    return rollbackStack ~= nil and #rollbackStack > 0
end

function UndoStore:Clear(profileName)
    profileName = profileName or CharacterInfo:GetFullName()
    local profile = profiles[profileName]
    if profile then
        profile.Undo = {}
    end
end
