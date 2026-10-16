-- wotlk-hd: retail's Map & Quest Log (Blizzard_WorldMap and QuestMapFrame, mainline) on 3.3.5's windowed
-- world map: the metal frame with the quest log book, breadcrumbs over a 697x465 map, and the quest
-- log beside it (zone headers, quests with their objectives, tracking checkboxes, search, the quest's
-- details), collapsible as retail's. The map opens windowed, as retail's does; the maximize button is
-- 3.3.5's own size button, so the client's own code switches to its fullscreen map.
--
-- The map itself is 3.3.5's: its tiles, quest areas, quest markers and player arrow all sit on
-- WorldMapDetailFrame at the client's windowed scale (WORLDMAP_WINDOWED_SIZE), and WorldMapFrame is
-- scaled up to retail's size around it. Nothing writes WORLDMAP_SETTINGS (the quest tracker reads it),
-- so the client's own placement maths is untouched; our frame and quest log draw at normal scale.

local Retail = WotlkHD_Retail
local CANVAS_W, CANVAS_H = 697, 465 -- retail's map canvas, windowed with the quest log
local TOP = 67 -- retail's TITLE_CANVAS_SPACER_FRAME_HEIGHT
local LOG_W = 333 -- retail's questLogWidth
local FRAME_H = 534
local SCALE = CANVAS_W / (1002 * WORLDMAP_WINDOWED_SIZE) -- WorldMapFrame's, so the windowed map is retail's
local TILE = "Interface\\AddOns\\WotlkHD\\Art\\cs_helptextures_tile"
local HELP = "Interface\\AddOns\\WotlkHD\\Art\\cs_helptextures"

local saved -- WotlkHD_Saved.worldMap
local function logShown()
    return not (saved and saved.hideLog)
end

-- [[ The frame ]] --
-- Ours at normal scale on the scaled WorldMapFrame (1 / SCALE cancels it out).
local f = CreateFrame("Frame", "WotlkHDWorldMap", WorldMapFrame)
f:SetScale(1 / SCALE)
f:SetPoint("TOPLEFT")
f:SetHeight(FRAME_H)
f:SetFrameLevel(WorldMapFrame:GetFrameLevel())
f:Hide()
local bg = f:CreateTexture(nil, "BACKGROUND")
bg:SetTexture(0x1f / 255, 0x1e / 255, 0x21 / 255, 1)
bg:SetPoint("TOPLEFT", 2, -2)
bg:SetPoint("BOTTOMRIGHT", -2, 2)
local border, portrait = Retail.MetalFrame(f, true)
SetPortraitToTexture(portrait, "Interface\\QuestFrame\\UI-QuestLog-BookIcon")
-- The title on its own frame over the border (whose top edge shares the OVERLAY layer).
local titleFrame = CreateFrame("Frame", nil, border)
titleFrame:SetAllPoints()
local title = titleFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOP", 17, -5)
title:SetText("Map & Quest Log")
local innerTop = border:CreateTexture(nil, "ARTWORK")
innerTop:SetAtlas("_UI-Frame-InnerTopTile")
innerTop:SetHeight(3)
innerTop:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -63)
innerTop:SetPoint("TOPRIGHT", f, "TOPLEFT", 2 + CANVAS_W, -63)

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
local close = redButton(border, "RedButton-Exit", "RedButton-exit-pressed")
close:SetPoint("TOPRIGHT", 1, 0)
close:SetScript("OnClick", function() ToggleFrame(WorldMapFrame) end)

-- Maximize: 3.3.5's own size button (its click runs the client's code), on ours and in retail's art.
local maximize = WorldMapFrameSizeUpButton
local function placeMaximize()
    maximize:SetParent(border)
    maximize:SetWidth(24)
    maximize:SetHeight(24)
    maximize:ClearAllPoints()
    maximize:SetPoint("RIGHT", close, "LEFT", 1, 0)
end
for _, t in ipairs({{"GetNormalTexture", "RedButton-Expand"}, {"GetPushedTexture", "RedButton-Expand-Pressed"},
    {"GetHighlightTexture", "RedButton-Highlight"}, {"GetDisabledTexture", "RedButton-Expand-Disabled"}}) do
    local tex = maximize[t[1]](maximize)
    if tex then
        tex:SetAtlas(t[2])
        tex:SetAllPoints()
    end
end

-- [[ Breadcrumbs ]] --
-- Retail's NavBar: World, then the continent and zone shown, each a button; the last one's arrow
-- lists the maps under the one before it.
local nav = CreateFrame("Frame", nil, border)
nav:SetPoint("TOPLEFT", f, "TOPLEFT", 66, -25)
nav:SetPoint("TOPRIGHT", f, "TOPLEFT", 2 + CANVAS_W - 4, -25)
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
local menu -- the dropdown list, below
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
        b.arrow = CreateFrame("Button", nil, b)
        b.arrow:SetWidth(21)
        b.arrow:SetHeight(30)
        b.arrow:SetPoint("RIGHT")
        local a = b.arrow:CreateTexture(nil, "ARTWORK")
        a:SetTexture(HELP)
        a:SetTexCoord(.88867188, .9296875, .296875, .53125)
        a:SetAllPoints()
        b.arrow:SetScript("OnClick", function(self) menu(self:GetParent()) end)
        crumbs[i] = b
    end
    return b
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
            b:SetPoint("LEFT", prev, "RIGHT", -15, 0)
        else
            b:SetPoint("LEFT", 2, 0)
        end
        b:SetScript("OnClick", p.go)
        b:Show()
        prev = b
    end
    for i = #path + 1, #crumbs do
        crumbs[i]:Hide()
    end
end

-- A plain list under a breadcrumb (UIDropDownMenu would taint the map's own dropdowns).
local list = CreateFrame("Frame", nil, border)
list:SetFrameStrata("FULLSCREEN_DIALOG")
list:EnableMouse(true)
list:Hide()
local listBg = list:CreateTexture(nil, "BACKGROUND")
listBg:SetTexture(0, 0, 0, .9)
listBg:SetAllPoints()
local listButtons = {}
function menu(b)
    if list:IsShown() and list.owner == b then
        list:Hide()
        return
    end
    local names, pick = b.list()
    for i, name in ipairs(names) do
        local item = listButtons[i]
        if not item then
            item = CreateFrame("Button", nil, list)
            item:SetHeight(16)
            item:SetPoint("TOPLEFT", 6, -4 - (i - 1) * 16)
            item:SetPoint("RIGHT", -6, 0)
            item.text = item:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            item.text:SetPoint("LEFT")
            item:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            item:GetHighlightTexture():SetBlendMode("ADD")
            listButtons[i] = item
        end
        item.text:SetText(name)
        item:SetScript("OnClick", function()
            list:Hide()
            pick(i)
        end)
        item:Show()
    end
    for i = #names + 1, #listButtons do
        listButtons[i]:Hide()
    end
    list:SetWidth(180)
    list:SetHeight(#names * 16 + 8)
    list:ClearAllPoints()
    list:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 10, 0)
    list.owner = b
    list:Show()
end

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
            elseif button == "LeftButton" then
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
local shownIndex, focused, returnMap
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
abandon:SetScript("OnClick", function()
    SelectQuestLogEntry(shownIndex)
    SetAbandonQuest()
    local items = GetAbandonQuestItems()
    if items then
        StaticPopup_Show("ABANDON_QUEST_WITH_ITEMS", GetAbandonQuestName(), items)
    else
        StaticPopup_Show("ABANDON_QUEST", GetAbandonQuestName())
    end
end)
share:SetScript("OnClick", function()
    SelectQuestLogEntry(shownIndex)
    QuestLogPushQuest()
end)
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

-- [[ Collapsing the quest log ]] --
-- Retail's button on the map's lower right: the log folds away and the frame narrows to the map.
local toggle = CreateFrame("Button", nil, border)
toggle:SetWidth(32)
toggle:SetHeight(32)
toggle:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", 2 + CANVAS_W - 2, 3)
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
-- In windowed mode only (not 3.3.5's movable "advanced" one): WorldMapFrame scaled, the map placed on
-- ours, 3.3.5's border, title and quest tracking box hidden. Fullscreen keeps 3.3.5's own.
local OLD = {WorldMapFrameMiniBorderLeft, WorldMapFrameMiniBorderRight, WorldMapFrameTitle, WorldMapTrackQuest,
    WorldMapFrameCloseButton}
-- Frame levels, set again on every layout: the client sets the map's (WorldMapFrame_ResetFrameLevels,
-- WORLDMAP_POI_FRAMELEVEL - 13 to + 0) when it changes mode. Ours: the background under the map, the
-- quest log over its layers, the border and its buttons on top. 3.3.5 doesn't move children with
-- their parent, so each frame below gets its level.
local function relevel(frame, level)
    frame:SetFrameLevel(level)
    for _, child in ipairs({frame:GetChildren()}) do
        relevel(child, level + 1)
    end
end
local function levels()
    relevel(f, WorldMapFrame:GetFrameLevel())
    relevel(log, WORLDMAP_POI_FRAMELEVEL + 20)
    relevel(border, WORLDMAP_POI_FRAMELEVEL + 40)
    list:SetFrameLevel(WORLDMAP_POI_FRAMELEVEL + 60)
end

local function layout()
    local windowed = WORLDMAP_SETTINGS.size == WORLDMAP_WINDOWED_SIZE and not WORLDMAP_SETTINGS.advanced
    if not windowed then
        -- fullscreen: 3.3.5's own frame (its scale set by the client on show), and the anchors its
        -- layout code adds to, put back as it sets them
        f:Hide()
        if WORLDMAP_SETTINGS.size == WORLDMAP_WINDOWED_SIZE then
            WorldMapFrame:SetScale(1) -- the movable windowed mode
        end
        maximize:SetParent(WorldMapFrame)
        for _, r in ipairs(OLD) do
            r:SetAlpha(1)
            if r.EnableMouse then -- the borders and title are textures
                r:EnableMouse(true)
            end
        end
        if WORLDMAP_SETTINGS.size ~= WORLDMAP_WINDOWED_SIZE then
            WorldMapLevelDropDown:ClearAllPoints()
            WorldMapLevelDropDown:SetPoint("TOPRIGHT", WorldMapPositioningGuide, "TOPRIGHT", -50, -35)
            WorldMapQuestShowObjectives:ClearAllPoints()
            WorldMapQuestShowObjectives:SetPoint("BOTTOMRIGHT", WorldMapPositioningGuide, "BOTTOMRIGHT",
                -15 - WorldMapQuestShowObjectivesText:GetWidth(), 4)
        end
        return
    end
    local width = CANVAS_W + 5 + (logShown() and LOG_W or 0)
    WorldMapFrame:SetScale(SCALE)
    WorldMapFrame:SetWidth(width / SCALE)
    WorldMapFrame:SetHeight(FRAME_H / SCALE)
    f:SetWidth(width)
    -- the map's offsets are in its own units: WORLDMAP_WINDOWED_SIZE under WorldMapFrame's SCALE
    local unit = SCALE * WORLDMAP_WINDOWED_SIZE
    WorldMapDetailFrame:ClearAllPoints()
    WorldMapDetailFrame:SetPoint("TOPLEFT", WorldMapFrame, "TOPLEFT", 2 / unit, -TOP / unit)
    WorldMapBlobFrame.xRatio = nil -- the client's hit maths again for the moved map
    for _, r in ipairs(OLD) do
        r:SetAlpha(0)
        if r.EnableMouse then -- the borders and title are textures
            r:EnableMouse(false)
        end
    end
    placeMaximize()
    WorldMapQuestShowObjectives:ClearAllPoints()
    WorldMapQuestShowObjectives:SetPoint("BOTTOMLEFT", WorldMapDetailFrame, "BOTTOMLEFT", 4, 4)
    WorldMapLevelDropDown:ClearAllPoints()
    WorldMapLevelDropDown:SetPoint("TOPLEFT", WorldMapDetailFrame, "TOPLEFT", -14, -2)
    if logShown() then
        log:Show()
    else
        log:Hide()
    end
    toggleArt()
    f:Show()
    navUpdate()
    logUpdate()
    levels()
end
toggle:SetScript("OnClick", function()
    saved.hideLog = logShown() or nil
    layout()
end)
WorldMapFrame:HookScript("OnHide", function() list:Hide() end)

-- The client rebuilds the markers and its selection with each map update: our focus again after it.
-- A marker clicked on the map opens its quest, as retail's pins do.
hooksecurefunc("WorldMapFrame_UpdateMap", focus)
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
