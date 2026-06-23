local _, addon = ...
local ModuleRegistry = addon:NewObject("ModuleRegistry")

local C = LibStub("Contracts-1.0")
local Interface = addon:GetObject("ModuleInterface")

local modules = {}

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
