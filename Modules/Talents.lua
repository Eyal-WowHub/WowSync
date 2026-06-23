local _, addon = ...
local Talents = addon:NewObject("Talents")
local ProfileManager = addon:GetObject("ProfileManager")

local L = addon.L
local HashSet = addon.HashSet
local SnapshotApplyMode = addon.SnapshotApplyMode

Talents.Config = {
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

local function GetPvpTalentsForSpec(specIndex)
    -- Must be the active spec to query PvP talents
    if specIndex ~= GetSpecialization() then
        return nil
    end

    local talentIDs = C_SpecializationInfo.GetAllSelectedPvpTalentIDs()
    if not talentIDs or #talentIDs == 0 then
        return nil
    end

    local pvpTalents = {}
    for _, talentID in ipairs(talentIDs) do
        if talentID and talentID > 0 then
            local _, name = GetPvpTalentInfoByID(talentID)
            tinsert(pvpTalents, {
                TalentID = talentID,
                Name = name,
            })
        end
    end

    return #pvpTalents > 0 and pvpTalents or nil
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
    local results = {}
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

        results[i] = {
            isNodeSelected = isNodeSelected,
            isNodeGranted = isNodeSelected and not isNodePurchased,
            isPartiallyRanked = isPartiallyRanked,
            partialRanksPurchased = partialRanksPurchased,
            isChoiceNode = isChoiceNode,
            choiceNodeSelection = choiceNodeSelection + 1,
        }
    end
    return results
end

local function CreateEntryInfoFromSingleNode(results, configID, nodeInfo, indexInfo)
    if not nodeInfo or not indexInfo or not indexInfo.isNodeSelected then
        return
    end

    local result = {
        nodeID = nodeInfo.ID,
        ranksGranted = indexInfo.isNodeGranted and 1 or 0,
    }

    if indexInfo.isNodeSelected and not indexInfo.isNodeGranted then
        result.ranksPurchased = indexInfo.isPartiallyRanked and indexInfo.partialRanksPurchased or nodeInfo.maxRanks
    else
        result.ranksPurchased = 0
    end

    if indexInfo.isChoiceNode and indexInfo.choiceNodeSelection then
        result.selectionEntryID = nodeInfo.entryIDs[indexInfo.choiceNodeSelection]
    elseif nodeInfo.activeEntry then
        result.selectionEntryID = nodeInfo.activeEntry.entryID
    end

    if not result.selectionEntryID then
        result.selectionEntryID = nodeInfo.entryIDs[1]
    end

    if result.selectionEntryID then
        tinsert(results, result)
    end
end

local function CreateEntryInfoFromTieredNode(results, configID, nodeInfo, indexInfo)
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
                tinsert(results, {
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
    local results = {}
    local treeNodes = C_Traits.GetTreeNodes(treeID)
    for index, treeNodeID in ipairs(treeNodes) do
        local indexInfo = loadoutContent[index]
        local nodeInfo = C_Traits.GetNodeInfo(configID, treeNodeID)
        if nodeInfo then
            if nodeInfo.type == Enum.TraitNodeType.Tiered then
                CreateEntryInfoFromTieredNode(results, configID, nodeInfo, indexInfo)
            else
                CreateEntryInfoFromSingleNode(results, configID, nodeInfo, indexInfo)
            end
        end
    end
    return results
end

local function IsTreeHashEmpty(treeHash)
    for _, v in ipairs(treeHash) do
        if v ~= 0 then return false end
    end
    return true
end

local function TreeHashesMatch(a, b)
    if #a ~= #b then return false end
    for i, v in ipairs(a) do
        if v ~= b[i] then return false end
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
    local data = {
        Specs = {},
        StarterBuildActive = C_ClassTalents.GetHasStarterBuild() and C_ClassTalents.GetStarterBuildActive() or false,
    }

    local numSpecs = GetNumSpecializations()

    for specIndex = 1, numSpecs do
        local specID = GetSpecializationInfo(specIndex)
        local specEntry = {
            Loadouts = {},
            ActiveLoadoutConfigID = C_ClassTalents.GetLastSelectedSavedConfigID(specID),
            PvpTalents = GetPvpTalentsForSpec(specIndex),
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

        if #specEntry.Loadouts > 0 or specEntry.PvpTalents then
            data.Specs[specID] = specEntry
        end
    end

    return data
end

function Talents:Apply(data, meta)
    local currentSpecID = GetSpecializationInfo(GetSpecialization())
    local specEntry = data.Specs[currentSpecID]

    if not specEntry then
        return
    end

    if data.StarterBuildActive then
        addon:Print(L["Note: This profile was saved with the Starter Build active."])
    end

    local configID = C_ClassTalents.GetActiveConfigID()
    if not configID then
        addon:Print(L["Could not retrieve active talent configuration."])
        return
    end

    local treeID = C_ClassTalents.GetTraitTreeForSpec(currentSpecID)
    if not treeID then
        addon:Print(L["Could not retrieve talent tree for current spec."])
        return
    end

    local importedCount = 0
    for _, loadout in ipairs(specEntry.Loadouts) do
        if loadout.ExportString then
            local ok, result1, result2 = pcall(ImportLoadoutFromString, configID, treeID, loadout.ExportString, loadout.Name)
            if not ok then
                addon:Print(L["Failed to import 'X': Y"]:format(loadout.Name, tostring(result1)))
                addon:Print(L["  Export string: X"]:format(loadout.ExportString))
            elseif result1 then
                local activeTag = loadout.WasActive and L[" (was active)"] or ""
                addon:Print(L["Imported talent loadout 'X'Y"]:format(loadout.Name, activeTag))
                importedCount = importedCount + 1
            else
                addon:Print(L["Failed to import 'X': Y"]:format(loadout.Name, result2 or L["Unknown error"]))
                addon:Print(L["  Export string: X"]:format(loadout.ExportString))
            end
        end
    end

    if importedCount > 0 then
        addon:Print(L["Loadouts created. Open the Talent UI to activate your desired loadout."])
    end

    -- PvP talents (informational — must be selected manually in the Talent UI)
    if specEntry.PvpTalents then
        local names = {}
        for _, pvp in ipairs(specEntry.PvpTalents) do
            tinsert(names, pvp.Name)
        end
        addon:Print(L["PvP Talents to restore: X"]:format(table.concat(names, ", ")))
    end
end

-- Flatten the current spec's loadouts into a keyed list, hashing only the
-- stable identity (name + export string) so a changed active flag isn't a
-- "change". Mirror Apply, which only imports the current spec's loadouts.
local function FlattenLoadouts(data)
    local list = {}
    local specID = GetSpecializationInfo(GetSpecialization())
    local specEntry = specID and data and data.Specs and data.Specs[specID]
    if specEntry then
        for _, loadout in ipairs(specEntry.Loadouts or {}) do
            tinsert(list, { Name = loadout.Name, ExportString = loadout.ExportString })
        end
    end
    return list
end

local function LoadoutKey(loadout)
    return loadout.Name
end

-- Preview of which talent loadouts applying this profile would change.
function Talents:Diff(current, snapshot)
    local currentSet = HashSet:From(FlattenLoadouts(current), LoadoutKey, LoadoutKey)
    local snapshotSet = HashSet:From(FlattenLoadouts(snapshot), LoadoutKey, LoadoutKey)

    return {
        added = currentSet:Added(snapshotSet),
        changed = currentSet:Changed(snapshotSet),
        removed = currentSet:Removed(snapshotSet),
    }
end

function Talents:CanApply(meta)
    if meta.ClassID ~= PlayerUtil.GetClassID() then
        return false, L["Talents are class-specific"]
    end
    return true
end

-- Events that mean this module's live state may have changed, so the GameWatcher
-- can re-mirror it into Current (debounced).
function Talents:GetWatchedEvents()
    return { "TRAIT_CONFIG_UPDATED", "PLAYER_SPECIALIZATION_CHANGED" }
end

--[[ Registration ]]

function Talents:OnInitialized()
    ProfileManager:RegisterModule(self)
end
