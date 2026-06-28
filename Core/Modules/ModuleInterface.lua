local _, addon = ...
local ModuleInterface = addon:NewObject("ModuleInterface")

--[[
    ModuleInterface — the contract every sync module fulfils.

    A "module" is the unit WowSync captures, diffs, and applies for one slice of
    the game (action bars, talents, macros, ...). Modules are plain Addon objects
    created with addon:NewObject(name); they self-register in their OnInitialized
    via ModuleRegistry:Register(self). Registration validates each module against
    the member lists at the bottom of this file, so this is the single source of
    truth for the contract: edit a list here and the registry enforces the change.

    Members fall into three groups — required methods, optional methods, and
    optional fields — each documented below with its signature, semantics, and
    the framework code that calls it.

    ── Required methods ──────────────────────────────────────────────────────

    GetName() -> string
        The module's stable identity (e.g. "ActionBars"), used as its key in
        snapshots, the registry, and the UI. Provided automatically by
        addon:NewObject(name) — modules do not implement it themselves, but it
        must be present, so it is listed as required.

    Capture() -> capturedData
        Read the player's current live state for this domain and return it as a
        plain, serializable table. No side effects. Called by CurrentStore when
        mirroring live state and when saving a snapshot.

    Apply(capturedData, sourceMetadata, applyOptions)
        Write a previously captured module table back into the game. The source
        metadata carries the snapshot's provenance (notably ClassID).
        applyOptions.mode is "merge" (add/overwrite snapshot items, leave the
        rest) or "exact" (also remove live items absent from the snapshot);
        modules that only support merge may ignore applyOptions. The only
        contract member with real side effects. Called by SnapshotManager during
        apply and undo.

    CanApply(sourceMetadata) -> boolean[, warning]
        Pre-flight gate asked before Apply. Returns whether applying is sensible
        for this snapshot's origin, plus an optional human-readable caveat shown
        in the UI/chat (e.g. a cross-class warning). A false return blocks the
        apply. Called by SnapshotManager.

    ── Optional methods (validated only when present) ────────────────────────

    Diff(currentData, snapshotData) -> { added, changed, removed }
        Pure comparison, no side effects. Returns three lists of display labels
        describing what an apply would change. Powers the preview UI and the
        unsaved-changes badge. Called by Differ.

    ShouldCapture() -> boolean
        Guard asked before Capture. Return false to defer because the live state
        is momentarily untrustworthy (e.g. ActionBars during combat, when bar
        paging shows a transient layout). Called by CurrentStore.

    GetWatchedEvents() -> { eventName, ... }
        Declares the game events meaning "my live state may have changed." The
        GameWatcher registers them and re-captures just this module (debounced)
        when one fires. Modules with no live trigger omit it. Called by
        GameWatcher.

    GetDebugState() -> table
        Read this module's live state into a plain, readable table for the debug
        log. No side effects. Debugger calls it right before and right after an
        apply or undo, capturing a "before" and "after" picture of the live game
        so a developer can see exactly what the operation changed. Omit it on
        modules not worth tracing.

    RenderDebugPayload(capturedData) -> table
        Re-express a captured payload (this module's own Capture() output, as
        stored in a snapshot or passed to Apply) into the same table shape
        GetDebugState() returns. Capture() may keep data in a compact or
        reordered form that doesn't read cleanly on its own; this renders it the
        way the live state reads, so the saved/applied data lines up beside the
        live before/after in the log and can be compared field for field. Omit
        it when the captured payload already reads clearly. 

    ── Optional fields ───────────────────────────────────────────────────────

    Config = { SnapshotApplyMode = <flags>, ApplyPriority = <number> }
        Static, declarative settings for the module. A table field, not a method.

        SnapshotApplyMode declares supported apply modes (Merge, or All =
        Merge+Exact). Read by SnapshotManager:GetModuleApplyMode to drive the
        UI's merge/exact toggle and the `opts.mode` passed to Apply.

        ApplyPriority orders modules during an apply: lower numbers apply first,
        so modules others reference (Macros, Talents) precede the modules
        pointing at them (ActionBars, Keybindings). Omitted modules apply at a
        default mid priority in stable name order.

    Lifecycle note: OnInitialized() is an Addon-1.0 hook, not part of this
    contract; every module uses it to call ModuleRegistry:Register(self).
]]

-- Must be present on every module (GetName is supplied by NewObject).
ModuleInterface.RequiredMethods = {
    "GetName",
    "Capture",
    "Apply",
    "CanApply",
}

-- Validated as functions only when a module provides them.
ModuleInterface.OptionalMethods = {
    "Diff",
    "ShouldCapture",
    "GetWatchedEvents",
    "GetDebugState",
    "RenderDebugPayload",
}

-- Non-method members, validated to be of the given type only when present.
ModuleInterface.OptionalFields = {
    Config = "table",
}
