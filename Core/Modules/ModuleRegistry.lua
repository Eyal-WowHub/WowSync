local _, addon = ...
local ModuleRegistry = {}
addon.ModuleRegistry = ModuleRegistry

local C = addon.Contracts
local AsyncTask = addon.AsyncTask
local Interface = addon.ModuleInterface
local ModuleIds = addon.ModuleIds

local registeredModules = {}

-- Apply priority used for modules that don't declare an ApplyPriority.
local DEFAULT_APPLY_PRIORITY = 100

function ModuleRegistry:Register(module)
    C:IsTable(module, 2)

    -- The module contract is documented and declared in ModuleInterface; validate
    -- against those lists so the two can never drift apart.
    for _, method in ipairs(Interface.RequiredMethods) do
        C:Ensures(type(module[method]) == "function", "Register: module must implement %s()", method)
    end

    -- Optional capabilities: validated only when the module provides them.
    for _, method in ipairs(Interface.OptionalMethods) do
        if module[method] ~= nil then
            C:Ensures(type(module[method]) == "function", "Register: module %s must be a function", method)
        end
    end

    for field, expectedType in pairs(Interface.OptionalFields) do
        if module[field] ~= nil then
            C:Ensures(type(module[field]) == expectedType, "Register: module %s must be a %s", field, expectedType)
        end
    end

    local moduleName = module:GetName()
    C:Ensures(not registeredModules[moduleName], "Register: module '%s' is already registered", moduleName)

    C:Ensures(ModuleIds:GetId(moduleName) ~= nil, "Register: module '%s' has no id assigned in ModuleIds", moduleName)

    registeredModules[moduleName] = module
end

-- Replace the module registered under an existing name with a new implementation,
-- returning the module it replaced. The name must already be registered, so a
-- plugin can only layer over a built-in module — reusing its permanent id and
-- stored data — never invent one; the returned module lets the replacement
-- delegate to the original. Held to the same contract as Register.
function ModuleRegistry:Override(module)
    C:IsTable(module, 2)

    for _, method in ipairs(Interface.RequiredMethods) do
        C:Ensures(type(module[method]) == "function", "Override: module must implement %s()", method)
    end

    for _, method in ipairs(Interface.OptionalMethods) do
        if module[method] ~= nil then
            C:Ensures(type(module[method]) == "function", "Override: module %s must be a function", method)
        end
    end

    for field, expectedType in pairs(Interface.OptionalFields) do
        if module[field] ~= nil then
            C:Ensures(type(module[field]) == expectedType, "Override: module %s must be a %s", field, expectedType)
        end
    end

    local moduleName = module:GetName()
    local previous = registeredModules[moduleName]
    C:Ensures(previous ~= nil, "Override: module '%s' is not registered", moduleName)

    registeredModules[moduleName] = module
    return previous
end

function ModuleRegistry:Get(moduleName)
    return registeredModules[moduleName]
end

function ModuleRegistry:Iterate()
    return pairs(registeredModules)
end

-- A module's apply priority (lower applies first), or the default when unset.
local function ApplyPriorityOf(moduleName)
    local module = registeredModules[moduleName]
    return module and module.Config and module.Config.ApplyPriority or DEFAULT_APPLY_PRIORITY
end

-- The given module names as an array in apply order: ascending ApplyPriority,
-- ties broken by name so the order is deterministic.
local function SortByApplyPriority(moduleNames)
    local ordered = {}
    for _, name in ipairs(moduleNames) do
        ordered[#ordered + 1] = name
    end
    table.sort(ordered, function(a, b)
        local priorityA = ApplyPriorityOf(a)
        local priorityB = ApplyPriorityOf(b)
        if priorityA ~= priorityB then
            return priorityA < priorityB
        end
        return a < b
    end)
    return ordered
end

-- Iterates the given module names (an ordered array) in apply order (ascending
-- ApplyPriority, ties broken by name), yielding each name and its module.
function ModuleRegistry:IterableModulesByPriority(moduleNames)
    local ordered = SortByApplyPriority(moduleNames)
    local i = 0
    local n = #ordered
    return function()
        i = i + 1
        if i <= n then
            local name = ordered[i]
            return name, registeredModules[name]
        end
    end
end

-- Apply the given module names (an ordered array, e.g. from
-- Snapshot:GetModuleNames) to the live game in apply-priority order, honoring
-- each module's CanApply gate and per-module mode (strategy.default, with
-- strategy.overrides[name] taking precedence). classID is the target character's
-- class, passed to each module's CanApply/Apply. A module whose work finishes
-- after Apply returns hands back an AsyncTask; those are gathered into one
-- returned task. Returns the per-module results, whether anything was actually
-- applied, and the combined task (already resolved when nothing is asynchronous).
function ModuleRegistry:ApplyModules(moduleNames, sourceModules, strategy, classID)
    C:IsArray(moduleNames, 2)
    C:IsTable(sourceModules, 3)
    strategy = strategy or {}
    local defaultMode = strategy.default or "merge"
    local overrides = strategy.overrides or {}
    local meta = { ClassID = classID }
    local applyResults = {}
    local applied = false
    local tasks = {}
    for name, module in self:IterableModulesByPriority(moduleNames) do
        local capturedData = sourceModules[name]
        if module and capturedData ~= nil then
            local canApply, warning = module:CanApply(meta)
            if not canApply then
                applyResults[name] = { applied = false, reason = warning }
            else
                local mode = overrides[name] or defaultMode
                local applySucceeded, applyReturn = pcall(module.Apply, module, capturedData, meta, { mode = mode })
                if applySucceeded then
                    applyResults[name] = { applied = true, mode = mode, warning = warning }
                    applied = true
                    -- A module returns an AsyncTask when its apply settles later;
                    -- gather them so the caller can wait for the whole write.
                    if getmetatable(applyReturn) == AsyncTask then
                        tinsert(tasks, applyReturn)
                    end
                else
                    applyResults[name] = { applied = false, reason = tostring(applyReturn) }
                end
            end
        end
    end
    return applyResults, applied, AsyncTask:WhenAll(tasks)
end
