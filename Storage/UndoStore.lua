local _, addon = ...
local UndoStore = addon:NewObject("UndoStore")

local CharacterInfo = LibStub("CharacterInfo-1.0")

--[[
    UndoStore — a per-character stack of safety snapshots.

    Before any apply, the current live setup is captured and pushed here so the
    change can be undone. Entries share the Snapshot shape and live under
    DB.global.Characters[charKey].Undo. The stack is capped at Settings.MaxUndo;
    the oldest entry is dropped when the cap is exceeded.
]]

local characters

local function EnsureStack(key)
    local entry = characters[key]
    if not entry then
        entry = { Meta = {}, Current = {}, Undo = {} }
        characters[key] = entry
    end
    entry.Undo = entry.Undo or {}
    return entry.Undo
end

function UndoStore:OnInitialized()
    characters = addon.DB.global.Characters
end

function UndoStore:Push(key, snapshot)
    key = key or CharacterInfo:GetFullName()
    local stack = EnsureStack(key)
    tinsert(stack, snapshot)

    local max = addon.DB.global.Settings.MaxUndo or 20
    while #stack > max do
        tremove(stack, 1)
    end
end

function UndoStore:Peek(key)
    key = key or CharacterInfo:GetFullName()
    local entry = characters[key]
    local stack = entry and entry.Undo
    return stack and stack[#stack]
end

function UndoStore:Pop(key)
    key = key or CharacterInfo:GetFullName()
    local entry = characters[key]
    local stack = entry and entry.Undo
    if stack and #stack > 0 then
        return tremove(stack)
    end
end

function UndoStore:List(key)
    key = key or CharacterInfo:GetFullName()
    local entry = characters[key]
    return (entry and entry.Undo) or {}
end

function UndoStore:Has(key)
    key = key or CharacterInfo:GetFullName()
    local entry = characters[key]
    local stack = entry and entry.Undo
    return stack ~= nil and #stack > 0
end

function UndoStore:Clear(key)
    key = key or CharacterInfo:GetFullName()
    local entry = characters[key]
    if entry then
        entry.Undo = {}
    end
end
