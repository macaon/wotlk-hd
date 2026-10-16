-- wotlk-hd: retail's Map & Quest Log (Blizzard_WorldMap and QuestMapFrame, mainline) on 3.3.5's windowed
-- world map: the metal frame with the quest log book, breadcrumbs over a 697x465 map, and the quest
-- log beside it (zone headers, quests with their objectives, tracking checkboxes, search, the quest's
-- details, a right-click menu), collapsible as retail's; retail's filter button and quest markers (on the
-- map and the rows). The map opens windowed, as retail's does; maximized it is the same map scaled to
-- the screen, as retail's, not 3.3.5's fullscreen map (left as it is for its own toggle).
--
-- The map itself is 3.3.5's: its tiles, quest areas, quest markers and player arrow all sit on
-- WorldMapDetailFrame at the client's windowed scale (WORLDMAP_WINDOWED_SIZE), and WorldMapFrame is
-- scaled up to retail's size around it. Nothing writes WORLDMAP_SETTINGS (the quest tracker reads it),
-- so the client's own placement maths is untouched; our frame and quest log draw at normal scale.

local Retail = WotlkHD_Retail
local CANVAS_W, CANVAS_H = 697, 465 -- retail's map canvas, windowed with the quest log
local TOP = 67 -- retail's TITLE_CANVAS_SPACER_FRAME_HEIGHT
local LOG_W = 333 -- retail's questLogWidth
local TILE = "Interface\\AddOns\\WotlkHD\\Art\\cs_helptextures_tile"
local HELP = "Interface\\AddOns\\WotlkHD\\Art\\cs_helptextures"

local saved -- WotlkHD_Saved.worldMap
local function logShown()
    return not (saved and saved.hideLog)
end

-- [[ The frame ]] --
-- Ours at normal scale on the scaled WorldMapFrame (f's scale cancels WorldMapFrame's). Two borders:
-- retail's PortraitFrameTemplate windowed, ButtonFrameTemplateNoPortrait maximized; the title, buttons,
-- breadcrumbs and menus on one frame (top) over whichever shows.
local f = CreateFrame("Frame", "WotlkHDWorldMap", WorldMapFrame)
f:SetPoint("TOPLEFT")
f:Hide()
local bg = f:CreateTexture(nil, "BACKGROUND")
bg:SetTexture(0x1f / 255, 0x1e / 255, 0x21 / 255, 1)
bg:SetPoint("TOPLEFT", 2, -2)
bg:SetPoint("BOTTOMRIGHT", -2, 2)
local border, portrait = Retail.MetalFrame(f, true)
SetPortraitToTexture(portrait, "Interface\\QuestFrame\\UI-QuestLog-BookIcon")
local plainBorder = Retail.MetalFrame(f, false)
local top = CreateFrame("Frame", nil, f)
top:SetAllPoints()
local title = top:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOP", 0, -5)
local innerTop = top:CreateTexture(nil, "ARTWORK")
innerTop:SetAtlas("_UI-Frame-InnerTopTile")
innerTop:SetHeight(3)

local function redButton(parent, normal, pushed, disabled)
    local b = CreateFrame("Button", nil, parent)
    b:SetWidth(24)
    b:SetHeight(24)
    for _, t in ipairs({{"SetNormalTexture", "GetNormalTexture", normal},
        {"SetPushedTexture", "GetPushedTexture", pushed},
        {"SetHighlightTexture", "GetHighlightTexture", "RedButton-Highlight"},
        {"SetDisabledTexture", "GetDisabledTexture", disabled}}) do
        if t[3] then
            b[t[1]](b, WotlkHD_Atlas[strlower(t[3])][1])
            b[t[2]](b):SetAtlas(t[3])
        end
    end
    return b
end
local close = redButton(top, "RedButton-Exit", "RedButton-exit-pressed")
close:SetPoint("TOPRIGHT", 1, 0)
close:SetScript("OnClick", function() ToggleFrame(WorldMapFrame) end)
-- Retail's maximize and minimize (MaximizeMinimizeButtonFrameTemplate): ours, the same windowed map scaled
-- to the screen (the client's fullscreen map isn't used).
local maximize = redButton(top, "RedButton-Expand", "RedButton-Expand-Pressed", "RedButton-Expand-Disabled")
maximize:SetPoint("RIGHT", close, "LEFT", 1, 0)
local minimize = redButton(top, "RedButton-Condense", "RedButton-Condense-Pressed")
minimize:SetPoint("RIGHT", close, "LEFT", 1, 0)

-- [[ Menus ]] --
-- A plain list for the breadcrumbs, the filter button and quests' right-click menu (UIDropDownMenu would
-- taint the map's own dropdowns). Items: {text, func, checked}; checked nil for a plain entry.
local list = CreateFrame("Frame", nil, top)
list:SetFrameStrata("FULLSCREEN_DIALOG")
list:EnableMouse(false) -- only a background: the entries (level with it at 3.3.5's level cap) take the clicks
list:Hide()
local listBg = list:CreateTexture(nil, "BACKGROUND")
listBg:SetTexture(0, 0, 0, .9)
listBg:SetAllPoints()
local listButtons = {}
local function showMenu(owner, items, point, relPoint, x, y)
    if list:IsShown() and list.owner == owner then
        list:Hide()
        return
    end
    local width = 120
    for i, it in ipairs(items) do
        local item = listButtons[i]
        if not item then
            -- the entry's text, check and highlight on the list itself, over its background whatever
            -- the frame levels (3.3.5 tops out near the map's)
            item = CreateFrame("Button", nil, list)
            item:SetHeight(16)
            item:SetPoint("TOPLEFT", 6, -4 - (i - 1) * 16)
            item:SetPoint("RIGHT", -6, 0)
            item.check = list:CreateTexture(nil, "ARTWORK")
            item.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
            item.check:SetWidth(14)
            item.check:SetHeight(14)
            item.check:SetPoint("LEFT", item)
            item.text = list:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            item.lit = list:CreateTexture(nil, "BORDER")
            item.lit:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            item.lit:SetBlendMode("ADD")
            item.lit:SetAllPoints(item)
            item.lit:Hide()
            item:SetScript("OnEnter", function(self) self.lit:Show() end)
            item:SetScript("OnLeave", function(self) self.lit:Hide() end)
            listButtons[i] = item
        end
        item.text:ClearAllPoints()
        item.text:SetPoint("LEFT", item, "LEFT", it[3] ~= nil and 16 or 0, 0)
        item.text:SetText(it[1])
        if it[3] then
            item.check:Show()
        else
            item.check:Hide()
        end
        item.text:Show()
        item:SetScript("OnClick", function()
            list:Hide()
            it[2]()
        end)
        item:Show()
        width = math.max(width, item.text:GetStringWidth() + (it[3] ~= nil and 16 or 0) + 12)
    end
    for i = #items + 1, #listButtons do
        listButtons[i]:Hide()
        listButtons[i].text:Hide()
        listButtons[i].check:Hide()
    end
    list:SetWidth(width)
    list:SetHeight(#items * 16 + 8)
    list:ClearAllPoints()
    list:SetPoint(point or "TOPLEFT", owner, relPoint or "BOTTOMLEFT", x or 10, y or 0)
    list.owner = owner
    list:Show()
end

-- [[ Breadcrumbs ]] --
-- Retail's NavBar: World, then the continent and zone shown, each a button; the last ones' arrows list
-- the maps beside them.
local nav = CreateFrame("Frame", nil, top)
nav:SetHeight(33)
local navBg = nav:CreateTexture(nil, "BACKGROUND")
navBg:SetTexture(TILE)
navBg:SetTexCoord(0, 1, .1875, .25390625)
navBg:SetAllPoints()
local navOverlay = nav:CreateTexture(nil, "BORDER")
navOverlay:SetTexture(TILE)
navOverlay:SetTexCoord(0, 1, .2578125, .32421875)
navOverlay:SetAllPoints()

local crumbs = {}
local SQUARE = "Interface\\AddOns\\WotlkHD\\Art\\"
-- Retail's NavButtonTemplate: the chevron outside the button's right edge (over the next one, so the
-- buttons to the left sit above), and for a button with a list, its menu arrow button (a small arrow,
-- its square shown on hover) inside the right end.
local function crumb(i)
    local b = crumbs[i]
    if not b then
        b = CreateFrame("Button", nil, nav)
        b:SetHeight(30)
        b:SetNormalTexture(TILE)
        b:GetNormalTexture():SetTexCoord(0, 1, .0625, .12109375)
        b:SetPushedTexture(TILE)
        b:GetPushedTexture():SetTexCoord(0, 1, .125, .18359375)
        b.text = b:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        b.text:SetPoint("LEFT", 20, 0)
        b.chevron = b:CreateTexture(nil, "OVERLAY")
        b.chevron:SetTexture(HELP)
        b.chevron:SetTexCoord(.88867188, .9296875, .296875, .53125)
        b.chevron:SetWidth(21)
        b.chevron:SetHeight(30)
        b.chevron:SetPoint("LEFT", b, "RIGHT")
        b:SetScript("OnMouseDown", function(self)
            self.chevron:SetTexCoord(.6328125, .67382813, .7578125, .9921875)
        end)
        b:SetScript("OnMouseUp", function(self)
            self.chevron:SetTexCoord(.88867188, .9296875, .296875, .53125)
        end)
        b.arrow = CreateFrame("Button", nil, b)
        b.arrow:SetWidth(27)
        b.arrow:SetHeight(31)
        b.arrow:SetPoint("RIGHT", b, "TOPRIGHT", -2, -15)
        local art = b.arrow:CreateTexture(nil, "OVERLAY")
        art:SetTexture(SQUARE .. "squarebuttontextures")
        art:SetTexCoord(.453125, .640625, .203125, .015625)
        art:SetWidth(12)
        art:SetHeight(12)
        art:SetPoint("CENTER", 0, -1)
        b.arrow:SetNormalTexture(SQUARE .. "ui-squarebutton-up")
        b.arrow:SetPushedTexture(SQUARE .. "ui-squarebutton-down")
        for _, t in ipairs({b.arrow:GetNormalTexture(), b.arrow:GetPushedTexture()}) do
            t:ClearAllPoints()
            t:SetWidth(32)
            t:SetHeight(32)
            t:SetPoint("CENTER")
            t:SetAlpha(0)
        end
        b.arrow:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
        b.arrow:GetHighlightTexture():SetBlendMode("ADD")
        b.arrow:SetScript("OnEnter", function(self)
            self:GetNormalTexture():SetAlpha(1)
            self:GetPushedTexture():SetAlpha(1)
        end)
        b.arrow:SetScript("OnLeave", function(self)
            self:GetNormalTexture():SetAlpha(0)
            self:GetPushedTexture():SetAlpha(0)
        end)
        b.arrow:SetScript("OnMouseDown", function() art:SetPoint("CENTER", -1, -2) end)
        b.arrow:SetScript("OnMouseUp", function() art:SetPoint("CENTER", 0, -1) end)
        b.arrow:SetScript("OnClick", function(self)
            local names, pick = self:GetParent().list()
            local items = {}
            for n, name in ipairs(names) do
                items[n] = {name, function() pick(n) end}
            end
            showMenu(self:GetParent(), items)
        end)
        crumbs[i] = b
    end
    return b
end
-- The buttons to the left over the ones to their right, so each chevron covers its neighbour's edge.
local function crumbLevels()
    local base = nav:GetFrameLevel()
    for i, b in ipairs(crumbs) do
        b:SetFrameLevel(base + 2 * (#crumbs - i) + 1)
        b.arrow:SetFrameLevel(b:GetFrameLevel() + 1)
    end
end

local function navUpdate()
    local path = {{name = WORLD or "World", go = function() SetMapZoom(0) end}}
    local continent, zone = GetCurrentMapContinent(), GetCurrentMapZone()
    if continent > 0 then
        local names = {GetMapContinents()}
        path[2] = {name = names[continent], go = function() SetMapZoom(continent) end,
            list = function() return {GetMapContinents()}, function(i) SetMapZoom(i) end end}
        if zone > 0 then
            local zones = {GetMapZones(continent)}
            path[3] = {name = zones[zone], go = function() SetMapZoom(continent, zone) end,
                list = function() return zones, function(i) SetMapZoom(continent, i) end end}
        end
    end
    local prev
    for i, p in ipairs(path) do
        local b = crumb(i)
        b.text:SetText(p.name)
        b.list = p.list
        b:SetWidth(i == 1 and math.min(128, b.text:GetStringWidth() + 50)
            or b.text:GetStringWidth() + (p.list and 53 or 30))
        if p.list then
            b.arrow:Show()
        else
            b.arrow:Hide()
        end
        b:ClearAllPoints()
        if prev then
            b:SetPoint("LEFT", prev, "RIGHT", i == 2 and -12 or 0, 0) -- the home button's point over the next
        else
            b:SetPoint("LEFT", 2, 0)
        end
        if i == 1 then -- retail's home button (NavBar's HomeButton art, its own point: no chevron)
            b.chevron:Hide()
            b:GetNormalTexture():SetTexture(HELP)
            b:GetNormalTexture():SetTexCoord(.453125, .703125, .0078125, .2421875)
            b:GetPushedTexture():SetTexture(HELP)
            b:GetPushedTexture():SetTexCoord(.453125, .703125, .2578125, .4921875)
        end
        b:SetScript("OnClick", p.go)
        b:Show()
        prev = b
    end
    for i = #path + 1, #crumbs do
        crumbs[i]:Hide()
    end
    crumbLevels()
end

-- [[ Filter ]] --
-- Retail's map filter button on the map's top right; its menu holds what 3.3.5 had as a checkbox
-- (Show Quest Objectives, clicked so the client's own handler runs).
local filter = CreateFrame("Button", nil, top)
filter:SetWidth(32)
filter:SetHeight(32)
local filterIcon = filter:CreateTexture(nil, "ARTWORK")
filterIcon:SetAtlas("Map-Filter-Button")
filterIcon:SetAllPoints()
local filterLit = filter:CreateTexture(nil, "HIGHLIGHT")
filterLit:SetAtlas("Map-Filter-Button")
filterLit:SetAllPoints()
filterLit:SetBlendMode("ADD")
filterLit:SetAlpha(.4)
filter:SetScript("OnMouseDown", function() filterIcon:SetAtlas("Map-Filter-Button-down") end)
filter:SetScript("OnMouseUp", function() filterIcon:SetAtlas("Map-Filter-Button") end)
filter:SetScript("OnClick", function(self)
    showMenu(self, {{WorldMapQuestShowObjectivesText:GetText(), function() WorldMapQuestShowObjectives:Click() end,
        WorldMapQuestShowObjectives:GetChecked() and true or false}}, "TOPRIGHT", "BOTTOMRIGHT", 0, 0)
end)

-- [[ Quest log ]] --
-- Whether a quest is tracked, as the tracker has it (its watch list; IsQuestWatched disagreed with it).
local function isWatched(index)
    for w = 1, GetNumQuestWatches() do
        if GetQuestIndexForWatch(w) == index then
            return true
        end
    end
end
-- Retail's QuestMapFrame: 330 wide right of the map, a search box over the list.
local log = CreateFrame("Frame", nil, f)
log:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -25)
log:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -3, 3)
log:SetWidth(LOG_W - 3)
-- The list, with retail's background and frame (QuestLogBorderFrameTemplate, nine slices) around it
-- and the search box over it (retail's QuestScrollFrame).
local scroll = CreateFrame("ScrollFrame", nil, log)
scroll:SetPoint("TOPLEFT", 0, -29)
scroll:SetPoint("BOTTOMRIGHT", -22, 0)
local content = CreateFrame("Frame", nil, scroll)
content:SetWidth(308)
content:SetHeight(1)
scroll:SetScrollChild(content)
scroll:EnableMouseWheel(true)
local logBg = log:CreateTexture(nil, "BACKGROUND")
logBg:SetAtlas("QuestLog-main-background")
logBg:SetAllPoints(scroll)
local frameArt = CreateFrame("Frame", nil, log)
frameArt:SetPoint("TOPLEFT", scroll, "TOPLEFT", -3, 7)
frameArt:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 3, -6)
Retail.NineSlice(frameArt, "BORDER", "questlog-frame", 24):SetPoints(frameArt, 0, 0, 0, 0)
local filigree = frameArt:CreateTexture(nil, "ARTWORK")
filigree:SetAtlas("questlog-frame-filigree", true)
filigree:SetPoint("TOP", 0, 1)
local shadow = log:CreateTexture(nil, "ARTWORK")
shadow:SetAtlas("questlog-frame-gradient-bottom")
shadow:SetPoint("BOTTOMLEFT", scroll, "BOTTOMLEFT", 0, 4)
shadow:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 0, 4)
shadow:SetHeight(66)

local logUpdate -- below
local search = Retail.SearchBox(log, "WotlkHDQuestSearch", function() logUpdate() end)
search:SetWidth(301)
search:SetPoint("BOTTOMLEFT", scroll, "TOPLEFT", 6, 7)

-- Retail's minimal scroll bar, right of the list.
local bar = CreateFrame("Slider", nil, log)
bar:SetWidth(8)
bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 8, 2)
bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 8, -4)
bar:SetOrientation("VERTICAL")
bar:SetMinMaxValues(0, 0)
local trackTop = bar:CreateTexture(nil, "BACKGROUND")
trackTop:SetAtlas("minimal-scrollbar-track-top", true)
trackTop:SetPoint("TOPLEFT")
local trackBottom = bar:CreateTexture(nil, "BACKGROUND")
trackBottom:SetAtlas("minimal-scrollbar-track-bottom", true)
trackBottom:SetPoint("BOTTOMLEFT")
local trackMiddle = bar:CreateTexture(nil, "BACKGROUND")
trackMiddle:SetAtlas("!minimal-scrollbar-track-middle")
trackMiddle:SetPoint("TOPLEFT", trackTop, "BOTTOMLEFT")
trackMiddle:SetPoint("BOTTOMRIGHT", trackBottom, "TOPRIGHT")
bar:SetThumbTexture(WotlkHD_Atlas["minimal-scrollbar-thumb-middle"][1])
local thumb = bar:GetThumbTexture()
thumb:SetAtlas("minimal-scrollbar-thumb-middle")
thumb:SetWidth(8)
thumb:SetHeight(40)
bar:SetScript("OnValueChanged", function(_, v) scroll:SetVerticalScroll(v) end)
scroll:SetScript("OnMouseWheel", function(_, d)
    local lo, hi = bar:GetMinMaxValues()
    bar:SetValue(math.min(math.max(bar:GetValue() - d * 40, lo), hi))
end)

-- Rows: zone headers (retail's QuestLogHeaderTemplate, 289x22) and quests (QuestLogTitleTemplate: the
-- title in the quest's difficulty colour, its unfinished objectives under it, a tracking checkbox).
local questMenu, focused, mapMarkers, questsPage -- below

-- [[ Markers ]] --
-- 3.3.5's quest markers on the map (QuestPOI buttons on WorldMapPOIFrame) in retail's art (its map
-- legend's): its disc and number textures hidden, retail's disc with the in-progress or turn-in glyph,
-- and retail's gold disc when selected. The client only ever changes those textures' coordinates, so
-- hiding them holds.
local GLYPH_DROP = .031 -- the in-progress glyph's art sits this much of its height above centre
local function skinMarker(b)
    if not b or b.wotlkhd then
        return
    end
    b.wotlkhd = b:CreateTexture(nil, "BACKGROUND")
    b.wotlkhd:SetAtlas("ui-questpoi-questnumber")
    b.wotlkhd:SetPoint("CENTER")
    b.wotlkhd:SetWidth(28)
    b.wotlkhd:SetHeight(28)
    b.normalTexture:SetAlpha(0)
    b.pushedTexture:SetAlpha(0)
    b.highlightTexture:SetAlpha(0)
    local lit = b:CreateTexture(nil, "HIGHLIGHT")
    lit:SetAtlas("ui-questpoi-innerglow")
    lit:SetAllPoints(b.wotlkhd)
    lit:SetBlendMode("ADD")
    if b.number then -- retail shows no numbers: the in-progress glyph on numbered markers
        b.number:SetAlpha(0)
        if b.type == QUEST_POI_NUMERIC then
            local glyph = b:CreateTexture(nil, "ARTWORK")
            glyph:SetAtlas("Quest-In-Progress-Icon-yellow")
            glyph:SetWidth(28)
            glyph:SetHeight(28)
            glyph:SetPoint("CENTER", b.wotlkhd, "CENTER", 0, -28 * GLYPH_DROP)
        end
    end
    if b.turnin then
        b.turnin:SetAtlas("ui-questpoi-questbangturnin")
    else -- QuestPOICompletedTemplate: its "?" was the normal texture
        local glyph = b:CreateTexture(nil, "ARTWORK")
        glyph:SetAtlas("ui-questpoi-questbangturnin")
        glyph:SetAllPoints(b.wotlkhd)
    end
end
hooksecurefunc("QuestPOI_DisplayButton", function(parentName, buttonType, buttonIndex)
    if parentName == "WorldMapPOIFrame" then
        skinMarker(_G["poi" .. parentName .. buttonType .. "_" .. buttonIndex])
        skinMarker(QUEST_POI_SWAP_BUTTONS[parentName])
    end
end)
hooksecurefunc("QuestPOI_SelectButton", function(b)
    if b and b.wotlkhd then
        b.wotlkhd:SetAtlas("ui-questpoi-questnumber-supertracked")
    end
end)
hooksecurefunc("QuestPOI_DeselectButton", function(b)
    if b and b.wotlkhd then
        b.wotlkhd:SetAtlas("ui-questpoi-questnumber")
    end
end)
-- {questID: marker button} for the markers on the map shown.
-- (by name: QuestPOI.lua keeps its button counts local; types 1 to 4, numbered from 1)
function mapMarkers()
    local found = {}
    for t = 1, 4 do
        local i = 1
        local b = _G["poiWorldMapPOIFrame" .. t .. "_" .. i]
        while b do
            if b:IsShown() and b.questId then
                found[b.questId] = b
            end
            i = i + 1
            b = _G["poiWorldMapPOIFrame" .. t .. "_" .. i]
        end
    end
    return found
end

local headerRows, questRows, objectiveLines = {}, {}, {}
local showDetails -- below

local function headerRow(i)
    local r = headerRows[i]
    if not r then
        r = CreateFrame("Button", nil, content)
        r:SetWidth(289)
        r:SetHeight(22)
        local t = r:CreateTexture(nil, "BACKGROUND")
        t:SetAtlas("questlog-tab")
        t:SetAllPoints()
        r.text = r:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        r.text:SetPoint("LEFT", 9, 0)
        r.toggle = r:CreateTexture(nil, "ARTWORK")
        r.toggle:SetWidth(18)
        r.toggle:SetHeight(18)
        r.toggle:SetPoint("RIGHT", -6, 0)
        local lit = r:CreateTexture(nil, "HIGHLIGHT")
        lit:SetAtlas("questlog-header-glow-yellow")
        lit:SetAllPoints()
        lit:SetBlendMode("ADD")
        r:SetScript("OnClick", function(self)
            if self.collapsed then
                ExpandQuestHeader(self.index)
            else
                CollapseQuestHeader(self.index)
            end
        end)
        headerRows[i] = r
    end
    return r
end

local function questRow(i)
    local r = questRows[i]
    if not r then
        r = CreateFrame("Button", nil, content)
        r:SetWidth(290)
        r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        r.text = r:CreateFontString(nil, "ARTWORK", "GameFontNormalLeft")
        r.text:SetPoint("TOPLEFT", 31, -8)
        r.text:SetWidth(220)
        r.text:SetJustifyH("LEFT")
        -- retail's marker on the row (the quest's on the map shown), at retail's TOPLEFT (6, -4)
        r.poi = CreateFrame("Button", nil, r)
        r.poi:SetWidth(22)
        r.poi:SetHeight(22)
        r.poi:SetPoint("TOPLEFT", 4, -3)
        r.poi.disc = r.poi:CreateTexture(nil, "BACKGROUND")
        r.poi.disc:SetAllPoints()
        r.poi.number = r.poi:CreateTexture(nil, "ARTWORK") -- retail's in-progress glyph
        r.poi.number:SetAtlas("Quest-In-Progress-Icon-yellow")
        r.poi.number:SetWidth(22)
        r.poi.number:SetHeight(22)
        r.poi.number:SetPoint("CENTER", 0, -22 * GLYPH_DROP)
        r.poi.turnin = r.poi:CreateTexture(nil, "ARTWORK")
        r.poi.turnin:SetAtlas("ui-questpoi-questbangturnin")
        r.poi.turnin:SetAllPoints()
        r.poi:SetScript("OnClick", function() showDetails(r.index, true) end)
        r.glow = r:CreateTexture(nil, "BACKGROUND")
        r.glow:SetAtlas("questlog-quest-glow-yellow")
        r.glow:SetPoint("TOPLEFT", r.text, "TOPLEFT", -27, 6)
        r.glow:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 4, -4)
        r.glow:SetBlendMode("ADD")
        r.glow:Hide()
        r.check = CreateFrame("Button", nil, r)
        r.check:SetWidth(14)
        r.check:SetHeight(14)
        r.check:SetPoint("TOPRIGHT", 0, -8)
        local box = r.check:CreateTexture(nil, "ARTWORK")
        box:SetAtlas("questlog-icon-ticksquare")
        box:SetAllPoints()
        r.tick = r.check:CreateTexture(nil, "OVERLAY")
        r.tick:SetAtlas("questlog-icon-checkmark-yellow", true)
        r.tick:SetPoint("CENTER", 1, 1)
        -- The tick changes at once: QUEST_WATCH_UPDATE comes before the watch list has the change, and
        -- the list follows the tracker (WatchFrame_Update, hooked below) once it has.
        r.check:SetScript("OnClick", function()
            local index = r.index
            if isWatched(index) then
                RemoveQuestWatch(index)
                r.tick:Hide()
            elseif GetNumQuestWatches() < MAX_WATCHABLE_QUESTS then
                AddQuestWatch(index)
                r.tick:Show()
            else
                UIErrorsFrame:AddMessage(format(QUEST_WATCH_TOO_MANY, MAX_WATCHABLE_QUESTS), 1, .1, .1, 1)
            end
            WatchFrame_Update()
        end)
        r:SetScript("OnEnter", function(self)
            self.glow:Show()
            self.text:SetTextColor(self.hr, self.hg, self.hb)
            if self.questID then
                WorldMapBlobFrame:DrawQuestBlob(self.questID, true)
            end
        end)
        r:SetScript("OnLeave", function(self)
            self.glow:Hide()
            self.text:SetTextColor(self.r, self.g, self.b)
            if self.questID then
                WorldMapBlobFrame:DrawQuestBlob(self.questID, false)
            end
        end)
        r:SetScript("OnClick", function(self, button)
            if IsModifiedClick("CHATLINK") and ChatEdit_GetActiveWindow() then
                ChatEdit_InsertLink(GetQuestLink(self.index))
            elseif IsShiftKeyDown() then -- retail's: shift-click tracks
                self.check:Click()
            elseif button == "RightButton" then
                questMenu(self)
            else
                showDetails(self.index, true)
            end
        end)
        questRows[i] = r
    end
    return r
end

local function objectiveLine(i)
    local l = objectiveLines[i]
    if not l then
        l = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        l:SetWidth(240)
        l:SetJustifyH("LEFT")
        objectiveLines[i] = l
    end
    return l
end

-- Retail's gaps between rows (previous kind -> this kind).
local GAP = {none = {header = 8, quest = 2}, header = {header = 6, quest = 2}, quest = {header = 4, quest = -3}}

local function matches(text, needle)
    return needle == "" or (text and strfind(strlower(text), needle, 1, true))
end

function logUpdate() -- the local declared with the search box
    if not f:IsVisible() then
        return
    end
    local needle = strlower(search:GetText() or "")
    local markers = mapMarkers()
    -- the watched quests as the tracker has them (GetQuestIndexForWatch)
    local watched = {}
    for w = 1, GetNumQuestWatches() do
        local index = GetQuestIndexForWatch(w)
        if index then
            watched[index] = true
        end
    end
    -- gather headers and their quests first, so a search can drop headers with nothing left
    local groups, group = {}
    for i = 1, GetNumQuestLogEntries() do
        local name, level, tag, _, isHeader, collapsed, complete, daily, questID = GetQuestLogTitle(i)
        if isHeader then
            group = {index = i, name = name, collapsed = collapsed, quests = {}}
            groups[#groups + 1] = group
        elseif group then
            local objectives, hit = {}, matches(name, needle)
            for j = 1, GetNumQuestLeaderBoards(i) do
                local text, _, finished = GetQuestLogLeaderBoard(j, i)
                if not finished then
                    objectives[#objectives + 1] = text
                end
                hit = hit or matches(text, needle)
            end
            if complete == 1 then
                objectives = {QUEST_WATCH_QUEST_READY or "Ready for turn-in"}
            elseif complete == -1 then
                objectives = {FAILED}
            end
            if hit then
                group.quests[#group.quests + 1] = {index = i, name = name, level = level, tag = tag,
                    daily = daily, questID = questID, objectives = objectives}
            end
        end
    end

    local y, prev, nh, nq, nl = 0, "none", 0, 0, 0
    for _, g in ipairs(groups) do
        if needle == "" or #g.quests > 0 then
            nh = nh + 1
            local h = headerRow(nh)
            y = y + GAP[prev].header
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", content, "TOPLEFT", 9, -y)
            h.text:SetText(g.name)
            h.index, h.collapsed = g.index, g.collapsed
            h.toggle:SetAtlas(g.collapsed and "questlog-icon-expand" or "questlog-icon-shrink")
            h:Show()
            y, prev = y + 22, "header"
            for _, q in ipairs(g.quests) do
                nq = nq + 1
                local r = questRow(nq)
                y = y + GAP[prev].quest
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", content, "TOPLEFT", 9, -y)
                r.index, r.questID = q.index, q.questID
                local label = q.name
                if q.tag and q.tag ~= "" then
                    label = format("%s (%s)", label, q.tag)
                elseif q.daily then
                    label = format("%s (%s)", label, DAILY)
                end
                r.text:SetText(label)
                local c = GetQuestDifficultyColor(q.level)
                r.r, r.g, r.b = c.r, c.g, c.b
                r.hr, r.hg, r.hb = math.min(c.r + .2, 1), math.min(c.g + .2, 1), math.min(c.b + .2, 1)
                r.text:SetTextColor(c.r, c.g, c.b)
                if watched[q.index] then
                    r.tick:Show()
                else
                    r.tick:Hide()
                end
                local m = q.questID and markers[q.questID]
                if m then
                    r.poi.disc:SetAtlas(q.questID == focused and "ui-questpoi-questnumber-supertracked"
                        or "ui-questpoi-questnumber")
                    if m.type == QUEST_POI_NUMERIC then
                        r.poi.number:Show()
                        r.poi.turnin:Hide()
                    else
                        r.poi.number:Hide()
                        r.poi.turnin:Show()
                    end
                    r.poi:Show()
                else
                    r.poi:Hide()
                end
                local h2 = 8 + r.text:GetStringHeight()
                for j, text in ipairs(q.objectives) do
                    nl = nl + 1
                    local l = objectiveLine(nl)
                    l:ClearAllPoints()
                    l:SetPoint("TOPLEFT", r, "TOPLEFT", 31, -(h2 + (j == 1 and 3 or 2)))
                    l:SetText(QUEST_DASH .. text)
                    l:Show()
                    h2 = h2 + (j == 1 and 3 or 2) + l:GetStringHeight()
                end
                r:SetHeight(h2 + 6)
                r:Show()
                y, prev = y + h2 + 6, "quest"
            end
        end
    end
    for i = nh + 1, #headerRows do headerRows[i]:Hide() end
    for i = nq + 1, #questRows do questRows[i]:Hide() end
    for i = nl + 1, #objectiveLines do objectiveLines[i]:Hide() end
    content:SetHeight(math.max(y + 8, 1))
    local max = math.max(y + 8 - scroll:GetHeight(), 0)
    bar:SetMinMaxValues(0, max)
    if max > 0 then
        bar:Show()
    else
        bar:Hide()
    end
end

-- [[ Details ]] --
-- Retail's details view in the list's place: a Back bar, the quest (3.3.5's QuestInfo, as its quest
-- log shows it) and Abandon, Share and Track under it.
local details = CreateFrame("Frame", nil, log)
details:SetPoint("TOPLEFT", 0, -1)
details:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT")
details:Hide()
local detailsBg = details:CreateTexture(nil, "BACKGROUND")
detailsBg:SetAtlas("QuestDetailsBackgrounds")
detailsBg:SetPoint("TOPLEFT", 0, -43)
detailsBg:SetPoint("BOTTOMRIGHT", 0, 23)
local topBar = details:CreateTexture(nil, "BORDER")
topBar:SetAtlas("questlog-reward-top-frame")
topBar:SetPoint("TOPLEFT")
topBar:SetPoint("TOPRIGHT")
topBar:SetHeight(52)
local back = CreateFrame("Button", nil, details, "UIPanelButtonTemplate")
back:SetWidth(90)
back:SetHeight(22)
back:SetPoint("TOPLEFT", 11, -11)
back:SetText(BACK)
local detailScroll = CreateFrame("ScrollFrame", "WotlkHDQuestDetailScroll", details, "UIPanelScrollFrameTemplate")
detailScroll:SetPoint("TOPLEFT", 5, -43)
detailScroll:SetPoint("BOTTOMRIGHT", -24, 27)
local detailChild = CreateFrame("Frame", "WotlkHDQuestDetailChild", detailScroll)
detailChild:SetWidth(280)
detailChild:SetHeight(1)
detailScroll:SetScrollChild(detailChild)

local function bottomButton(text, w)
    local b = CreateFrame("Button", nil, details, "UIPanelButtonTemplate")
    b:SetWidth(w)
    b:SetHeight(22)
    b:SetText(text)
    return b
end
local abandon = bottomButton(ABANDON_QUEST_ABBREV or ABANDON_QUEST, 105)
abandon:SetPoint("BOTTOMLEFT", -3, -2)
local share = bottomButton(SHARE_QUEST_ABBREV or SHARE_QUEST, 103)
share:SetPoint("LEFT", abandon, "RIGHT")
-- Retail's labels (TRACK_QUEST_ABBREV / UNTRACK_QUEST_ABBREV; 3.3.5 has no "Untrack")
local TRACK, UNTRACK = TRACK_QUEST_ABBREV or "Track", UNTRACK_QUEST_ABBREV or "Untrack"
local track = bottomButton(TRACK, 105)
track:SetPoint("LEFT", share, "RIGHT")

-- The quest shown: retail's focused quest, its area drawn and its marker selected on the map. Opening
-- it from the list moves the map to its zone (as WorldMap_OpenToQuest does); Back returns the map.
local shownIndex, returnMap
local function focus()
    if not focused or not f:IsVisible() then
        return
    end
    local selected = WORLDMAP_SETTINGS.selectedQuestId -- the client's own selection, read only
    if selected and selected ~= focused then
        WorldMapBlobFrame:DrawQuestBlob(selected, false)
    end
    WorldMapBlobFrame:DrawQuestBlob(focused, true)
    QuestPOI_SelectButtonByQuestId("WorldMapPOIFrame", focused, true)
end
function showDetails(index, moveMap)
    questsPage() -- off the Map Legend page, if it shows
    shownIndex = index
    local questID = select(9, GetQuestLogTitle(index))
    if focused and focused ~= questID then
        WorldMapBlobFrame:DrawQuestBlob(focused, false)
    end
    focused = questID
    if moveMap and questID then
        if not returnMap then
            -- SetMapByID takes one less than GetCurrentMapAreaID gives (WorldMapFrame_ToggleWindowSize)
            returnMap = {GetCurrentMapAreaID() - 1, GetCurrentMapDungeonLevel()}
        end
        local mapID, floor = GetQuestWorldMapAreaID(questID)
        if mapID and mapID ~= 0 then
            SetMapByID(mapID)
            if floor and floor ~= 0 then
                SetDungeonMapLevel(floor)
            end
        end
    end
    focus()
    SelectQuestLogEntry(index)
    scroll:Hide()
    bar:Hide()
    search:Hide()
    details:Show()
    QuestInfo_Display(QUEST_TEMPLATE_LOG, detailChild)
    detailScroll:SetVerticalScroll(0)
    if GetQuestLogPushable() and GetNumPartyMembers() > 0 then
        share:Enable()
    else
        share:Disable()
    end
    track:SetText(isWatched(index) and UNTRACK or TRACK)
end
local function hideDetails()
    shownIndex = nil
    if focused then
        WorldMapBlobFrame:DrawQuestBlob(focused, false)
        focused = nil
    end
    if returnMap then
        SetMapByID(returnMap[1])
        if returnMap[2] and returnMap[2] ~= 0 then
            SetDungeonMapLevel(returnMap[2])
        end
        returnMap = nil
    end
    details:Hide()
    scroll:Show()
    search:Show()
    logUpdate()
end
back:SetScript("OnClick", hideDetails)
local function abandonQuest(index)
    SelectQuestLogEntry(index)
    SetAbandonQuest()
    local items = GetAbandonQuestItems()
    if items then
        StaticPopup_Show("ABANDON_QUEST_WITH_ITEMS", GetAbandonQuestName(), items)
    else
        StaticPopup_Show("ABANDON_QUEST", GetAbandonQuestName())
    end
end
local function shareQuest(index)
    SelectQuestLogEntry(index)
    QuestLogPushQuest()
end
abandon:SetScript("OnClick", function() abandonQuest(shownIndex) end)
share:SetScript("OnClick", function() shareQuest(shownIndex) end)

-- Retail's right-click menu on a quest: track, share (in a group, if it can be shared), abandon, open.
function questMenu(row)
    local index = row.index
    SelectQuestLogEntry(index)
    local items = {{isWatched(index) and UNTRACK or TRACK, function() row.check:Click() end}}
    if GetQuestLogPushable() and GetNumPartyMembers() > 0 then
        items[#items + 1] = {SHARE_QUEST, function() shareQuest(index) end}
    end
    items[#items + 1] = {ABANDON_QUEST, function() abandonQuest(index) end}
    items[#items + 1] = {"Open Quest Details", function() showDetails(index, true) end}
    local x = GetCursorPosition() / row:GetEffectiveScale() - row:GetLeft()
    showMenu(row, items, "TOPLEFT", "TOPLEFT", x, -14)
end
track:SetScript("OnClick", function() -- labelled from the action: the watch list lags (see the rows)
    if isWatched(shownIndex) then
        RemoveQuestWatch(shownIndex)
        track:SetText(TRACK)
    elseif GetNumQuestWatches() < MAX_WATCHABLE_QUESTS then
        AddQuestWatch(shownIndex)
        track:SetText(UNTRACK)
    end
    WatchFrame_Update()
end)

-- [[ Side tabs ]] --
-- Retail's tabs outside the quest log's right edge: Quests and Map Legend (3.3.5 has no events). The
-- legend lists what 3.3.5's map shows: quests in progress and to turn in, in retail's art.
local legend = CreateFrame("Frame", nil, log)
legend:SetAllPoints(scroll)
legend:Hide()
local legendTitle = log:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
legendTitle:SetPoint("BOTTOM", scroll, "TOP", 0, 9)
legendTitle:SetText("Map Legend")
legendTitle:Hide()
local legendHeader = legend:CreateFontString(nil, "ARTWORK", "GameFontNormal")
legendHeader:SetPoint("TOPLEFT", 14, -14)
legendHeader:SetText(QUESTS_LABEL or "Quests")
local LEGEND = {{"Quest-In-Progress-Icon-yellow", "In Progress"}, {"ui-questpoi-questbangturnin", "Turn In"}}
for i, e in ipairs(LEGEND) do
    local disc = legend:CreateTexture(nil, "ARTWORK")
    disc:SetAtlas("ui-questpoi-questnumber")
    disc:SetWidth(24)
    disc:SetHeight(24)
    disc:SetPoint("TOPLEFT", 14 + (i - 1) * 150, -34)
    local glyph = legend:CreateTexture(nil, "OVERLAY")
    glyph:SetAtlas(e[1])
    glyph:SetAllPoints(disc)
    local text = legend:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    text:SetPoint("LEFT", disc, "RIGHT", 6, 0)
    text:SetText(e[2])
end

local sideTabs, sidePage = {}, 1
local function sideTab(i, icon)
    local t = CreateFrame("Button", nil, top)
    t:SetWidth(51)
    t:SetHeight(60)
    local tabBg = t:CreateTexture(nil, "BACKGROUND")
    tabBg:SetAtlas("QuestLog-tab-side")
    tabBg:SetAllPoints()
    t.icon = t:CreateTexture(nil, "ARTWORK")
    t.icon:SetWidth(29)
    t.icon:SetHeight(29)
    t.icon:SetPoint("CENTER", -2, 0)
    t.iconName = icon
    t.selected = t:CreateTexture(nil, "OVERLAY")
    t.selected:SetAtlas("QuestLog-Tab-side-Glow-Select")
    t.selected:SetAllPoints()
    t.selected:SetBlendMode("ADD")
    local hover = t:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAtlas("QuestLog-Tab-side-Glow-hover")
    hover:SetAllPoints()
    hover:SetBlendMode("ADD")
    if i == 1 then
        t:SetPoint("TOPLEFT", log, "TOPRIGHT", 3, -28)
    else
        t:SetPoint("TOP", sideTabs[i - 1], "BOTTOM", 0, -3)
    end
    sideTabs[i] = t
    return t
end
local function showPage(page)
    sidePage = page
    for i, t in ipairs(sideTabs) do
        t.icon:SetAtlas(t.iconName .. (i == page and "" or "-inactive"))
        if i == page then
            t.selected:Show()
        else
            t.selected:Hide()
        end
    end
    if page == 2 then
        if details:IsShown() then
            hideDetails()
        end
        scroll:Hide()
        bar:Hide()
        search:Hide()
        legend:Show()
        legendTitle:Show()
    else
        legend:Hide()
        legendTitle:Hide()
        scroll:Show()
        search:Show()
        logUpdate()
    end
end
sideTab(1, "QuestLog-tab-icon-quest"):SetScript("OnClick", function() showPage(1) end)
sideTab(2, "QuestLog-tab-icon-MapLegend"):SetScript("OnClick", function() showPage(2) end)
function questsPage()
    if sidePage ~= 1 then
        showPage(1)
    end
end
showPage(1)

-- [[ Coordinates ]] --
-- Retail's player position at the map's lower left, with the zone's name.
local coords = top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
local coordsTimer = 0
top:SetScript("OnUpdate", function(_, elapsed)
    coordsTimer = coordsTimer + elapsed
    if coordsTimer < .1 then
        return
    end
    coordsTimer = 0
    local x, y = GetPlayerMapPosition("player")
    if x == 0 and y == 0 then
        coords:SetText("")
    else
        coords:SetFormattedText("Player: %.1f, %.1f (%s)", x * 100, y * 100, GetZoneText())
    end
end)

-- [[ Collapsing the quest log ]] --
-- Retail's button on the map's lower right: the log folds away and the frame narrows to the map.
local toggle = CreateFrame("Button", nil, top)
toggle:SetWidth(32)
toggle:SetHeight(32)
toggle:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
toggle:GetHighlightTexture():SetBlendMode("ADD")
local corner = toggle:CreateTexture(nil, "BACKGROUND")
corner:SetAtlas("MapCornerShadow-Right", true)
corner:SetPoint("BOTTOMRIGHT", 2, -1)
local function toggleArt()
    local kind = logShown() and "Hide" or "Show"
    toggle:SetNormalTexture(WotlkHD_Atlas["questcollapse-" .. strlower(kind) .. "-up"][1])
    toggle:GetNormalTexture():SetAtlas("QuestCollapse-" .. kind .. "-Up")
    toggle:SetPushedTexture(WotlkHD_Atlas["questcollapse-" .. strlower(kind) .. "-down"][1])
    toggle:GetPushedTexture():SetAtlas("QuestCollapse-" .. kind .. "-Down")
end

-- [[ Layout ]] --
-- In 3.3.5's windowed mode only (not its movable "advanced" one, nor its fullscreen map, both left as
-- they are): WorldMapFrame scaled so the map is retail's 697x465, or, maximized, as large as the screen
-- allows (retail's maximized map: no portrait, no quest log, "World Map"). 3.3.5's own border, title,
-- close and size buttons, quest tracking box and objectives checkbox are hidden (the last now in the
-- filter menu).
local OLD = {WorldMapFrameMiniBorderLeft, WorldMapFrameMiniBorderRight, WorldMapFrameTitle, WorldMapTrackQuest,
    WorldMapFrameCloseButton, WorldMapFrameSizeUpButton, WorldMapQuestShowObjectives}
-- Frame levels, set again on every layout: the client sets the map's (WorldMapFrame_ResetFrameLevels,
-- WORLDMAP_POI_FRAMELEVEL - 13 to + 0) when it changes mode. Ours: the background under the map, the
-- quest log over its layers, the borders and controls on top. 3.3.5 doesn't move children with their
-- parent, so each frame below gets its level.
local function relevel(frame, level)
    frame:SetFrameLevel(level)
    for _, child in ipairs({frame:GetChildren()}) do
        relevel(child, level + 1)
    end
end
local function levels()
    relevel(f, WorldMapFrame:GetFrameLevel())
    relevel(log, WORLDMAP_POI_FRAMELEVEL + 20)
    relevel(border, WORLDMAP_POI_FRAMELEVEL + 30)
    relevel(plainBorder, WORLDMAP_POI_FRAMELEVEL + 30)
    relevel(top, WORLDMAP_POI_FRAMELEVEL + 40)
    crumbLevels()
    relevel(list, WORLDMAP_POI_FRAMELEVEL + 60) -- its entries above its background
end

local function maximized()
    return saved and saved.maximized
end
-- The maximized map centered on the screen, wherever the panel layout puts the windowed one.
local function center()
    if maximized() and f:IsShown() then
        WorldMapFrame:ClearAllPoints()
        WorldMapFrame:SetPoint("CENTER", UIParent, "CENTER")
    end
end

local function layout()
    local windowed = WORLDMAP_SETTINGS.size == WORLDMAP_WINDOWED_SIZE and not WORLDMAP_SETTINGS.advanced
    if not windowed then
        -- fullscreen or movable: 3.3.5's own frame (its scale set by the client on show), and the
        -- anchors its layout code adds to, put back as it sets them
        f:Hide()
        if WORLDMAP_SETTINGS.size == WORLDMAP_WINDOWED_SIZE then
            WorldMapFrame:SetScale(1) -- the movable windowed mode
        end
        for _, r in ipairs(OLD) do
            r:SetAlpha(1)
            if r.EnableMouse then -- the borders and title are textures
                r:EnableMouse(true)
            end
        end
        if WORLDMAP_SETTINGS.size ~= WORLDMAP_WINDOWED_SIZE then
            WorldMapLevelDropDown:ClearAllPoints()
            WorldMapLevelDropDown:SetPoint("TOPRIGHT", WorldMapPositioningGuide, "TOPRIGHT", -50, -35)
        end
        return
    end
    local max = maximized()
    local canvasW = CANVAS_W
    if max then
        local h = math.min(UIParent:GetHeight() - 20 - TOP - 2, (UIParent:GetWidth() - 20 - 5) / 1.5)
        canvasW = math.floor(h * 1.5)
    end
    local canvasH = canvasW * 668 / 1002
    local scale = canvasW / (1002 * WORLDMAP_WINDOWED_SIZE)
    local withLog = logShown() and not max
    local width, height = 2 + canvasW + 3 + (withLog and LOG_W or 0), TOP + canvasH + 2
    WorldMapFrame:SetScale(scale)
    WorldMapFrame:SetWidth(width / scale)
    WorldMapFrame:SetHeight(height / scale)
    f:SetScale(1 / scale)
    f:SetWidth(width)
    f:SetHeight(height)
    -- the map's offsets are in its own units: WORLDMAP_WINDOWED_SIZE under WorldMapFrame's scale
    local unit = scale * WORLDMAP_WINDOWED_SIZE
    WorldMapDetailFrame:ClearAllPoints()
    WorldMapDetailFrame:SetPoint("TOPLEFT", WorldMapFrame, "TOPLEFT", 2 / unit, -TOP / unit)
    WorldMapBlobFrame.xRatio = nil -- the client's hit maths again for the moved map
    for _, r in ipairs(OLD) do
        r:SetAlpha(0)
        if r.EnableMouse then -- the borders and title are textures
            r:EnableMouse(false)
        end
    end
    WorldMapLevelDropDown:ClearAllPoints()
    WorldMapLevelDropDown:SetPoint("TOPLEFT", WorldMapDetailFrame, "TOPLEFT", -14, -2)

    -- the frame: the portrait border and "Map & Quest Log" windowed, the plain one and "World Map"
    -- maximized (retail's TitleContainer runs from 58 past the portrait, or from the edge, to -24)
    if max then
        border:Hide()
        plainBorder:Show()
        title:SetText(WORLD_MAP)
        title:SetPoint("TOP", -12, -5)
        maximize:Hide()
        minimize:Show()
        toggle:Hide()
    else
        border:Show()
        plainBorder:Hide()
        title:SetText("Map & Quest Log")
        title:SetPoint("TOP", 17, -5)
        maximize:Show()
        minimize:Hide()
        toggle:Show()
    end
    innerTop:ClearAllPoints()
    innerTop:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -63)
    innerTop:SetPoint("TOPRIGHT", f, "TOPLEFT", 2 + canvasW, -63)
    nav:ClearAllPoints()
    nav:SetPoint("TOPLEFT", f, "TOPLEFT", 2 + (max and 8 or 64), -25)
    nav:SetPoint("TOPRIGHT", f, "TOPLEFT", 2 + canvasW - 4, -25)
    filter:ClearAllPoints()
    filter:SetPoint("TOPRIGHT", f, "TOPLEFT", 2 + canvasW - 4, -TOP - 2)
    toggle:ClearAllPoints()
    toggle:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", 2 + canvasW - 2, 3)
    if withLog then
        log:Show()
        for _, t in ipairs(sideTabs) do t:Show() end
    else
        log:Hide()
        for _, t in ipairs(sideTabs) do t:Hide() end
    end
    coords:ClearAllPoints()
    coords:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 2 + 68, 6)
    toggleArt()
    f:Show()
    center()
    navUpdate()
    logUpdate()
    levels()
end
toggle:SetScript("OnClick", function()
    saved.hideLog = logShown() or nil
    layout()
end)
maximize:SetScript("OnClick", function()
    saved.maximized = true
    layout()
end)
minimize:SetScript("OnClick", function()
    saved.maximized = nil
    if WorldMapFrame:IsShown() then
        -- back where the panel layout keeps it: close and open, as the client's size toggle does
        ToggleFrame(WorldMapFrame)
        ToggleFrame(WorldMapFrame)
    else
        layout()
    end
end)
-- after the panel layout moves it (FramePositionDelegate is local to UIParent.lua: its global callers)
hooksecurefunc("UpdateUIPanelPositions", center)
hooksecurefunc("ShowUIPanel", center)

-- [[ The quest log key ]] --
-- Retail's L opens and closes the Map & Quest Log. The keys bound to Toggle Quest Log get an override
-- binding that clicks our button (set out of combat, at login and when bindings change; it works in
-- combat too). Anything else opening 3.3.5's quest log window, as a quest clicked in the tracker does
-- (QuestLog_OpenToQuest), has it close again and the map open with its log instead, at that quest's
-- details (a frame later, once QuestLog_OpenToQuest has said which quest).
local function openLog(questIndex)
    if WORLDMAP_SETTINGS.size ~= WORLDMAP_WINDOWED_SIZE or WORLDMAP_SETTINGS.advanced then
        return false -- 3.3.5's own map modes keep 3.3.5's quest log
    end
    saved.hideLog, saved.maximized = nil, nil
    if WorldMapFrame:IsShown() then
        layout()
    else
        ShowUIPanel(WorldMapFrame)
    end
    if questIndex then
        showDetails(questIndex, true)
    elseif details:IsShown() then
        hideDetails()
    end
    return true
end

local key = CreateFrame("Button", "WotlkHDQuestLogKey", UIParent)
key:SetScript("OnClick", function()
    if f:IsVisible() and log:IsShown() then
        HideUIPanel(WorldMapFrame)
    elseif not openLog() then
        ToggleFrame(QuestLogFrame)
    end
end)
local function bindKeys()
    local keys = {GetBindingKey("TOGGLEQUESTLOG")}
    local sig = table.concat(keys, " ")
    -- only when the keys change: setting an override fires UPDATE_BINDINGS again
    if InCombatLockdown() or sig == key.sig then
        return
    end
    key.sig = sig
    ClearOverrideBindings(key)
    for _, k in ipairs(keys) do
        SetOverrideBindingClick(key, false, k, "WotlkHDQuestLogKey")
    end
end
key:RegisterEvent("PLAYER_LOGIN")
key:RegisterEvent("UPDATE_BINDINGS")
key:SetScript("OnEvent", bindKeys)

local openToQuest
hooksecurefunc("QuestLog_OpenToQuest", function(index) openToQuest = index end)
local redirect = CreateFrame("Frame")
redirect:Hide()
redirect:SetScript("OnUpdate", function(self)
    self:Hide()
    if openLog(openToQuest) then
        HideUIPanel(QuestLogFrame)
    end
    openToQuest = nil
end)
QuestLogFrame:HookScript("OnShow", function() redirect:Show() end)

-- The client rebuilds the markers and its selection with each map update: our focus again after it.
-- A marker clicked on the map opens its quest, as retail's pins do.
hooksecurefunc("WorldMapFrame_UpdateMap", focus)
hooksecurefunc("WorldMapFrame_UpdateQuests", function() -- the markers rebuilt: the rows' too
    if not details:IsShown() then
        logUpdate()
    end
end)
hooksecurefunc("WorldMapQuestPOI_OnClick", function(self)
    if f:IsVisible() and self.quest and self.quest.questLogIndex and not IsShiftKeyDown() then
        showDetails(self.quest.questLogIndex)
    end
end)
hooksecurefunc("WatchFrame_Update", function()
    if not details:IsShown() then
        logUpdate()
    end
end)
hooksecurefunc("WorldMap_ToggleSizeDown", layout)
hooksecurefunc("WorldMap_ToggleSizeUp", layout)
hooksecurefunc("WorldMapFrame_SetMiniMode", layout)
hooksecurefunc("WorldMapQuestShowObjectives_AdjustPosition", layout)
WorldMapFrame:HookScript("OnShow", layout)

local events = CreateFrame("Frame")
for _, e in ipairs({"ADDON_LOADED", "WORLD_MAP_UPDATE", "QUEST_LOG_UPDATE", "QUEST_WATCH_UPDATE"}) do
    events:RegisterEvent(e)
end
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name == "WotlkHD" then
            WotlkHD_Saved = WotlkHD_Saved or {}
            WotlkHD_Saved.worldMap = WotlkHD_Saved.worldMap or {}
            saved = WotlkHD_Saved.worldMap
            -- retail's map opens windowed: once, before the client reads the setting (VARIABLES_LOADED)
            if not saved.windowed then
                saved.windowed = true
                SetCVar("miniWorldMap", "1")
            end
        end
    elseif event == "WORLD_MAP_UPDATE" then
        if f:IsVisible() then
            navUpdate()
        end
    elseif details:IsShown() then
        if shownIndex and shownIndex <= GetNumQuestLogEntries() then
            showDetails(shownIndex)
        else
            hideDetails()
        end
    else
        logUpdate()
    end
end)
