local _, addon = ...

local L = addon.L

local ImportManager = addon:GetObject("ImportManager")
local ProfileManager = addon:GetObject("ProfileManager")

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

-- Confirms a full database reset, which wipes every saved profile, snapshot,
-- and imported profile while keeping the player's settings, then reloads so
-- views reinitialise.
StaticPopupDialogs["WOWSYNC_RESET_DB"] = {
    text = L["Reset WowSync? This permanently deletes every saved profile, snapshot, and imported profile. Your settings are kept."],
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        ProfileManager:ResetDatabase()
        ImportManager:ResetDatabase()
        C_UI.Reload()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
    preferredIndex = 3,
}
