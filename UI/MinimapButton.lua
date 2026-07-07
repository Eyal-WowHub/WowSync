local _, addon = ...
local MinimapButton = addon:NewObject("MinimapButton")

local L = addon.L

local LDB = LibStub("LibDataBroker-1.1")
local LibDBIcon = LibStub("LibDBIcon-1.0")

--[[
    MinimapButton — a minimap launcher that toggles the companion window.

    Registered through LibDBIcon, so it inherits the standard minimap-button
    behaviour (ring placement on round and square minimaps, drag-to-move, and a
    hide toggle) and persists its position in the addon's saved settings. Lives
    in the always-loaded core so it is present at login, and only registers when
    the on-demand WowSync_UI companion is installed and enabled; clicking loads
    that companion and toggles its window.
]]

-- Whether the companion UI addon is installed and enabled. It loads on demand,
-- so an enabled-but-unloaded companion still counts as available.
local function IsCompanionAvailable()
    if C_AddOns.GetAddOnInfo("WowSync_UI") == nil then
        return false
    end
    return C_AddOns.GetAddOnEnableState("WowSync_UI", UnitName("player")) > 0
end

-- The data object LibDBIcon renders on the minimap: the addon icon, a left-click
-- that toggles the window, and a short tooltip.
local function CreateLauncher()
    return LDB:NewDataObject("WowSync", {
        type = "launcher",
        icon = "Interface\\AddOns\\WowSync\\icon",
        OnClick = function(_, mouseButton)
            if mouseButton == "LeftButton" then
                WowSync:Import("UI"):ToggleUI()
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine("WowSync")
            tooltip:AddLine(L["Left-click to open."], 1, 1, 1)
        end,
    })
end

function MinimapButton:OnInitialized()
    if not IsCompanionAvailable() then
        return
    end
    -- LibDBIcon owns this table (minimapPos, hide, ...) and persists it through
    -- the addon's saved settings.
    local settings = addon.DB.Settings
    settings.Minimap = settings.Minimap or {}
    -- Default to the upper-right of the minimap ring (angle in degrees, measured
    -- counter-clockwise from east); a manual drag overwrites this afterwards.
    if settings.Minimap.minimapPos == nil then
        settings.Minimap.minimapPos = 45
    end
    LibDBIcon:Register("WowSync", CreateLauncher(), settings.Minimap)
end
