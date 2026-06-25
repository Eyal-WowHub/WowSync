local _, addon = ...
local EditMode = addon:NewObject("EditMode")
local ModuleRegistry = addon:GetObject("ModuleRegistry")

local HashSet = addon.HashSet
local SnapshotApplyMode = addon.SnapshotApplyMode

EditMode.Config = {
    SnapshotApplyMode = SnapshotApplyMode.Merge,
}

--[[
    Edit Mode layout sync.

    Edit Mode (added in 10.0) lets players rearrange their entire HUD:
    action bars, unit frames, minimap, buffs, chat, bags, micro menu, etc.

    API surface:
        C_EditMode.GetLayouts()                    → { layouts = EditModeLayoutInfo[], activeLayout = number }
        C_EditMode.SaveLayouts(saveInfo)            → saves all custom layouts
        C_EditMode.SetActiveLayout(index)           → activates a layout by overall index (presets + custom)
        C_EditMode.ConvertLayoutInfoToString(info)  → serialized export string
        C_EditMode.ConvertStringToLayoutInfo(str)   → deserialized EditModeLayoutInfo

    GetLayouts() only returns CUSTOM layouts in its .layouts array.
    The .activeLayout index counts PRESET layouts first (Modern, Classic, etc.)
    followed by custom ones.

    EditModeManagerFrame.layoutInfo (when loaded) contains the full list
    including presets, so we use it to determine the preset count.

    We store the export string — the same canonical format used by wago.io
    and the in-game import/export clipboard. This ensures forward compatibility
    as Blizzard adds new systems.
]]

local LAYOUT_NAME = "WowSync"

-- Fallback preset count used only when EditModeManagerFrame.layoutInfo is
-- unavailable. As of 11.0.5 there are 3 preset layouts (Modern, Classic, ...).
local DEFAULT_PRESET_COUNT = 3

--[[ Helpers ]]

local function EnsureEditModeLoaded()
    if not EditModeManagerFrame then
        C_AddOns.LoadAddOn("Blizzard_EditMode")
    end
end

local function GetPresetCount()
    EnsureEditModeLoaded()

    if EditModeManagerFrame and EditModeManagerFrame.layoutInfo then
        local totalInFrame = #EditModeManagerFrame.layoutInfo.layouts
        local customCount = #(C_EditMode.GetLayouts().layouts)
        return totalInFrame - customCount
    end

    return DEFAULT_PRESET_COUNT
end

local function GetActiveLayoutInfo()
    EnsureEditModeLoaded()

    if EditModeManagerFrame and EditModeManagerFrame.layoutInfo then
        local layoutInfo = EditModeManagerFrame.layoutInfo
        if layoutInfo.layouts and layoutInfo.activeLayout then
            return layoutInfo.layouts[layoutInfo.activeLayout]
        end
    end

    -- Fallback: try to find the active layout among custom layouts
    local layoutInfo = C_EditMode.GetLayouts()
    local numPresets = GetPresetCount()
    local customIndex = layoutInfo.activeLayout - numPresets

    if customIndex >= 1 and customIndex <= #layoutInfo.layouts then
        return layoutInfo.layouts[customIndex]
    end

    return nil
end

--[[ Module API ]]

function EditMode:Capture()
    local activeLayout = GetActiveLayoutInfo()

    if not activeLayout then
        return nil
    end

    return {
        LayoutString = C_EditMode.ConvertLayoutInfoToString(activeLayout),
        LayoutName = activeLayout.layoutName or "Unknown",
    }
end

function EditMode:Apply(capturedData, sourceMetadata)
    if not capturedData or not capturedData.LayoutString then
        return
    end

    local importedLayout = C_EditMode.ConvertStringToLayoutInfo(capturedData.LayoutString)
    if not importedLayout then
        return
    end

    EnsureEditModeLoaded()

    local customLayouts = C_EditMode.GetLayouts()
    local numPresets = GetPresetCount()

    -- Find existing "WowSync" layout among custom layouts
    local targetIndex = nil
    for i, layout in ipairs(customLayouts.layouts) do
        if layout.layoutName == LAYOUT_NAME then
            targetIndex = i
            break
        end
    end

    -- Configure the imported layout
    importedLayout.layoutName = LAYOUT_NAME
    importedLayout.layoutType = Enum.EditModeLayoutType.Character

    if targetIndex then
        customLayouts.layouts[targetIndex] = importedLayout
    else
        tinsert(customLayouts.layouts, importedLayout)
        targetIndex = #customLayouts.layouts
    end

    -- Overall index = preset count + position in custom array
    local overallIndex = numPresets + targetIndex
    customLayouts.activeLayout = overallIndex

    C_EditMode.SaveLayouts(customLayouts)
    C_EditMode.SetActiveLayout(overallIndex)

    -- Notify the Edit Mode UI if it's loaded
    if EditModeManagerFrame and EditModeManagerFrame.UpdateLayoutInfo then
        EditModeManagerFrame:UpdateLayoutInfo(C_EditMode.GetLayouts())
    end
end

-- The single layout as a keyed list entry, hashed by its export string.
local function LayoutEntries(capturedData)
    if capturedData and capturedData.LayoutString then
        return { { key = "layout", name = capturedData.LayoutName or "Layout", String = capturedData.LayoutString } }
    end
    return {}
end

local function LayoutKey(entry)
    return entry.key
end

local function LayoutLabel(entry)
    return entry.name
end

-- Preview of whether applying this snapshot would change the Edit Mode layout.
function EditMode:Diff(currentData, snapshotData)
    local currentSet = HashSet:From(LayoutEntries(currentData), LayoutKey, LayoutLabel)
    local snapshotSet = HashSet:From(LayoutEntries(snapshotData), LayoutKey, LayoutLabel)

    return {
        added = currentSet:Added(snapshotSet),
        changed = currentSet:Changed(snapshotSet),
        removed = currentSet:Removed(snapshotSet),
    }
end

function EditMode:CanApply(sourceMetadata)
    return true
end

-- Events that mean this module's live state may have changed, so the GameWatcher
-- can re-mirror it into Current (debounced).
function EditMode:GetWatchedEvents()
    return { "EDIT_MODE_LAYOUTS_UPDATED" }
end

--[[ Registration ]]

function EditMode:OnInitialized()
    ModuleRegistry:Register(self)
end
