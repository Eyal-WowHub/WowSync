local _, addon = ...
local Talents = addon:NewObject("Talents")

local L = addon.L
local AsyncTask = addon.AsyncTask
local HashSet = addon.HashSet
local ModuleRegistry = addon.ModuleRegistry
local SnapshotApplyMode = addon.SnapshotApplyMode

Talents.Config = {
    -- Runs early: bar slots holding talent spells need the talents applied first.
    ApplyPriority = 20,
    SnapshotApplyMode = SnapshotApplyMode.Merge,
}

local BIT_WIDTH_VERSION = 8
local BIT_WIDTH_SPEC_ID = 16
local BIT_WIDTH_RANKS_PURCHASED = 6

--[[ Capture Helpers ]]

local function FixExportStringSpecID(exportString, specID)
    -- C_Traits.GenerateImportString always encodes the *current* spec's ID
    -- in the header, even when generating for a different spec's config.
    -- This fixes the header to contain the correct specID.
    -- Format: 8 bits version + 16 bits specID + 128 bits treeHash + content

    local importStream = ExportUtil.MakeImportDataStream(exportString)
    local version = importStream:ExtractValue(BIT_WIDTH_VERSION)

    local currentVersion = C_Traits.GetLoadoutSerializationVersion()
    if version ~= currentVersion then
        return exportString
    end

    local headerSpecID = importStream:ExtractValue(BIT_WIDTH_SPEC_ID)
    if headerSpecID == specID then
        return exportString -- Already correct
    end

    local exportStream = ExportUtil.MakeExportDataStream()
    exportStream:AddValue(BIT_WIDTH_VERSION, version)
    exportStream:AddValue(BIT_WIDTH_SPEC_ID, specID)

    local remainingBits = importStream:GetNumberOfBits() - BIT_WIDTH_VERSION - BIT_WIDTH_SPEC_ID
    while remainingBits > 0 do
        local bitsToCopy = math.min(remainingBits, 16)
        exportStream:AddValue(bitsToCopy, importStream:ExtractValue(bitsToCopy))
        remainingBits = remainingBits - bitsToCopy
    end

    return exportStream:GetExportString()
end

local function GetLoadoutData(configID, specID)
    local configInfo = C_Traits.GetConfigInfo(configID)
    if not configInfo then
        return nil
    end

    -- GenerateImportString takes configID, not treeID
    local exportString = C_Traits.GenerateImportString(configID)
    if not exportString or exportString == "" then
        return nil
    end

    -- Fix the specID in the header if capturing a non-active spec
    exportString = FixExportStringSpecID(exportString, specID)

    return {
        Name = configInfo.name,
        ExportString = exportString,
        UsesSharedActionBars = configInfo.usesSharedActionBars,
    }
end

--[[ Import Helpers ]]

local function ReadLoadoutHeader(importStream)
    local headerBitWidth = BIT_WIDTH_VERSION + BIT_WIDTH_SPEC_ID + 128
    if importStream:GetNumberOfBits() < headerBitWidth then
        return false, 0, 0, {}
    end
    local serializationVersion = importStream:ExtractValue(BIT_WIDTH_VERSION)
    local specID = importStream:ExtractValue(BIT_WIDTH_SPEC_ID)
    local treeHash = {}
    for i = 1, 16 do
        treeHash[i] = importStream:ExtractValue(8)
    end
    return true, serializationVersion, specID, treeHash
end

local function ReadLoadoutContent(importStream, treeID)
    local loadoutContent = {}
    local treeNodes = C_Traits.GetTreeNodes(treeID)
    for i, _ in ipairs(treeNodes) do
        local isNodeSelected = importStream:ExtractValue(1) == 1
        local isNodePurchased = false
        local isPartiallyRanked = false
        local partialRanksPurchased = 0
        local isChoiceNode = false
        local choiceNodeSelection = 0

        if isNodeSelected then
            isNodePurchased = importStream:ExtractValue(1) == 1
            if isNodePurchased then
                isPartiallyRanked = importStream:ExtractValue(1) == 1
                if isPartiallyRanked then
                    partialRanksPurchased = importStream:ExtractValue(BIT_WIDTH_RANKS_PURCHASED)
                end
                isChoiceNode = importStream:ExtractValue(1) == 1
                if isChoiceNode then
                    choiceNodeSelection = importStream:ExtractValue(2)
                end
            end
        end

        loadoutContent[i] = {
            isNodeSelected = isNodeSelected,
            isNodeGranted = isNodeSelected and not isNodePurchased,
            isPartiallyRanked = isPartiallyRanked,
            partialRanksPurchased = partialRanksPurchased,
            isChoiceNode = isChoiceNode,
            choiceNodeSelection = choiceNodeSelection + 1,
        }
    end
    return loadoutContent
end

local function CreateEntryInfoFromSingleNode(loadoutEntries, configID, nodeInfo, indexInfo)
    if not nodeInfo or not indexInfo or not indexInfo.isNodeSelected then
        return
    end

    local loadoutEntry = {
        nodeID = nodeInfo.ID,
        ranksGranted = indexInfo.isNodeGranted and 1 or 0,
    }

    if indexInfo.isNodeSelected and not indexInfo.isNodeGranted then
        loadoutEntry.ranksPurchased = indexInfo.isPartiallyRanked and indexInfo.partialRanksPurchased or nodeInfo.maxRanks
    else
        loadoutEntry.ranksPurchased = 0
    end

    if indexInfo.isChoiceNode and indexInfo.choiceNodeSelection then
        loadoutEntry.selectionEntryID = nodeInfo.entryIDs[indexInfo.choiceNodeSelection]
    elseif nodeInfo.activeEntry then
        loadoutEntry.selectionEntryID = nodeInfo.activeEntry.entryID
    end

    if not loadoutEntry.selectionEntryID then
        loadoutEntry.selectionEntryID = nodeInfo.entryIDs[1]
    end

    if loadoutEntry.selectionEntryID then
        tinsert(loadoutEntries, loadoutEntry)
    end
end

local function CreateEntryInfoFromTieredNode(loadoutEntries, configID, nodeInfo, indexInfo)
    if not nodeInfo or not indexInfo or not indexInfo.isNodeSelected then
        return
    end

    local totalRanksPurchased = 0
    if not indexInfo.isNodeGranted then
        totalRanksPurchased = indexInfo.isPartiallyRanked and indexInfo.partialRanksPurchased or nodeInfo.maxRanks
    end

    local remainingRanks = totalRanksPurchased
    for index, entryID in ipairs(nodeInfo.entryIDs) do
        local entryInfo = C_Traits.GetEntryInfo(configID, entryID)
        if entryInfo then
            local ranksForThisEntry = math.min(remainingRanks, entryInfo.maxRanks)
            local isGranted = indexInfo.isNodeGranted and (index == 1)
            if ranksForThisEntry > 0 or isGranted then
                tinsert(loadoutEntries, {
                    nodeID = nodeInfo.ID,
                    ranksGranted = isGranted and 1 or 0,
                    ranksPurchased = ranksForThisEntry,
                    selectionEntryID = entryID,
                })
            end
            remainingRanks = remainingRanks - ranksForThisEntry
        end
    end
end

local function ConvertToImportLoadoutEntryInfo(configID, treeID, loadoutContent)
    local loadoutEntries = {}
    local treeNodes = C_Traits.GetTreeNodes(treeID)
    for index, treeNodeID in ipairs(treeNodes) do
        local indexInfo = loadoutContent[index]
        local nodeInfo = C_Traits.GetNodeInfo(configID, treeNodeID)
        if nodeInfo then
            if nodeInfo.type == Enum.TraitNodeType.Tiered then
                CreateEntryInfoFromTieredNode(loadoutEntries, configID, nodeInfo, indexInfo)
            else
                CreateEntryInfoFromSingleNode(loadoutEntries, configID, nodeInfo, indexInfo)
            end
        end
    end
    return loadoutEntries
end

local function IsTreeHashEmpty(treeHash)
    for _, hashByte in ipairs(treeHash) do
        if hashByte ~= 0 then return false end
    end
    return true
end

local function TreeHashesMatch(leftHash, rightHash)
    if #leftHash ~= #rightHash then return false end
    for i, hashByte in ipairs(leftHash) do
        if hashByte ~= rightHash[i] then return false end
    end
    return true
end

local function ImportLoadoutFromString(configID, treeID, importString, loadoutName)
    local importStream = ExportUtil.MakeImportDataStream(importString)

    local headerValid, serializationVersion, specID, treeHash = ReadLoadoutHeader(importStream)
    if not headerValid then
        return false, L["Invalid import string"]
    end

    local currentVersion = C_Traits.GetLoadoutSerializationVersion()
    if serializationVersion ~= currentVersion then
        return false, L["Serialization version mismatch (talent tree format has changed)"]
    end

    if specID ~= PlayerUtil.GetCurrentSpecID() then
        return false, L["Wrong specialization"]
    end

    -- Validate tree hash (empty hashes bypass validation, matching Blizzard behavior)
    if not IsTreeHashEmpty(treeHash) then
        local currentHash = C_Traits.GetTreeHash(treeID)
        if currentHash and not TreeHashesMatch(treeHash, currentHash) then
            return false, L["Talent tree has changed since this profile was saved"]
        end
    end

    local loadoutContent = ReadLoadoutContent(importStream, treeID)
    local loadoutEntryInfo = ConvertToImportLoadoutEntryInfo(configID, treeID, loadoutContent)

    return C_ClassTalents.ImportLoadout(configID, loadoutEntryInfo, loadoutName, importString)
end

--[[ Module API ]]

function Talents:Capture()
    local capturedData = {
        Specs = {},
        StarterBuildActive = C_ClassTalents.GetHasStarterBuild() and C_ClassTalents.GetStarterBuildActive() or false,
    }

    -- Only the active spec's loadouts are captured: ImportLoadout is spec-locked,
    -- so a snapshot can only ever be restored into the spec it was taken in.
    local specID = GetSpecializationInfo(GetSpecialization())
    if specID then
        local specEntry = {
            Loadouts = {},
            ActiveLoadoutConfigID = C_ClassTalents.GetLastSelectedSavedConfigID(specID),
        }

        local configIDs = C_ClassTalents.GetConfigIDsBySpecID(specID)
        if configIDs then
            for _, configID in ipairs(configIDs) do
                local loadout = GetLoadoutData(configID, specID)
                if loadout then
                    loadout.WasActive = (configID == specEntry.ActiveLoadoutConfigID)
                    tinsert(specEntry.Loadouts, loadout)
                end
            end
        end

        if #specEntry.Loadouts > 0 then
            capturedData.Specs[specID] = specEntry
        end
    end

    return capturedData
end

--[[ Loadout import ]]

-- ImportLoadout starts an asynchronous config creation that only reports on a
-- later TRAIT_CONFIG_CREATED, and a second import fired before the first finishes
-- is silently dropped -- so the loadouts must be created strictly one at a time.
-- LoadoutImporter (below) is that state machine; this bounds how long it waits
-- for any one create to report back before moving on.
local IMPORT_TIMEOUT_SECONDS = 5

-- Commit the current spec's loadout named `name` the same way the Talent UI does.
-- A just-imported config is not ready to load until a later TRAIT_CONFIG_UPDATED
-- reports it populated, so an unready target waits for that event (bounded by a
-- timeout) rather than loading into an empty config.
local ACTIVATE_READY_TIMEOUT_SECONDS = 5

local function LoadLoadoutByName(specID, name)
    local configID
    for _, id in ipairs(C_ClassTalents.GetConfigIDsBySpecID(specID) or {}) do
        local configInfo = C_Traits.GetConfigInfo(id)
        if configInfo and configInfo.name == name then
            configID = id
            break
        end
    end
    if not configID then return end

    local function Commit()
        C_ClassTalents.UpdateLastSelectedSavedConfigID(specID, configID)
        local loadResult = C_ClassTalents.LoadConfig(configID, true)
        if loadResult == Enum.LoadConfigResult.Error then
            addon:Print(L["Could not activate talent loadout 'X'."]:format(name))
        else
            addon:Print(L["Activated talent loadout 'X'."]:format(name))
        end
    end

    if C_ClassTalents.IsConfigPopulated(configID) then
        Commit()
        return
    end

    -- The config exists but is not ready yet; load it once it reports populated.
    local timer
    local function OnConfigReady(_, _, updatedConfigID)
        if updatedConfigID ~= configID or not C_ClassTalents.IsConfigPopulated(configID) then
            return
        end
        timer:Cancel()
        Talents:UnregisterEvent("TRAIT_CONFIG_UPDATED", OnConfigReady)
        Commit()
    end

    Talents:RegisterEvent("TRAIT_CONFIG_UPDATED", OnConfigReady)
    timer = C_Timer.NewTimer(ACTIVATE_READY_TIMEOUT_SECONDS, function()
        Talents:UnregisterEvent("TRAIT_CONFIG_UPDATED", OnConfigReady)
        addon:Print(L["Could not activate talent loadout 'X'."]:format(name))
    end)
end

-- Re-select the loadout (or Starter Build) that was active when the snapshot was
-- saved, so the character ends up on the same build it had.
local function ActivateSavedSelection(specID, activeLoadoutName, starterBuildActive)
    if not specID then return end
    if starterBuildActive then
        if C_ClassTalents.GetHasStarterBuild() then
            C_ClassTalents.SetStarterBuildActive(true)
            addon:Print(L["Activated the Starter Build."])
        end
        return
    end
    if activeLoadoutName then
        LoadLoadoutByName(specID, activeLoadoutName)
    end
end

--[[
    LoadoutImporter — the sequential loadout-import state machine.

    Imports a queue of talent loadouts into the current spec one at a time (each
    ImportLoadout must finish creating before the next starts), then re-selects
    the loadout that was active when the snapshot was saved. Its states:

        Start        -- listen for created configs, import the first loadout
        (importing)  -- a loadout is in flight; wait for its TRAIT_CONFIG_CREATED
                        or the per-loadout timeout
        Advance      -- that create landed (or timed out); import the next
        Finish       -- queue drained: re-select the active loadout, then settle
        Cancel       -- a newer import superseded this one: settle, no activation

    It settles exactly once, calling onDone -- the resolve of the apply's
    AsyncTask -- so the write is never left hanging.
]]
local LoadoutImporter = {}
LoadoutImporter.__index = LoadoutImporter

-- params: specID, configID, treeID, existingStrings, queue, activeLoadoutName,
-- starterBuildActive, and onDone (called once when the import settles).
function LoadoutImporter:New(params)
    return setmetatable({
        specID = params.specID,
        configID = params.configID,
        treeID = params.treeID,
        existingStrings = params.existingStrings,
        queue = params.queue,
        activeLoadoutName = params.activeLoadoutName,
        starterBuildActive = params.starterBuildActive,
        onDone = params.onDone,
        timer = nil,
        finished = false,
    }, self)
end

-- Enter the machine: listen for created configs, then import the first loadout.
function LoadoutImporter:Start()
    self.onConfigCreated = function(_, _, configInfo)
        -- Only a combat config finishing means the in-flight import completed.
        if not self.timer then return end
        if type(configInfo) == "table" and configInfo.type and configInfo.type ~= Enum.TraitConfigType.Combat then
            return
        end
        self:Advance()
    end
    Talents:RegisterEvent("TRAIT_CONFIG_CREATED", self.onConfigCreated)
    self:ProcessNext()
end

-- The in-flight import reported back (or its timeout fired): import the next.
function LoadoutImporter:Advance()
    if self.timer then
        self.timer:Cancel()
        self.timer = nil
    end
    self:ProcessNext()
end

-- Import queued loadouts until one is actually created (then wait for it) or the
-- queue is drained (then finish); skips and failures fall through to the next.
function LoadoutImporter:ProcessNext()
    while true do
        local loadout = tremove(self.queue, 1)
        if not loadout then
            self:Finish()
            return
        end

        if loadout.ExportString then
            if self.existingStrings[loadout.ExportString] then
                addon:Print(L["Skipped talent loadout 'X' (an identical loadout already exists)."]:format(loadout.Name))
            else
                local importSucceeded, importResult, importError = pcall(ImportLoadoutFromString, self.configID, self.treeID, loadout.ExportString, loadout.Name)
                if not importSucceeded then
                    addon:Print(L["Failed to import 'X': Y"]:format(loadout.Name, tostring(importResult)))
                    addon:Print(L["  Export string: X"]:format(loadout.ExportString))
                elseif importResult then
                    self.existingStrings[loadout.ExportString] = true
                    local activeTag = loadout.WasActive and L[" (was active)"] or ""
                    addon:Print(L["Imported talent loadout 'X'Y"]:format(loadout.Name, activeTag))
                    -- Wait for its TRAIT_CONFIG_CREATED (or the timeout) before the next.
                    self.timer = C_Timer.NewTimer(IMPORT_TIMEOUT_SECONDS, function() self:Advance() end)
                    return
                else
                    addon:Print(L["Failed to import 'X': Y"]:format(loadout.Name, importError or L["Unknown error"]))
                    addon:Print(L["  Export string: X"]:format(loadout.ExportString))
                end
            end
        end
    end
end

-- Drop the event and timer registrations, shared by both terminal transitions.
function LoadoutImporter:Teardown()
    if self.timer then
        self.timer:Cancel()
        self.timer = nil
    end
    if self.onConfigCreated then
        Talents:UnregisterEvent("TRAIT_CONFIG_CREATED", self.onConfigCreated)
    end
end

-- Terminal: the queue drained. Re-select the active loadout, then settle.
function LoadoutImporter:Finish()
    if self.finished then return end
    self.finished = true
    self:Teardown()
    ActivateSavedSelection(self.specID, self.activeLoadoutName, self.starterBuildActive)
    self.onDone()
end

-- Terminal: a newer import took over. Settle without re-selecting anything.
function LoadoutImporter:Cancel()
    if self.finished then return end
    self.finished = true
    self:Teardown()
    self.onDone()
end

-- The import currently running, so a new apply can supersede it. nil when idle.
local activeImport

function Talents:Apply(capturedData, sourceMetadata)
    local currentSpecID = GetSpecializationInfo(GetSpecialization())
    local specEntry = capturedData.Specs[currentSpecID]

    if not specEntry then
        return AsyncTask:Resolved()
    end

    local configID = C_ClassTalents.GetActiveConfigID()
    if not configID then
        addon:Print(L["Could not retrieve active talent configuration."])
        return AsyncTask:Resolved()
    end

    local treeID = C_ClassTalents.GetTraitTreeForSpec(currentSpecID)
    if not treeID then
        addon:Print(L["Could not retrieve talent tree for current spec."])
        return AsyncTask:Resolved()
    end

    -- Loadouts already saved on this character, keyed by their exported content.
    -- WoW lets several loadouts share a name and ImportLoadout never rejects a
    -- duplicate, so the name guards nothing; the export string is a build's real
    -- identity. A snapshot loadout whose string is already present is the very
    -- same build (whatever it is named), so it is skipped rather than piling up
    -- another identical copy on every apply.
    local existingStrings = {}
    local existingConfigIDs = C_ClassTalents.GetConfigIDsBySpecID(currentSpecID)
    if existingConfigIDs then
        for _, existingConfigID in ipairs(existingConfigIDs) do
            local existingString = C_Traits.GenerateImportString(existingConfigID)
            if existingString and existingString ~= "" then
                existingStrings[existingString] = true
            end
        end
    end

    local activeLoadoutName
    for _, loadout in ipairs(specEntry.Loadouts) do
        if loadout.WasActive then
            activeLoadoutName = loadout.Name
            break
        end
    end

    local queue = {}
    for _, loadout in ipairs(specEntry.Loadouts) do
        tinsert(queue, loadout)
    end

    return AsyncTask:Run(function(resolve)
        if activeImport then activeImport:Cancel() end
        activeImport = LoadoutImporter:New({
            specID = currentSpecID,
            configID = configID,
            treeID = treeID,
            existingStrings = existingStrings,
            queue = queue,
            activeLoadoutName = activeLoadoutName,
            starterBuildActive = capturedData.StarterBuildActive,
            onDone = resolve,
        })
        activeImport:Start()
    end)
end

-- Flatten the current spec's loadouts into a keyed list, hashing only the
-- stable identity (name + export string) so a changed active flag isn't a
-- "change". Mirror Apply, which only imports the current spec's loadouts.
local function FlattenLoadouts(capturedData)
    local loadoutEntries = {}
    local specID = GetSpecializationInfo(GetSpecialization())
    local specEntry = specID and capturedData and capturedData.Specs and capturedData.Specs[specID]
    if specEntry then
        for _, loadout in ipairs(specEntry.Loadouts or {}) do
            tinsert(loadoutEntries, { Name = loadout.Name, ExportString = loadout.ExportString, SpecID = specID })
        end
    end
    return loadoutEntries
end

local function LoadoutKey(loadout)
    return loadout.Name
end

-- The icon of the specialization a loadout belongs to, for diff previews.
local function LoadoutIcon(loadout)
    return select(4, GetSpecializationInfoByID(loadout.SpecID))
end

-- Preview of which talent loadouts applying this snapshot would change.
function Talents:Diff(currentData, snapshotData)
    local currentSet = HashSet:From(FlattenLoadouts(currentData), LoadoutKey, LoadoutKey, LoadoutIcon)
    local snapshotSet = HashSet:From(FlattenLoadouts(snapshotData), LoadoutKey, LoadoutKey, LoadoutIcon)

    return {
        added = currentSet:Added(snapshotSet),
        changed = currentSet:Changed(snapshotSet),
        removed = currentSet:Removed(snapshotSet),
    }
end

function Talents:CanApply(sourceMetadata)
    if sourceMetadata.ClassID ~= PlayerUtil.GetClassID() then
        return false, L["Talents are class-specific"]
    end
    return true
end

-- Events that mean this module's live state may have changed, so the GameWatcher
-- can re-mirror it into Current (debounced).
function Talents:GetWatchedEvents()
    return { "TRAIT_CONFIG_UPDATED", "PLAYER_SPECIALIZATION_CHANGED" }
end

-- The current spec's live loadouts (name + config ID) and which one is active,
-- so the debug log shows exactly which loadouts existed before and after a sync.
function Talents:GetDebugState()
    local specID = GetSpecializationInfo(GetSpecialization())

    local loadouts = {}
    local configIDs = specID and C_ClassTalents.GetConfigIDsBySpecID(specID)
    if configIDs then
        for _, configID in ipairs(configIDs) do
            local configInfo = C_Traits.GetConfigInfo(configID)
            tinsert(loadouts, { ConfigID = configID, Name = configInfo and configInfo.name })
        end
    end

    return {
        SpecID = specID,
        ActiveConfigID = C_ClassTalents.GetActiveConfigID(),
        LastSelectedConfigID = specID and C_ClassTalents.GetLastSelectedSavedConfigID(specID) or nil,
        StarterBuildActive = C_ClassTalents.GetHasStarterBuild() and C_ClassTalents.GetStarterBuildActive() or false,
        Loadouts = loadouts,
    }
end

--[[ Registration ]]

function Talents:OnInitialized()
    ModuleRegistry:Register(self)
end
