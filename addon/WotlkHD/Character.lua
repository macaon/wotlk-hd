-- wotlk-hd: retail's character window (Blizzard_UIPanels_Game, mainline CharacterFrame and PaperDollFrame)
-- on the Character tab: the metal frame with the portrait, the name and a class coloured level line,
-- retail's slot columns around a taller model on its race backdrop, and retail's stats pane (item level,
-- attributes, enhancements) with the sidebar tabs for stats, titles and the equipment manager. The tabs
-- under the frame get retail's art on every tab; the other tabs keep 3.3.5's frames for now.
--
-- The client's slots, model, title picker and equipment manager are moved, not replaced; none of them
-- is protected. While the Character tab shows, CharacterFrame takes retail's size so the panel layout
-- (which reads its width) leaves room for it.

local Retail = WotlkHD_Retail
local W, H = 540, 424 -- retail's CHARACTERFRAME_EXPANDED_WIDTH and height
local LEFT, TOP = 16, -12 -- the frame inside CharacterFrame, clear of the screen edge
local PARTS = "Interface\\AddOns\\WotlkHD\\Art\\char-paperdoll-parts"
local SIDEBAR = "Interface\\AddOns\\WotlkHD\\Art\\paperdollsidebartabs"

-- [[ The frame ]] --
-- Its own frame under PaperDollFrame, at CharacterFrame's level so the slots and model draw over it.
local f = CreateFrame("Frame", "WotlkHDCharacterFrame", PaperDollFrame)
f:SetWidth(W)
f:SetHeight(H)
f:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", LEFT, TOP)
f:SetFrameLevel(CharacterFrame:GetFrameLevel())
local bg = f:CreateTexture(nil, "BACKGROUND", nil)
bg:SetTexture(0x1f / 255, 0x1e / 255, 0x21 / 255, 1)
bg:SetPoint("TOPLEFT", 2, -2)
bg:SetPoint("BOTTOMRIGHT", -2, 2)
local inset = f:CreateTexture(nil, "BORDER")
inset:SetAtlas("character-panel-background")
inset:SetPoint("TOPLEFT", 4, -60)
inset:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", 332, 4)
local border, portrait = Retail.MetalFrame(f, true)

-- Text on its own frame over the border, whose top edge shares the OVERLAY layer and can draw over it.
local text = CreateFrame("Frame", nil, border)
text:SetAllPoints()
text:SetFrameLevel(border:GetFrameLevel() + 1)
local title = text:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
title:SetPoint("TOP", 17, -5) -- centered between the portrait and the close button, as retail's
title:SetWidth(W - 82)
title:SetHeight(13)
local level = text:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
level:SetPoint("CENTER", f, "TOP", 0, -42)

local close = CreateFrame("Button", nil, border)
close:SetWidth(24)
close:SetHeight(24)
close:SetPoint("TOPRIGHT", 1, 0)
for _, t in ipairs({{"SetNormalTexture", "GetNormalTexture", "RedButton-Exit"},
    {"SetPushedTexture", "GetPushedTexture", "RedButton-exit-pressed"},
    {"SetHighlightTexture", "GetHighlightTexture", "RedButton-Highlight"}}) do
    close[t[1]](close, WotlkHD_Atlas[strlower(t[3])][1])
    close[t[2]](close):SetAtlas(t[3])
end
close:SetScript("OnClick", function() HideUIPanel(CharacterFrame) end)

local statsIcon -- the sidebar's stats tab shows the portrait too (below)
local function header()
    SetPortraitTexture(portrait, "player")
    if statsIcon then
        SetPortraitTexture(statsIcon, "player")
    end
    title:SetText(UnitPVPName("player"))
    local _, class = UnitClass("player")
    local c = RAID_CLASS_COLORS[class]
    level:SetFormattedText("%s %d |cff%02x%02x%02x%s|r", LEVEL, UnitLevel("player"), c.r * 255, c.g * 255,
        c.b * 255, UnitClass("player"))
end

-- [[ Slots ]] --
-- Retail's columns down the inset's sides and the weapons centered under the model; 3.3.5's ranged slot
-- joins them (three centered) and its ammo slot stays right of it. Each gets retail's slot frame.
CharacterHeadSlot:ClearAllPoints()
CharacterHeadSlot:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -62)
CharacterHandsSlot:ClearAllPoints()
CharacterHandsSlot:SetPoint("TOPLEFT", f, "TOPLEFT", 291, -62)
CharacterMainHandSlot:ClearAllPoints()
CharacterMainHandSlot:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 108, 16)

local function slotArt(slot, w, h, l, r, t, b, point, x, y)
    local a = slot:CreateTexture(nil, "BACKGROUND", nil)
    a:SetTexture(PARTS)
    a:SetTexCoord(l, r, t, b)
    a:SetWidth(w)
    a:SetHeight(h)
    a:SetPoint(point, slot, point, x, y)
end
for _, s in ipairs({"Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist"}) do
    slotArt(_G["Character" .. s .. "Slot"], 49, 44, .20703125, .3984375, .59375, .9375, "TOPLEFT", -4, 0)
end
for _, s in ipairs({"Hands", "Waist", "Legs", "Feet", "Finger0", "Finger1", "Trinket0", "Trinket1"}) do
    slotArt(_G["Character" .. s .. "Slot"], 50, 44, .00390625, .19921875, .59375, .9375, "TOPRIGHT", 4, 0)
end
for _, s in ipairs({"MainHand", "SecondaryHand", "Ranged"}) do
    slotArt(_G["Character" .. s .. "Slot"], 42, 53, .671875, .8359375, .0078125, .421875, "TOPLEFT", -4, 8)
end

-- [[ Model ]] --
-- Retail's taller model on the race's dressing room backdrop, desaturated and darkened as retail's.
CharacterModelFrame:ClearAllPoints()
CharacterModelFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 52, -66)
CharacterModelFrame:SetWidth(231)
CharacterModelFrame:SetHeight(320)
CharacterModelFrameRotateLeftButton:ClearAllPoints()
CharacterModelFrameRotateLeftButton:SetPoint("TOPRIGHT", CharacterModelFrame, "TOP", -2, -4)
CharacterModelFrameRotateRightButton:ClearAllPoints()
CharacterModelFrameRotateRightButton:SetPoint("TOPLEFT", CharacterModelFrame, "TOP", 2, -4)

local DARKEN = {BloodElf = .8, NightElf = .6, Scourge = .3, Troll = .6, Orc = .6}
local backdrop = {}
-- (layers: the inset BORDER, the backdrop ARTWORK, its shade OVERLAY; the model is a frame above)
local BACKDROP = { -- retail's pieces (212+19 wide, 245+128 tall), fitted to the inset's height
    {"TOPLEFT", 0, 0, 212, 234}, {"TOPLEFT", 212, 0, 19, 234},
    {"TOPLEFT", 0, -234, 212, 122}, {"TOPLEFT", 212, -234, 19, 122},
}
for i, p in ipairs(BACKDROP) do
    local t = f:CreateTexture(nil, "ARTWORK")
    t:SetPoint(p[1], f, "TOPLEFT", 52 + p[2], -62 + p[3])
    t:SetWidth(p[4])
    t:SetHeight(p[5])
    backdrop[i] = t
end
local shade = f:CreateTexture(nil, "OVERLAY")
shade:SetPoint("TOPLEFT", backdrop[1])
shade:SetPoint("BOTTOMRIGHT", backdrop[4])
local function race()
    local _, file = UnitRace("player")
    for i, t in ipairs(backdrop) do
        t:SetTexture("Interface\\DressUpFrame\\DressUpBackground-" .. file .. i)
        t:SetDesaturated(true)
    end
    shade:SetTexture(0, 0, 0, DARKEN[file] or .7)
end

-- [[ Stats ]] --
-- Retail's pane right of the inset on the class's backdrop: Item Level, then Attributes and
-- Enhancements in rows striped as retail's. 3.3.5 has no mastery or versatility; enhancements are
-- the role's (spell, melee or ranged) with defence added for tanks.
local pane = CreateFrame("Frame", nil, f)
pane:SetPoint("TOPLEFT", f, "TOPLEFT", 336, -63)
pane:SetWidth(197)
pane:SetHeight(355)
local classBg = pane:CreateTexture(nil, "BACKGROUND")
classBg:SetPoint("TOPLEFT")
classBg:SetWidth(197)
classBg:SetHeight(355)

local headers, rows = {}, {}
local function headerFrame(i)
    local h = headers[i]
    if not h then
        h = CreateFrame("Frame", nil, pane)
        h:SetWidth(197)
        h:SetHeight(40)
        local t = h:CreateTexture(nil, "BACKGROUND")
        t:SetAtlas("UI-Character-Info-Title", true)
        t:SetPoint("TOPLEFT")
        h.text = h:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        h.text:SetPoint("CENTER", 0, 1)
        headers[i] = h
    end
    return h
end
local function rowFrame(i)
    local r = rows[i]
    if not r then
        r = CreateFrame("Frame", nil, pane)
        r:SetWidth(187)
        r:SetHeight(15)
        r.stripe = r:CreateTexture(nil, "BACKGROUND")
        r.stripe:SetAtlas("UI-Character-Info-Line-Bounce", true)
        r.stripe:SetAlpha(.3)
        r.stripe:SetPoint("CENTER")
        r.label = r:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        r.label:SetPoint("LEFT", 11, 0)
        r.value = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        r.value:SetPoint("RIGHT", -8, 0)
        rows[i] = r
    end
    return r
end

local ilvlBox = CreateFrame("Frame", nil, pane)
ilvlBox:SetWidth(187)
ilvlBox:SetHeight(29)
local ilvlBounce = ilvlBox:CreateTexture(nil, "BACKGROUND")
ilvlBounce:SetAtlas("UI-Character-Info-ItemLevel-Bounce", true)
ilvlBounce:SetAlpha(.3)
ilvlBounce:SetPoint("CENTER")
local ilvlText = ilvlBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
ilvlText:SetPoint("CENTER", 0, -1)

-- Average item level over the 17 slots that hold gear (shirt, tabard and ammo left out), a two-hander
-- counting for both hands; an item the client hasn't cached yet counts 0 until the next update.
local function itemLevel()
    local total = 0
    for slot = 1, 18 do
        if slot ~= 4 then
            local link = GetInventoryItemLink("player", slot)
            local _, _, _, ilvl, _, _, _, _, equip = GetItemInfo(link or "")
            if ilvl then
                total = total + ilvl
                if slot == 16 and equip == "INVTYPE_2HWEAPON" and not GetInventoryItemLink("player", 17) then
                    total = total + ilvl
                end
            end
        end
    end
    return math.floor(total / 17)
end

local function pct(x)
    return format("%d%%", math.floor(x + .5))
end
local function role()
    local _, class = UnitClass("player")
    if class == "HUNTER" then
        return "ranged"
    elseif class == "MAGE" or class == "PRIEST" or class == "WARLOCK" then
        return "spell"
    end
    local base, pos, neg = UnitAttackPower("player")
    local spell = 0
    for school = 2, 7 do
        spell = math.max(spell, GetSpellBonusDamage(school))
    end
    if UnitPowerType("player") == 0 and math.max(spell, GetSpellBonusHealing()) > base + pos + neg then
        return "spell"
    end
    return "melee"
end
local function tank()
    local offhand = GetInventoryItemLink("player", 17)
    local shield = offhand and select(9, GetItemInfo(offhand)) == "INVTYPE_SHIELD"
    return GetCombatRating(CR_DEFENSE_SKILL) > 0 or (shield and select(2, UnitClass("player")) ~= "SHAMAN")
end

local function stats()
    local attributes = {}
    for i = 1, 5 do
        local _, stat = UnitStat("player", i)
        attributes[#attributes + 1] = {_G["SPELL_STAT" .. i .. "_NAME"], stat}
    end
    local _, armor = UnitArmor("player")
    attributes[#attributes + 1] = {ARMOR, armor}

    local e, r = {}, role()
    if r == "spell" then
        local power, crit = 0, 0
        for school = 2, 7 do
            power = math.max(power, GetSpellBonusDamage(school))
            crit = math.max(crit, GetSpellCritChance(school))
        end
        e[#e + 1] = {ITEM_MOD_SPELL_POWER_SHORT or "Spell Power", math.max(power, GetSpellBonusHealing())}
        e[#e + 1] = {CRIT_ABBR or "Crit", pct(crit)}
        e[#e + 1] = {SPELL_HASTE_ABBR or "Haste", pct(GetCombatRatingBonus(CR_HASTE_SPELL))}
        e[#e + 1] = {COMBAT_RATING_NAME8 or "Hit", pct(GetCombatRatingBonus(CR_HIT_SPELL))}
        local base, casting = GetManaRegen() -- per second; retail shows the combat rate in combat
        local regen = UnitAffectingCombat("player") and casting or base
        e[#e + 1] = {ITEM_MOD_MANA_REGENERATION_SHORT or "Mana Regen", math.floor(regen * 5 + .5)}
    elseif r == "ranged" then
        local base, pos, neg = UnitRangedAttackPower("player")
        e[#e + 1] = {ITEM_MOD_RANGED_ATTACK_POWER_SHORT or "Attack Power", base + pos + neg}
        e[#e + 1] = {CRIT_ABBR or "Crit", pct(GetRangedCritChance())}
        e[#e + 1] = {SPELL_HASTE_ABBR or "Haste", pct(GetCombatRatingBonus(CR_HASTE_RANGED))}
        e[#e + 1] = {COMBAT_RATING_NAME8 or "Hit", pct(GetCombatRatingBonus(CR_HIT_RANGED))}
    else
        local base, pos, neg = UnitAttackPower("player")
        e[#e + 1] = {ITEM_MOD_ATTACK_POWER_SHORT or "Attack Power", base + pos + neg}
        e[#e + 1] = {CRIT_ABBR or "Crit", pct(GetCritChance())}
        e[#e + 1] = {SPELL_HASTE_ABBR or "Haste", pct(GetCombatRatingBonus(CR_HASTE_MELEE))}
        e[#e + 1] = {COMBAT_RATING_NAME8 or "Hit", pct(GetCombatRatingBonus(CR_HIT_MELEE))}
        e[#e + 1] = {STAT_EXPERTISE or "Expertise", (GetExpertise())}
    end
    local arp = GetCombatRatingBonus(CR_ARMOR_PENETRATION)
    if r ~= "spell" and arp > 0 then
        e[#e + 1] = {ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT or "Armor Penetration", pct(arp)}
    end
    if tank() then
        local base, mod = UnitDefense("player")
        e[#e + 1] = {DEFENSE, base + mod}
        e[#e + 1] = {STAT_DODGE or DODGE, pct(GetDodgeChance())}
        e[#e + 1] = {STAT_PARRY or PARRY, pct(GetParryChance())}
        if GetBlockChance() > 0 then
            e[#e + 1] = {STAT_BLOCK or BLOCK, pct(GetBlockChance())}
        end
    end
    local resilience = GetCombatRating(CR_CRIT_TAKEN_MELEE)
    if resilience > 0 then
        e[#e + 1] = {STAT_RESILIENCE or "Resilience", resilience}
    end
    return {{STAT_CATEGORY_ATTRIBUTES or "Attributes", attributes},
        {STAT_CATEGORY_ENHANCEMENTS or "Enhancements", e}}
end

local function update()
    if not f:IsVisible() then
        return
    end
    header()
    local _, class = UnitClass("player")
    classBg:SetAtlas("UI-Character-Info-" .. class .. "-BG")
    local h = headerFrame(1)
    h:SetPoint("TOP", pane, "TOP", 0, -2)
    h.text:SetText(STAT_AVERAGE_ITEM_LEVEL or "Item Level")
    ilvlBox:SetPoint("TOP", h, "BOTTOM")
    ilvlText:SetText(itemLevel())
    local below, n = ilvlBox, 0
    for c, category in ipairs(stats()) do
        h = headerFrame(c + 1)
        h:SetPoint("TOP", below, "BOTTOM")
        h.text:SetText(category[1])
        below = h
        for i, stat in ipairs(category[2]) do
            n = n + 1
            local r = rowFrame(n)
            r:SetPoint("TOP", below, "BOTTOM", 0, i == 1 and -2 or 0)
            r.label:SetFormattedText(STAT_FORMAT or "%s:", stat[1])
            r.value:SetText(stat[2])
            if i % 2 == 0 then
                r.stripe:Show()
            else
                r.stripe:Hide()
            end
            r:Show()
            below = r
        end
    end
    for i = n + 1, #rows do
        rows[i]:Hide()
    end
end

-- [[ Sidebar tabs ]] --
-- Retail's three tabs over the pane: stats, titles (3.3.5's title picker in the pane's place) and the
-- equipment manager (its dialog beside the frame), the last only with the Equipment Manager option on.
local sidebar = CreateFrame("Frame", nil, f)
sidebar:SetWidth(168)
sidebar:SetHeight(35)
sidebar:SetPoint("BOTTOMRIGHT", f, "TOPLEFT", 530, -61)
local tabs = {}
local selected = 1
local function sidebarTab(i, icon)
    local t = CreateFrame("Button", nil, sidebar)
    t:SetWidth(33)
    t:SetHeight(35)
    t.bg = t:CreateTexture(nil, "BACKGROUND")
    t.bg:SetTexture(SIDEBAR)
    t.bg:SetWidth(50)
    t.bg:SetHeight(43)
    t.bg:SetPoint("BOTTOMLEFT", -9, -2)
    t.icon = t:CreateTexture(nil, "ARTWORK")
    icon(t.icon)
    t.hider = t:CreateTexture(nil, "OVERLAY")
    t.hider:SetTexture(SIDEBAR)
    t.hider:SetTexCoord(.015625, .546875, .11328125, .1875)
    t.hider:SetWidth(34)
    t.hider:SetHeight(19)
    t.hider:SetPoint("BOTTOM")
    local lit = t:CreateTexture(nil, "HIGHLIGHT")
    lit:SetTexture(SIDEBAR)
    lit:SetTexCoord(.015625, .5, .1953125, .31640625)
    lit:SetWidth(31)
    lit:SetHeight(31)
    lit:SetPoint("TOPLEFT", 2, -3)
    tabs[i] = t
    return t
end
local function sidebarIcon(l, r, t, b)
    return function(tex)
        tex:SetTexture(SIDEBAR)
        tex:SetTexCoord(l, r, t, b)
        tex:SetWidth(33)
        tex:SetHeight(35)
        tex:SetPoint("BOTTOM", 1, -2)
    end
end
local statsTab = sidebarTab(1, function(tex)
    tex:SetWidth(29)
    tex:SetHeight(31)
    tex:SetPoint("BOTTOM", 1, 0)
    tex:SetTexCoord(.109375, .890625, .09375, .90625)
    statsIcon = tex
end)
local titlesTab = sidebarTab(2, sidebarIcon(.015625, .53125, .32421875, .4609375))
local gearTab = sidebarTab(3, sidebarIcon(.015625, .53125, .46875, .60546875))
gearTab:SetPoint("BOTTOMRIGHT", -30, 0)
titlesTab:SetPoint("RIGHT", gearTab, "LEFT", -4, 0)
statsTab:SetPoint("RIGHT", titlesTab, "LEFT", -4, 0)

local function selectTab(i)
    selected = i
    for n, t in ipairs(tabs) do
        if n == i then
            t.bg:SetTexCoord(.015625, .796875, .7890625, .95703125)
            t.hider:Hide()
        else
            t.bg:SetTexCoord(.015625, .796875, .61328125, .78125)
            t.hider:Show()
        end
    end
    if i == 1 then
        pane:Show()
    else
        pane:Hide()
    end
    if i == 2 then
        PlayerTitleFrame_UpdateTitles()
        PlayerTitlePickerFrame:ClearAllPoints()
        PlayerTitlePickerFrame:SetPoint("TOPLEFT", pane, "TOPLEFT", -3, 3)
        PlayerTitlePickerFrame:Show()
    else
        PlayerTitlePickerFrame:Hide()
    end
    if i == 3 then
        GearManagerDialog:ClearAllPoints()
        GearManagerDialog:SetPoint("TOPLEFT", f, "TOPRIGHT", 0, 0)
        GearManagerDialog:Show()
    else
        GearManagerDialog:Hide()
    end
    update()
end
statsTab:SetScript("OnClick", function() selectTab(1) end)
titlesTab:SetScript("OnClick", function() selectTab(2) end)
gearTab:SetScript("OnClick", function() selectTab(selected == 3 and 1 or 3) end)
-- Picking a title closes the picker; back to stats then, as retail stays on its list (ours is a popup).
PlayerTitlePickerFrame:HookScript("OnHide", function()
    if selected == 2 and f:IsVisible() then
        selectTab(1)
    end
end)
GearManagerDialog:HookScript("OnHide", function()
    if selected == 3 and f:IsVisible() then
        selectTab(1)
    end
end)

-- [[ Bottom tabs ]] --
-- Retail's tab art (PanelTabButtonTemplate) on 3.3.5's tab regions: Left/Middle/Right are the unselected
-- art, the Disabled ones the selected; the client's PanelTemplates show one set or the other. Retail's
-- tabs are text + 20 wide and 1 apart.
local NUM_TABS = 5
local function tabArt(tab, suffix, kind, l, r)
    local name = tab:GetName()
    local left, middle, right = _G[name .. "Left" .. suffix], _G[name .. "Middle" .. suffix], _G[name .. "Right" .. suffix]
    left:SetAtlas("uiframe-" .. kind .. "-left", true)
    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", tab, "TOPLEFT", l, 0)
    right:SetAtlas("uiframe-" .. kind .. "-right", true)
    right:ClearAllPoints()
    right:SetPoint("TOPRIGHT", tab, "TOPRIGHT", r, 0)
    middle:SetAtlas("_uiframe-" .. kind .. "-center")
    middle:ClearAllPoints()
    middle:SetPoint("TOPLEFT", left, "TOPRIGHT")
    middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
end
for i = 1, NUM_TABS do
    local tab = _G["CharacterFrameTab" .. i]
    tabArt(tab, "", "tab", -3, 7)
    tabArt(tab, "Disabled", "activetab", -1, 8)
    local lit = _G[tab:GetName() .. "HighlightTexture"]
    lit:SetAtlas("_uiframe-tab-center")
    lit:ClearAllPoints()
    lit:SetPoint("TOPLEFT", tab, "TOPLEFT", 4, 0)
    lit:SetPoint("BOTTOMRIGHT", tab, "TOPRIGHT", -4, -36)
    lit:SetAlpha(.4)
end
local function tabWidth(tab)
    if tab:GetName() and tab:GetName():find("^CharacterFrameTab") then
        local text = _G[tab:GetName() .. "Text"]
        tab:SetWidth(math.max(text:GetStringWidth() + 20, 72))
    end
end
hooksecurefunc("PanelTemplates_TabResize", tabWidth)
local function tabText(tab, selectedTab)
    if tab:GetName() and tab:GetName():find("^CharacterFrameTab") then
        local text = _G[tab:GetName() .. "Text"]
        text:ClearAllPoints()
        text:SetPoint("CENTER", 0, selectedTab and -3 or 2)
    end
end
hooksecurefunc("PanelTemplates_SelectTab", function(tab) tabText(tab, true) end)
hooksecurefunc("PanelTemplates_DeselectTab", function(tab) tabText(tab, false) end)

local tab1Point = {CharacterFrameTab1:GetPoint(1)}
local function chainTabs()
    local prev = CharacterFrameTab1
    for i = 2, NUM_TABS do
        local tab = _G["CharacterFrameTab" .. i]
        if tab:IsShown() then
            tab:ClearAllPoints()
            tab:SetPoint("TOPLEFT", prev, "TOPRIGHT", 1, 0)
            prev = tab
        end
    end
end
hooksecurefunc("PetPaperDollFrame_UpdateIsAvailable", chainTabs)
for i = 2, NUM_TABS do
    _G["CharacterFrameTab" .. i]:HookScript("OnShow", chainTabs)
    _G["CharacterFrameTab" .. i]:HookScript("OnHide", chainTabs)
end

-- [[ Showing ]] --
-- The Character tab takes CharacterFrame at retail's size, its own portrait, name and close button, and
-- the tabs under it; the other tabs get 3.3.5's back. The size stays when the window closes, so the
-- panel layout places other windows beside it right when it opens again on this tab.
for _, r in ipairs({PaperDollFrame:GetRegions()}) do
    if r:GetObjectType() == "Texture" and (r:GetTexture() or ""):find("UI%-Character%-CharacterTab") then
        r:Hide()
    end
end
local hidden = CreateFrame("Frame")
hidden:Hide()
for _, r in ipairs({PlayerTitleFrame, CharacterAttributesFrame, CharacterResistanceFrame,
    GearManagerToggleButton}) do
    r:SetParent(hidden)
end
CharacterLevelText:SetAlpha(0)
CharacterGuildText:SetAlpha(0)

local SHARED = {CharacterFramePortrait, CharacterNameFrame, CharacterFrameCloseButton}
local tab1Point = {CharacterFrameTab1:GetPoint(1)}
local function retailSize(on)
    if on then
        CharacterFrame:SetWidth(W + LEFT)
        CharacterFrame:SetHeight(H - TOP)
        CharacterFrame:SetHitRectInsets(0, 0, 0, 0)
        CharacterFrameTab1:ClearAllPoints()
        CharacterFrameTab1:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 11, 2)
    else
        CharacterFrame:SetWidth(384)
        CharacterFrame:SetHeight(512)
        CharacterFrame:SetHitRectInsets(0, 30, 0, 45)
        CharacterFrameTab1:ClearAllPoints()
        CharacterFrameTab1:SetPoint(unpack(tab1Point))
    end
    for _, r in ipairs(SHARED) do
        if on then
            r:Hide()
        else
            r:Show()
        end
    end
end
f:SetScript("OnShow", function()
    retailSize(true)
    chainTabs()
    race()
    if GetCVar("equipmentManager") == "1" then
        gearTab:Show()
    else
        gearTab:Hide()
    end
    selectTab(1)
end)
f:SetScript("OnHide", function()
    PlayerTitlePickerFrame:Hide()
end)
hooksecurefunc("CharacterFrame_ShowSubFrame", function(name)
    if name ~= "PaperDollFrame" then
        retailSize(false)
    end
end)

local events = CreateFrame("Frame", nil, f)
for _, e in ipairs({"UNIT_STATS", "UNIT_AURA", "UNIT_INVENTORY_CHANGED", "COMBAT_RATING_UPDATE",
    "UNIT_ATTACK_POWER", "UNIT_RANGED_ATTACK_POWER", "UNIT_RESISTANCES", "PLAYER_LEVEL_UP",
    "UNIT_PORTRAIT_UPDATE", "UNIT_NAME_UPDATE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED"}) do
    events:RegisterEvent(e)
end
events:SetScript("OnEvent", function(_, _, unit)
    if not unit or unit == "player" or type(unit) ~= "string" then
        update()
    end
end)
