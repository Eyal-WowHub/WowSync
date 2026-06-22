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
L["Nothing changed since the last save."] = "Nothing changed since the last save."
L["'current' and 'latest' are reserved; name a profile to apply."] = "'current' and 'latest' are reserved; name a profile to apply."
L["Nothing to undo."] = "Nothing to undo."
L["Undid the last apply:"] = "Undid the last apply:"
L["empty"] = "empty"
L["Unknown"] = "Unknown"
L["unknown"] = "unknown"

-- Apply / undo result lines
L["X: applied"] = "%s: applied"
L["X (Y)"] = "%s (%s)"
L["X: skipped - Y"] = "%s: skipped - %s"
L["  X (Y) - Z"] = "  %s (%s) - %s"
L["  X: restored"] = "  %s: restored"

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

-- Macros module
L["X (character)"] = "%s (character)"

-- Chat module
L["Could not create chat tab 'X' — maximum tabs reached."] = "Could not create chat tab '%s' — maximum tabs reached."

-- Addons module
L["Addon list has been updated.\nReload UI to apply changes?"] = "Addon list has been updated.\nReload UI to apply changes?"
L["Reload"] = "Reload"
L["Later"] = "Later"

-- Usage
L["Usage:"] = "Usage:"
L["  /ws save <name> - Save current setup to a profile"] = "  /ws save <name> - Save current setup to a profile"
L["  /ws apply <name> [merge|replace] - Apply a profile's latest snapshot"] = "  /ws apply <name> [merge|replace] - Apply a profile's latest snapshot"
L["  /ws undo - Undo the last apply"] = "  /ws undo - Undo the last apply"
L["  /ws delete <name> - Delete a profile"] = "  /ws delete <name> - Delete a profile"
L["  /ws list - List all saved profiles"] = "  /ws list - List all saved profiles"
