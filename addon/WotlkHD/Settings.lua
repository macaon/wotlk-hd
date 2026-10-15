-- wotlk-hd: retail's Settings window (Blizzard_SettingsPanel, 920x724) in place of the Interface, Video and
-- Sound frames. Every option page is the client's own panel, shown in the window as retail shows addon
-- pages ("canvas" categories) with retail skins on its controls; okay runs when the window closes, as
-- retail keeps changes on close. Opening any of the old frames, or a panel by
-- InterfaceOptionsFrame_OpenToCategory, opens this window instead.

local Retail = WotlkHD_Retail
local size = Retail.size

local GAMEPLAY = {"Controls", "Combat", "Display", "Objectives", "Social", "ActionBars", "Names", "CombatText",
                  "StatusText", "UnitFrame", "Camera", "Buffs", "Battlenet", "Mouse", "Features", "Help", "Languages"}
local HEADER_FONT = GameFontHighlightMedium or GameFontHighlightLarge or GameFontHighlight
local TITLE_FONT = GameFontHighlightHuge or GameFontHighlightLarge or GameFontHighlight

local panel = CreateFrame("Frame", "WotlkHDSettingsPanel", UIParent)
size(panel, 920, 724)
panel:SetPoint("CENTER")
panel:SetFrameStrata("HIGH")
panel:SetToplevel(true)
panel:EnableMouse(true)
panel:SetMovable(true)
panel:SetClampedToScreen(true)
panel:Hide()
tinsert(UISpecialFrames, "WotlkHDSettingsPanel")

-- FlatPanelBackgroundTemplate's colour (PANEL_BACKGROUND_COLOR, GlobalColor 191: 0xcc1f1e21)
local bg = panel:CreateTexture(nil, "BACKGROUND")
bg:SetTexture(0x1f / 255, 0x1e / 255, 0x21 / 255, 0.8)
bg:SetPoint("TOPLEFT", 7, -18)
bg:SetPoint("BOTTOMRIGHT", -3, 3)
local inner = panel:CreateTexture(nil, "OVERLAY")
inner:SetAtlas("Options_InnerFrame", true)
inner:SetPoint("TOPLEFT", 17, -64)
local border = Retail.MetalFrame(panel)

local title = border:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOP", 0, -5)
title:SetText(GAMEOPTIONS_MENU or "Options")
local drag = CreateFrame("Frame", nil, panel)
drag:SetPoint("TOPLEFT", 0, 0)
drag:SetPoint("TOPRIGHT", -30, 0)
drag:SetHeight(20)
drag:EnableMouse(true)
drag:SetScript("OnMouseDown", function() panel:StartMoving() end)
drag:SetScript("OnMouseUp", function() panel:StopMovingOrSizing() end)

local close = CreateFrame("Button", nil, border)
size(close, 24, 24)
close:SetPoint("TOPRIGHT", 1, 0)
for setter, atlas in pairs({SetNormalTexture = "RedButton-Exit", SetPushedTexture = "RedButton-exit-pressed",
                            SetDisabledTexture = "RedButton-Exit-Disabled", SetHighlightTexture = "RedButton-Highlight"}) do
    close[setter](close, WotlkHD_Atlas[strlower(atlas)][1])
end
close:GetNormalTexture():SetAtlas("RedButton-Exit")
close:GetPushedTexture():SetAtlas("RedButton-exit-pressed")
close:GetDisabledTexture():SetAtlas("RedButton-Exit-Disabled")
close:GetHighlightTexture():SetAtlas("RedButton-Highlight")
close:SetScript("OnClick", function() panel:Hide() end)

local function button(text, w)
    local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    size(b, w or 96, 22)
    b:SetText(text)
    return b
end
local closeButton = button(CLOSE)
closeButton:SetPoint("BOTTOMRIGHT", -16, 16)
closeButton:SetScript("OnClick", function() panel:Hide() end)
local applyButton = button(APPLY)
applyButton:SetPoint("RIGHT", closeButton, "LEFT", -2, 0)

-- [[ Pages ]] --

local container = CreateFrame("Frame", nil, panel)
container:SetPoint("TOPLEFT", 18 + 199 + 16, -76)
container:SetPoint("BOTTOMRIGHT", -22, 46)

local header = CreateFrame("Frame", nil, container)
header:SetPoint("TOPLEFT")
header:SetPoint("TOPRIGHT")
header:SetHeight(50)
local pageTitle = header:CreateFontString(nil, "ARTWORK")
pageTitle:SetFontObject(TITLE_FONT)
pageTitle:SetPoint("TOPLEFT", 7, -22)
local divider = header:CreateTexture(nil, "ARTWORK")
divider:SetAtlas("Options_HorizontalDivider", true)
divider:SetPoint("TOP", 0, -50)
local defaults = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
size(defaults, 96, 22)
defaults:SetPoint("TOPRIGHT", -36, -16)
defaults:SetText(DEFAULTS)

local shown -- the page (a client or addon options panel) in the window

StaticPopupDialogs["WOTLKHD_SETTINGS_DEFAULTS"] = {
    text = "Reset these settings to their defaults?",
    button1 = OKAY,
    button2 = CANCEL,
    OnAccept = function()
        if shown then
            pcall(shown.default, shown)
            pcall(shown.refresh, shown)
        end
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
}
defaults:SetScript("OnClick", function() StaticPopup_Show("WOTLKHD_SETTINGS_DEFAULTS") end)

local function showPage(page)
    if shown and shown ~= page then
        shown:Hide()
    end
    shown = page
    page:SetParent(container)
    page:ClearAllPoints()
    page:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    page:SetPoint("BOTTOMRIGHT")
    local own = page:GetName() and _G[page:GetName() .. "Title"]
    if own and own.Hide then
        own:Hide()
    end
    pageTitle:SetText(page.name)
    Retail.SkinControls(page)
    page:Show()
end

-- [[ Category list ]] --

local list = CreateFrame("ScrollFrame", nil, panel)
list:SetPoint("TOPLEFT", 18, -76)
list:SetPoint("BOTTOMLEFT", 18, 46)
list:SetWidth(199)
local rows = CreateFrame("Frame", nil, list)
size(rows, 199, 1)
list:SetScrollChild(rows)
list:EnableMouseWheel(true)
list:SetScript("OnMouseWheel", function(self, delta)
    local max = math.max(0, rows:GetHeight() - self:GetHeight())
    self:SetVerticalScroll(math.min(max, math.max(0, self:GetVerticalScroll() - delta * 40)))
end)

local headers, buttons, selected = {}, {}, nil

local function refreshButton(b)
    local on = b.page == shown
    b.texture:SetAtlas(on and "Options_List_Active" or "Options_List_Hover", true)
    if on or b.hover then
        b.texture:Show()
        b.label:SetTextColor(1, 1, 1)
    else
        b.texture:Hide()
        b.label:SetTextColor(NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
    end
end

local function selectPage(page)
    showPage(page)
    for _, b in ipairs(buttons) do
        refreshButton(b)
    end
end

local function headerRow(i)
    local h = headers[i]
    if not h then
        h = CreateFrame("Frame", nil, rows)
        size(h, 175, 30)
        h.bg = h:CreateTexture(nil, "ARTWORK")
        h.bg:SetAtlas("Options_CategoryHeader_1", true)
        h.bg:SetPoint("TOPLEFT")
        h.label = h:CreateFontString(nil, "OVERLAY")
        h.label:SetFontObject(HEADER_FONT)
        h.label:SetPoint("LEFT", 20, -1)
        headers[i] = h
    end
    return h
end

local function buttonRow(i)
    local b = buttons[i]
    if not b then
        b = CreateFrame("Button", nil, rows)
        size(b, 175, 20)
        b.texture = b:CreateTexture(nil, "BACKGROUND")
        b.texture:SetPoint("CENTER")
        b.label = b:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        b.label:SetJustifyH("LEFT")
        b.label:SetPoint("BOTTOMRIGHT", 0, 1)
        b:SetScript("OnEnter", function(self) self.hover = true refreshButton(self) end)
        b:SetScript("OnLeave", function(self) self.hover = nil refreshButton(self) end)
        b:SetScript("OnClick", function(self)
            PlaySound("igMainMenuOptionCheckBoxOn")
            if self.page.wotlkhdOpen then
                self.page.wotlkhdOpen()
            else
                selectPage(self.page)
            end
        end)
        buttons[i] = b
    end
    return b
end

-- Key Bindings stays the client's own frame (Blizzard_BindingUI); its row opens it.
local keybindings = {name = KEY_BINDINGS, wotlkhdOpen = function()
    panel:Hide()
    KeyBindingFrame_LoadUI()
    ShowUIPanel(KeyBindingFrame)
end}

local function gameCategories()
    local groups = {{name = GAMEPLAY_HEADER or "Gameplay"}, {name = "Accessibility"}, {name = SYSTEM_HEADER or "System"}}
    for _, key in ipairs(GAMEPLAY) do
        local page = _G["InterfaceOptions" .. key .. "Panel"]
        if page then
            tinsert(groups[1], page)
        end
    end
    tinsert(groups[1], keybindings)
    for _, page in ipairs(WotlkHD_AccessibilityPages) do
        tinsert(groups[2], page)
    end
    for _, frame in ipairs({VideoOptionsFrame, AudioOptionsFrame}) do
        for _, page in ipairs(frame.categoryList) do
            tinsert(groups[3], page)
        end
    end
    return groups
end

local function addOnCategories()
    local group = {name = ADDONS}
    for _, page in ipairs(INTERFACEOPTIONS_ADDONCATEGORIES) do
        tinsert(group, page)
    end
    return {group}
end

local tab = 1
local function layoutList()
    for _, h in ipairs(headers) do
        h:Hide()
    end
    for _, b in ipairs(buttons) do
        b:Hide()
    end
    local y, nh, nb = 0, 0, 0
    for _, group in ipairs(tab == 1 and gameCategories() or addOnCategories()) do
        nh = nh + 1
        local h = headerRow(nh)
        h.label:SetText(group.name)
        h:SetPoint("TOPLEFT", 0, -y)
        h:Show()
        y = y + 30
        for _, page in ipairs(group) do
            nb = nb + 1
            local b = buttonRow(nb)
            b.page = page
            b.label:SetText(page.name)
            b.label:SetPoint("TOPLEFT", page.parent and 46 or 36, 1)
            b:SetPoint("TOPLEFT", 0, -y)
            refreshButton(b)
            b:Show()
            y = y + 20
        end
        y = y + 18 -- SettingsCategoryListSpacerTemplate
    end
    rows:SetHeight(math.max(1, y))
    list:SetVerticalScroll(0)
end

-- [[ Tabs (MinimalTabTemplate) ]] --

local tabs = {}
local function refreshTabs()
    for i, t in ipairs(tabs) do
        local on = i == tab
        t.left:SetAtlas(on and "Options_Tab_Active_Left" or "Options_Tab_Left", true)
        t.middle:SetAtlas(on and "Options_Tab_Active_Middle" or "Options_Tab_Middle", true)
        t.right:SetAtlas(on and "Options_Tab_Active_Right" or "Options_Tab_Right", true)
        t.middle:SetPoint("TOPRIGHT", t.right, "TOPLEFT")
        if on then
            t.text:SetTextColor(1, 1, 1)
        else
            t.text:SetTextColor(NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
        end
    end
end

for i, label in ipairs({GAME or "Game", ADDONS}) do
    local t = CreateFrame("Button", nil, panel)
    t:SetHeight(37)
    t.left = t:CreateTexture(nil, "BACKGROUND")
    t.left:SetPoint("BOTTOMLEFT")
    t.right = t:CreateTexture(nil, "BACKGROUND")
    t.right:SetPoint("BOTTOMRIGHT")
    t.middle = t:CreateTexture(nil, "BACKGROUND")
    t.middle:SetPoint("TOPLEFT", t.left, "TOPRIGHT")
    t.text = t:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    t.text:SetPoint("BOTTOM", 0, 6)
    t.text:SetText(label)
    t:SetWidth(t.text:GetStringWidth() + 40)
    if i == 1 then
        t:SetPoint("TOPLEFT", 32, -27)
    else
        t:SetPoint("TOPLEFT", tabs[i - 1], "TOPRIGHT", 5, 0)
    end
    t:SetScript("OnClick", function()
        PlaySound("igCharacterInfoTab")
        tab = i
        refreshTabs()
        layoutList()
    end)
    tabs[i] = t
end

-- [[ Opening and closing ]] --

local OPTION_FRAMES = {InterfaceOptionsFrame, VideoOptionsFrame, AudioOptionsFrame}

local function okay()
    InterfaceOptionsFrameOkay_OnClick(nil, nil, true)
    VideoOptionsFrameOkay_OnClick(nil, nil, true)
    OptionsFrameOkay_OnClick(AudioOptionsFrame)
    if AudioOptionsFrame.audioRestart then
        AudioOptionsFrame_AudioRestart()
    end
end
applyButton:SetScript("OnClick", okay)

panel:SetScript("OnShow", function()
    PlaySound("igMainMenuOption")
    InterfaceOptionsOptionsFrame_RefreshCategories()
    InterfaceOptionsOptionsFrame_RefreshAddOns()
    OptionsFrame_RefreshCategories(VideoOptionsFrame)
    OptionsFrame_RefreshCategories(AudioOptionsFrame)
    refreshTabs()
    layoutList()
    if not shown then
        selectPage(InterfaceOptionsControlsPanel)
    end
end)

panel:SetScript("OnHide", function()
    PlaySound("gsTitleOptionExit")
    okay()
    for _, frame in ipairs(OPTION_FRAMES) do
        if frame.gameRestart then
            StaticPopup_Show("CLIENT_RESTART_ALERT")
        elseif frame.logout then
            StaticPopup_Show("CLIENT_LOGOUT_ALERT")
        end
        frame.gameRestart, frame.logout = nil, nil
    end
end)

function WotlkHD_OpenSettings(page)
    if page then
        local addOn = true
        for _, p in ipairs(gameCategories()[1]) do
            addOn = addOn and p ~= page
        end
        for _, p in ipairs(gameCategories()[2]) do
            addOn = addOn and p ~= page
        end
        tab = addOn and 2 or 1
        shown = nil
    end
    panel:Show()
    if page then
        selectPage(page)
        refreshTabs()
        layoutList()
    end
end

-- The old frames open this window instead, at the page they would have shown.
for _, frame in ipairs(OPTION_FRAMES) do
    frame:HookScript("OnShow", function(self)
        local page = self.panelContainer and self.panelContainer.displayedPanel
            or self == InterfaceOptionsFrame and InterfaceOptionsFramePanelContainer.displayedPanel
        HideUIPanel(self)
        WotlkHD_OpenSettings(page)
    end)
end

-- The game menu's Video, Sound and Interface buttons become retail's one Options button.
GameMenuButtonOptions:SetText(GAMEOPTIONS_MENU or "Options")
GameMenuButtonOptions:SetScript("OnClick", function()
    PlaySound("igMainMenuOption")
    HideUIPanel(GameMenuFrame)
    WotlkHD_OpenSettings()
end)
GameMenuButtonSoundOptions:Hide()
GameMenuButtonUIOptions:Hide()
GameMenuButtonKeybindings:ClearAllPoints()
GameMenuButtonKeybindings:SetPoint("TOP", GameMenuButtonOptions, "BOTTOM", 0, -1)
GameMenuFrame:SetHeight(GameMenuFrame:GetHeight() - 2 * (GameMenuButtonOptions:GetHeight() + 1))
