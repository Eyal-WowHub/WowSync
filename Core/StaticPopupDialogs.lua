local _, addon = ...
local L = addon.L

--[[
    Shared StaticPopup dialog definitions.

    Centralises the popup templates WowSync registers with the global
    StaticPopupDialogs table so modules can trigger them by key via
    StaticPopup_Show(...) without each owning its own definition.

    Loaded after Locales so the dialog text can be localised at registration.
]]

-- Prompts the player to reload the UI after addon enable/disable changes,
-- which only take effect on the next reload.
StaticPopupDialogs["WOWSYNC_RELOAD_UI"] = {
    text = L["Addon list has been updated.\nReload UI to apply changes?"],
    button1 = L["Reload"],
    button2 = L["Later"],
    OnAccept = function()
        ReloadUI()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}
