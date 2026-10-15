-- wotlk-hd: retail's action bars (Dragonflight's UI-HUD-ActionBar art, from Blizzard_ActionBar's
-- ActionButtonTemplate.xml and MainActionBar.xml) on the client's bars: retail's icon frame, pressed and
-- mouseover art and slot on every button; the main bar without its stone background, with retail's
-- gryphons (wyverns for the Horde) and page arrows; the micro menu and bag buttons at the bottom right in
-- retail's art. The buttons keep their place for now (Edit Mode will move them); only art and unprotected
-- frames change, so nothing here is blocked in combat.

local ATLAS = WotlkHD_Atlas
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

-- Gryphons, or wyverns for the Horde, flank the twelve buttons, at retail's place for 45 pixel buttons
-- scaled to the client's 36.
local SCALE = 36 / 45
local beast = UnitFactionGroup("player") == "Horde" and "Wyvern" or "Gryphon"
local left, right = MainMenuBarLeftEndCap, MainMenuBarRightEndCap
left:SetAtlas("UI-HUD-ActionBar-" .. beast .. "-Left")
right:SetAtlas("UI-HUD-ActionBar-" .. beast .. "-Right")
for _, cap in ipairs({left, right}) do
    cap:SetWidth(104.5 * SCALE)
    cap:SetHeight(98 * SCALE)
    cap:ClearAllPoints()
end
left:SetPoint("BOTTOMRIGHT", ActionButton1, "BOTTOMLEFT", (9 - 21) * SCALE, -22 * SCALE)
right:SetPoint("BOTTOMLEFT", ActionButton12, "BOTTOMRIGHT", -8 * SCALE, -22 * SCALE)

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
ActionBarUpButton:SetPoint("CENTER", ActionButton1, "LEFT", -12, 10)
ActionBarDownButton:SetPoint("CENTER", ActionButton1, "LEFT", -12, -10)
MainMenuBarPageNumber:ClearAllPoints()
MainMenuBarPageNumber:SetPoint("CENTER", ActionButton1, "LEFT", -12, 0)

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
-- Retail's: the main bar centered at the bottom with the experience and reputation bars under it, the
-- bottom bars stacked above it, stance and pet bars above those, bars 4 and 5 on the right (the client's),
-- bars 6-8 in the middle of the screen.
--
-- The main bar's buttons move into our own secure bar (as Dominos and Bartender did), which pages them
-- with a state driver: secure, so stances, forms, paging and possess switch in combat. The client's
-- bonus bar (its stance overlay) goes under a hidden parent. The other bars stay the client's frames,
-- placed again after its layout code (UIParent_ManageFramePositions) runs, out of combat only: they're
-- protected, so one the client moves in combat (a pet summoned mid-fight) comes back when it ends.

local BUTTON, GAP = 36, 6
local WIDTH = NUM_ACTIONBAR_BUTTONS * BUTTON + (NUM_ACTIONBAR_BUTTONS - 1) * GAP
local XP_HEIGHT, REP_HEIGHT, BOTTOM = 10, 8, 4
local MAIN_Y = BOTTOM + XP_HEIGHT + 2 + REP_HEIGHT + 6

local main = CreateFrame("Frame", "WotlkHDMainBar", UIParent, "SecureHandlerStateTemplate")
main:SetWidth(WIDTH)
main:SetHeight(BUTTON)
main:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, MAIN_Y)
-- Possess first, then the pages (Shift+number, the page arrows), then the stances and forms, as the
-- client's own ActionButton_CalculateAction orders them.
local PAGING = "[bonusbar:5]11;[bar:2]2;[bar:3]3;[bar:4]4;[bar:5]5;[bar:6]6;"
    .. "[bonusbar:1]7;[bonusbar:2]8;[bonusbar:3]9;[bonusbar:4]10;1"
main:SetAttribute("_onstate-page", [[
    for _, button in ipairs(newtable(self:GetChildren())) do
        button:SetAttribute("actionpage", tonumber(newstate))
    end
]])

-- Bars 6-8 on slots no bar of the client's uses: page 2 (13-24, the client's Shift+2 page), page 12
-- (133-144: the server keeps 144 slots, the client uses 132), and page 10 (109-120, a stance page no
-- class but the druid's moonkin uses).
local EXTRA = {{6, 2}, {7, 12}}
if select(2, UnitClass("player")) ~= "DRUID" then
    tinsert(EXTRA, {8, 10})
end
local extra = {}
for _, e in ipairs(EXTRA) do
    local bar = CreateFrame("Frame", "WotlkHDBar" .. e[1], UIParent, "SecureHandlerStateTemplate")
    bar:SetWidth(WIDTH)
    bar:SetHeight(BUTTON)
    bar:SetAttribute("actionpage", e[2])
    for i = 1, NUM_ACTIONBAR_BUTTONS do
        local b = CreateFrame("CheckButton", "WotlkHDBar" .. e[1] .. "Button" .. i, bar, "ActionBarButtonTemplate")
        b:SetID(i)
        b.buttonType = "WOTLKHDBAR" .. e[1] .. "BUTTON" -- no bindings yet: no hotkey text
        ActionButton_UpdateHotkeys(b, b.buttonType)
        b:SetPoint("BOTTOMLEFT", (i - 1) * (BUTTON + GAP), 0)
        skin(b)
    end
    bar.number = e[1]
    extra[#extra + 1] = bar
    RegisterStateDriver(bar, "visibility", "[vehicleui] hide; show")
end

-- Bars 2 and 3 likewise: the client's layout code anchors them 17 above the first main button, also in
-- combat, so their buttons go into our bars (with the client's pages), shown when the client's bar is.
local bottom = {}
for i, e in ipairs({{MultiBarBottomLeft, "MultiBarBottomLeftButton"}, {MultiBarBottomRight, "MultiBarBottomRightButton"}}) do
    local bar = CreateFrame("Frame", "WotlkHDBar" .. (i + 1), UIParent, "SecureHandlerStateTemplate")
    bar:SetWidth(WIDTH)
    bar:SetHeight(BUTTON)
    bar:SetAttribute("actionpage", e[1]:GetAttribute("actionpage"))
    bar.client, bar.buttons = e[1], e[2]
    bottom[i] = bar
end

local function bottomButtons()
    for _, bar in ipairs(bottom) do
        for i = 1, NUM_ACTIONBAR_BUTTONS do
            local b = _G[bar.buttons .. i]
            b:SetParent(bar)
            b:ClearAllPoints()
            b:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", (i - 1) * (BUTTON + GAP), 0)
        end
    end
end

-- The stance buttons in our own secure bar too: the client's layout code moves its stance bar, and in
-- combat (forms change it) only its code may, so ours would jump until combat ended.
local stance = CreateFrame("Frame", "WotlkHDStanceBar", UIParent, "SecureHandlerStateTemplate")
stance:SetWidth(NUM_SHAPESHIFT_SLOTS * 38)
stance:SetHeight(30)

local function stanceButtons()
    if InCombatLockdown() then
        return
    end
    for i = 1, NUM_SHAPESHIFT_SLOTS do
        local b = _G["ShapeshiftButton" .. i]
        b:SetParent(stance)
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", stance, "BOTTOMLEFT", (i - 1) * 38, 0)
    end
end
-- With one form the client anchors the first button to its own bar again.
hooksecurefunc("ShapeshiftBar_Update", stanceButtons)

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
    local top = main
    for _, bar in ipairs(bottom) do
        bar:ClearAllPoints()
        bar:SetPoint("BOTTOMLEFT", top, "TOPLEFT", 0, GAP)
        if bar.client:IsShown() then -- the client's option for the bar
            RegisterStateDriver(bar, "visibility", "[vehicleui] hide; show")
            top = bar
        else
            RegisterStateDriver(bar, "visibility", "hide")
        end
    end
    -- Bars 6-8 stack in the middle of the screen, a little below center, as retail places them.
    local below
    for _, bar in ipairs(extra) do
        bar:ClearAllPoints()
        if below then
            bar:SetPoint("BOTTOMLEFT", below, "TOPLEFT", 0, GAP)
        else
            bar:SetPoint("BOTTOM", UIParent, "CENTER", 0, -100)
        end
        if (WotlkHD_Saved and WotlkHD_Saved.actionBars or {})[bar.number] then
            RegisterStateDriver(bar, "visibility", "[vehicleui] hide; show")
            below = bar
        else
            RegisterStateDriver(bar, "visibility", "hide")
        end
    end
    stance:ClearAllPoints()
    stance:SetPoint("BOTTOMLEFT", top, "TOPLEFT", 0, GAP)
    for _, bar in ipairs({PossessBarFrame, MultiCastActionBarFrame}) do
        bar:ClearAllPoints()
        bar:SetPoint("BOTTOMLEFT", top, "TOPLEFT", -8, GAP - 2)
    end
    PetActionBarFrame:ClearAllPoints()
    PetActionBarFrame:SetPoint("BOTTOMRIGHT", top, "TOPRIGHT", 0, GAP - 2)
end

local function setup()
    if InCombatLockdown() then
        return
    end
    for i = 1, NUM_ACTIONBAR_BUTTONS do
        local b = _G["ActionButton" .. i]
        b:SetParent(main)
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", main, "BOTTOMLEFT", (i - 1) * (BUTTON + GAP), 0)
        -- Empty slots show, as on retail (3.3.5 drew them in the main bar's art and hid the buttons;
        -- dragging adds to showgrid and takes it off again, so 1 stays).
        b:SetAttribute("showgrid", 1)
        b:Show()
    end
    for _, bar in ipairs(extra) do
        for i = 1, NUM_ACTIONBAR_BUTTONS do
            _G[bar:GetName() .. "Button" .. i]:SetAttribute("showgrid", 1)
            _G[bar:GetName() .. "Button" .. i]:Show()
        end
    end
    BonusActionBarFrame:SetParent(hidden)
    stanceButtons()
    bottomButtons()
    RegisterStateDriver(stance, "visibility", "[vehicleui][bonusbar:5] hide; show")
    RegisterStateDriver(main, "page", PAGING)
    RegisterStateDriver(main, "visibility", "[vehicleui] hide; show")
    place()
end

-- Experience and reputation: thin bars under the main bar, as wide as it.
local function statusBars()
    MainMenuExpBar:ClearAllPoints()
    MainMenuExpBar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, BOTTOM)
    MainMenuExpBar:SetWidth(WIDTH)
    MainMenuExpBar:SetHeight(XP_HEIGHT)
    if ReputationWatchBar:IsShown() then
        ReputationWatchBar:ClearAllPoints()
        ReputationWatchBar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0,
            MainMenuExpBar:IsShown() and BOTTOM + XP_HEIGHT + 2 or BOTTOM)
        ReputationWatchBar:SetWidth(WIDTH)
        ReputationWatchStatusBar:SetWidth(WIDTH)
        ReputationWatchBar:SetHeight(REP_HEIGHT)
        ReputationWatchStatusBar:SetHeight(REP_HEIGHT)
    end
end
for _, bar in ipairs({MainMenuExpBar, ReputationWatchStatusBar}) do
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", -1, 1)
    bg:SetPoint("BOTTOMRIGHT", 1, -1)
    bg:SetTexture(0, 0, 0, 0.7)
end
hooksecurefunc("ReputationWatchBar_Update", statusBars)
hooksecurefunc("MainMenuExpBar_Update", statusBars)

hooksecurefunc("UIParent_ManageFramePositions", place)
hooksecurefunc("MultiActionBar_Update", place)

-- Bars 6-8 on and off (from the Action Bars options); out of combat, as the bars are protected.
WotlkHD_ActionBars = {extra = EXTRA}
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
