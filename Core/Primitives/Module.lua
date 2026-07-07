local _, addon = ...
local Module = {}
addon.Module = Module
Module.__index = Module

local C = addon.Contracts
local ModuleIds = addon.ModuleIds
local ModuleRegistry = addon.ModuleRegistry
local HashedModule = addon.HashedModule

-- Identity cache so exactly one wrapper exists per registered module (weak, so
-- an unloaded module's wrapper is collected).
local cache = setmetatable({}, { __mode = "k" })

-- Apply priority used for a module that declares none (lower applies first).
local DEFAULT_APPLY_PRIORITY = 100

--[[
    Module — the behaviour/identity face over one registered sync module.

    A registered module (owned by ModuleRegistry) is a plain contract object
    (ModuleInterface): Capture/Apply/CanApply plus an optional Diff and a static
    Config. Module wraps one so callers hold a typed object instead of reaching
    into module.Config.X or routing identity/config reads through manager helpers.
    It reads the module's identity and static config and forwards its
    capture/diff/apply behaviour; the RULES that orchestrate modules (apply
    ordering, the write loop) stay on ModuleRegistry. Wrappers are identity-cached,
    so one Module exists per registered module.
]]

--[[ Factory (identity-cached) ]]

-- Create the Module wrapping a registered module. Returns the same wrapper per
-- module across calls.
function Module:Create(rawModule)
    C:IsTable(rawModule, 2)
    local module = cache[rawModule]
    if not module then
        module = setmetatable({ raw = rawModule }, Module)
        cache[rawModule] = module
    end
    return module
end

-- The Module for a registered name, or nil when no module is registered under it.
function Module:WrapRegisteredModule(name)
    C:IsString(name, 2)
    local rawModule = ModuleRegistry:Get(name)
    return rawModule and Module:Create(rawModule) or nil
end

--[[ Instance: identity + static config ]]

-- The module's stable name: its key in snapshots, the registry, and the UI.
function Module:Name()
    return self.raw:GetName()
end

-- The module's permanent numeric id from ModuleIds.
function Module:Id()
    return ModuleIds:GetId(self:Name())
end

-- The apply modes the module supports (a SnapshotApplyMode flag set), None when
-- it declares none.
function Module:ApplyMode()
    local config = self.raw.Config
    return config and config.SnapshotApplyMode or addon.SnapshotApplyMode.None
end

-- The fallback diff-preview icon the module supplies for entries that carry none
-- of their own, or nil when unset.
function Module:DefaultIcon()
    local config = self.raw.Config
    return config and config.DefaultIcon or nil
end

-- The module's apply priority (lower applies first), or the default when unset.
function Module:Priority()
    local config = self.raw.Config
    return config and config.ApplyPriority or DEFAULT_APPLY_PRIORITY
end

--[[ Instance: behaviour ]]

-- Whether applying this module is sensible for a snapshot's origin metadata,
-- plus an optional human-readable caveat. Asked before Apply.
function Module:CanApply(meta)
    return self.raw:CanApply(meta)
end

-- Read the player's current live state for this module as a plain table.
function Module:Capture()
    return self.raw:Capture()
end

-- Preview what applying snapshotData over currentData would change, or nil when
-- the module does not support diffing.
function Module:Diff(currentData, snapshotData)
    if not self.raw.Diff then
        return nil
    end
    return self.raw:Diff(currentData, snapshotData)
end

-- Write a captured payload back into the game under the given source metadata
-- and apply options.
function Module:Apply(capturedData, meta, applyOptions)
    return self.raw:Apply(capturedData, meta, applyOptions)
end

-- The content fingerprint of a captured payload for this module, as a HashedModule.
function Module:Hash(moduleData)
    return HashedModule:Compute(self:Id(), moduleData)
end

--[[ Guard ]]

-- Guard that value is a Module, returning it for convenient chaining.
function Module.Validate(value, pos)
    C:Ensures(getmetatable(value) == Module, "bad argument #%d: expected a Module", pos or 1)
    return value
end
