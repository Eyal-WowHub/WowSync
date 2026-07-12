local _, addon = ...
local PluginManager = {}
addon.PluginManager = PluginManager

local C = addon.Contracts
local AsyncTask = addon.AsyncTask
local Interface = addon.ModuleInterface
local ModuleRegistry = addon.ModuleRegistry

--[[
    PluginManager — the seam a separate addon uses to extend WowSync without
    editing it, and the backing store for the single "Plugin" module.

    WowSync exposes exactly one umbrella module identity, "Plugin" (see
    ModuleIds), under which every plugin's data is consolidated — so a plugin
    never mints a permanent id or mutates WowSync's identity registry. A plugin
    (an addon that depends on WowSync) registers itself once for a handle, then
    adds sync behaviour through it:

      - RegisterModule: a brand-new module the plugin owns, kept in this manager's
        own registry (namespaced under the plugin's name) and captured, hashed,
        applied and diffed through the core Plugin module — never as a first-class
        WowSync module.
      - OverrideModule: replace a built-in module with the plugin's version (via
        ModuleRegistry:Override), to layer over ActionBars, Chat and the like.

    Each plugin keeps its own isolated slice of every snapshot (data is keyed by
    plugin name) and its own db, a SavedVariables table handed in at Register.
    Because the
    consolidated data is keyed by plugin and module name, the Plugin module's hash
    reflects each plugin's named slice — a change in one plugin is visible without
    disturbing the others.
]]

-- Registered plugins, keyed by name, so a repeated Register hands back the same
-- handle instead of a second one.
local plugins = {}

-- Hold a plugin module to the same contract as a built-in one, since it flows
-- through the same capture/apply/diff machinery (just under the Plugin umbrella).
local function ValidateModule(module)
    for _, method in ipairs(Interface.RequiredMethods) do
        C:Ensures(type(module[method]) == "function", "RegisterModule: module must implement %s()", method)
    end
    for _, method in ipairs(Interface.OptionalMethods) do
        if module[method] ~= nil then
            C:Ensures(type(module[method]) == "function", "RegisterModule: module %s must be a function", method)
        end
    end
    for field, expectedType in pairs(Interface.OptionalFields) do
        if module[field] ~= nil then
            C:Ensures(type(module[field]) == expectedType, "RegisterModule: module %s must be a %s", field, expectedType)
        end
    end
end

local Plugin = {}
Plugin.__index = Plugin

-- The plugin's name.
function Plugin:GetName()
    return self.name
end

-- Register a brand-new sync module this plugin owns: a standard contract object
-- (Capture/Apply/CanApply, optional Diff/Config). It is stored under this plugin,
-- not in WowSync's registry, and reaches snapshots through the core Plugin module.
function Plugin:RegisterModule(module)
    C:IsTable(module, 2)
    ValidateModule(module)

    local moduleName = module:GetName()
    C:Ensures(self.modules[moduleName] == nil, "RegisterModule: '%s' is already registered for plugin '%s'", moduleName, self.name)
    self.modules[moduleName] = module
    return module
end

-- Replace a built-in module with this plugin's implementation, returning the
-- module it replaced so the replacement can delegate to the original. The target
-- must already be registered.
function Plugin:OverrideModule(module)
    C:IsTable(module, 2)
    return ModuleRegistry:Override(module)
end

-- Register a plugin and return its handle. plugin = { name = <the plugin's addon
-- name>, db = <the plugin's own SavedVariables table, optional> }.
-- Registering the same name twice returns the existing handle.
function PluginManager:Register(plugin)
    C:IsTable(plugin, 2)
    C:IsString(plugin.name, 2)

    local existing = plugins[plugin.name]
    if existing then
        return existing
    end

    local instance = setmetatable({
        name = plugin.name,
        db = plugin.db or {},
        modules = {},
    }, Plugin)
    plugins[plugin.name] = instance
    return instance
end

-- The registered plugins and their submodule names, each sorted, so the UI can
-- offer selectable "Plugin: <name>" groups (Apply/Save/Share) mirroring the diff
-- preview. Empty when no plugin is installed.
function PluginManager:GetSubModuleLayout()
    local pluginNames = {}
    for pluginName in pairs(plugins) do
        pluginNames[#pluginNames + 1] = pluginName
    end
    table.sort(pluginNames)

    local layout = {}
    for _, pluginName in ipairs(pluginNames) do
        local plugin = plugins[pluginName]
        local moduleNames = {}
        for moduleName in pairs(plugin.modules) do
            moduleNames[#moduleNames + 1] = moduleName
        end
        if #moduleNames > 0 then
            table.sort(moduleNames)
            layout[#layout + 1] = { plugin = pluginName, subModules = moduleNames }
        end
    end
    return layout
end

--[[ Backing for the core Plugin module ]]

-- Capture every registered plugin module, grouped by plugin then module name.
-- Returns nil when no plugin contributes data, so the Plugin module leaves no
-- footprint in a snapshot when nothing is installed.
function PluginManager:CaptureAll()
    local captured
    for pluginName, plugin in pairs(plugins) do
        for moduleName, module in pairs(plugin.modules) do
            local data = module:Capture()
            if data ~= nil then
                captured = captured or {}
                captured[pluginName] = captured[pluginName] or {}
                captured[pluginName][moduleName] = data
            end

            -- When driven by a sliced save (a coroutine), let the frame breathe
            -- between plugin modules so a heavy capture spreads across frames
            -- instead of hitching; a synchronous caller runs straight through.
            if coroutine.running() then
                coroutine.yield()
            end
        end
    end
    return captured
end

-- Apply consolidated plugin data back to the game, dispatching each slice to its
-- owning module. Data for a plugin that is not currently installed is skipped (and
-- left untouched in the snapshot), and each module's own CanApply gate is honoured.
-- A module's Apply is guarded so one failing plugin never aborts the rest.
function PluginManager:ApplyAll(capturedData, meta, applyOptions)
    -- A plugin module whose apply finishes later (e.g. after a user answers a
    -- prompt) returns an AsyncTask; gather them so the caller can wait for the
    -- whole plugin apply, the same way built-in modules defer.
    local tasks = {}
    for pluginName, modulesData in pairs(capturedData or {}) do
        local plugin = plugins[pluginName]
        if plugin then
            for moduleName, data in pairs(modulesData) do
                local module = plugin.modules[moduleName]
                if module and module:CanApply(meta) then
                    local ok, applyReturn = pcall(module.Apply, module, data, meta, applyOptions)
                    if ok and getmetatable(applyReturn) == AsyncTask then
                        tinsert(tasks, applyReturn)
                    end
                end
            end
        end
    end
    return AsyncTask:WhenAll(tasks)
end

-- Whether a module's declared apply modes include Exact, so its removals are real
-- deletions rather than a merge-only module's ignored ones.
local function ModuleCanExact(module)
    local SnapshotApplyMode = addon.SnapshotApplyMode
    local modes = module.Config and module.Config.SnapshotApplyMode
    return SnapshotApplyMode.CanExact(modes or SnapshotApplyMode.None)
end

-- True when a module diff carries any entry in any category.
local function HasEntries(diff)
    return #(diff.added or {}) + #(diff.changed or {}) + #(diff.removed or {}) > 0
end

-- Preview what applying snapshotData over currentData would change, organized by
-- plugin then submodule so the UI can render "Plugin: <name>" with a section per
-- submodule beneath it. Each submodule entry carries canExact so the preview
-- gates its removals exactly as an apply would. Plugins and submodules are walked
-- in name order for a stable layout; only those with visible changes are kept.
-- Returns nil when nothing changed, so the Plugin umbrella contributes no diff.
function PluginManager:DiffAll(currentData, snapshotData)
    currentData = currentData or {}
    snapshotData = snapshotData or {}

    local pluginNames = {}
    for pluginName in pairs(plugins) do
        pluginNames[#pluginNames + 1] = pluginName
    end
    table.sort(pluginNames)

    local pluginDiffs
    for _, pluginName in ipairs(pluginNames) do
        local plugin = plugins[pluginName]
        local currentPlugin = currentData[pluginName]
        local snapshotPlugin = snapshotData[pluginName]

        local moduleNames = {}
        for moduleName in pairs(plugin.modules) do
            moduleNames[#moduleNames + 1] = moduleName
        end
        table.sort(moduleNames)

        local subModules
        for _, moduleName in ipairs(moduleNames) do
            local module = plugin.modules[moduleName]
            if module.Diff then
                local diff = module:Diff(currentPlugin and currentPlugin[moduleName], snapshotPlugin and snapshotPlugin[moduleName])
                if diff and HasEntries(diff) then
                    subModules = subModules or {}
                    subModules[#subModules + 1] = {
                        name = moduleName,
                        canExact = ModuleCanExact(module),
                        added = diff.added or {},
                        changed = diff.changed or {},
                        removed = diff.removed or {},
                    }
                end
            end
        end

        if subModules then
            pluginDiffs = pluginDiffs or {}
            pluginDiffs[#pluginDiffs + 1] = { name = pluginName, subModules = subModules }
        end
    end

    if not pluginDiffs then
        return nil
    end
    return { plugins = pluginDiffs }
end
