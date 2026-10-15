# Retail Options and Edit Mode, mapped to 3.3.5

From retail screenshots (The War Within / Midnight, October 2026). For each retail setting: what
backs it in 3.3.5, and how hard it is.

- **have:** the WotlkHD addon or the DLL already does it.
- **cvar:** a 3.3.5 cvar exists, confirmed as a string in Wow.exe.
- **addon:** Lua work in the WotlkHD addon.
- **DLL:** needs client code.
- **no:** depends on retail systems or servers.

## Structure

Retail's window has three groups:

- **Gameplay:** Controls, Interface, Action Bars, Combat, Social, Ping System, Keybindings, Gameplay
  Enhancements, Nameplates.
- **Accessibility:** Interface, Audio Assist, Subtitles, General, Colors, Mounts.
- **System:** Graphics, Audio, Languages, Network.

Each page is a single column. Each row has a label on the left and a control at a fixed column on
the right. Pages are split by white section headers ("Mouse", "Camera"). Dependent settings sit
under their parent, indented and in a smaller font.

Retail's controls:

- **Checkbox.**
- **Stepper:** a ◄ value ► button pair. Retail uses it instead of dropdowns for short lists.
- **Slider:** ‹ › arrows, with the value on the right.
- **Checkbox and control on one row:** for example Mouseover Cast with its key.
- **Red buttons:** for example Reset Tutorials.
- **Dropdown:** for long or multi-select lists.

Our window hosts the client's old Interface, Video and Sound panels, each with its own layout. To
look like retail, the next step is building the pages ourselves. Each page would be a table of
sections and rows, each row naming a cvar (the client's, or ours) and a control type, rendered in
retail's column layout. The old panels then go away, and the client's own option functions keep
working because they are only cvars.

Matched to retail since:

- **Mouseover Cast:** now on Combat, with its key on the same row.
- **Colorblind filter:** renamed "Colorblind Filter", strength defaults to 50%, and "Enable UI
  Colorblind Mode" (the client's `colorblindMode`) has moved to Colors from Display.
- **Raid frames:** green health bars by default, with "Display Class Colors" for class colours.
  The option sits on Unit Frames until we build our own Interface page.
- **Edit Mode panel:** it is now "HUD Edit Mode", in the dark dialog. It has Show Grid with the
  spacing slider on the same row, Snap to Elements, a checkbox list of which boxes show, and
  Revert All Changes and Save, which are greyed until something changes. Exiting with unsaved
  changes asks whether to save first.

Still different:

- **Lock Cursor to Window:** retail has it under Controls, in the Mouse section. We have it on the
  client's Mouse page.
- **Colors page:** retail also has Item Quality colour pickers.

## Gameplay

**Controls**

| Retail | 3.3.5 | |
|---|---|---|
| Sticky Targeting | `deselectOnClick` (inverted) | cvar |
| Auto Dismount in Flight | `autoDismountFlying` | cvar |
| Auto Cancel Away Mode | `autoClearAFK` | cvar |
| Interact On Left Click | | no |
| Open Loot Window at Mouse | `lootUnderMouse` | cvar |
| Auto Loot, Loot Key | `autoLootDefault`, AUTOLOOTTOGGLE modifier | cvar |
| Combine Bags | our bags | addon, later |
| Interact Key, Interact With Target, sound cue | | no, or DLL |
| *Mouse:* Lock Cursor to Window | `hdLockCursor` | have |
| Invert Mouse | `mouseInvertPitch` | cvar |
| Mouse Look Speed, Mouse Sensitivity | `cameraYawMoveSpeed`, `mouseSpeed` | cvar |
| Click-to-Move (+ camera mode) | `autointeract`, its camera style | cvar |
| *Camera:* Water Collision | `cameraWaterCollision` | cvar |
| Auto Follow Speed | `cameraYawSmoothSpeed` | cvar |
| Camera Following Style | `cameraSmoothStyle` | cvar |

**Interface**

| Retail | 3.3.5 | |
|---|---|---|
| Tutorials (+ Reset) | `showTutorials` | cvar |
| Outline Mode | | DLL, maybe never |
| Status Text (None, Value, Percent, Both) | `statusText`, `statusTextPercentage` | cvar |
| Chat Bubbles, Party Chat Bubbles | `chatBubbles`, `chatBubblesParty` | cvar |
| Replace Portraits (class icons) | | addon, easy |
| Show Low-Level Quests | | no |
| *Raid Frames:* incoming heals | no heal API in 3.3.5 | no |
| Display Power Bars (+ healers only) | | addon |
| Aggro Highlight | | have (always on) |
| Display Class Colors (off by default), Background Color | | addon |
| Display Pets | | addon |
| Main Tank and Assist | `GetPartyAssignment` | addon |
| Show Debuffs, bigger role debuffs, only dispellable | | addon (have: debuffs) |
| Dispellable Debuff Indicator, colour, flashing | | have (indicator), addon |
| Display Health Text | | addon |
| *Arena Enemy Frames* | the client's arena frames | later |
| *Map Coordinates:* player, cursor, minimap, tenths | | addon, easy |

**Action Bars**

| Retail | 3.3.5 | |
|---|---|---|
| Action Bar 2 to 8 | the four extra bars (`SHOW_MULTI_ACTIONBAR_1` to `4`) | cvar; 6 to 8 no |
| Lock Action Bars (+ pickup key) | `lockActionBars`, PICKUPACTION modifier | cvar |
| Show Numbers for Cooldowns | | addon |

**Combat**

| Retail | 3.3.5 | |
|---|---|---|
| Personal Resource Display | | addon, later |
| Self Highlight, Silhouette | | no |
| Target of Target | `showTargetOfTarget` | cvar |
| Do Not Flash Screen at Low Health | the low health warning cvar | check |
| Loss of Control Alerts | from auras (no LoC API) | addon, later |
| Scrolling Combat Text for Self | `enableCombatText` | cvar |
| Mouseover Cast (+ key) | `hdMouseoverCast`, `hdMouseoverCastKey` | have, wrong page |
| Self Cast (+ key) | `autoSelfCast`, SELFCAST modifier | cvar |
| Focus Cast Key | FOCUSCAST modifier | check |
| Empowered input, Press and Hold, Action Targeting | | no |
| Spell Alert Opacity | there are no spell alerts in 3.3.5 | addon, later |

**Social**

| Retail | 3.3.5 | |
|---|---|---|
| Mature Language Filter | `profanityFilter` | cvar |
| Guild Member Alert | `guildMemberNotify` | cvar |
| Block Trades | `blockTrades` | cvar |
| Block Guild Invites | the client's option | check |
| Restrict Calendar Invites, Block Chat Channel Invites | the client's options | check |
| Online/Offline Friends toasts | `showToastOnline` (Battle.net, unused) | no |
| Chat Style, New Whispers, Chat Timestamps | `chatStyle`, whisper mode, `showTimestamps` | cvar |
| Reset Chat Position | `FCF_ResetChatWindows` | addon |
| Real Time Chat Filtering, Discord, Quick Join, Location | | no |

**Ping System:** no.

**Keybindings:** retail has keybindings as a page inside Options. It has collapsible categories,
"Character Specific Keybindings", Click Casting and Quick Keybind Mode.

- The page itself: addon, already on the TODO.
- Click Casting: addon, using secure attributes on our raid frames.
- Quick Keybind: addon, later.

**Gameplay Enhancements:** Combat Assistant, Boss Warnings, Cooldown Manager, External Defensives,
Damage Meter and Diminishing Returns are all retail systems. Of these, a damage meter is possible
as addon work, from the combat log.

**Nameplates**

| Retail | 3.3.5 | |
|---|---|---|
| *Names:* My Name, NPC Names, Friendly/Enemy Players (+ minions), critters | `UnitNameOwn`, `UnitNameNPC`, `UnitNameFriendlyPlayerName`, `UnitNameEnemyPlayerName`, pet name cvars | cvar |
| *Nameplates:* Always Show Nameplates | both show cvars, with no key needed | cvar |
| Enemy Unit Nameplate (+ minions, minor) | `nameplateShowEnemies` (+ Pets, Guardians, Totems) | cvar |
| Friendly Player Nameplates (+ minions, only names, class colour, realm) | `nameplateShowFriends` (+ pets etc.) | cvar, addon |
| Friendly NPC Nameplates, Offscreen | | no |
| Stack Nameplates | `nameplateAllowOverlap` (inverted) | cvar |
| Preview | | addon |
| Size, Buff/Debuff Scale | | addon |
| Style, Nameplate Information, Cast Bar Information | | addon |
| Aggro Display (none, flash, progressive) | | have (threat border), addon |
| Buffs/Debuffs per unit type, Debuff Padding, Simplify | | addon |

Retail's current nameplate, from the screenshots:

- The name is inside the bar, left-aligned and white, rather than above it.
- The bar is longer, with a thin light border; the target's border is white.
- Auras sit above the bar's left end, with a countdown on each icon. That's where Corruption
  showed. Curse of Weakness showed on the right of the bar instead, so retail puts some auras
  on the side; which ones, and why, isn't known yet.

## Accessibility

| Page | Retail | 3.3.5 | |
|---|---|---|---|
| Interface | Text Scale, Quest Text Contrast | | addon, maybe |
| Audio Assist | text to speech, narrator | | no |
| Subtitles | cinematic subtitles | | no |
| General | Move Pad, Photosensitivity, min name size, Motion Sickness, Camera Shake, Cursor Size, Show Target Tooltip, Interact Key Icons, Arachnophobia | camera shake: DLL; cursor size: maybe DLL | mostly no |
| Colors | Enable UI Colorblind Mode | `colorblindMode` | cvar |
| Colors | Colorblind Filter + Adjust Strength (50%) | `hdColorblind`, `hdColorblindStrength` | have (default 100) |
| Colors | Item Quality colours | `ITEM_QUALITY_COLORS` | addon |
| Mounts | skyriding | | no |

## System

**Graphics**

| Retail | 3.3.5 | |
|---|---|---|
| Monitor, Display Mode, Resolution | the client's video options | cvar |
| Render Scale | | DLL, maybe |
| Use UI Scale | `useUiScale`, `uiScale` | cvar |
| Vertical Sync, Triple Buffering | `gxVSync`, `gxTripleBuffer` | cvar |
| Low Latency Mode | | no |
| Anti-Aliasing (image-based / multisample) | `hdSMAA`, the client's multisample | have |
| Camera FOV (slider, 90) | patch_exe.py's fixed FoV | DLL |
| Graphics Quality presets and per-setting | the client's video panel | cvar |
| SSAO, Depth Effects | `hdAO`, `hdHaze`, `hdSunshafts` | have |
| Texture Filtering | `textureFilteringMode` | cvar |
| Max Foreground/Background FPS | `maxFPS`, `maxFPSBk` | cvar |
| Resample Sharpness | `hdSharpen`, `hdSharpness` | have |
| Contrast, Brightness | | DLL (post pass) |
| Gamma | `gamma` | cvar |
| Ray tracing, VRS, API, compatibility | | no |

**Audio:** volumes, toggles, reverb, background sound, error speech and channels all map to the
client's `Sound_*` cvars. Ping and boss warning sounds: no.

**Languages:** no.

**Network:** Optimize Network for Speed has a client cvar. Advanced combat logging and IPv6: no.

## Edit Mode

The panel is titled "HUD Edit Mode". It is a dark dialog with a gold rim and an info button. It
contains:

- **Layout:** a dropdown ("Modern (Preset)") with a new-layout option.
- **Grid:** Show Grid, with the spacing slider on the same row (default 100). Ours defaults to 40.
- **Snap and options:** Snap to Elements, and Advanced Options.
- **Which boxes show:** a framed list of checkboxes.
  - Basic: Target and Focus, Party Frames, Buffs and Debuffs, Talking Head, Raid Frames, Boss
    Frames, Cast Bar.
  - Advanced Options adds three groups:
    - Frames: Pet, Arena.
    - Combat: Stance, Pet and Possess bars, Extra Abilities, Encounter Bar, Personal Resource
      Display, Cooldown Manager, Boss Warnings, Loss of Control.
    - Misc: Vehicle Exit, Vehicle Seats, Durability, HUD Tooltip, Duration Bars, Status Bar 2,
      Archaeology Bar, Raid Warnings.
- **Buttons:** Revert All Changes and Save. Both are greyed until something changes.

Every visible part of the UI gets a box, including action bars, chat, the minimap, the quest
tracker, buffs and the bag bar. With nothing selected, the boxes are the light blue highlight.

Parts of the 3.3.5 UI we could add as Edit Mode boxes:

| Part | 3.3.5 frame |
|---|---|
| Pet frame | `PetFrame` |
| Boss frames | `Boss1TargetFrame` to `Boss4TargetFrame` |
| Arena frames | `ArenaEnemyFrames` |
| Stance, pet and possess bars | `ShapeshiftBarFrame`, `PetActionBarFrame`, `PossessBarFrame` |
| Durability | `DurabilityFrame` |
| Vehicle seats | `VehicleSeatIndicator` |
| Tooltip anchor | the game tooltip |
| Talking head | none in 3.3.5 |
