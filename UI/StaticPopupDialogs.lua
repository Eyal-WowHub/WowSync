local _, addon = ...

local L = addon.L

local ImportManager = addon:GetObject("ImportManager")
local ProfileManager = addon:GetObject("ProfileManager")
local Upgrade = addon:GetObject("Upgrade")

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

-- Announces the one-time reset this overhaul requires: the old saved data is
-- incompatible, so it must be cleared once before WowSync can be used again.
-- Dismissible, but the UI toggle and slash handler re-raise it until accepted.
StaticPopupDialogs["WOWSYNC_UPGRADE"] = {
    text = L["WowSync has had a major overhaul and your old data is no longer compatible. A one-time reset is required to continue: this deletes every saved profile, snapshot, and imported profile, but keeps your settings."],
    button1 = L["Reset now"],
    button2 = L["Later"],
    OnAccept = function()
        Upgrade:PerformReset()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
    preferredIndex = 3,
}
