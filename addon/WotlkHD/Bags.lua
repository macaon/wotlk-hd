-- wotlk-hd: retail's combined bags (ContainerFrameCombinedBags, as with Combine Bags on): the backpack
-- and the four bags in one window with a portrait, the title, a search box, 10 columns of retail item
-- slots with quality borders, and money. Item buttons are the client's ContainerFrameItemButtonTemplate
-- under one frame per bag (its ID the bag), so clicking, tooltips and use stay the client's own code.
--
-- The client's bag frames still open and close as before (keys, the bag bar, OpenAllBags); one showing
-- a bag of ours goes under a hidden parent, and our window shows while any of them is open (checked
-- after each of the client's bag functions). Nothing of
-- the client's is replaced or written into (see docs/notes.md, Taint).

local Retail = WotlkHD_Retail
local COLUMNS, SIZE, SPACING, PADDING = 10, 37, 5, 15
local BAGS = {0, 1, 2, 3, 4}

local frame = CreateFrame("Frame", "WotlkHDBags", UIParent)
frame:SetFrameStrata("MEDIUM")
frame:SetToplevel(true)
frame:EnableMouse(true)
frame:SetMovable(true)
frame:SetClampedToScreen(true)
frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -20, 110)
frame:Hide() -- Esc closes the client's bag frames, and with them this

local bg = frame:CreateTexture(nil, "BACKGROUND")
bg:SetTexture(0x1f / 255, 0x1e / 255, 0x21 / 255, 0.8)
bg:SetPoint("TOPLEFT", 2, -2)
bg:SetPoint("BOTTOMRIGHT", -2, 2)
local border, portrait = Retail.MetalFrame(frame, true)
SetPortraitToTexture(portrait, "Interface\\Icons\\INV_Misc_Bag_08")
local title = border:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOP", 0, -5)
title:SetText(COMBINED_BAG_TITLE or "Combined Backpack")
local drag = CreateFrame("Frame", nil, frame)
drag:SetPoint("TOPLEFT", 60, 0)
drag:SetPoint("TOPRIGHT", -30, 0)
drag:SetHeight(20)
drag:EnableMouse(true)
drag:SetScript("OnMouseDown", function() frame:StartMoving() end)
drag:SetScript("OnMouseUp", function() frame:StopMovingOrSizing() end)

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
close:SetScript("OnClick", function() CloseAllBags() end)

-- [[ Search ]] --
-- Retail's search box; items that don't match are dimmed.

local layout -- below
local search = Retail.SearchBox(frame, "WotlkHDBagsSearch", function()
    if frame:IsShown() then
        layout()
    end
end)
search:SetPoint("TOPLEFT", 62, -37)
search:SetPoint("TOPRIGHT", -46, -37)

-- [[ Items ]] --

local holders, buttons = {}, {}
local newItems = {} -- "bag:slot" -> true for items looted since the bags were last closed
for _, bag in ipairs(BAGS) do
    holders[bag] = CreateFrame("Frame", "WotlkHDBagsBag" .. bag, frame)
    holders[bag]:SetID(bag)
    holders[bag]:SetAllPoints()
end

local function button(n)
    local b = buttons[n]
    if b then
        return b
    end
    b = CreateFrame("Button", "WotlkHDBagsItem" .. n, holders[0], "ContainerFrameItemButtonTemplate")
    b:SetWidth(SIZE)
    b:SetHeight(SIZE)
    local slot = b:CreateTexture(nil, "BACKGROUND")
    slot:SetAtlas("bags-item-slot64")
    slot:SetAllPoints()
    b.quality = b:CreateTexture(nil, "OVERLAY")
    b.quality:SetTexture("Interface\\AddOns\\WotlkHD\\Art\\whiteiconframe")
    b.quality:SetAllPoints()
    b.quality:SetBlendMode("ADD")
    b.junk = b:CreateTexture(nil, "OVERLAY")
    b.junk:SetAtlas("bags-junkcoin", true)
    b.junk:SetPoint("TOPLEFT", 1, 0)
    b.glow = b:CreateTexture(nil, "OVERLAY")
    b.glow:SetPoint("TOPLEFT", -2, 2)
    b.glow:SetPoint("BOTTOMRIGHT", 2, -2)
    b.glow:SetBlendMode("ADD")
    b.quest = _G[b:GetName() .. "IconQuestTexture"]
    b.dim = b:CreateTexture(nil, "OVERLAY")
    b.dim:SetTexture(0, 0, 0, 0.8)
    b.dim:SetAllPoints()
    b:HookScript("OnEnter", function(self) -- seen: no longer new
        if self.newKey and newItems[self.newKey] then
            newItems[self.newKey] = nil
            self.glow:Hide()
        end
    end)
    buttons[n] = b
    return b
end

local function matches(bag, slot, text)
    if text == "" then
        return true
    end
    local link = GetContainerItemLink(bag, slot)
    local name = link and GetItemInfo(link)
    return name and strlower(name):find(text, 1, true)
end

local GLOW = {[2] = "bags-glow-green", [3] = "bags-glow-blue", [4] = "bags-glow-purple", [5] = "bags-glow-orange",
    [6] = "bags-glow-orange", [7] = "bags-glow-orange"}

local function updateItem(b, bag, slot, text)
    local texture, count, locked, quality = GetContainerItemInfo(bag, slot)
    SetItemButtonTexture(b, texture)
    SetItemButtonCount(b, count)
    SetItemButtonDesaturated(b, locked)
    local link = texture and GetContainerItemLink(bag, slot)
    if link and (not quality or quality < 0) then
        quality = select(3, GetItemInfo(link))
    end
    if texture and quality and quality >= 2 and ITEM_QUALITY_COLORS[quality] then
        local c = ITEM_QUALITY_COLORS[quality]
        b.quality:SetVertexColor(c.r, c.g, c.b)
        b.quality:Show()
    else
        b.quality:Hide()
    end
    if texture and quality == 0 then
        b.junk:Show()
    else
        b.junk:Hide()
    end
    local isQuest, questId, active = GetContainerItemQuestInfo(bag, slot)
    if texture and questId and not active then
        b.quest:SetTexture(TEXTURE_ITEM_QUEST_BANG)
        b.quest:Show()
    elseif texture and (questId or isQuest) then
        b.quest:SetTexture(TEXTURE_ITEM_QUEST_BORDER)
        b.quest:Show()
    else
        b.quest:Hide()
    end
    b.newKey = bag .. ":" .. slot
    if texture and newItems[b.newKey] then
        b.glow:SetAtlas(GLOW[quality or 1] or "bags-glow-white")
        b.glow:Show()
    else
        b.glow:Hide()
    end
    if texture and not matches(bag, slot, text) then
        b.dim:Show()
    else
        b.dim:Hide()
    end
    ContainerFrame_UpdateCooldown(bag, b)
end

-- Retail lays the slots out from the bottom right: the backpack at the bottom, the last bag on top.
function layout() -- the local declared with the search box
    local n, text = 0, strlower(search:GetText())
    for _, bag in ipairs(BAGS) do
        for slot = 1, GetContainerNumSlots(bag) do
            n = n + 1
            local b = button(n)
            b:SetParent(holders[bag])
            b:SetID(slot)
            b:Show()
            updateItem(b, bag, slot, text)
        end
    end
    for i = n + 1, #buttons do
        buttons[i]:Hide()
    end
    local rows = math.max(math.ceil(n / COLUMNS), 1)
    for i = 1, n do
        local col, row = (i - 1) % COLUMNS, math.floor((i - 1) / COLUMNS)
        buttons[i]:ClearAllPoints()
        buttons[i]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8 - col * (SIZE + SPACING),
            30 + row * (SIZE + SPACING))
    end
    frame:SetWidth(COLUMNS * SIZE + (COLUMNS - 1) * SPACING + PADDING)
    frame:SetHeight(rows * SIZE + (rows - 1) * SPACING + 75 + 26)
end


local money = CreateFrame("Frame", "WotlkHDBagsMoney", frame, "SmallMoneyFrameTemplate")
money:SetPoint("BOTTOMRIGHT", -6, 10)
MoneyFrame_SetType(money, "PLAYER")

-- [[ Opening and closing with the client's bag frames ]] --

local hidden = CreateFrame("Frame")
hidden:Hide()

local function anyOpen()
    for i = 1, NUM_CONTAINER_FRAMES do
        local f = _G["ContainerFrame" .. i]
        if f:IsShown() and f:GetID() >= 0 and f:GetID() <= 4 then
            return true
        end
    end
end

-- A frame under a hidden parent is already invisible, so it gets no OnShow or OnHide: after each of the
-- client's bag functions, ours follows whether any of our bags is open.
local function sync()
    for i = 1, NUM_CONTAINER_FRAMES do
        local f = _G["ContainerFrame" .. i]
        local ours = f:GetID() >= 0 and f:GetID() <= 4
        f:SetParent(ours and hidden or UIParent)
    end
    if anyOpen() then
        frame:Show()
    else
        frame:Hide()
    end
end
for _, name in ipairs({"ContainerFrame_GenerateFrame", "CloseBag", "CloseBackpack", "CloseAllBags", "ToggleBag",
    "ToggleBackpack", "OpenBag", "OpenBackpack", "OpenAllBags", "CloseAllWindows"}) do
    hooksecurefunc(name, sync)
end

frame:SetScript("OnShow", function()
    PlaySound("igBackPackOpen")
    MoneyFrame_UpdateMoney(money)
    layout()
end)
frame:SetScript("OnHide", function()
    PlaySound("igBackPackClose")
    search:ClearFocus()
    wipe(newItems) -- retail's new item glow lasts until the bags close
    if anyOpen() then -- closed by Esc: close the client's too
        CloseAllBags()
    end
end)

local events = CreateFrame("Frame")
for _, e in ipairs({"BAG_UPDATE", "ITEM_LOCK_CHANGED", "BAG_UPDATE_COOLDOWN", "PLAYERBANKSLOTS_CHANGED"}) do
    events:RegisterEvent(e)
end
events:SetScript("OnEvent", function()
    if frame:IsShown() then
        layout()
    end
end)

-- The bank opens your bags, as on retail (3.3.5 opens only the backpack, and only at a vendor); those it
-- opened close with it.
local openedForBank
local bank = CreateFrame("Frame")
bank:RegisterEvent("BANKFRAME_OPENED")
bank:RegisterEvent("BANKFRAME_CLOSED")
bank:SetScript("OnEvent", function(_, event)
    if event == "BANKFRAME_OPENED" then
        openedForBank = not anyOpen()
        if openedForBank then
            OpenBackpack()
            for bag = 1, 4 do
                OpenBag(bag)
            end
        end
    elseif openedForBank then
        openedForBank = nil
        CloseAllBags()
    end
end)

-- [[ New items ]] --
-- 3.3.5 doesn't track new items: what a bag holds more of than before (by item) glows, from a snapshot
-- taken after login settles.

local known, ready = {}, false

local function totals()
    local t = {}
    for _, bag in ipairs(BAGS) do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local id = tonumber(link:match("item:(%d+)"))
                t[id] = (t[id] or 0) + select(2, GetContainerItemInfo(bag, slot))
            end
        end
    end
    return t
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("BAG_UPDATE")
watcher:SetScript("OnEvent", function(self, event, bag)
    if event == "PLAYER_ENTERING_WORLD" then
        local wait = 3
        self:SetScript("OnUpdate", function(_, dt)
            wait = wait - dt
            if wait < 0 then
                self:SetScript("OnUpdate", nil)
                known, ready = totals(), true
            end
        end)
        return
    end
    if not ready or not bag or bag < 0 or bag > 4 then
        return
    end
    local now = totals()
    for slot = 1, GetContainerNumSlots(bag) do
        local link = GetContainerItemLink(bag, slot)
        local id = link and tonumber(link:match("item:(%d+)"))
        if id and (now[id] or 0) > (known[id] or 0) then
            newItems[bag .. ":" .. slot] = true
        end
    end
    known = now
end)

-- [[ Bag settings: assignments and ignore (per character, WotlkHD_CharSaved.bags) ]] --

local CATEGORY = {"equipment", "consumables", "tradegoods", "junk"}
local CATEGORY_NAME = {equipment = BAG_FILTER_EQUIPMENT or "Equipment", consumables = BAG_FILTER_CONSUMABLES or "Consumables",
    tradegoods = BAG_FILTER_TRADE_GOODS or "Trade Goods", junk = BAG_FILTER_JUNK or "Junk"}

local function bagSettings(bag)
    WotlkHD_CharSaved = WotlkHD_CharSaved or {}
    WotlkHD_CharSaved.bags = WotlkHD_CharSaved.bags or {}
    WotlkHD_CharSaved.bags[bag] = WotlkHD_CharSaved.bags[bag] or {}
    return WotlkHD_CharSaved.bags[bag]
end

-- [[ Sorting ]] --
-- Retail's Clean Up Bags: stacks merged, then items in order (by type, quality, item level, name; junk
-- last), an assigned bag taking its kind first. 3.3.5 has no sort, so items move one pick-up at a time,
-- each after the last one's locks clear. Profession bags and ignored bags are left alone.

-- GetAuctionItemClasses: Weapon, Armor, Container, Consumable, Glyph, Trade Goods, Projectile, Quiver,
-- Recipe, Gem, Miscellaneous, Quest (localized; by position).
local CLASS = {}
for i, name in ipairs({GetAuctionItemClasses()}) do
    CLASS[name] = i
end

local function itemInfo(bag, slot)
    local link = GetContainerItemLink(bag, slot)
    if not link then
        return
    end
    local name, _, quality, level, _, class, _, maxStack = GetItemInfo(link)
    local c = CLASS[class]
    local category = quality == 0 and "junk" or (c == 1 or c == 2) and "equipment" or c == 4 and "consumables"
        or (c == 6 or c == 9 or c == 10) and "tradegoods"
    return {link = link, id = tonumber(link:match("item:(%d+)")), count = select(2, GetContainerItemInfo(bag, slot)),
        name = name or "", quality = quality or 1, level = level or 0, class = c or 99, max = maxStack or 1,
        category = category}
end

local function before(a, b)
    if (a.quality == 0) ~= (b.quality == 0) then
        return b.quality == 0
    elseif a.class ~= b.class then
        return a.class < b.class
    elseif a.quality ~= b.quality then
        return a.quality > b.quality
    elseif a.level ~= b.level then
        return a.level > b.level
    elseif a.name ~= b.name then
        return a.name < b.name
    end
    return a.count > b.count
end

local function key(bag, slot)
    local link = GetContainerItemLink(bag, slot)
    return link and link .. "#" .. select(2, GetContainerItemInfo(bag, slot))
end

local sorter = CreateFrame("Frame")
sorter:Hide()
local slots, order, plan, phase, waited, from

local function sortableSlots()
    local list = {}
    for _, bag in ipairs(BAGS) do
        local _, family = GetContainerNumFreeSlots(bag)
        if family == 0 and not bagSettings(bag).ignore then
            for slot = 1, GetContainerNumSlots(bag) do
                tinsert(list, {bag, slot})
            end
        end
    end
    return list
end

local function busy()
    if CursorHasItem() then
        return true
    end
    for _, s in ipairs(slots) do
        if select(3, GetContainerItemInfo(s[1], s[2])) then
            return true
        end
    end
end

-- A stack dropped on a partial stack of the same item fills it and keeps the rest on the cursor: that goes
-- back where it came from (see the OnUpdate).
local function move(a, b)
    from = a
    PickupContainerItem(a[1], a[2])
    PickupContainerItem(b[1], b[2])
end

-- One merge of two partial stacks of the same item, the later onto the earlier; false when none is left.
local function mergeStep()
    local partial = {}
    for _, s in ipairs(slots) do
        local it = itemInfo(s[1], s[2])
        if it and it.max > 1 and it.count < it.max then
            if partial[it.id] then
                move(s, partial[it.id])
                return true
            end
            partial[it.id] = s
        end
    end
end

-- Where everything goes: each assigned bag's slots take its kind first, the rest fill the other slots in
-- order, then what's left of the assigned bags.
local function makePlan()
    local items = {}
    for _, s in ipairs(slots) do
        local it = itemInfo(s[1], s[2])
        if it then
            it.key = key(s[1], s[2])
            tinsert(items, it)
        end
    end
    table.sort(items, before)
    order, plan = {}, {}
    local used, spare = {}, {}
    for _, bag in ipairs(BAGS) do
        local cat = bagSettings(bag).assign
        if cat then
            for _, s in ipairs(slots) do
                if s[1] == bag then
                    local pick
                    for i, it in ipairs(items) do
                        if not used[it] and it.category == cat then
                            pick = it
                            break
                        end
                    end
                    if pick then
                        used[pick] = true
                        tinsert(order, s)
                        tinsert(plan, pick.key)
                    else
                        tinsert(spare, s)
                    end
                end
            end
        end
    end
    local rest = {}
    for _, s in ipairs(slots) do
        if not bagSettings(s[1]).assign then
            tinsert(rest, s)
        end
    end
    for _, s in ipairs(spare) do
        tinsert(rest, s)
    end
    local i = 0
    for _, it in ipairs(items) do
        if not used[it] then
            i = i + 1
            tinsert(order, rest[i])
            tinsert(plan, it.key)
        end
    end
end

-- One move toward the plan: the first slot that's wrong gets its item from a later one; false when done.
local function arrangeStep()
    for i, s in ipairs(order) do
        if key(s[1], s[2]) ~= plan[i] then
            for j = i + 1, #order do
                local t = order[j]
                if key(t[1], t[2]) == plan[i] then
                    move(t, s)
                    return true
                end
            end
        end
    end
end

sorter:SetScript("OnUpdate", function(self, dt)
    if CursorHasItem() and from then
        PickupContainerItem(from[1], from[2])
        from = nil
        return
    end
    if busy() then
        waited = waited + dt
        if waited > 5 then -- stuck (an item that won't move): stop where it is
            self:Hide()
        end
        return
    end
    waited = 0
    if phase == "merge" then
        if not mergeStep() then
            phase = "arrange"
            makePlan()
        end
    elseif not arrangeStep() then
        self:Hide()
    end
end)
sorter:SetScript("OnHide", function()
    if frame:IsShown() then
        layout()
    end
end)

local function sortBags()
    if sorter:IsShown() then
        return
    end
    slots, phase, waited = sortableSlots(), "merge", 0
    sorter:Show()
end

local sort = CreateFrame("Button", nil, frame)
sort:SetWidth(28)
sort:SetHeight(28)
sort:SetPoint("LEFT", search, "RIGHT", 6, 0)
sort:SetNormalTexture(WotlkHD_Atlas["bags-button-autosort-up"][1])
sort:GetNormalTexture():SetAtlas("bags-button-autosort-up")
sort:SetPushedTexture(WotlkHD_Atlas["bags-button-autosort-down"][1])
sort:GetPushedTexture():SetAtlas("bags-button-autosort-down")
sort:SetHighlightTexture(WotlkHD_Atlas["bags-button-autosort-up"][1])
sort:GetHighlightTexture():SetAtlas("bags-button-autosort-up")
sort:GetHighlightTexture():SetBlendMode("ADD")
sort:SetScript("OnClick", sortBags)
sort:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(BAG_CLEANUP_BAGS or "Clean Up Bags")
    GameTooltip:Show()
end)
sort:SetScript("OnLeave", GameTooltip_Hide)

-- [[ Bag menu: right-click a bag on the bag bar ]] --

local menu = CreateFrame("Frame", "WotlkHDBagMenu", UIParent, "UIDropDownMenuTemplate")
UIDropDownMenu_Initialize(menu, function(self)
    local bag = self.bag
    if not bag then
        return
    end
    local settings = bagSettings(bag)
    local info = UIDropDownMenu_CreateInfo()
    if bag > 0 then
        info.text, info.isTitle, info.notCheckable = BAG_FILTER_ASSIGN_TO or "Assign To:", true, true
        UIDropDownMenu_AddButton(info)
        for _, cat in ipairs(CATEGORY) do
            info = UIDropDownMenu_CreateInfo()
            info.text, info.checked = CATEGORY_NAME[cat], settings.assign == cat
            info.func = function()
                settings.assign = settings.assign ~= cat and cat or nil
            end
            UIDropDownMenu_AddButton(info)
        end
    end
    info = UIDropDownMenu_CreateInfo()
    info.text, info.isTitle, info.notCheckable = BAG_FILTER_CLEANUP or "Clean Up:", true, true
    UIDropDownMenu_AddButton(info)
    info = UIDropDownMenu_CreateInfo()
    info.text, info.checked = BAG_FILTER_IGNORE or "Ignore This Bag", settings.ignore
    info.func = function()
        settings.ignore = not settings.ignore or nil
    end
    UIDropDownMenu_AddButton(info)
end, "MENU")

local function bagMenu(button, bag)
    local click = button:GetScript("OnClick")
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", function(self, which, ...)
        if which == "RightButton" then
            menu.bag = bag
            ToggleDropDownMenu(1, nil, menu, self, 0, 0)
        else
            click(self, which, ...)
        end
    end)
end
bagMenu(MainMenuBarBackpackButton, 0)
for i = 0, NUM_BAG_SLOTS - 1 do
    bagMenu(_G["CharacterBag" .. i .. "Slot"], i + 1)
end
