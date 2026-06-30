local _, addon = ...

--[[
    Comprehensive list of CVars from WoW's Settings UI, each with an optional
    human description shown beneath it in the diff preview.
    Organized by settings category for maintainability.
    Source: https://warcraft.wiki.gg/wiki/Console_variables (Patch 12.0.1)

    Each entry is { cvar = <name>, desc = <text> }; desc is optional, so a CVar
    with no curated description simply shows its raw name. CVars that don't
    exist on the current game version are safely skipped because Capture()
    checks for nil from C_CVar.GetCVar().
]]

addon.SETTINGS_CVARS = {
    -- =====================
    -- CONTROLS
    -- =====================
    { cvar = "autoSelfCast", desc = "Cast self-targeted spells on yourself when no friendly target is selected" },
    { cvar = "ActionButtonUseKeyDown", desc = "Trigger action buttons on key press instead of release" },
    { cvar = "ActionButtonUseKeyHeldSpell", desc = "Keep casting while an action key is held down" },
    { cvar = "empowerTapControls", desc = "Use tap controls for empowered, charge-up spells" },
    { cvar = "interactOnLeftClick", desc = "Interact with NPCs and objects using left-click" },
    { cvar = "autoInteract", desc = "Move into a target to interact with it automatically" },
    { cvar = "autoDismountFlying", desc = "Allow abilities to dismount you while flying" },
    { cvar = "autoDismount", desc = "Automatically dismount when using abilities that require it" },
    { cvar = "autoClearAFK", desc = "Clear your Away status automatically when you take an action" },
    { cvar = "stopAutoAttackOnTargetChange", desc = "Stop auto-attacking when you change targets" },
    { cvar = "deselectOnClick", desc = "Clear your target when you click empty terrain" },
    { cvar = "mouseInvertPitch", desc = "Invert vertical mouse movement when turning the camera" },
    { cvar = "enableMouseSpeed", desc = "Enable an adjustable mouse look speed" },
    { cvar = "enableMouseoverCast", desc = "Cast spells on the unit under your cursor" },
    { cvar = "enableMovePad", desc = "Show the on-screen movement pad" },
    { cvar = "secureAbilityToggle", desc = "Protect against accidentally double-clicking an aura" },

    -- =====================
    -- COMBAT
    -- =====================
    { cvar = "SpellQueueWindow", desc = "Time window for queuing your next spell before the current one ends" },
    { cvar = "lossOfControl", desc = "Show the Loss of Control alert when stunned, feared, or silenced" },
    { cvar = "enableFloatingCombatText", desc = "Show floating combat text" },
    { cvar = "floatingCombatTextCombatDamage_v2", desc = "Show damage you deal as floating combat text" },
    { cvar = "floatingCombatTextCombatState_v2", desc = "Show entering and leaving combat as floating text" },
    { cvar = "floatingCombatTextComboPoints_v2", desc = "Show combo point gains as floating combat text" },
    { cvar = "floatingCombatTextDamageReduction_v2", desc = "Show damage you absorb or block as floating text" },
    { cvar = "floatingCombatTextDodgeParryMiss_v2", desc = "Show dodges, parries, and misses as floating text" },
    { cvar = "floatingCombatTextEnergyGains_v2", desc = "Show resource gains as floating combat text" },
    { cvar = "floatingCombatTextFloatMode_v2", desc = "Direction floating combat text moves as it appears" },
    { cvar = "floatingCombatTextFriendlyHealers_v2", desc = "Show healing from friendly healers as floating text" },
    { cvar = "floatingCombatTextHonorGains_v2", desc = "Show honor gains as floating combat text" },
    { cvar = "floatingCombatTextLowManaHealth_v2", desc = "Warn with floating text when health or mana is low" },
    { cvar = "floatingCombatTextPeriodicEnergyGains_v2", desc = "Show periodic resource gains as floating text" },
    { cvar = "floatingCombatTextReactives_v2", desc = "Show reactive ability triggers as floating combat text" },
    { cvar = "floatingCombatTextRepChanges_v2", desc = "Show reputation changes as floating combat text" },
    { cvar = "floatingCombatTextAuras_v2", desc = "Show buff and debuff changes as floating combat text" },
    { cvar = "spellActivationOverlayOpacity", desc = "Opacity of spell activation (proc) glow effects" },
    { cvar = "displaySpellActivationOverlays", desc = "Show spell activation (proc) glows on action buttons" },
    { cvar = "showBuilderFeedback", desc = "Show feedback for resource-building abilities" },
    { cvar = "showSpenderFeedback", desc = "Show feedback for resource-spending abilities" },

    -- =====================
    -- LOOT
    -- =====================
    { cvar = "autoLootDefault", desc = "Automatically loot corpses without holding a modifier key" },
    { cvar = "lootUnderMouse", desc = "Open the loot window at your cursor instead of a fixed position" },

    -- =====================
    -- ACTION BARS
    -- =====================
    { cvar = "lockActionBars", desc = "Lock action bar buttons so abilities can't be dragged off" },
    { cvar = "countdownForCooldowns", desc = "Show a numeric countdown on ability cooldowns" },
    { cvar = "AutoPushSpellToActionBar", desc = "Automatically place newly learned spells on your action bars" },
    { cvar = "enableMultiActionBars", desc = "Enable the additional action bars" },

    -- =====================
    -- ENCOUNTER (12.0.0+)
    -- =====================
    { cvar = "encounterTimelineEnabled", desc = "Show the encounter timeline of upcoming boss events" },
    { cvar = "encounterTimelineHideForOtherRoles", desc = "Hide encounter timeline events meant for other roles" },
    { cvar = "encounterTimelineHideLongCountdowns", desc = "Hide encounter timeline events with long countdowns" },
    { cvar = "encounterWarningsEnabled", desc = "Show on-screen warnings during boss encounters" },
    { cvar = "encounterWarningsHideIfNotTargetingPlayer", desc = "Only show encounter warnings that target you" },
    { cvar = "encounterWarningsLevel", desc = "How many encounter warnings to display" },
    { cvar = "combatWarningsEnabled", desc = "Show combat warning alerts" },
    { cvar = "cooldownViewerEnabled", desc = "Show the cooldown viewer" },
    { cvar = "damageMeterEnabled", desc = "Show the built-in damage meter" },
    { cvar = "damageMeterResetOnNewInstance", desc = "Reset the damage meter when entering a new instance" },
    { cvar = "externalDefensivesEnabled", desc = "Track external defensive cooldowns cast on you" },

    -- =====================
    -- INTERFACE
    -- =====================
    { cvar = "showTargetOfTarget", desc = "Show your target's target" },
    { cvar = "showTargetCastbar", desc = "Show your target's cast bar" },
    { cvar = "showVKeyCastbar", desc = "Show the enemy cast bar with the target's health bar when the V key display is active" },
    { cvar = "doNotFlashLowHealthWarning", desc = "Disable the screen flash when your health is low" },
    { cvar = "flashErrorMessageRepeats", desc = "Flash the center-screen red error text when the same message repeats" },
    { cvar = "UberTooltips", desc = "Show detailed, enhanced tooltips" },
    { cvar = "alwaysCompareItems", desc = "Always show item comparison tooltips" },
    { cvar = "showTimestamps", desc = "Timestamp format for chat messages" },
    { cvar = "statusText", desc = "Show status text on health and resource bars" },
    { cvar = "statusTextDisplay", desc = "How status text is shown on bars" },
    { cvar = "breakUpLargeNumbers", desc = "Insert separators into large numbers" },
    { cvar = "screenEdgeFlash", desc = "Flash the screen red while in combat with the world map open" },
    { cvar = "showInGameNavigation", desc = "Show on-screen navigation to tracked objectives" },
    { cvar = "buffDurations", desc = "Show remaining duration on buffs and debuffs" },
    { cvar = "showTempMaxHealthLoss", desc = "Show temporary maximum health loss on your health bar" },
    { cvar = "occludedSilhouettePlayer", desc = "Show your silhouette when hidden behind objects" },
    { cvar = "collapseExpandBuffs", desc = "Show a button to collapse and hide long-duration buffs" },
    { cvar = "xpBarText", desc = "Show text on the experience bar" },
    { cvar = "comboPointLocation", desc = "Where your combo points are displayed" },
    { cvar = "showHonorAsExperience", desc = "Show the honor bar in place of the experience bar" },
    { cvar = "combinedBags", desc = "Combine all bags into a single window" },
    { cvar = "expandBagBar", desc = "Show all equipped bags on the bag bar, not just the backpack and reagent bag" },

    -- =====================
    -- UNIT FRAMES
    -- =====================
    { cvar = "showPartyPets", desc = "Show party members' pets" },
    { cvar = "ReplaceMyPlayerPortrait", desc = "Show your portrait as a 3D model" },
    { cvar = "ReplaceOtherPlayerPortraits", desc = "Show other players' portraits as 3D models" },
    { cvar = "partyBackgroundOpacity", desc = "Opacity of party frame backgrounds" },
    { cvar = "threatShowNumeric", desc = "Show numeric threat on the target and focus frames" },
    { cvar = "threatWarning", desc = "When to show threat warnings" },

    -- =====================
    -- NAMEPLATES
    -- =====================
    { cvar = "nameplateShowAll", desc = "Always show nameplates" },
    { cvar = "nameplateShowSelf", desc = "Show your personal resource nameplate" },
    { cvar = "nameplateMotion", desc = "How nameplates spread apart to avoid overlap" },
    { cvar = "nameplateMaxScale", desc = "Maximum nameplate scale" },
    { cvar = "nameplateSelectedScale", desc = "Scale of the selected target's nameplate" },
    { cvar = "nameplateShowCastBars", desc = "Show cast bars on nameplates" },
    { cvar = "nameplateShowFriendlyPlayers", desc = "Show nameplates on friendly players" },
    { cvar = "nameplateShowFriendlyPlayerPets", desc = "Show nameplates on friendly players' pets" },
    { cvar = "nameplateShowFriendlyPlayerGuardians", desc = "Show nameplates on friendly players' guardians" },
    { cvar = "nameplateShowFriendlyPlayerTotems", desc = "Show nameplates on friendly players' totems" },
    { cvar = "nameplateShowFriendlyPlayerMinions", desc = "Show nameplates on friendly players' minions" },
    { cvar = "nameplateShowOnlyNameForFriendlyPlayerUnits", desc = "Show only names for friendly players" },
    { cvar = "nameplateShowOffscreen", desc = "Always show a nameplate when its owner is in combat with you or your group" },
    { cvar = "nameplateSize", desc = "Overall nameplate size" },
    { cvar = "nameplateStyle", desc = "Nameplate display style" },
    { cvar = "nameplateAuraScale", desc = "Scale of auras shown on nameplates" },
    { cvar = "nameplateDebuffPadding", desc = "Padding between the debuff list and the health bar on nameplates" },

    -- =====================
    -- RAID FRAMES
    -- =====================
    { cvar = "raidFramesDisplayClassColor", desc = "Color raid frames by class" },
    { cvar = "raidFramesDisplayIncomingHeals", desc = "Show incoming heals on raid frames" },
    { cvar = "raidFramesDisplayPowerBars", desc = "Show power bars on raid frames" },
    { cvar = "raidFramesDisplayOnlyHealerPowerBars", desc = "Show power bars only for healers on raid frames" },
    { cvar = "raidFramesDisplayAggroHighlight", desc = "Highlight raid members who have aggro" },
    { cvar = "raidFramesDisplayDebuffs", desc = "Show debuffs on raid frames" },
    { cvar = "raidFramesDisplayOnlyDispellableDebuffs", desc = "Show only debuffs you can dispel on raid frames" },
    { cvar = "raidFramesDisplayLargerRoleSpecificDebuffs", desc = "Enlarge debuffs relevant to your role" },
    { cvar = "raidFramesCenterBigDefensive", desc = "Show large defensive cooldowns centered on raid frames" },
    { cvar = "raidFramesDispelIndicatorType", desc = "Style of the dispel indicator on raid frames" },
    { cvar = "raidFramesDispelIndicatorOverlay", desc = "Also show a color gradient overlay with dispel indicators" },
    { cvar = "raidOptionIsShown", desc = "Show the raid frames" },

    -- =====================
    -- PVP FRAMES
    -- =====================
    { cvar = "pvpFramesDisplayClassColor", desc = "Color PvP frames by class" },
    { cvar = "pvpFramesDisplayPowerBars", desc = "Show power bars on PvP frames" },
    { cvar = "pvpFramesDisplayOnlyHealerPowerBars", desc = "Show power bars only for healers on PvP frames" },
    { cvar = "pvpFramesHealthText", desc = "Show health text on PvP frames" },
    { cvar = "pvpOptionDisplayPets", desc = "Show pets on PvP frames" },
    { cvar = "showArenaEnemyCastbar", desc = "Show enemy cast bars in arenas" },
    { cvar = "showArenaEnemyFrames", desc = "Show enemy frames in arenas" },
    { cvar = "showArenaEnemyPets", desc = "Show enemy pets in arenas" },

    -- =====================
    -- BUFFS & DEBUFFS
    -- =====================
    { cvar = "showCastableBuffs", desc = "Show only buffs you can apply on your target frame" },
    { cvar = "showDispelDebuffs", desc = "Show only debuffs you can dispel on your target frame" },
    { cvar = "noBuffDebuffFilterOnTarget", desc = "Show all buffs and debuffs on your target without filtering" },

    -- =====================
    -- CHAT
    -- =====================
    { cvar = "chatBubbles", desc = "Show chat bubbles above characters" },
    { cvar = "chatBubblesParty", desc = "Show chat bubbles for party chat" },
    { cvar = "chatBubblesRaid", desc = "Show chat bubbles for raid chat" },
    { cvar = "chatMouseScroll", desc = "Scroll chat with the mouse wheel" },
    { cvar = "chatStyle", desc = "Chat window editing style" },
    { cvar = "chatClassColorOverride", desc = "Allow class coloring of player names in chat" },
    { cvar = "profanityFilter", desc = "Filter profanity in chat" },
    { cvar = "wholeChatWindowClickable", desc = "Make the whole chat window clickable" },

    -- =====================
    -- SOCIAL
    -- =====================
    { cvar = "guildMemberNotify", desc = "Announce when guild members log in or out" },
    { cvar = "blockTrades", desc = "Block incoming trade requests" },
    { cvar = "blockChannelInvites", desc = "Block invitations to chat channels" },
    { cvar = "whisperMode", desc = "How new whispers are displayed (popout or inline)" },
    { cvar = "showToastWindow", desc = "Show Battle.net system messages in a toast window" },
    { cvar = "toastDuration", desc = "How long toast notifications stay on screen" },
    { cvar = "showTutorials", desc = "Show tutorial tips" },
    { cvar = "showNPETutorials", desc = "Show new player experience tutorials" },
    { cvar = "enablePVPNotifyAFK", desc = "Allow reporting AFK players in battlegrounds" },
    { cvar = "communitiesShowOffline", desc = "Show offline members in communities and guild lists" },
    { cvar = "excludedCensorSources", desc = "Who is exempt from inappropriate-message filtering" },
    { cvar = "restrictCalendarInvites", desc = "Only accept calendar invites from friends and guild" },
    { cvar = "autoAcceptQuickJoinRequests", desc = "Automatically accept players joining your party through Quick Join" },

    -- =====================
    -- UNIT NAMES
    -- =====================
    { cvar = "UnitNameOwn", desc = "Show your own name" },
    { cvar = "UnitNameNPC", desc = "Show NPC names" },
    { cvar = "UnitNamePlayerGuild", desc = "Show players' guild names" },
    { cvar = "UnitNameFriendlyPlayerName", desc = "Show friendly players' names" },
    { cvar = "UnitNameFriendlyPetName", desc = "Show friendly pets' names" },
    { cvar = "UnitNameFriendlyGuardianName", desc = "Show friendly guardians' names" },
    { cvar = "UnitNameFriendlyMinionName", desc = "Show friendly minions' names" },
    { cvar = "UnitNameFriendlyTotemName", desc = "Show friendly totems' names" },
    { cvar = "UnitNameFriendlySpecialNPCName", desc = "Show special friendly NPC names" },
    { cvar = "UnitNameHostleNPC", desc = "Show hostile NPC names" },
    { cvar = "UnitNameInteractiveNPC", desc = "Show interactive NPC names" },
    { cvar = "UnitNameEnemyPlayerName", desc = "Show enemy players' names" },
    { cvar = "UnitNameEnemyPetName", desc = "Show enemy pets' names" },
    { cvar = "UnitNameEnemyGuardianName", desc = "Show enemy guardians' names" },
    { cvar = "UnitNameEnemyMinionName", desc = "Show enemy minions' names" },
    { cvar = "UnitNameEnemyTotemName", desc = "Show enemy totems' names" },
    { cvar = "UnitNameNonCombatCreatureName", desc = "Show non-combat creature names" },
    { cvar = "UnitNameFocused", desc = "Show the focused unit's name" },

    -- =====================
    -- FIND YOURSELF
    -- =====================
    { cvar = "findYourselfAnywhere", desc = "Highlight your character to find yourself in crowds" },
    { cvar = "findYourselfMode", desc = "How your character is highlighted when hard to see" },
    { cvar = "findYourselfModeCircle", desc = "Show a circle beneath your character to find yourself" },
    { cvar = "findYourselfModeIcon", desc = "Show an overhead icon to find yourself" },
    { cvar = "findYourselfModeOutline", desc = "Outline your character to find yourself" },

    -- =====================
    -- CAMERA
    -- =====================
    { cvar = "CameraKeepCharacterCentered", desc = "Keep your character centered in the camera view" },
    { cvar = "CameraReduceUnexpectedMovement", desc = "Reduce unexpected camera movement" },
    { cvar = "cameraSmoothTrackingStyle", desc = "Camera smoothing style" },
    { cvar = "cameraPitchMoveSpeed", desc = "Vertical camera movement speed" },
    { cvar = "cameraPitchSmoothSpeed", desc = "Vertical camera smoothing speed" },
    { cvar = "cameraYawSmoothSpeed", desc = "Horizontal camera smoothing speed" },

    -- =====================
    -- SOFT TARGETING
    -- =====================
    { cvar = "SoftTargetInteract", desc = "Enable soft targeting for interaction" },
    { cvar = "SoftTargetIconInteract", desc = "Show an icon over the soft interaction target" },
    { cvar = "SoftTargetTooltipEnemy", desc = "Show tooltips for soft enemy targets" },
    { cvar = "SoftTargetTooltipInteract", desc = "Show tooltips for soft interaction targets" },
    { cvar = "SoftTargetLowPriorityIcons", desc = "Show interact icons even when other visual indicators are present" },
    { cvar = "SoftTargetNameplateSize", desc = "Size of the soft-target icon on nameplates" },
    { cvar = "softTargettingInteractKeySound", desc = "Play sound cues for soft-target interaction" },

    -- =====================
    -- MAP & QUESTS
    -- =====================
    { cvar = "questPOI", desc = "Show quest objectives on the map and minimap" },
    { cvar = "questPOILocalStory", desc = "Show local story quest offers on the world map" },
    { cvar = "questPOIWQ", desc = "Show world quests on the map" },
    { cvar = "showQuestObjectivesInLog", desc = "Show objectives in the quest log" },
    { cvar = "miniWorldMap", desc = "Use the smaller world map" },
    { cvar = "rotateMinimap", desc = "Rotate the minimap with your character's facing" },
    { cvar = "scrollToLogQuest", desc = "Scroll to a quest in the log when hovering its map pin" },
    { cvar = "questLogOpen", desc = "Show the quest log beside the windowed map" },
    { cvar = "questTextContrast", desc = "Increase contrast of quest text" },
    { cvar = "primaryProfessionsFilter", desc = "Show primary profession locations on the map" },
    { cvar = "secondaryProfessionsFilter", desc = "Show secondary profession locations on the map" },
    { cvar = "showTamers", desc = "Show pet battle tamers on the map" },
    { cvar = "showTamersWQ", desc = "Show pet battle world quests on the map" },
    { cvar = "showDungeonEntrancesOnMap", desc = "Show dungeon entrances on the map" },
    { cvar = "showDelveEntrancesOnMap", desc = "Show delve entrances on the map" },
    { cvar = "ShowQuestUnitCircles", desc = "Show ground indicators beneath units related to a quest" },
    { cvar = "contentTrackingFilter", desc = "Show tracked content on the world map" },

    -- =====================
    -- PVP
    -- =====================
    { cvar = "spellDiminishPVPEnemiesEnabled", desc = "Show diminishing returns on enemy crowd control" },
    { cvar = "spellDiminishPVPOnlyTriggerableByMe", desc = "Only show diminishing returns you can trigger" },
    { cvar = "showBattlefieldMinimap", desc = "Show the battlefield minimap in battlegrounds" },

    -- =====================
    -- SPELLBOOK
    -- =====================
    { cvar = "spellBookHidePassives", desc = "Hide passive spells in the spellbook" },
    { cvar = "spellBookMinimize", desc = "Always show the spellbook in half-screen minimized mode" },

    -- =====================
    -- ACCESSIBILITY
    -- =====================
    { cvar = "colorblindMode", desc = "Enable colorblind accessibility mode" },
    { cvar = "colorblindSimulator", desc = "Simulate a type of colorblindness" },
    { cvar = "colorblindWeaknessFactor", desc = "Strength of the colorblind adjustment" },
    { cvar = "arachnophobiaMode", desc = "Swap spider creatures for other variants" },
    { cvar = "motionSicknessFocalCircle", desc = "Show a focal circle while mounted to reduce motion sickness" },
    { cvar = "motionSicknessLandscapeDarkening", desc = "Darken the landscape at higher speeds to reduce motion sickness" },
    { cvar = "DisableAdvancedFlyingFullScreenEffects", desc = "Disable full-screen effects during skyriding" },
    { cvar = "DisableAdvancedFlyingVelocityVFX", desc = "Disable speed effects during skyriding" },
    { cvar = "ShakeStrengthCamera", desc = "Strength of camera shake effects" },
    { cvar = "ShakeStrengthUI", desc = "Strength of UI shake effects" },
    { cvar = "movieSubtitleBackgroundAlpha", desc = "Opacity of the subtitle background" },
    { cvar = "showPhotosensitivityWarning", desc = "Show the photosensitivity warning at login" },

    -- =====================
    -- TEXT-TO-SPEECH
    -- =====================
    { cvar = "textToSpeech", desc = "Enable text-to-speech" },
    { cvar = "speechToText", desc = "Enable speech-to-text transcription" },
    { cvar = "remoteTextToSpeech", desc = "Read incoming chat aloud with text-to-speech" },
    { cvar = "remoteTextToSpeechVoice", desc = "Voice used for text-to-speech" },
    { cvar = "TTSUseCharacterSettings", desc = "Use per-character text-to-speech settings" },

    -- =====================
    -- SOUND
    -- =====================
    { cvar = "Sound_MasterVolume", desc = "Master volume" },
    { cvar = "Sound_SFXVolume", desc = "Sound effects volume" },
    { cvar = "Sound_MusicVolume", desc = "Music volume" },
    { cvar = "Sound_AmbienceVolume", desc = "Ambient sound volume" },
    { cvar = "Sound_DialogVolume", desc = "Dialog volume" },
    { cvar = "Sound_EnableAllSound", desc = "Enable all sound" },
    { cvar = "Sound_EnableSFX", desc = "Enable sound effects" },
    { cvar = "Sound_EnableMusic", desc = "Enable music" },
    { cvar = "Sound_EnableAmbience", desc = "Enable ambient sounds" },
    { cvar = "Sound_EnableDialog", desc = "Enable dialog" },
    { cvar = "Sound_EnableSoundWhenGameIsInBG", desc = "Keep playing sound when the game is in the background" },
    { cvar = "Sound_EnableErrorSpeech", desc = "Play spoken error messages" },
    { cvar = "Sound_EnableEmoteSounds", desc = "Play emote sounds" },
    { cvar = "Sound_EnablePetSounds", desc = "Play pet sounds" },
    { cvar = "Sound_EnablePetBattleMusic", desc = "Play music during pet battles" },
    { cvar = "Sound_EnableReverb", desc = "Enable sound reverb" },
    { cvar = "Sound_EnablePositionalLowPassFilter", desc = "Muffle sounds based on their position" },
    { cvar = "Sound_ListenerAtCharacter", desc = "Place the sound listener at your character instead of the camera" },
    { cvar = "Sound_ZoneMusicNoDelay", desc = "Play zone music without delay" },
    { cvar = "Sound_EnablePingSounds", desc = "Play sounds for pings" },
    { cvar = "Sound_PingVolume", desc = "Ping sound volume" },
    { cvar = "Sound_EnableGameplaySFX", desc = "Enable gameplay-specific sound effects" },
    { cvar = "Sound_GameplaySFX", desc = "Gameplay sound effects volume" },
    { cvar = "Sound_EnableEncounterWarningsSounds", desc = "Play sounds for encounter warnings" },
    { cvar = "Sound_EncounterWarningsVolume", desc = "Encounter warning sound volume" },
    { cvar = "Sound_NumChannels", desc = "Number of simultaneous sound channels" },

    -- =====================
    -- VOICE CHAT
    -- =====================
    { cvar = "VoiceInputVolume", desc = "Microphone input volume for voice chat" },
    { cvar = "VoiceOutputVolume", desc = "Voice chat output volume" },
    { cvar = "VoicePushToTalkKeybind", desc = "Push-to-talk key for voice chat" },
    { cvar = "VoiceChatMasterVolumeScale", desc = "Master volume scale for voice chat" },

    -- =====================
    -- GRAPHICS
    -- =====================
    { cvar = "graphicsQuality", desc = "Overall graphics quality preset" },
    { cvar = "graphicsViewDistance", desc = "View distance" },
    { cvar = "graphicsTextureResolution", desc = "Texture resolution" },
    { cvar = "graphicsShadowQuality", desc = "Shadow quality" },
    { cvar = "graphicsSSAO", desc = "Ambient occlusion quality" },
    { cvar = "graphicsProjectedTextures", desc = "Projected texture quality" },
    { cvar = "graphicsSpellDensity", desc = "Spell visual effect density" },
    { cvar = "graphicsComputeEffects", desc = "Compute effects quality" },
    { cvar = "Brightness", desc = "Display brightness" },
    { cvar = "Contrast", desc = "Display contrast" },
    { cvar = "Gamma", desc = "Display gamma" },
    { cvar = "ffxAntiAliasingMode", desc = "Anti-aliasing mode" },
    { cvar = "MSAAQuality", desc = "Multisample anti-aliasing quality" },
    { cvar = "MSAAAlphaTest", desc = "Enable MSAA on alpha-tested geometry" },
    { cvar = "ResampleQuality", desc = "Resampling quality" },
    { cvar = "ResampleSharpness", desc = "Resampling sharpness" },
    { cvar = "LowLatencyMode", desc = "Low latency rendering mode" },
    { cvar = "farclip", desc = "Maximum terrain view distance" },
    { cvar = "particleDensity", desc = "Particle effect density" },
    { cvar = "cameraFov", desc = "Camera field of view" },
    { cvar = "vsync", desc = "Vertical sync" },
    { cvar = "maxFPS", desc = "Maximum frame rate" },
    { cvar = "maxFPSBk", desc = "Maximum frame rate while the game is in the background" },
    { cvar = "useMaxFPS", desc = "Enable the maximum frame rate limit" },
    { cvar = "shadowRt", desc = "Ray-traced shadow quality" },
    { cvar = "physicsLevel", desc = "Physics interaction level" },
    { cvar = "SSAO", desc = "Ambient occlusion quality" },
    { cvar = "projectedTextures", desc = "Enable projected textures" },
    { cvar = "cursorSizePreferred", desc = "Preferred cursor size" },
    { cvar = "NotchedDisplayMode", desc = "How the game handles notched displays" },
    { cvar = "ClipCursor", desc = "Confine the cursor to the game window" },
    { cvar = "uiScale", desc = "User interface scale" },

    -- =====================
    -- MISC
    -- =====================
    { cvar = "advancedCombatLogging", desc = "Enable advanced combat logging" },
    { cvar = "scriptErrors", desc = "Show Lua script errors" },
    { cvar = "enablePings", desc = "Enable the ping system" },
}
