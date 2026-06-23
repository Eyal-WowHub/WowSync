local _, addon = ...
local Chat = addon:NewObject("Chat")

local ProfileManager = addon:GetObject("ProfileManager")
local HashSet = addon.HashSet
local SnapshotApplyMode = addon.SnapshotApplyMode
local L = addon.L

Chat.Config = {
    SnapshotApplyMode = SnapshotApplyMode.All,
}

local NUM_CHAT_WINDOWS = NUM_CHAT_WINDOWS or 10

--[[ Helpers ]]

local CHAT_COLOR_TYPES = {
    "SAY", "YELL", "WHISPER", "PARTY", "PARTY_LEADER",
    "RAID", "RAID_LEADER", "RAID_WARNING",
    "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER",
    "GUILD", "OFFICER",
    "EMOTE", "CHANNEL", "SYSTEM",
    "LOOT", "MONEY", "SKILL", "EXPERIENCE",
    "BN_WHISPER",
}

local MESSAGE_GROUP_TYPES = {
    "SAY", "YELL", "WHISPER", "WHISPER_INFORM",
    "PARTY", "PARTY_LEADER",
    "RAID", "RAID_LEADER", "RAID_WARNING",
    "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER",
    "GUILD", "OFFICER",
    "EMOTE", "TEXT_EMOTE",
    "SYSTEM", "LOOT", "MONEY", "SKILL", "EXPERIENCE",
    "CHANNEL", "BN_WHISPER", "BN_WHISPER_INFORM",
    "MONSTER_SAY", "MONSTER_YELL", "MONSTER_EMOTE", "MONSTER_WHISPER",
    "MONSTER_PARTY",
}

local function CaptureChatColors()
    local colors = {}
    for _, chatType in ipairs(CHAT_COLOR_TYPES) do
        local r, g, b = GetMessageTypeColor(chatType)
        if r then
            colors[chatType] = { r = r, g = g, b = b }
        end
    end
    return colors
end

local function CaptureChannels(chatFrame)
    local channels = {}
    -- GetChatWindowChannels returns: name1, channelId1, name2, channelId2, ...
    local channelList = { GetChatWindowChannels(chatFrame:GetID()) }
    for i = 1, #channelList, 2 do
        local name = channelList[i]
        if name then
            tinsert(channels, name)
        end
    end
    return channels
end

local function CaptureMessageGroups(chatFrame)
    local groups = {}
    for _, msgType in ipairs(MESSAGE_GROUP_TYPES) do
        if chatFrame:IsEventRegistered("CHAT_MSG_" .. msgType) then
            tinsert(groups, msgType)
        end
    end
    return groups
end

local function ConfigureTab(chatFrame, tab, frameIndex)
    FCF_SetWindowName(chatFrame, tab.Name)

    if tab.FontSize then
        FCF_SetChatWindowFontSize(nil, chatFrame, tab.FontSize)
    end

    if tab.Locked ~= nil then
        FCF_SetLocked(chatFrame, tab.Locked)
    end

    if tab.BackgroundColor then
        FCF_SetWindowColor(chatFrame, tab.BackgroundColor.r, tab.BackgroundColor.g, tab.BackgroundColor.b)
    end

    if tab.BackgroundAlpha then
        FCF_SetWindowAlpha(chatFrame, tab.BackgroundAlpha)
    end

    -- Fading
    if tab.Fading ~= nil then
        chatFrame:SetFading(tab.Fading)
    end
    if tab.FadeTime then
        chatFrame:SetTimeVisible(tab.FadeTime)
    end

    -- Position and dimensions
    if tab.Position then
        SetChatWindowSavedPosition(frameIndex, tab.Position.Point, tab.Position.XOffset, tab.Position.YOffset)
    end
    if tab.Width and tab.Height then
        SetChatWindowSavedDimensions(frameIndex, tab.Width, tab.Height)
    end

    ChatFrame_RemoveAllMessageGroups(chatFrame)
    if tab.MessageGroups then
        for _, msgType in ipairs(tab.MessageGroups) do
            ChatFrame_AddMessageGroup(chatFrame, msgType)
        end
    end

    ChatFrame_RemoveAllChannels(chatFrame)
    if tab.Channels then
        for _, channelName in ipairs(tab.Channels) do
            ChatFrame_AddChannel(chatFrame, channelName)
        end
    end
end

--[[ Module API ]]

function Chat:Capture()
    local tabs = {}

    for i = 1, NUM_CHAT_WINDOWS do
        local chatFrame = _G["ChatFrame" .. i]
        if chatFrame then
            -- docked is the dock order index (1, 2, ...) or nil if floating
            local name, fontSize, r, g, b, alpha, shown, locked, docked = GetChatWindowInfo(i)
            if name and name ~= "" and (shown or docked) then
                -- Frame position and dimensions
                local point, xOffset, yOffset = GetChatWindowSavedPosition(i)
                local width, height = GetChatWindowSavedDimensions(i)

                tinsert(tabs, {
                    Name = name,
                    FontSize = fontSize,
                    BackgroundColor = { r = r, g = g, b = b },
                    BackgroundAlpha = alpha,
                    Shown = shown,
                    Locked = locked,
                    Docked = docked ~= nil,
                    DockOrder = docked,
                    Position = point and { Point = point, XOffset = xOffset, YOffset = yOffset } or nil,
                    Width = width,
                    Height = height,
                    Fading = chatFrame.GetFading and chatFrame:GetFading() or nil,
                    FadeTime = chatFrame.GetTimeVisible and chatFrame:GetTimeVisible() or nil,
                    Channels = CaptureChannels(chatFrame),
                    MessageGroups = CaptureMessageGroups(chatFrame),
                })
            end
        end
    end

    return {
        Tabs = tabs,
        Colors = CaptureChatColors(),
    }
end

local function TabKey(tab)
    return tab.Name
end

function Chat:Apply(data, meta, opts)
    local exact = opts and opts.mode == "exact"

    if data.Tabs then
        -- Index the existing custom tabs (3+) by name so we can reconfigure a
        -- tab in place instead of opening a duplicate window.
        local existing = {}
        for i = 3, NUM_CHAT_WINDOWS do
            local chatFrame = _G["ChatFrame" .. i]
            if chatFrame then
                local name = GetChatWindowInfo(i)
                if name and name ~= "" then
                    existing[name] = chatFrame
                end
            end
        end

        -- Exact mode: close custom tabs that the snapshot does not contain.
        -- Iterate in reverse to avoid issues with dock reordering during close.
        if exact then
            local wanted = {}
            for _, tab in ipairs(data.Tabs) do
                wanted[tab.Name] = true
            end

            for i = NUM_CHAT_WINDOWS, 3, -1 do
                local chatFrame = _G["ChatFrame" .. i]
                if chatFrame then
                    local name = GetChatWindowInfo(i)
                    if name and name ~= "" and not wanted[name] then
                        FCF_Close(chatFrame, ChatFrame1)
                        existing[name] = nil
                    end
                end
            end
        end

        -- Create or reconfigure each saved tab.
        for tabIndex, tab in ipairs(data.Tabs) do
            local chatFrame
            local frameIndex

            if tabIndex <= 2 then
                -- General (1) and Combat Log (2) always exist
                chatFrame = _G["ChatFrame" .. tabIndex]
                frameIndex = tabIndex
            else
                -- Reuse an existing tab with the same name, else open a new one.
                chatFrame = existing[tab.Name] or FCF_OpenNewWindow(tab.Name)
                if not chatFrame then
                    addon:Print(L["Could not create chat tab 'X' — maximum tabs reached."]:format(tab.Name))
                    break
                end
                frameIndex = chatFrame:GetID()
            end

            ConfigureTab(chatFrame, tab, frameIndex)

            -- Handle docking (cannot undock the primary General tab)
            if tabIndex > 1 then
                if tab.Docked then
                    FCF_DockFrame(chatFrame, 0, true)
                else
                    FCF_UnDockFrame(chatFrame)
                end
            end

            -- Refresh the frame to apply position/dimension changes
            FloatingChatFrame_Update(frameIndex)
        end

        -- Re-select the primary chat frame
        FCF_SelectDockFrame(ChatFrame1)
    end

    -- Apply chat colors
    if data.Colors then
        for chatType, color in pairs(data.Colors) do
            ChangeChatColor(chatType, color.r, color.g, color.b)
        end
    end
end

-- Preview of what applying these chat tabs would change.
function Chat:Diff(current, snapshot)
    local currentSet = HashSet:From(current and current.Tabs, TabKey, TabKey)
    local snapshotSet = HashSet:From(snapshot and snapshot.Tabs, TabKey, TabKey)

    return {
        added = currentSet:Added(snapshotSet),
        changed = currentSet:Changed(snapshotSet),
        removed = currentSet:Removed(snapshotSet),
    }
end

function Chat:CanApply(meta)
    return true
end

-- Events that mean this module's live state may have changed, so the GameWatcher
-- can re-mirror it into Current (debounced).
function Chat:GetWatchedEvents()
    return { "UPDATE_CHAT_WINDOWS", "UPDATE_FLOATING_CHAT_WINDOWS", "UPDATE_CHAT_COLOR" }
end

--[[ Registration ]]

function Chat:OnInitialized()
    ProfileManager:RegisterModule(self)
end
