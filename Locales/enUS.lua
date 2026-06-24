local _, addon = ...
local L = {}
addon.L = L

-- Slash command feedback
L["WowSync_UI addon not found."] = "WowSync_UI addon not found."
L["Snapshot saved."] = "Snapshot saved."
L["Reached the snapshot limit — removed the oldest (X)."] = "Reached the snapshot limit — removed the oldest (%s)."
L["Profile 'X' deleted."] = "Profile '%s' deleted."
L["Profile 'X' not found."] = "Profile '%s' not found."
L["Profile 'X' has no snapshots."] = "Profile '%s' has no snapshots."
L["Snapshot 'X' deleted."] = "Snapshot '%s' deleted."
L["Multiple snapshots match 'X'. Use the full snapshot selector:"] = "Multiple snapshots match '%s'. Use the full snapshot selector:"
L["No snapshot matches 'X'."] = "No snapshot matches '%s'."
L["Saved profiles:"] = "Saved profiles:"
L["Snapshots for 'X':"] = "Snapshots for '%s':"
L["No saved profiles."] = "No saved profiles."
L["'current' and 'latest' are reserved; name a profile to apply."] = "'current' and 'latest' are reserved; name a profile to apply."
L["Nothing to undo."] = "Nothing to undo."
L["Undid the last apply:"] = "Undid the last apply:"
L["Live tracking is on."] = "Live tracking is on."
L["Live tracking is off."] = "Live tracking is off."
L["Reset WowSync? This permanently deletes every saved profile and snapshot. Your settings are kept."] = "Reset WowSync? This permanently deletes every saved profile and snapshot. Your settings are kept."
L["empty"] = "empty"
L["Unknown"] = "Unknown"
L["unknown"] = "unknown"

-- Apply / undo result lines
L["X: applied"] = "%s: applied"
L["X (Y)"] = "%s (%s)"
L["X: skipped - Y"] = "%s: skipped - %s"
L["  X (Y) - Z"] = "  %s (%s) - %s"
L["  X - Y"] = "  %s - %s"
L["  X - Y (pinned)"] = "  %s - %s (pinned)"
L["  X: restored"] = "  %s: restored"

-- Module warnings
L["Only common actions will be applied"] = "Only common actions will be applied"

-- Capture diagnostics
L["Could not capture module 'X': Y"] = "Could not capture module '%s': %s"

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

-- Usage (command tokens stay literal; only descriptions are translated)
L["Usage: X"] = "Usage: %s"
L["Usage: (X and Y are interchangeable)"] = "Usage: (%s and %s are interchangeable)"
L["Toggle the UI"] = "Toggle the UI"
L["Snapshot your current setup"] = "Snapshot your current setup"
L["Apply latest or a specific snapshot"] = "Apply latest or a specific snapshot"
L["Undo the last apply"] = "Undo the last apply"
L["Delete a character's profile or one of its snapshots"] = "Delete a character's profile or one of its snapshots"
L["List profiles, or a character's snapshots"] = "List profiles, or a character's snapshots"
L["Mirror your changes live"] = "Mirror your changes live"
L["Delete all saved profiles and snapshots"] = "Delete all saved profiles and snapshots"
L["Unknown command. Type X."] = "Unknown command. Type %s."
