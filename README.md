# WowSync

> ⚠️ **Work in progress & experimental.** WowSync is under active development and should be considered experimental. Features may change or break between updates, and applying profiles can overwrite your existing setup — use it with care and back up anything important.

WowSync lets you capture your character's setup as a reusable **profile** and apply it to any other character with a single click. Set up one character exactly how you like it, save it, then bring action bars, talents, macros, key bindings and more to your alts in seconds.

To open the WowSync window, click the AddOn Compartment icon or type `/ws`.

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

## The WowSync Window (WowSync_UI)

The window is the heart of WowSync, and it is where the addon really shines. It is a dedicated, point-and-click interface for managing every profile and snapshot visually — no commands to memorise, nothing to type. Browse your profiles in a sortable list, scroll through each one's snapshot history, and read the note attached to every save. Before you apply anything, a **preview** shows you exactly what will change, module by module, so there are no surprises. You pick which parts to bring over and, for each one, whether to **Merge** or replace with an **Exact** copy — all from a few clicks.

This rich interface lives in a separate companion addon, **WowSync_UI**, which ships alongside WowSync. The core addon loads it on demand the moment you open the window, so there is nothing extra to set up — just keep both addons in your `AddOns` folder and click the AddOn Compartment icon.

The [slash commands](#slash-commands) are a convenient shortcut for quick, repetitive actions and for scripting in macros, but they are not the main event — the window is. If WowSync_UI is missing or disabled, the core still works on its own through the commands, so you are never locked out; you simply lose the visual experience that makes WowSync worth using.

## Using the Window

Open or close the window in either of two ways:

* Click the **WowSync icon in the AddOn Compartment** (the menu at the top of the minimap).
* Type `/ws` or `/wowsync`.

Once it is open:

* **Profiles** — the left panel lists your saved profiles. Select one to see its history on the right.
* **Save** — saving captures the current character's setup as a new **snapshot**. Use the save dialog to add a short note and to choose which parts of your setup to include.
* **Snapshot timeline** — each profile keeps a history of snapshots, newest at the top. Select a snapshot to see its note and what changed compared to your current setup.
* **Unsaved changes** — with a profile selected, a badge beside its name shows whether your current setup matches the profile's most recent snapshot or has changes you have not saved yet.
* **Apply** — apply a snapshot to the current character. You can choose which modules to apply and, per module, whether to **Merge** (add to what you already have) or use **Exact** (replace it to match the snapshot).
* **Rename** / **Delete** — manage your saved profiles.

## Live Tracking

WowSync keeps an eye on your setup as you play. When you move an action button, edit a macro, change a key binding, or tweak any other tracked part of your setup, WowSync notices and keeps its picture of your current setup up to date on its own — so a preview or a save always reflects exactly what you have right now.

This is what powers the **unsaved changes** badge in the window: with a profile selected, WowSync compares your live setup to that profile's most recent snapshot and shows at a glance whether you are up to date or have changes you have not saved yet, including how many entries were added, changed, or removed.

Anything that could interfere during combat (such as action bars) waits until you leave combat and then catches up automatically. Live tracking is on by default; you can turn it off or back on at any time with `/ws watcher on|off`.

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
| `/ws watcher on\|off` | Turn live tracking of your setup on or off (on by default). |
| `/ws help` | Show the list of commands. |

When targeting a specific snapshot, `@hash` accepts the short hash shown by `/ws list <name>`. As with Git, any unambiguous prefix works.

## Undo

Applying a profile is reversible. After an apply, use **Undo** (in the window or `/ws undo`) to restore your previous setup. The window keeps a history of recent changes, so you can step back through several applies in one go — pick an entry in the **Recent changes** list to undo everything back to that point.

## Side Notes

* Profiles are saved per account, so they are shared across all of your characters.
* When applying a profile from a different class, class-specific content (such as talents) is skipped — only what is compatible is applied.
* Feedback is always welcome.
