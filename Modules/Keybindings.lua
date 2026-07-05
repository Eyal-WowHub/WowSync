local _, addon = ...
local Keybindings = addon:NewObject("Keybindings")

local HashSet = addon.HashSet
local ModuleRegistry = addon.ModuleRegistry
local SnapshotApplyMode = addon.SnapshotApplyMode

Keybindings.Config = {
    -- Runs after macros so bindings to named macros resolve.
    ApplyPriority = 60,
    SnapshotApplyMode = SnapshotApplyMode.All,
}

--[[ Helpers ]]

-- The map { [command] = {Key1,Key2} } as a list of keyed entries for HashSet.
local function BindingEntries(capturedData)
    local bindingEntries = {}
    for command, keys in pairs(capturedData or {}) do
        tinsert(bindingEntries, { Command = command, Key1 = keys.Key1, Key2 = keys.Key2 })
    end
    return bindingEntries
end

local function BindingKey(binding)
    return binding.Command
end

local function BindingLabel(binding)
    return _G["BINDING_NAME_" .. binding.Command] or binding.Command
end

-- The key(s) currently assigned to a binding, shown beneath its name.
local function BindingDescription(binding)
    local keys = {}
    if binding.Key1 then tinsert(keys, binding.Key1) end
    if binding.Key2 then tinsert(keys, binding.Key2) end
    if #keys == 0 then return nil end
    return table.concat(keys, ", ")
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

function Keybindings:Apply(capturedData, sourceMetadata, applyOptions)
    -- Apply saved bindings. SetBinding overrides existing key assignments.
    -- In Exact mode, every currently bound key is cleared first so the
    -- result matches the snapshot exactly (including keys that merely moved
    -- from one command to another).
    local currentSet = GetCurrentBindingSet()
    if not currentSet then
        -- Binding set isn't determinable yet; don't touch bindings.
        return
    end

    if applyOptions and applyOptions.mode == "exact" then
        for _, keys in pairs(self:Capture()) do
            if keys.Key1 then
                SetBinding(keys.Key1, nil)
            end
            if keys.Key2 then
                SetBinding(keys.Key2, nil)
            end
        end
    end

    for command, keys in pairs(capturedData) do
        if keys.Key1 then
            SetBinding(keys.Key1, command)
        end
        if keys.Key2 then
            SetBinding(keys.Key2, command)
        end
    end

    SaveBindings(currentSet)
end

-- Preview of what applying these bindings would change.
function Keybindings:Diff(currentData, snapshotData)
    local currentSet = HashSet:From(BindingEntries(currentData), BindingKey, BindingLabel, nil, BindingDescription)
    local snapshotSet = HashSet:From(BindingEntries(snapshotData), BindingKey, BindingLabel, nil, BindingDescription)

    return {
        added = currentSet:Added(snapshotSet),
        changed = currentSet:Changed(snapshotSet),
        removed = currentSet:Removed(snapshotSet),
    }
end

function Keybindings:CanApply(sourceMetadata)
    return true
end

-- Events that mean this module's live state may have changed, so the GameWatcher
-- can re-mirror it into Current (debounced).
function Keybindings:GetWatchedEvents()
    return { "UPDATE_BINDINGS" }
end

-- The live bindings and which binding set is active, so the debug log can show
-- exactly which keys were bound before and after a sync.
function Keybindings:GetDebugState()
    return {
        BindingSet = GetCurrentBindingSet(),
        Bindings = self:Capture(),
    }
end

--[[ Registration ]]

function Keybindings:OnInitialized()
    ModuleRegistry:Register(self)
end
