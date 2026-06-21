local _, addon = ...
local Settings = addon:NewObject("Settings")

local ProfileManager = addon:GetObject("ProfileManager")

--[[
    Comprehensive list of CVars from WoW's Settings UI.
    Organized by settings category for maintainability.
    Source: https://warcraft.wiki.gg/wiki/Console_variables (Patch 12.0.1)

    CVars that don't exist on the current game version are safely skipped
    because Capture() checks for nil from C_CVar.GetCVar().
]]

local TRACKED_CVARS = {
    -- =====================
    -- CONTROLS
    -- =====================
    "autoSelfCast",
    "ActionButtonUseKeyDown",
    "ActionButtonUseKeyHeldSpell",
    "empowerTapControls",
    "interactOnLeftClick",
    "autoInteract",
    "autoDismountFlying",
    "autoDismount",
    "autoClearAFK",
    "stopAutoAttackOnTargetChange",
    "deselectOnClick",
    "mouseInvertPitch",
    "enableMouseSpeed",
    "enableMouseoverCast",
    "enableMovePad",
    "secureAbilityToggle",

    -- =====================
    -- COMBAT
    -- =====================
    "SpellQueueWindow",
    "lossOfControl",
    "enableFloatingCombatText",
    "floatingCombatTextCombatDamage_v2",
    "floatingCombatTextCombatState_v2",
    "floatingCombatTextComboPoints_v2",
    "floatingCombatTextDamageReduction_v2",
    "floatingCombatTextDodgeParryMiss_v2",
    "floatingCombatTextEnergyGains_v2",
    "floatingCombatTextFloatMode_v2",
    "floatingCombatTextFriendlyHealers_v2",
    "floatingCombatTextHonorGains_v2",
    "floatingCombatTextLowManaHealth_v2",
    "floatingCombatTextPeriodicEnergyGains_v2",
    "floatingCombatTextReactives_v2",
    "floatingCombatTextRepChanges_v2",
    "floatingCombatTextAuras_v2",
    "spellActivationOverlayOpacity",
    "displaySpellActivationOverlays",
    "showBuilderFeedback",
    "showSpenderFeedback",

    -- =====================
    -- LOOT
    -- =====================
    "autoLootDefault",
    "lootUnderMouse",

    -- =====================
    -- ACTION BARS
    -- =====================
    "lockActionBars",
    "countdownForCooldowns",
    "AutoPushSpellToActionBar",
    "enableMultiActionBars",

    -- =====================
    -- ENCOUNTER (12.0.0+)
    -- =====================
    "encounterTimelineEnabled",
    "encounterTimelineHideForOtherRoles",
    "encounterTimelineHideLongCountdowns",
    "encounterWarningsEnabled",
    "encounterWarningsHideIfNotTargetingPlayer",
    "encounterWarningsLevel",
    "combatWarningsEnabled",
    "cooldownViewerEnabled",
    "damageMeterEnabled",
    "damageMeterResetOnNewInstance",
    "externalDefensivesEnabled",

    -- =====================
    -- INTERFACE
    -- =====================
    "showTargetOfTarget",
    "showTargetCastbar",
    "showVKeyCastbar",
    "doNotFlashLowHealthWarning",
    "flashErrorMessageRepeats",
    "UberTooltips",
    "alwaysCompareItems",
    "showTimestamps",
    "statusText",
    "statusTextDisplay",
    "breakUpLargeNumbers",
    "screenEdgeFlash",
    "showInGameNavigation",
    "buffDurations",
    "showTempMaxHealthLoss",
    "occludedSilhouettePlayer",
    "collapseExpandBuffs",
    "xpBarText",
    "comboPointLocation",
    "showHonorAsExperience",
    "combinedBags",
    "expandBagBar",

    -- =====================
    -- UNIT FRAMES
    -- =====================
    "showPartyPets",
    "ReplaceMyPlayerPortrait",
    "ReplaceOtherPlayerPortraits",
    "partyBackgroundOpacity",
    "threatShowNumeric",
    "threatWarning",

    -- =====================
    -- NAMEPLATES
    -- =====================
    "nameplateShowAll",
    "nameplateShowSelf",
    "nameplateMotion",
    "nameplateMaxScale",
    "nameplateSelectedScale",
    "nameplateShowCastBars",
    "nameplateShowFriendlyPlayers",
    "nameplateShowFriendlyPlayerPets",
    "nameplateShowFriendlyPlayerGuardians",
    "nameplateShowFriendlyPlayerTotems",
    "nameplateShowFriendlyPlayerMinions",
    "nameplateShowOnlyNameForFriendlyPlayerUnits",
    "nameplateShowOffscreen",
    "nameplateSize",
    "nameplateStyle",
    "nameplateAuraScale",
    "nameplateDebuffPadding",

    -- =====================
    -- RAID FRAMES
    -- =====================
    "raidFramesDisplayClassColor",
    "raidFramesDisplayIncomingHeals",
    "raidFramesDisplayPowerBars",
    "raidFramesDisplayOnlyHealerPowerBars",
    "raidFramesDisplayAggroHighlight",
    "raidFramesDisplayDebuffs",
    "raidFramesDisplayOnlyDispellableDebuffs",
    "raidFramesDisplayLargerRoleSpecificDebuffs",
    "raidFramesCenterBigDefensive",
    "raidFramesDispelIndicatorType",
    "raidFramesDispelIndicatorOverlay",
    "raidOptionIsShown",

    -- =====================
    -- PVP FRAMES
    -- =====================
    "pvpFramesDisplayClassColor",
    "pvpFramesDisplayPowerBars",
    "pvpFramesDisplayOnlyHealerPowerBars",
    "pvpFramesHealthText",
    "pvpOptionDisplayPets",
    "showArenaEnemyCastbar",
    "showArenaEnemyFrames",
    "showArenaEnemyPets",

    -- =====================
    -- BUFFS & DEBUFFS
    -- =====================
    "showCastableBuffs",
    "showDispelDebuffs",
    "noBuffDebuffFilterOnTarget",

    -- =====================
    -- CHAT
    -- =====================
    "chatBubbles",
    "chatBubblesParty",
    "chatBubblesRaid",
    "chatMouseScroll",
    "chatStyle",
    "chatClassColorOverride",
    "profanityFilter",
    "wholeChatWindowClickable",

    -- =====================
    -- SOCIAL
    -- =====================
    "guildMemberNotify",
    "blockTrades",
    "blockChannelInvites",
    "whisperMode",
    "showToastWindow",
    "toastDuration",
    "showTutorials",
    "showNPETutorials",
    "enablePVPNotifyAFK",
    "communitiesShowOffline",
    "excludedCensorSources",
    "restrictCalendarInvites",
    "autoAcceptQuickJoinRequests",

    -- =====================
    -- UNIT NAMES
    -- =====================
    "UnitNameOwn",
    "UnitNameNPC",
    "UnitNamePlayerGuild",
    "UnitNameFriendlyPlayerName",
    "UnitNameFriendlyPetName",
    "UnitNameFriendlyGuardianName",
    "UnitNameFriendlyMinionName",
    "UnitNameFriendlyTotemName",
    "UnitNameFriendlySpecialNPCName",
    "UnitNameHostleNPC",
    "UnitNameInteractiveNPC",
    "UnitNameEnemyPlayerName",
    "UnitNameEnemyPetName",
    "UnitNameEnemyGuardianName",
    "UnitNameEnemyMinionName",
    "UnitNameEnemyTotemName",
    "UnitNameNonCombatCreatureName",
    "UnitNameFocused",

    -- =====================
    -- FIND YOURSELF
    -- =====================
    "findYourselfAnywhere",
    "findYourselfMode",
    "findYourselfModeCircle",
    "findYourselfModeIcon",
    "findYourselfModeOutline",

    -- =====================
    -- CAMERA
    -- =====================
    "CameraKeepCharacterCentered",
    "CameraReduceUnexpectedMovement",
    "cameraSmoothTrackingStyle",
    "cameraPitchMoveSpeed",
    "cameraPitchSmoothSpeed",
    "cameraYawSmoothSpeed",

    -- =====================
    -- SOFT TARGETING
    -- =====================
    "SoftTargetInteract",
    "SoftTargetIconInteract",
    "SoftTargetTooltipEnemy",
    "SoftTargetTooltipInteract",
    "SoftTargetLowPriorityIcons",
    "SoftTargetNameplateSize",
    "softTargettingInteractKeySound",

    -- =====================
    -- MAP & QUESTS
    -- =====================
    "questPOI",
    "questPOILocalStory",
    "questPOIWQ",
    "showQuestObjectivesInLog",
    "miniWorldMap",
    "rotateMinimap",
    "scrollToLogQuest",
    "questLogOpen",
    "questTextContrast",
    "primaryProfessionsFilter",
    "secondaryProfessionsFilter",
    "showTamers",
    "showTamersWQ",
    "showDungeonEntrancesOnMap",
    "showDelveEntrancesOnMap",
    "ShowQuestUnitCircles",
    "contentTrackingFilter",

    -- =====================
    -- PVP
    -- =====================
    "spellDiminishPVPEnemiesEnabled",
    "spellDiminishPVPOnlyTriggerableByMe",
    "showBattlefieldMinimap",

    -- =====================
    -- SPELLBOOK
    -- =====================
    "spellBookHidePassives",
    "spellBookMinimize",

    -- =====================
    -- ACCESSIBILITY
    -- =====================
    "colorblindMode",
    "colorblindSimulator",
    "colorblindWeaknessFactor",
    "arachnophobiaMode",
    "motionSicknessFocalCircle",
    "motionSicknessLandscapeDarkening",
    "DisableAdvancedFlyingFullScreenEffects",
    "DisableAdvancedFlyingVelocityVFX",
    "ShakeStrengthCamera",
    "ShakeStrengthUI",
    "movieSubtitleBackgroundAlpha",
    "showPhotosensitivityWarning",

    -- =====================
    -- TEXT-TO-SPEECH
    -- =====================
    "textToSpeech",
    "speechToText",
    "remoteTextToSpeech",
    "remoteTextToSpeechVoice",
    "TTSUseCharacterSettings",

    -- =====================
    -- SOUND
    -- =====================
    "Sound_MasterVolume",
    "Sound_SFXVolume",
    "Sound_MusicVolume",
    "Sound_AmbienceVolume",
    "Sound_DialogVolume",
    "Sound_EnableAllSound",
    "Sound_EnableSFX",
    "Sound_EnableMusic",
    "Sound_EnableAmbience",
    "Sound_EnableDialog",
    "Sound_EnableSoundWhenGameIsInBG",
    "Sound_EnableErrorSpeech",
    "Sound_EnableEmoteSounds",
    "Sound_EnablePetSounds",
    "Sound_EnablePetBattleMusic",
    "Sound_EnableReverb",
    "Sound_EnablePositionalLowPassFilter",
    "Sound_ListenerAtCharacter",
    "Sound_ZoneMusicNoDelay",
    "Sound_EnablePingSounds",
    "Sound_PingVolume",
    "Sound_EnableGameplaySFX",
    "Sound_GameplaySFX",
    "Sound_EnableEncounterWarningsSounds",
    "Sound_EncounterWarningsVolume",
    "Sound_NumChannels",

    -- =====================
    -- VOICE CHAT
    -- =====================
    "VoiceInputVolume",
    "VoiceOutputVolume",
    "VoicePushToTalkKeybind",
    "VoiceChatMasterVolumeScale",

    -- =====================
    -- GRAPHICS
    -- =====================
    "graphicsQuality",
    "graphicsViewDistance",
    "graphicsTextureResolution",
    "graphicsShadowQuality",
    "graphicsSSAO",
    "graphicsProjectedTextures",
    "graphicsSpellDensity",
    "graphicsComputeEffects",
    "Brightness",
    "Contrast",
    "Gamma",
    "ffxAntiAliasingMode",
    "MSAAQuality",
    "MSAAAlphaTest",
    "ResampleQuality",
    "ResampleSharpness",
    "LowLatencyMode",
    "farclip",
    "particleDensity",
    "cameraFov",
    "vsync",
    "maxFPS",
    "maxFPSBk",
    "useMaxFPS",
    "shadowRt",
    "physicsLevel",
    "SSAO",
    "projectedTextures",
    "cursorSizePreferred",
    "NotchedDisplayMode",
    "ClipCursor",
    "uiScale",

    -- =====================
    -- MISC
    -- =====================
    "advancedCombatLogging",
    "scriptErrors",
    "enablePings",
}

--[[ Helpers ]]

local function SetTrackedCVar(cvar, value)
    -- GetCVarInfo returns: value, defaultValue, isStoredServerAccount,
    --   isStoredServerCharacter, isLockedFromUser, isSecure, isReadOnly
    local _, _, _, _, isLockedFromUser, isSecure, isReadOnly = C_CVar.GetCVarInfo(cvar)
    if isLockedFromUser or isSecure or isReadOnly then
        return
    end

    -- Isolate each SetCVar: a protected or erroring CVar must not abort the
    -- rest of the batch (the whole module Apply runs under a single pcall).
    pcall(C_CVar.SetCVar, cvar, value)
end

--[[ Module API ]]

function Settings:Capture()
    local account, character = {}, {}

    for _, cvar in ipairs(TRACKED_CVARS) do
        local value = C_CVar.GetCVar(cvar)
        if value then
            -- GetCVarInfo returns: value, defaultValue, isStoredServerAccount,
            --   isStoredServerCharacter, isLockedFromUser, isSecure, isReadOnly
            local _, _, _, isStoredServerCharacter = C_CVar.GetCVarInfo(cvar)

            if isStoredServerCharacter then
                character[cvar] = value
            else
                account[cvar] = value
            end
        end
    end

    return {
        Account = account,
        Character = character,
    }
end

function Settings:Apply(data, meta)
    if data.Account then
        for cvar, value in pairs(data.Account) do
            SetTrackedCVar(cvar, value)
        end
    end

    if data.Character then
        for cvar, value in pairs(data.Character) do
            SetTrackedCVar(cvar, value)
        end
    end
end

function Settings:CanApply(meta)
    return true
end

--[[ Registration ]]

function Settings:OnInitialized()
    ProfileManager:RegisterModule(self)
end
