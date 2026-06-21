local _, addon = ...
local RevertManager = addon:NewObject("RevertManager")

local revertPoints

function RevertManager:OnInitialized()
    revertPoints = addon.DB.global.RevertPoints
end

function RevertManager:Set(character, revertPoint)
    revertPoints[character] = revertPoint
end

function RevertManager:Get(character)
    return revertPoints[character]
end

function RevertManager:Has(character)
    return revertPoints[character] ~= nil
end

function RevertManager:Clear(character)
    revertPoints[character] = nil
end

function RevertManager:GetInfo(character)
    local revertPoint = revertPoints[character]
    if not revertPoint then
        return nil
    end

    local moduleNames = {}
    for name in pairs(revertPoint.Modules) do
        tinsert(moduleNames, name)
    end
    table.sort(moduleNames)

    return {
        ProfileName = revertPoint.ProfileName,
        Timestamp = revertPoint.Timestamp,
        ModuleNames = moduleNames,
    }
end
