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

local search = CreateFrame("EditBox", "WotlkHDBagsSearch", frame)
search:SetAutoFocus(false)
search:SetFontObject("ChatFontNormal")
search:SetHeight(20)
search:SetPoint("TOPLEFT", 62, -37)
search:SetPoint("TOPRIGHT", -12, -37)
search:SetTextInsets(20, 20, 0, 0)
local parts = Retail.ThreeSlice(search, "BACKGROUND", "common-search-border-middle", 8, 8)
parts[1]:SetAtlas("common-search-border-left")
parts[1]:SetPoint("TOPLEFT", -5, 10)
parts[1]:SetPoint("BOTTOMLEFT", -5, -10)
parts[3]:SetAtlas("common-search-border-right")
parts[3]:SetPoint("TOPRIGHT", 5, 10)
parts[3]:SetPoint("BOTTOMRIGHT", 5, -10)
parts[2]:SetTexCoord(unpack(WotlkHD_Atlas["common-search-border-middle"], 4, 7))
local glass = search:CreateTexture(nil, "OVERLAY")
glass:SetAtlas("common-search-magnifyingglass")
glass:SetWidth(14)
glass:SetHeight(14)
glass:SetPoint("LEFT", 3, -1)
local hint = search:CreateFontString(nil, "OVERLAY", "GameFontDisable")
hint:SetPoint("LEFT", 20, 0)
hint:SetText(SEARCH)
local clear = CreateFrame("Button", nil, search)
clear:SetWidth(14)
clear:SetHeight(14)
clear:SetPoint("RIGHT", -3, 0)
clear:SetNormalTexture(WotlkHD_Atlas["common-search-clearbutton"][1])
clear:GetNormalTexture():SetAtlas("common-search-clearbutton")
clear:Hide()
clear:SetScript("OnClick", function()
    search:SetText("")
    search:ClearFocus()
end)
search:SetScript("OnEscapePressed", search.ClearFocus)
search:SetScript("OnEnterPressed", search.ClearFocus)

-- [[ Items ]] --

local holders, buttons = {}, {}
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
    b.dim = b:CreateTexture(nil, "OVERLAY")
    b.dim:SetTexture(0, 0, 0, 0.8)
    b.dim:SetAllPoints()
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
    if texture and not matches(bag, slot, text) then
        b.dim:Show()
    else
        b.dim:Hide()
    end
    ContainerFrame_UpdateCooldown(bag, b)
end

-- Retail lays the slots out from the bottom right: the backpack at the bottom, the last bag on top.
local function layout()
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

search:SetScript("OnTextChanged", function(self)
    if self:GetText() == "" then
        hint:Show()
        clear:Hide()
    else
        hint:Hide()
        clear:Show()
    end
    if frame:IsShown() then
        layout()
    end
end)

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
