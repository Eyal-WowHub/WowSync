local _, addon = ...
local Keybindings = addon:NewObject("Keybindings")
local ModuleRegistry = addon:GetObject("ModuleRegistry")

local HashSet = addon.HashSet
local SnapshotApplyMode = addon.SnapshotApplyMode

Keybindings.Config = {
    SnapshotApplyMode = SnapshotApplyMode.All,
}

--[[ Helpers ]]

-- The map { [command] = {Key1,Key2} } as a list of keyed entries for HashSet.
local function ToList(data)
    local list = {}
    for command, keys in pairs(data or {}) do
        tinsert(list, { Command = command, Key1 = keys.Key1, Key2 = keys.Key2 })
    end
    return list
end

local function BindingKey(binding)
    return binding.Command
end

local function BindingLabel(binding)
    return _G["BINDING_NAME_" .. binding.Command] or binding.Command
end

--[[ Module API ]]

function Keybindings:Capture()
    local bindings = {}

    for i = 1, GetNumBindings() do
        -- GetBinding returns: command, category, key1, key2, ...
        local command, category, key1, key2 = GetBinding(i)
        if command and (key1 or key2) then
            bindings[command] = {
                Key1 = key1,
                Key2 = key2,
            }
        end
    end

    return bindings
end

function Keybindings:Apply(data, meta, opts)
    -- Apply saved bindings. SetBinding overrides existing key assignments.
    -- In Exact mode, every currently bound key is cleared first so the
    -- result matches the snapshot exactly (including keys that merely moved
    -- from one command to another).
    local currentSet = GetCurrentBindingSet()
    if not currentSet then
        -- Binding set isn't determinable yet; don't touch bindings.
        return
    end

    if opts and opts.mode == "exact" then
        for _, keys in pairs(self:Capture()) do
            if keys.Key1 then
                SetBinding(keys.Key1, nil)
            end
            if keys.Key2 then
                SetBinding(keys.Key2, nil)
            end
        end
    end

    for action, keys in pairs(data) do
        if keys.Key1 then
            SetBinding(keys.Key1, action)
        end
        if keys.Key2 then
            SetBinding(keys.Key2, action)
        end
    end

    SaveBindings(currentSet)
end

-- Preview of what applying these bindings would change.
function Keybindings:Diff(current, snapshot)
    local currentSet = HashSet:From(ToList(current), BindingKey, BindingLabel)
    local snapshotSet = HashSet:From(ToList(snapshot), BindingKey, BindingLabel)

    return {
        added = currentSet:Added(snapshotSet),
        changed = currentSet:Changed(snapshotSet),
        removed = currentSet:Removed(snapshotSet),
    }
end

function Keybindings:CanApply(meta)
    return true
end

-- Events that mean this module's live state may have changed, so the GameWatcher
-- can re-mirror it into Current (debounced).
function Keybindings:GetWatchedEvents()
    return { "UPDATE_BINDINGS" }
end

--[[ Registration ]]

function Keybindings:OnInitialized()
    ModuleRegistry:Register(self)
end
