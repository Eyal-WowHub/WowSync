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

* **Profiles** — the left panel lists your saved profiles. Select one to see its history on the right.
* **Save** — saving captures the current character's setup as a new **snapshot**. Use the save dialog to add a short note and to choose which parts of your setup to include.
* **Snapshot timeline** — each profile keeps a history of snapshots, newest at the top. Select a snapshot to see its note and what changed compared to your current setup.
* **Apply** — apply a snapshot to the current character. You can choose which modules to apply and, per module, whether to **Merge** (add to what you already have) or use **Exact** (replace it to match the snapshot).
* **Rename** / **Delete** — manage your saved profiles.

## Undo

Applying a profile is reversible. After an apply, use **Undo** (in the window or `/ws undo`) to restore your previous setup. The window keeps a history of recent changes, so you can step back through several applies in one go — pick an entry in the **Recent changes** list to undo everything back to that point.

## Slash Commands

`/ws` and `/wowsync` are interchangeable — every command below works with either prefix.

| Command | Description |
| --- | --- |
| `/ws` | Open or close the WowSync window. |
| `/ws save <name>` | Save the current setup as a new snapshot of a profile. |
| `/ws apply <name>[@hash] [--merge\|--exact]` | Apply a profile's latest snapshot, or a specific one by hash (Merge by default). |
| `/ws undo` | Undo the last apply. |
| `/ws delete <name>[@hash]` | Delete a profile, or a single snapshot by hash. |
| `/ws list [name]` | List all saved profiles, or one profile's snapshots. |
| `/ws help` | Show the list of commands. |

When targeting a specific snapshot, `@hash` accepts the short hash shown by `/ws list <name>`. As with Git, any unambiguous prefix works.

## Side Notes

* Profiles are saved per account, so they are shared across all of your characters.
* When applying a profile from a different class, class-specific content (such as talents) is skipped — only what is compatible is applied.
* Feedback is always welcome.
