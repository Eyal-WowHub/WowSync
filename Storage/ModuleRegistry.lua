local _, addon = ...
local ModuleRegistry = addon:NewObject("ModuleRegistry")

local C = LibStub("Contracts-1.0")

local modules = {}

function ModuleRegistry:Register(module)
    C:IsTable(module, 2)
    C:Ensures(type(module.GetName) == "function", "Register: 'module' must have GetName()")
    C:Ensures(type(module.Capture) == "function", "Register: 'module' must have Capture()")
    C:Ensures(type(module.Apply) == "function", "Register: 'module' must have Apply()")
    C:Ensures(type(module.CanApply) == "function", "Register: 'module' must have CanApply()")

    -- Optional capabilities: validated only when the module provides them.
    if module.Diff ~= nil then
        C:Ensures(type(module.Diff) == "function", "Register: module Diff must be a function")
    end
    if module.CanCapture ~= nil then
        C:Ensures(type(module.CanCapture) == "function", "Register: module CanCapture must be a function")
    end

    local name = module:GetName()
    C:Ensures(not modules[name], "Register: module '%s' is already registered", name)

    modules[name] = module
end

function ModuleRegistry:Get(name)
    return modules[name]
end

function ModuleRegistry:Iterate()
    return pairs(modules)
end
