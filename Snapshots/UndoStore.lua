local _, addon = ...
local UndoStore = addon:NewObject("UndoStore")
local ProfileStore = addon:GetObject("ProfileStore")

local CharacterInfo = LibStub("CharacterInfo-1.0")
local BoundedList = addon.BoundedList

--[[
    UndoStore — a per-character stack of safety snapshots.

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

function UndoStore:Push(key, snapshot)
    key = key or CharacterInfo:GetFullName()
    local stack = ProfileStore:CreateProfile(key).Undo
    BoundedList:Wrap(stack, {
        max = function() return addon.DB.Settings.MaxUndo or 10 end,
    }):Push(snapshot)
end

function UndoStore:Peek(key)
    key = key or CharacterInfo:GetFullName()
    local profile = profiles[key]
    local stack = profile and profile.Undo
    return stack and stack[#stack]
end

function UndoStore:Pop(key)
    key = key or CharacterInfo:GetFullName()
    local profile = profiles[key]
    local stack = profile and profile.Undo
    if stack and #stack > 0 then
        return tremove(stack)
    end
end

function UndoStore:List(key)
    key = key or CharacterInfo:GetFullName()
    local profile = profiles[key]
    return (profile and profile.Undo) or {}
end

function UndoStore:Has(key)
    key = key or CharacterInfo:GetFullName()
    local profile = profiles[key]
    local stack = profile and profile.Undo
    return stack ~= nil and #stack > 0
end

function UndoStore:Clear(key)
    key = key or CharacterInfo:GetFullName()
    local profile = profiles[key]
    if profile then
        profile.Undo = {}
    end
end
