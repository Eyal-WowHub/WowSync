local _, addon = ...
local L = {}
addon.L = L

-- Slash command feedback
L["WowSync_UI addon not found."] = "WowSync_UI addon not found."
L["Could not open the WowSync window."] = "Could not open the WowSync window."
L["Profile 'X' saved."] = "Profile '%s' saved."
L["Profile 'X' deleted."] = "Profile '%s' deleted."
L["Profile 'X' not found."] = "Profile '%s' not found."
L["Saved profiles:"] = "Saved profiles:"
L["No saved profiles."] = "No saved profiles."
L["No revert point available for this character."] = "No revert point available for this character."
L["Reverted changes from profile 'X':"] = "Reverted changes from profile '%s':"
L["Unknown"] = "Unknown"
L["unknown"] = "unknown"

-- Apply / revert result lines
L["X: applied"] = "%s: applied"
L["X (Y)"] = "%s (%s)"
L["X: skipped - Y"] = "%s: skipped - %s"
L["  X (Y) - Z"] = "  %s (%s) - %s"
L["  X: reverted"] = "  %s: reverted"

-- Module warnings
L["Only common actions will be applied"] = "Only common actions will be applied"

-- Talents module
L["Talents are class-specific"] = "Talents are class-specific"
L["Note: This profile was saved with the Starter Build active."] = "Note: This profile was saved with the Starter Build active."
L["Could not retrieve active talent configuration."] = "Could not retrieve active talent configuration."
L["Could not retrieve talent tree for current spec."] = "Could not retrieve talent tree for current spec."
L["Failed to import 'X': Y"] = "Failed to import '%s': %s"
L["  Export string: X"] = "  Export string: %s"
L["Imported talent loadout 'X'Y"] = "Imported talent loadout '%s'%s"
L[" (was active)"] = " (was active)"
L["Unknown error"] = "Unknown error"
L["Loadouts created. Open the Talent UI to activate your desired loadout."] = "Loadouts created. Open the Talent UI to activate your desired loadout."
L["PvP Talents to restore: X"] = "PvP Talents to restore: %s"
L["Invalid import string"] = "Invalid import string"
L["Serialization version mismatch (talent tree format has changed)"] = "Serialization version mismatch (talent tree format has changed)"
L["Wrong specialization"] = "Wrong specialization"
L["Talent tree has changed since this profile was saved"] = "Talent tree has changed since this profile was saved"

-- Chat module
L["Could not create chat tab 'X' — maximum tabs reached."] = "Could not create chat tab '%s' — maximum tabs reached."

-- Addons module
L["Addon list has been updated.\nReload UI to apply changes?"] = "Addon list has been updated.\nReload UI to apply changes?"
L["Reload"] = "Reload"
L["Later"] = "Later"

-- Usage
L["Usage:"] = "Usage:"
L["  /ws save <name> - Save current setup as a profile"] = "  /ws save <name> - Save current setup as a profile"
L["  /ws apply <name> - Apply a profile to this character"] = "  /ws apply <name> - Apply a profile to this character"
L["  /ws delete <name> - Delete a profile"] = "  /ws delete <name> - Delete a profile"
L["  /ws list - List all saved profiles"] = "  /ws list - List all saved profiles"
L["  /ws revert - Undo the last applied profile"] = "  /ws revert - Undo the last applied profile"
