-- wotlk-hd: retail's action bars (Dragonflight's UI-HUD-ActionBar art, from Blizzard_ActionBar's
-- ActionButtonTemplate.xml and MainActionBar.xml) on the client's bars: retail's icon frame, pressed and
-- mouseover art and slot on every button; the main bar without its stone background, with retail's
-- gryphons (wyverns for the Horde) and page arrows; the micro menu and bag buttons at the bottom right in
-- retail's art. The buttons keep their place for now (Edit Mode will move them); only art and unprotected
-- frames change, so nothing here is blocked in combat.

local ATLAS = WotlkHD_Atlas
local Retail = WotlkHD_Retail
local hidden = CreateFrame("Frame")
hidden:Hide()

local function atlasOn(button, setter, getter, atlas)
    local a = ATLAS[strlower(atlas)]
    button[setter](button, a[1])
    local t = button[getter](button)
    t:SetTexCoord(a[4], a[5], a[6], a[7])
    return t
end

-- [[ Buttons ]] --

local skinned = {}

-- The icon frame states, sized to the button as retail's 46x45 frame is to its 45x45 button.
local function frameArt(b)
    local size = b:GetWidth()
    for _, s in ipairs({{"SetNormalTexture", "GetNormalTexture", "UI-HUD-ActionBar-IconFrame"},
        {"SetPushedTexture", "GetPushedTexture", "UI-HUD-ActionBar-IconFrame-Down"},
        {"SetHighlightTexture", "GetHighlightTexture", "UI-HUD-ActionBar-IconFrame-Mouseover"},
        {"SetCheckedTexture", "GetCheckedTexture", "UI-HUD-ActionBar-IconFrame-Mouseover"}}) do
        if b[s[1]] then
            local t = atlasOn(b, s[1], s[2], s[3])
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT")
            t:SetWidth(size * 46 / 45)
            t:SetHeight(size)
            if s[1] ~= "SetNormalTexture" and s[1] ~= "SetPushedTexture" then
                t:SetBlendMode("BLEND")
            end
        end
    end
end

local function skin(b)
    if not b or skinned[b] then
        return
    end
    skinned[b] = true
    local name = b:GetName()
    -- The empty slot on the main bar only (retail's other bars are see-through), on a frame under the
    -- button: in the icon's own layer, 3.3.5 might draw it on top.
    if name:find("^ActionButton%d+$") then
        local under = CreateFrame("Frame", nil, b)
        under:SetAllPoints()
        under:SetFrameLevel(math.max(b:GetFrameLevel() - 1, 0))
        local slot = under:CreateTexture(nil, "BACKGROUND")
        slot:SetAtlas("ui-hud-actionbar-iconframe-slot")
        slot:SetAllPoints()
    end
    -- Inside the frame's border, as retail's icon mask keeps it (3.3.5 has no masks).
    local inset = b:GetWidth() * 3 / 45
    for _, key in ipairs({"Icon", "Cooldown"}) do
        local t = _G[name .. key]
        if t then
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", inset, -inset)
            t:SetPoint("BOTTOMRIGHT", -inset, inset)
        end
    end
    if _G[name .. "Icon"] then
        _G[name .. "Icon"]:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    end
    for key, atlas in pairs({Flash = "UI-HUD-ActionBar-IconFrame-Flash", Border = "UI-HUD-ActionBar-IconFrame-Border"}) do
        local t = _G[name .. key]
        if t then
            t:SetAtlas(atlas)
            t:ClearAllPoints()
            t:SetAllPoints()
        end
    end
    local hotkey, count = _G[name .. "HotKey"], _G[name .. "Count"]
    if hotkey then
        hotkey:ClearAllPoints()
        hotkey:SetPoint("TOPRIGHT", -4, -4)
    end
    if count then
        count:ClearAllPoints()
        count:SetPoint("BOTTOMRIGHT", -4, 4)
    end
    frameArt(b)
end

for _, bar in ipairs({"ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
    "MultiBarLeftButton", "BonusActionButton"}) do
    for i = 1, NUM_ACTIONBAR_BUTTONS do
        skin(_G[bar .. i])
    end
end
for i = 1, NUM_SHAPESHIFT_SLOTS do
    skin(_G["ShapeshiftButton" .. i])
end
for i = 1, NUM_PET_ACTION_SLOTS do
    skin(_G["PetActionButton" .. i])
end
for i = 1, NUM_POSSESS_SLOTS do
    skin(_G["PossessButton" .. i])
end

-- The client sets the frame texture again on each update (UI-Quickslot2, or UI-Quickslot when empty).
hooksecurefunc("ActionButton_Update", function(b)
    if skinned[b] then
        frameArt(b)
    end
end)
hooksecurefunc("ShapeshiftBar_UpdateState", function()
    for i = 1, NUM_SHAPESHIFT_SLOTS do
        frameArt(_G["ShapeshiftButton" .. i])
    end
end)
hooksecurefunc("PossessBar_Update", function()
    for i = 1, NUM_POSSESS_SLOTS do
        frameArt(_G["PossessButton" .. i])
    end
end)
hooksecurefunc("PetActionBar_Update", function()
    for i = 1, NUM_PET_ACTION_SLOTS do
        frameArt(_G["PetActionButton" .. i])
    end
end)

-- [[ Main bar ]] --

for _, name in ipairs({"MainMenuBarTexture0", "MainMenuBarTexture1", "MainMenuBarTexture2", "MainMenuBarTexture3",
    "MainMenuMaxLevelBar0", "MainMenuMaxLevelBar1", "MainMenuMaxLevelBar2", "MainMenuMaxLevelBar3",
    "BonusActionBarTexture0", "BonusActionBarTexture1", "ShapeshiftBarLeft", "ShapeshiftBarMiddle",
    "ShapeshiftBarRight", "PossessBackground1", "PossessBackground2", "SlidingActionBarTexture0",
    "SlidingActionBarTexture1"}) do
    if _G[name] then
        _G[name]:SetTexture(nil)
    end
end

-- The client's gryphons give way to ours on the main bar (Layout, below).
MainMenuBarLeftEndCap:SetAlpha(0)
MainMenuBarRightEndCap:SetAlpha(0)

-- Page arrows and number, left of the first button as on retail.
for button, kind in pairs({[ActionBarUpButton] = "PageUpArrow", [ActionBarDownButton] = "PageDownArrow"}) do
    button:SetWidth(17)
    button:SetHeight(14)
    atlasOn(button, "SetNormalTexture", "GetNormalTexture", "UI-HUD-ActionBar-" .. kind .. "-Up")
    atlasOn(button, "SetPushedTexture", "GetPushedTexture", "UI-HUD-ActionBar-" .. kind .. "-Down")
    atlasOn(button, "SetHighlightTexture", "GetHighlightTexture", "UI-HUD-ActionBar-" .. kind .. "-Mouseover")
    atlasOn(button, "SetDisabledTexture", "GetDisabledTexture", "UI-HUD-ActionBar-" .. kind .. "-Disabled")
    button:ClearAllPoints()
end
ActionBarUpButton:SetPoint("CENTER", ActionButton1, "LEFT", -14, 10)
ActionBarDownButton:SetPoint("CENTER", ActionButton1, "LEFT", -14, -10)
MainMenuBarPageNumber:ClearAllPoints()
MainMenuBarPageNumber:SetPoint("CENTER", ActionButton1, "LEFT", -14, 0)

-- The experience and reputation bars lose their segmented frames.
for _, prefix in ipairs({"MainMenuXPBarTexture", "ReputationWatchBarTexture", "ReputationXPBarTexture"}) do
    for i = 0, 3 do
        if _G[prefix .. i] then
            _G[prefix .. i]:SetTexture(nil)
        end
    end
end

-- [[ Micro menu ]] --
-- Retail's buttons in a row at the bottom right; it has no PvP or Help button (both are on keys and in
-- the game menu), so those two go.

local MICRO = {{CharacterMicroButton, "ButtonBG"}, {SpellbookMicroButton, "SpellbookAbilities"},
    {TalentMicroButton, "SpecTalents"}, {AchievementMicroButton, "Achievements"}, {QuestLogMicroButton, "Questlog"},
    {SocialsMicroButton, "GuildCommunities"}, {LFDMicroButton, "Groupfinder"}, {MainMenuMicroButton, "GameMenu"}}

for _, m in ipairs(MICRO) do
    local b, art = m[1], "UI-HUD-MicroMenu-" .. m[2]
    b:SetWidth(32)
    b:SetHeight(41)
    b:SetHitRectInsets(0, 0, 0, 0)
    if m[2] ~= "ButtonBG" then -- retail's round background under the icon, pressed with it
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetAtlas("UI-HUD-MicroMenu-ButtonBG-Up", true)
        bg:SetPoint("CENTER")
        b:HookScript("OnMouseDown", function() bg:SetAtlas("UI-HUD-MicroMenu-ButtonBG-Down") end)
        b:HookScript("OnMouseUp", function() bg:SetAtlas("UI-HUD-MicroMenu-ButtonBG-Up") end)
    end
    atlasOn(b, "SetNormalTexture", "GetNormalTexture", art .. "-Up")
    atlasOn(b, "SetPushedTexture", "GetPushedTexture", art .. "-Down")
    if m[2] == "ButtonBG" then
        atlasOn(b, "SetHighlightTexture", "GetHighlightTexture", art .. "-Up"):SetBlendMode("ADD")
    else
        atlasOn(b, "SetHighlightTexture", "GetHighlightTexture", art .. "-Mouseover"):SetBlendMode("BLEND")
        atlasOn(b, "SetDisabledTexture", "GetDisabledTexture", art .. "-Disabled")
    end
end
MicroButtonPortrait:ClearAllPoints()
MicroButtonPortrait:SetPoint("CENTER", CharacterMicroButton, "CENTER", 0, 1)
MicroButtonPortrait:SetWidth(20)
MicroButtonPortrait:SetHeight(26)

-- Chained left to right as the client chains them (it anchors Socials to QuestLog itself; a chain the
-- other way would make that a loop), the first placed so the row ends at the bottom right.
local function microLayout()
    for i, m in ipairs(MICRO) do
        local b = m[1]
        b:SetParent(UIParent)
        b:ClearAllPoints()
        if i == 1 then
            b:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMRIGHT", -6 - #MICRO * 32 + (#MICRO - 1) * 5, 4)
        else
            b:SetPoint("BOTTOMLEFT", MICRO[i - 1][1], "BOTTOMRIGHT", -5, 0) -- retail's childXPadding
        end
    end
    PVPMicroButton:SetParent(hidden)
    HelpMicroButton:SetParent(hidden)
end
microLayout()
hooksecurefunc("VehicleMenuBar_MoveMicroButtons", microLayout) -- vehicles move them into their own bar

-- [[ Bags ]] --
-- Retail's round bag buttons above the micro menu: the backpack, and the four bags to its left.

local function roundIcon(button)
    local icon = _G[button:GetName() .. "IconTexture"]
    local texture = icon and icon:GetTexture()
    if texture then
        SetPortraitToTexture(icon, texture)
    end
end

MainMenuBarBackpackButton:SetParent(UIParent)
MainMenuBarBackpackButton:ClearAllPoints()
MainMenuBarBackpackButton:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -8, 50)
MainMenuBarBackpackButton:SetWidth(40)
MainMenuBarBackpackButton:SetHeight(40)
atlasOn(MainMenuBarBackpackButton, "SetNormalTexture", "GetNormalTexture", "bag-main"):SetAllPoints()
atlasOn(MainMenuBarBackpackButton, "SetHighlightTexture", "GetHighlightTexture", "bag-main-highlight"):SetAllPoints()
MainMenuBarBackpackButton:GetPushedTexture():SetTexture(nil)
SetPortraitToTexture(MainMenuBarBackpackButtonIconTexture, "Interface\\Buttons\\Button-Backpack-Up")
MainMenuBarBackpackButtonIconTexture:ClearAllPoints()
MainMenuBarBackpackButtonIconTexture:SetPoint("TOPLEFT", 4, -4)
MainMenuBarBackpackButtonIconTexture:SetPoint("BOTTOMRIGHT", -4, 4)

-- The free slot count (Display Free Bag Slots) above the bag art, at the bottom as retail's "(27)".
local over = CreateFrame("Frame", nil, MainMenuBarBackpackButton)
over:SetAllPoints()
over:SetFrameLevel(MainMenuBarBackpackButton:GetFrameLevel() + 2)
MainMenuBarBackpackButtonCount:SetParent(over)
MainMenuBarBackpackButtonCount:ClearAllPoints()
MainMenuBarBackpackButtonCount:SetPoint("BOTTOM", 0, 2)

local previous = MainMenuBarBackpackButton
for i = 0, NUM_BAG_SLOTS - 1 do
    local b = _G["CharacterBag" .. i .. "Slot"]
    b:SetParent(UIParent)
    b:ClearAllPoints()
    b:SetPoint("RIGHT", previous, "LEFT", -4, 0)
    b:SetWidth(30)
    b:SetHeight(30)
    atlasOn(b, "SetNormalTexture", "GetNormalTexture", "bag-border"):SetAllPoints()
    atlasOn(b, "SetHighlightTexture", "GetHighlightTexture", "bag-border-highlight"):SetAllPoints()
    b:GetPushedTexture():SetTexture(nil)
    local icon = _G[b:GetName() .. "IconTexture"]
    icon:ClearAllPoints()
    icon:SetPoint("TOPLEFT", 3, -3)
    icon:SetPoint("BOTTOMRIGHT", -3, 3)
    roundIcon(b)
    previous = b
end
KeyRingButton:SetParent(UIParent)
KeyRingButton:ClearAllPoints()
KeyRingButton:SetPoint("RIGHT", previous, "LEFT", -4, 0)

-- A bag's icon is set again when it changes: keep it round.
hooksecurefunc("PaperDollItemSlotButton_Update", function(b)
    local id = b:GetID()
    if id >= CharacterBag0Slot:GetID() and id <= CharacterBag3Slot:GetID() and b:GetName():find("^CharacterBag") then
        roundIcon(b)
    end
end)

-- [[ Layout ]] --
-- Retail's: the main bar centered at the bottom with the experience and reputation bars under it, bars 2
-- and 3 stacked above it, stance and pet bars above those, bars 4 and 5 down the right edge, bars 6-8 in
-- the middle of the screen; buttons 2 apart, as retail's default padding.
--
-- Every bar is our own secure frame holding the client's buttons (as Dominos and Bartender did): the
-- client's layout code (UIParent_ManageFramePositions) moves its own bars, in combat too where only its
-- code may, so ours would jump. The main bar pages with a state driver, secure, so stances, forms, paging
-- and possess switch in combat. A bar moved in Edit Mode (WotlkHD_Saved.editMode.frames) stays where it
-- was put, and the bars that stacked on it stack on what's below it.

-- Bars 1-8 at retail's 45 pixel buttons: the client's 36 pixel buttons, scaled. Offsets on a scaled bar
-- are in its own units, so the ones to the screen are divided by the scale.
local BUTTON, SMALL, GAP = 36, 30, 2
local BAR_SCALE = 45 / 36
local WIDTH = NUM_ACTIONBAR_BUTTONS * BUTTON + (NUM_ACTIONBAR_BUTTONS - 1) * GAP
-- Status bars at retail's 9 pixels, each in a frame 4 wider all round; the frames touch.
local XP_HEIGHT, REP_HEIGHT, BOTTOM, BAR_GAP = 9, 9, 4, 8
-- The main bar 14 over the upper bar's frame (measured from retail), clear of the gryphons' feet.
local MAIN_Y = BOTTOM + XP_HEIGHT + BAR_GAP + REP_HEIGHT + 4 + 14

local bars = {}

-- A secure bar for buttons named prefix..1..count (or created when make is set), size each, in a row or a
-- column. shown: a macro condition for its visibility, or a function giving one.
local function bar(key, name, prefix, count, size, vertical, shown, make)
    local f = CreateFrame("Frame", name, UIParent, "SecureHandlerStateTemplate")
    local long = count * size + (count - 1) * GAP
    f:SetWidth(vertical and size or long)
    f:SetHeight(vertical and long or size)
    f.key, f.prefix, f.count, f.size, f.vertical, f.shown = key, prefix, count, size, vertical, shown
    if size == BUTTON then
        f:SetScale(BAR_SCALE)
    end
    if make then
        for i = 1, count do
            local b = CreateFrame("CheckButton", prefix .. i, f, "ActionBarButtonTemplate")
            b:SetID(i)
            b.buttonType = strupper(prefix) -- bound as CLICK <name>:LeftButton (Bindings.xml)
            ActionButton_UpdateHotkeys(b, b.buttonType)
            skin(b)
        end
    end
    bars[key] = f
    return f
end

local function fill(f)
    for i = 1, f.count do
        local b = _G[f.prefix .. i]
        b:SetParent(f)
        b:ClearAllPoints()
        if f.vertical then
            b:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(i - 1) * (f.size + GAP))
        else
            b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", (i - 1) * (f.size + GAP), 0)
        end
    end
end

-- Key Bindings names for bars 6-8 (Bindings.xml binds their buttons as clicks).
BINDING_HEADER_WOTLKHD = "Action Bars 6-8"
for n = 6, 8 do
    for i = 1, NUM_ACTIONBAR_BUTTONS do
        _G["BINDING_NAME_CLICK WotlkHDBar" .. n .. "Button" .. i .. ":LeftButton"] =
            "Action Bar " .. n .. " Button " .. i
    end
end

local VEHICLE = "[vehicleui] hide; show"
local main = bar("bar1", "WotlkHDMainBar", "ActionButton", NUM_ACTIONBAR_BUTTONS, BUTTON, false, VEHICLE)
-- Possess first, then the pages (Shift+number, the page arrows), then the stances and forms, as the
-- client's own ActionButton_CalculateAction orders them.
local PAGING = "[bonusbar:5]11;[bar:2]2;[bar:3]3;[bar:4]4;[bar:5]5;[bar:6]6;"
    .. "[bonusbar:1]7;[bonusbar:2]8;[bonusbar:3]9;[bonusbar:4]10;1"
-- Retail's frame around the main bar and its gryphons (wyverns for the Horde), at MainActionBar.xml's
-- places in retail units (a 45 pixel button), so times 36/45 in the bar's.
do
    local S = 1 / BAR_SCALE
    local border = Retail.NineSlice(main, "BACKGROUND", "UI-HUD-ActionBar-Frame", 20)
    border:SetPoints(main, 4 * S, 4 * S, 8 * S, 7 * S)
    local caps = CreateFrame("Frame", nil, main)
    caps:SetAllPoints()
    caps:SetFrameLevel(main:GetFrameLevel() + 20)
    local beast = UnitFactionGroup("player") == "Horde" and "Wyvern" or "Gryphon"
    local left, right = caps:CreateTexture(nil, "OVERLAY"), caps:CreateTexture(nil, "OVERLAY")
    left:SetAtlas("UI-HUD-ActionBar-" .. beast .. "-Left")
    right:SetAtlas("UI-HUD-ActionBar-" .. beast .. "-Right")
    for _, cap in ipairs({left, right}) do
        cap:SetWidth(104.5 * S)
        cap:SetHeight(98 * S)
    end
    left:SetPoint("BOTTOMRIGHT", main, "BOTTOMLEFT", 9 * S, -22 * S)
    right:SetPoint("BOTTOMLEFT", main, "BOTTOMRIGHT", -8 * S, -22 * S)
end
main:SetAttribute("_onstate-page", [[
    for _, button in ipairs(newtable(self:GetChildren())) do
        button:SetAttribute("actionpage", tonumber(newstate))
    end
]])

-- Bars 2-5 hold the client's multibar buttons on the client's pages, shown when the client's option shows
-- its bar.
local function client(frame)
    return function() return frame:IsShown() and VEHICLE or "hide" end
end
for _, e in ipairs({{2, MultiBarBottomLeft, "MultiBarBottomLeftButton"}, {3, MultiBarBottomRight, "MultiBarBottomRightButton"},
    {4, MultiBarRight, "MultiBarRightButton", true}, {5, MultiBarLeft, "MultiBarLeftButton", true}}) do
    local f = bar("bar" .. e[1], "WotlkHDBar" .. e[1], e[3], NUM_ACTIONBAR_BUTTONS, BUTTON, e[4], client(e[2]))
    f:SetAttribute("actionpage", e[2]:GetAttribute("actionpage"))
end

-- Bars 6-8 on slots no bar of the client's uses: page 2 (13-24, the client's Shift+2 page), page 12
-- (133-144: the server keeps 144 slots, the client uses 132), and page 10 (109-120, a stance page no
-- class but the druid's moonkin uses).
local EXTRA = {{6, 2}, {7, 12}}
if select(2, UnitClass("player")) ~= "DRUID" then
    tinsert(EXTRA, {8, 10})
end
for _, e in ipairs(EXTRA) do
    local f = bar("bar" .. e[1], "WotlkHDBar" .. e[1], "WotlkHDBar" .. e[1] .. "Button", NUM_ACTIONBAR_BUTTONS, BUTTON,
        false, function()
            return (WotlkHD_Saved and WotlkHD_Saved.actionBars or {})[e[1]] and VEHICLE or "hide"
        end, true)
    f:SetAttribute("actionpage", e[2])
end

-- The client still shows and hides the stance and pet buttons themselves (forms you have, pet slots).
bar("stance", "WotlkHDStanceBar", "ShapeshiftButton", NUM_SHAPESHIFT_SLOTS, SMALL, false, "[vehicleui][bonusbar:5] hide; show")
bar("pet", "WotlkHDPetBar", "PetActionButton", NUM_PET_ACTION_SLOTS, SMALL, false, "[vehicleui] hide; [pet] show; hide")
bar("possess", "WotlkHDPossessBar", "PossessButton", NUM_POSSESS_SLOTS, SMALL, false, "[bonusbar:5] show; hide")

-- Bars 1-8 own the empty slots too: shown, as on retail (3.3.5 hid empty buttons outside its main bar art;
-- dragging adds to showgrid and takes it off again, so 1 stays).
local function grid()
    for n = 1, 8 do
        local f = bars["bar" .. n]
        for i = 1, f and f.count or 0 do
            _G[f.prefix .. i]:SetAttribute("showgrid", 1)
            _G[f.prefix .. i]:Show()
        end
    end
end

local function moved(f)
    local edit = WotlkHD_Saved and WotlkHD_Saved.editMode
    return edit and edit.frames and edit.frames[f.key]
end

local function anchor(f, ...)
    if not moved(f) then
        f:ClearAllPoints()
        f:SetPoint(...)
    end
end

-- The cast bar above the bars stacked over the main bar (bars 2 and 3, then stance or pet), as retail's
-- bottom managed frames, unless moved in Edit Mode. It is not protected: placed again whenever one of
-- those bars shows or hides, in combat too, and after the client's layout code (which places it for
-- its own bars).
local CAST_GAP = 20 -- room for the spell name under it
local function castBar()
    if moved({key = "castbar"}) then
        return
    end
    -- the highest top edge, in screen units (the stance and pet bars sit left and right, not centered)
    local y = 0
    for _, key in ipairs({"bar1", "bar2", "bar3", "stance", "possess", "pet"}) do
        local f = bars[key]
        if f:IsShown() and not moved(f) and f:GetTop() then
            y = math.max(y, f:GetTop() * f:GetEffectiveScale())
        end
    end
    if y > 0 then
        CastingBarFrame:ClearAllPoints()
        CastingBarFrame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0,
            y / CastingBarFrame:GetEffectiveScale() + CAST_GAP)
    end
end

-- Out of combat: the frames are protected.
local pending
local function place()
    -- The client's layout code sizes the stance buttons' frame texture to 50 or 64 each time.
    for i = 1, NUM_SHAPESHIFT_SLOTS do
        frameArt(_G["ShapeshiftButton" .. i])
    end
    if InCombatLockdown() then
        pending = true
        return
    end
    pending = nil
    for _, f in pairs(bars) do
        RegisterStateDriver(f, "visibility", type(f.shown) == "function" and f.shown() or f.shown)
    end
    anchor(main, "BOTTOM", UIParent, "BOTTOM", 0, MAIN_Y / BAR_SCALE)
    local top = main
    for _, key in ipairs({"bar2", "bar3"}) do
        local f = bars[key]
        anchor(f, "BOTTOMLEFT", top, "TOPLEFT", 0, GAP)
        if f.shown() ~= "hide" and not moved(f) then
            top = f
        end
    end
    anchor(bars.stance, "BOTTOMLEFT", top, "TOPLEFT", 0, GAP + 2)
    anchor(bars.possess, "BOTTOMLEFT", top, "TOPLEFT", 0, GAP + 2)
    anchor(bars.pet, "BOTTOMRIGHT", top, "TOPRIGHT", 0, GAP + 2)
    MultiCastActionBarFrame:ClearAllPoints() -- the shaman's totem bar is still the client's
    MultiCastActionBarFrame:SetPoint("BOTTOMLEFT", top, "TOPLEFT", -8, GAP)
    anchor(bars.bar4, "RIGHT", UIParent, "RIGHT", -4 / BAR_SCALE, 0)
    anchor(bars.bar5, "TOPRIGHT", bars.bar4, "TOPLEFT", -GAP, 0)
    -- Bars 6-8 stack in the middle of the screen, a little below center, as retail places them.
    local below
    for _, e in ipairs(EXTRA) do
        local f = bars["bar" .. e[1]]
        if below then
            anchor(f, "BOTTOMLEFT", below, "TOPLEFT", 0, GAP)
        else
            anchor(f, "BOTTOM", UIParent, "CENTER", 0, -100 / BAR_SCALE)
        end
        if f.shown() ~= "hide" and not moved(f) then
            below = f
        end
    end
    castBar()
end

for _, key in ipairs({"bar2", "bar3", "stance", "possess", "pet"}) do
    bars[key]:HookScript("OnShow", castBar)
    bars[key]:HookScript("OnHide", castBar)
end

local function setup()
    if InCombatLockdown() then
        return
    end
    for _, f in pairs(bars) do
        fill(f)
    end
    grid()
    BonusActionBarFrame:SetParent(hidden)
    RegisterStateDriver(main, "page", PAGING)
    place()
end

-- With one form the client anchors the first stance button to its own bar again.
hooksecurefunc("ShapeshiftBar_Update", function()
    if bars.stance:GetNumChildren() > 0 and not InCombatLockdown() then
        fill(bars.stance)
    end
end)

-- Experience and reputation: thin bars under the main bar, as wide as it.
local function statusBars()
    MainMenuExpBar:ClearAllPoints()
    MainMenuExpBar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, BOTTOM)
    MainMenuExpBar:SetWidth(WIDTH * BAR_SCALE)
    MainMenuExpBar:SetHeight(XP_HEIGHT)
    if ReputationWatchBar:IsShown() then
        ReputationWatchBar:ClearAllPoints()
        ReputationWatchBar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0,
            MainMenuExpBar:IsShown() and BOTTOM + XP_HEIGHT + BAR_GAP or BOTTOM)
        ReputationWatchBar:SetWidth(WIDTH * BAR_SCALE)
        ReputationWatchStatusBar:SetWidth(WIDTH * BAR_SCALE)
        ReputationWatchBar:SetHeight(REP_HEIGHT)
        ReputationWatchStatusBar:SetHeight(REP_HEIGHT)
    end
end
-- Retail's art: its background, fill and frame (StatusTrackingBar), and its ExpBar: rested experience
-- in the prediction fill, cut to its width, under the bar's own, with a pip at its end, and the bar in
-- the rested fill while rested.
for _, bar in ipairs({MainMenuExpBar, ReputationWatchStatusBar}) do
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetAtlas("UI-HUD-ExperienceBar-Background")
    local border = CreateFrame("Frame", nil, bar)
    border:SetAllPoints()
    border:SetFrameLevel(bar:GetFrameLevel() + 1)
    local frame = border:CreateTexture(nil, "BACKGROUND")
    frame:SetPoint("TOPLEFT", -4, 4)
    frame:SetPoint("BOTTOMRIGHT", 4, -4)
    frame:SetAtlas("UI-HUD-ExperienceBar-Frame")
end
ExhaustionLevelFillBar:SetDrawLayer("BORDER")
ExhaustionLevelFillBar:SetHeight(XP_HEIGHT)
Retail.size(ExhaustionTick, 10, 14)
ExhaustionTick:SetFrameLevel(MainMenuExpBar:GetFrameLevel() + 2) -- over the frame
ExhaustionTick:GetNormalTexture():SetAtlas("UI-HUD-ExperienceBar-Frame-Pip")
ExhaustionTickHighlight:SetAtlas("UI-HUD-ExperienceBar-Frame-Pip-Mouseover")
ExhaustionTickHighlight:SetBlendMode("ADD")
local PREDICTION = WotlkHD_Atlas["ui-hud-experiencebar-fill-prediction"]
ExhaustionLevelFillBar:SetTexture(PREDICTION[1])
local function rested()
    Retail.AtlasBar(MainMenuExpBar, GetRestState() == 1 and "UI-HUD-ExperienceBar-Fill-Rested"
        or "UI-HUD-ExperienceBar-Fill-Experience")
    ExhaustionLevelFillBar:SetVertexColor(1, 1, 1, 1)
    ExhaustionTickHighlight:SetVertexColor(1, 1, 1)
    local exhaustion, max = GetXPExhaustion(), UnitXPMax("player")
    if exhaustion and max > 0 then
        local ratio = math.min((UnitXP("player") + exhaustion) / max, 1)
        ExhaustionLevelFillBar:SetTexCoord(PREDICTION[4], PREDICTION[4] + (PREDICTION[5] - PREDICTION[4]) * ratio,
            PREDICTION[6], PREDICTION[7])
        if ratio < 0.01 or ratio > 0.99 then -- retail's: a pip at the bar's ends looks wrong
            ExhaustionTick:Hide()
        elseif ExhaustionTick:IsShown() then
            local point, to, rel, x = ExhaustionTick:GetPoint()
            ExhaustionTick:SetPoint(point, to, rel, x, 2)
        end
    end
end
rested()
hooksecurefunc("ExhaustionTick_OnEvent", rested)
-- The rested tooltip on the whole bar too, as retail's.
MainMenuExpBar:HookScript("OnEnter", ExhaustionToolTipText)
MainMenuExpBar:HookScript("OnLeave", GameTooltip_Hide)

-- Retail's reputation fills by standing: red for hated and hostile, orange, yellow, then green.
local REACTION = {"Red", "Red", "Orange", "Yellow", "Green", "Green", "Green", "Green"}
hooksecurefunc("ReputationWatchBar_Update", function()
    local color = REACTION[select(2, GetWatchedFactionInfo())] -- standing 0 with no faction watched
    if color then
        Retail.AtlasBar(ReputationWatchStatusBar, "UI-HUD-ExperienceBar-Fill-Reputation-Faction-" .. color)
    end
    statusBars()
end)
hooksecurefunc("MainMenuExpBar_Update", statusBars)

hooksecurefunc("UIParent_ManageFramePositions", place)

-- 3.3.5's tutorial alert ("?", shown while a tutorial tip waits) sits over the old main bar, now ours:
-- small, left of the micro menu, where it doesn't cover the buttons (retail has small help tips instead).
-- The client's layout code places it each time (UIPARENT_MANAGED_FRAME_POSITIONS); ours after.
TutorialFrameAlertButton:SetScale(0.6)
local function tutorialAlert()
    TutorialFrameAlertButton:ClearAllPoints()
    TutorialFrameAlertButton:SetPoint("BOTTOMRIGHT", CharacterMicroButton, "BOTTOMLEFT", -4 / 0.6, -8 / 0.6)
end
hooksecurefunc("UIParent_ManageFramePositions", tutorialAlert)
TutorialFrameAlertButton:HookScript("OnShow", tutorialAlert)
hooksecurefunc("MultiActionBar_Update", place)

-- Bars 6-8 on and off (from the Action Bars options); out of combat, as the bars are protected. Place is
-- for Edit Mode (bars put back after a reset).
WotlkHD_ActionBars = {extra = EXTRA, Place = place}
function WotlkHD_ActionBars.SetShown(number, on)
    WotlkHD_Saved.actionBars = WotlkHD_Saved.actionBars or {}
    WotlkHD_Saved.actionBars[number] = on or nil
    place()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        WotlkHD_Saved = WotlkHD_Saved or {}
        setup()
        statusBars()
    elseif pending then
        place()
    end
end)

-- [[ UI scale ]] --
-- With Use UI Scale off, retail draws the UI at the screen's own pixels (768 / screen height: about 0.53
-- at 1440); 3.3.5 draws it at 1.0. UIParent's scale is a widget value, read untainted by the client.
local function uiScale()
    if GetCVar("useUiScale") == "1" then
        return
    end
    local h = tonumber(strmatch(({GetScreenResolutions()})[GetCurrentResolution()] or "", "%d+x(%d+)"))
    if h and h > 768 then
        UIParent:SetScale(768 / h)
    end
end
local scale = CreateFrame("Frame")
scale:RegisterEvent("PLAYER_ENTERING_WORLD")
scale:RegisterEvent("DISPLAY_SIZE_CHANGED")
scale:RegisterEvent("CVAR_UPDATE")
scale:SetScript("OnEvent", uiScale)
