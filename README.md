# WowSync

> ⚠️ **Work in progress & experimental.** WowSync is under active development and should be considered experimental. Features may change or break between updates, and applying profiles can overwrite your existing setup — use it with care and back up anything important.

WowSync lets you capture your character's setup as a reusable **profile** and apply it to any other character with a single click. Set up one character exactly how you like it, save it, then bring action bars, talents, macros, key bindings and more to your alts in seconds.

To open the WowSync window, click the icon in the AddOn Compartment (top of the minimap) or use any of the following commands: `/wowsync` or `/ws`.

## What Gets Synced

Each profile stores the following, and you choose which parts to apply per character:

* **Action Bars** — your action bar layout. When applying across classes, only shared (non class-specific) actions are copied.
* **Talents** — talent loadouts for the matching specialization.
* **Macros** — account-wide and character-specific macros.
* **Key Bindings** — your key binding setup.
* **Edit Mode** — your Edit Mode HUD layout.
* **Chat** — chat windows and tabs.
* **Combat Log** — combat log filters.
* **Settings** — interface and console (CVar) settings.
* **Addons** — which addons are enabled.

## Using the Window

* **Save** — type a name in the left panel and save the current character's setup as a new profile (or overwrite an existing one).
* **Select** a profile from the list to see its details on the right.
* **Choose modules** — tick only the parts you want to apply, or use *Select All* / *Deselect All*.
* **Apply** — apply the selected modules to the current character.
* **Rename** / **Delete** — manage your saved profiles.

## Revert

Applying a profile is reversible. After an apply, use **Revert** (in the window or `/ws revert`) to undo the last applied profile on the current character and restore your previous setup.

## Slash Commands

| Command | Description |
| --- | --- |
| `/ws` | Open or close the WowSync window. |
| `/ws save <name>` | Save the current setup as a profile. |
| `/ws apply <name>` | Apply a profile to this character. |
| `/ws delete <name>` | Delete a profile. |
| `/ws list` | List all saved profiles. |
| `/ws revert` | Undo the last applied profile. |

## Side Notes

* Profiles are saved per account, so they are shared across all of your characters.
* When applying a profile from a different class, class-specific content (such as talents) is skipped — only what is compatible is applied.
* Feedback is always welcome.
