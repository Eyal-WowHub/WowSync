local _, addon = ...
local Debugger = addon:NewObject("Debugger")

local ModuleRegistry = addon:GetObject("ModuleRegistry")
local CharacterInfo = LibStub("CharacterInfo-1.0")
local Time = addon.Time

local tinsert, tremove = table.insert, table.remove

--[[
    Debugger — an opt-in recorder that mirrors what WowSync does into a separate,
    uncompressed saved variable (WowSyncDebugDB) so a developer can read exactly
    what happened without the player narrating it.

    When enabled, every apply and undo is logged with the game context at the
    time, plus each affected module's Before and After state (from the module's
    own GetDebugState() method) and the data that was applied. Command-line input and UI
    actions are logged too. The store is plain Lua tables on purpose: it is meant
    to be opened and read directly from the SavedVariables file.

    Enabling persists across sessions; disabling wipes the store completely.
]]

-- The on-disk schema revision for WowSyncDebugDB.
local DEBUG_SCHEMA_VERSION = 1

-- The newest events to retain; older ones are trimmed so the store stays
-- readable and bounded even across a long session.
local MAX_EVENTS = 100

--[[ Internal helpers ]]

-- A snapshot of the global game state useful for interpreting any operation.
local function CaptureGameContext()
    local _, classTag = UnitClass("player")
    local specIndex = GetSpecialization and GetSpecialization()
    return {
        Class = classTag,
        ClassID = PlayerUtil and PlayerUtil.GetClassID and PlayerUtil.GetClassID() or nil,
        SpecID = specIndex and GetSpecializationInfo(specIndex) or nil,
        Level = UnitLevel("player"),
        ShapeshiftForm = GetShapeshiftForm and GetShapeshiftForm() or nil,
        BonusBarOffset = GetBonusBarOffset and GetBonusBarOffset() or nil,
        ActionBarPage = GetActionBarPage and GetActionBarPage() or nil,
        InCombat = InCombatLockdown and InCombatLockdown() or false,
    }
end

-- Each module's self-reported live state, keyed by module name, for the given
-- name set. Modules without a GetDebugState() method are omitted; one that errors is
-- recorded as an error so a single bad module can't lose the whole event.
local function CaptureModuleStates(moduleNames)
    local states = {}
    for name in pairs(moduleNames) do
        local module = ModuleRegistry:Get(name)
        if module and type(module.GetDebugState) == "function" then
            local captureSucceeded, state = pcall(module.GetDebugState, module)
            states[name] = captureSucceeded and state or { Error = tostring(state) }
        end
    end
    return states
end

-- Append an event, trimming the oldest entries past the retention cap.
local function AppendEvent(event)
    local events = WowSyncDebugDB.Events
    events[#events + 1] = event
    while #events > MAX_EVENTS do
        tremove(events, 1)
    end
end

-- The surface that triggered the current run of operations: set by the most
-- recent Record and kept until the next one replaces it, so every step of a
-- multi-step action shares one source. Defaults to "auto" when nothing set it.
local function ActiveSource(self)
    return self.activeSource or "auto"
end

-- A module's stored or applied payload rendered into the same shape as its live
-- GetDebugState() output via the module's RenderDebugPayload, so stored, applied, and live
-- states line up for comparison. Falls back to the raw payload when the module
-- has no renderer, and to an error marker when one throws.
local function RenderModuleData(name, payload)
    if payload == nil then
        return nil
    end
    local module = ModuleRegistry:Get(name)
    if module and type(module.RenderDebugPayload) == "function" then
        local rendered, result = pcall(module.RenderDebugPayload, module, payload)
        if not rendered then
            return { Error = tostring(result) }
        end
        return result
    end
    return payload
end

--[[ Lifecycle ]]

function Debugger:OnInitialized()
    -- Adopt an existing enabled store; otherwise stay dormant until turned on.
    if WowSyncDebugDB and WowSyncDebugDB.Enabled then
        self:EnsureStore()
    end
end

-- Bring WowSyncDebugDB into its full shape, creating it if needed. Marks the
-- store enabled and refreshes the owning character.
function Debugger:EnsureStore()
    WowSyncDebugDB = WowSyncDebugDB or {}
    WowSyncDebugDB.SchemaVersion = DEBUG_SCHEMA_VERSION
    WowSyncDebugDB.Enabled = true
    WowSyncDebugDB.Character = CharacterInfo:GetFullName()
    WowSyncDebugDB.Events = WowSyncDebugDB.Events or {}
    WowSyncDebugDB.Seq = WowSyncDebugDB.Seq or 0
end

--[[ Enable state ]]

function Debugger:IsEnabled()
    return WowSyncDebugDB ~= nil and WowSyncDebugDB.Enabled == true
end

-- Turn recording on (persisting across sessions) or off (wiping the store).
function Debugger:SetEnabled(enabled)
    if enabled then
        self:EnsureStore()
    else
        WowSyncDebugDB = nil
        self.activeSource = nil
    end
end

-- The number of recorded events, or 0 when disabled.
function Debugger:GetEventCount()
    if not self:IsEnabled() then
        return 0
    end
    return #WowSyncDebugDB.Events
end

--[[ Recording ]]

-- A new event stamped with the next sequence number, the current time, and the
-- acting character, or nil when recording is disabled (so callers can build and
-- record unconditionally). Set fields on it, then hand it to Record.
function Debugger:NewEvent(op)
    if not self:IsEnabled() then
        return nil
    end

    WowSyncDebugDB.Seq = WowSyncDebugDB.Seq + 1
    local now = Time:Now()
    return {
        Seq = WowSyncDebugDB.Seq,
        Time = now,
        TimeText = Time:ToShortDisplay(now),
        Op = op,
        Character = CharacterInfo:GetFullName(),
    }
end

-- Store a prepared event (built with NewEvent) under the given source, which
-- also becomes the active source for the operations this event precedes, so
-- every step of the action it kicks off shares one source. A nil event
-- (recording was off when it was built) is ignored, so callers need no guard.
function Debugger:Record(source, event)
    if not event then
        return
    end

    self.activeSource = source
    event.Source = source
    AppendEvent(event)
end

--[[ Operation recording ]]

-- Begin recording an apply/undo. Captures the game context, the triggering
-- source, and each affected module's Before state. Returns an opaque handle to
-- pass to EndOperation, or nil when recording is disabled (so callers can hook
-- unconditionally at near-zero cost).
function Debugger:BeginOperation(op, info, moduleNames)
    if not self:IsEnabled() then
        return nil
    end

    moduleNames = moduleNames or {}
    return {
        Op = op,
        Info = info or {},
        ModuleNames = moduleNames,
        Source = ActiveSource(self),
        Game = CaptureGameContext(),
        Before = CaptureModuleStates(moduleNames),
    }
end

-- Finish an operation started by BeginOperation: capture each module's After
-- state, fold in the data that was applied and the per-module result, and store
-- the event. A nil handle (recording was off) is ignored.
function Debugger:EndOperation(handle, moduleData, applyResults)
    if not handle or not self:IsEnabled() then
        return
    end

    local after = CaptureModuleStates(handle.ModuleNames)

    local modules = {}
    for name in pairs(handle.ModuleNames) do
        modules[name] = {
            Before = handle.Before[name],
            After = after[name],
            Applied = RenderModuleData(name, moduleData and moduleData[name]),
            Result = applyResults and applyResults[name],
        }
    end

    local event = self:NewEvent(handle.Op)
    if not event then
        return
    end
    event.Profile = handle.Info.Profile
    event.Selector = handle.Info.Selector
    event.Strategy = handle.Info.Strategy
    event.Game = handle.Game
    event.Modules = modules
    self:Record(handle.Source, event)
end

--[[ Source-tagged records ]]

-- Record a freeform detail table as an ad-hoc event from the command line,
-- attributing the operations it kicks off to the command line.
function Debugger:RecordCommand(detail)
    local event = self:NewEvent("record")
    if not event then
        return
    end

    event.Detail = detail
    event.Game = CaptureGameContext()
    self:Record("command", event)
end

-- Record a freeform detail table as an ad-hoc event from the UI, attributing the
-- operations it kicks off to the UI.
function Debugger:RecordUI(detail)
    local event = self:NewEvent("record")
    if not event then
        return
    end

    event.Detail = detail
    event.Game = CaptureGameContext()
    self:Record("ui", event)
end

-- Record a save: stamp each saved module's captured payload, rendered like its
-- live GetDebugState() output, so a stored snapshot can be compared slot for slot
-- against what later lands on apply. Keeps whichever source triggered the save.
function Debugger:RecordSave(info, moduleData)
    local event = self:NewEvent("save")
    if not event then
        return
    end

    local modules = {}
    for name, payload in pairs(moduleData) do
        modules[name] = { Captured = RenderModuleData(name, payload) }
    end

    event.Profile = info and info.Profile
    event.Selector = info and info.Selector
    event.Hash = info and info.Hash
    event.Game = CaptureGameContext()
    event.Modules = modules
    self:Record(ActiveSource(self), event)
end
