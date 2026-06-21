local _, addon = ...
local L = {}
addon.L = L

-- Slash command feedback
L["WowSync_UI addon not found."] = "WowSync_UI addon not found."
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

-- Usage
L["Usage:"] = "Usage:"
L["  /ws save <name> - Save current setup as a profile"] = "  /ws save <name> - Save current setup as a profile"
L["  /ws apply <name> - Apply a profile to this character"] = "  /ws apply <name> - Apply a profile to this character"
L["  /ws delete <name> - Delete a profile"] = "  /ws delete <name> - Delete a profile"
L["  /ws list - List all saved profiles"] = "  /ws list - List all saved profiles"
L["  /ws revert - Undo the last applied profile"] = "  /ws revert - Undo the last applied profile"
