-- wotlk-hd: retail options that dinput8.dll adds to the client (cvars from client/controls.c and
-- client/effects.cpp), on the pages where retail has them: Mouseover Cast on Controls, Lock Cursor to
-- Window on Mouse, and Accessibility > Colors for the colorblind filter.
--
-- Our controls stay out of the client's pages' own tables (options, controls): a table that addon code
-- adds to is rebuilt by that code, which taints everything already in it, and the client then sets its
-- options up tainted (SHOW_TARGET_OF_TARGET from the Combat page's table: target of target blocked in
-- combat). So ours apply when changed, as on retail, and read their cvar when shown.

-- A checkbox bound to a cvar; dependent is a dropdown it enables.
local function check(page, cvar, label, tooltip, anchor, x, y)
    local c = CreateFrame("CheckButton", page:GetName() .. cvar, page, "InterfaceOptionsCheckButtonTemplate")
    c:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x, y)
    _G[c:GetName() .. "Text"]:SetText(label)
    c.tooltipText = tooltip
    local function dependent(self)
        if self.dependent and self:GetChecked() then
            UIDropDownMenu_EnableDropDown(self.dependent)
        elseif self.dependent then
            UIDropDownMenu_DisableDropDown(self.dependent)
        end
    end
    c:SetScript("OnShow", function(self)
        self:SetChecked(GetCVar(cvar) == "1")
        dependent(self)
    end)
    c:SetScript("OnClick", function(self)
        SetCVar(cvar, self:GetChecked() and "1" or "0")
        dependent(self)
    end)
    return c
end

-- A dropdown bound to a cvar; choices are {value, text}. Changes apply at once, as the client's own
-- dropdowns do.
local function dropdown(page, cvar, label, choices, anchor, x, y)
    local dd = CreateFrame("Frame", page:GetName() .. cvar, page, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x, y)
    local text = dd:CreateFontString(dd:GetName() .. "Label", "BACKGROUND", "GameFontHighlight")
    text:SetPoint("BOTTOMLEFT", dd, "TOPLEFT", 16, 3)
    text:SetText(label)
    local function textOf(value)
        for _, c in ipairs(choices) do
            if c[1] == value then
                return c[2]
            end
        end
    end
    local function init()
        for _, c in ipairs(choices) do
            local info = UIDropDownMenu_CreateInfo()
            info.text, info.value = c[2], c[1]
            info.checked = c[1] == dd.value
            info.func = function(button) dd:SetValue(button.value) end
            UIDropDownMenu_AddButton(info)
        end
    end
    function dd:SetValue(value)
        self.value = value
        SetCVar(cvar, value)
        UIDropDownMenu_SetSelectedValue(self, value)
        UIDropDownMenu_SetText(self, textOf(value))
    end
    function dd:GetValue()
        return GetCVar(cvar)
    end
    function dd:RefreshValue()
        self.value = GetCVar(cvar)
        UIDropDownMenu_Initialize(self, init)
        UIDropDownMenu_SetSelectedValue(self, self.value)
        UIDropDownMenu_SetText(self, textOf(self.value))
    end
    UIDropDownMenu_SetWidth(dd, 140)
    dd:SetScript("OnShow", dd.RefreshValue)
    return dd
end

-- [[ Combat: Mouseover Cast and its key, as on retail ]] --

local combat = InterfaceOptionsCombatPanel
local mouseover = check(combat, "hdMouseoverCast", "Mouseover Cast",
    "Action bar spells go to the unit under your mouse when they can, instead of your target.",
    InterfaceOptionsCombatPanelFocusCastKeyDropDown, 13, -16)
local mouseoverKey = dropdown(combat, "hdMouseoverCastKey", "",
    {{"0", NONE_KEY}, {"1", ALT_KEY}, {"2", CTRL_KEY}, {"3", SHIFT_KEY}}, mouseover, 0, 0)
mouseoverKey:ClearAllPoints() -- retail puts it on the same row; the client's page has no room right of it
mouseoverKey:SetPoint("TOPLEFT", mouseover, "BOTTOMLEFT", -13, -4)
mouseover.dependent = mouseoverKey

-- [[ Mouse: Lock Cursor to Window ]] --

check(InterfaceOptionsMousePanel, "hdLockCursor", "Lock Cursor to Window",
    "Keeps the cursor inside the game window while it has focus.", InterfaceOptionsMousePanelWoWMouse, 0, -8)

-- [[ Unit Frames: Raid-Style Party Frames ]] --

local raidStyle = check(InterfaceOptionsUnitFramePanel, "hdRaidStyleParty", "Use Raid-Style Party Frames",
    "Shows your party in raid frames instead of the party frames.", InterfaceOptionsUnitFramePanelFullSizeFocusFrame,
    0, -8)
check(InterfaceOptionsUnitFramePanel, "hdRaidClassColors", "Display Class Colors",
    "Raid frame health bars in class colours instead of green.", raidStyle, 0, -8)

-- [[ Accessibility: Colors ]] --

local colors = CreateFrame("Frame", "WotlkHDColorsPanel", UIParent)
colors.name = COLORS
colors.options = {}
colors:Hide()
BlizzardOptionsPanel_OnLoad(colors)
colors:SetScript("OnShow", BlizzardOptionsPanel_Refresh) -- not one of the client's categories: nothing else refreshes it
WotlkHD_AccessibilityPages = {colors}

-- The client's colorblind mode (item quality as text and the like) moves here from Display, as on
-- retail; Display still owns it for Okay and Defaults.
local uiMode = InterfaceOptionsDisplayPanelColorblindMode
InterfaceOptionsDisplayPanelShowItemLevel:SetPoint("TOPLEFT", InterfaceOptionsDisplayPanelPlayAggroSounds,
    "BOTTOMLEFT", 0, -8)
uiMode:SetParent(colors)
uiMode:ClearAllPoints()
uiMode:SetPoint("TOPLEFT", 16, -16)
_G[uiMode:GetName() .. "Text"]:SetText("Enable UI Colorblind Mode")
local filter = dropdown(colors, "hdColorblind", "Colorblind Filter",
    {{"0", NONE}, {"1", "Protanopia"}, {"2", "Deuteranopia"}, {"3", "Tritanopia"}}, uiMode, -13, -32)

local strength = CreateFrame("Slider", "WotlkHDColorsPanelStrength", colors, "OptionsSliderTemplate")
strength:SetPoint("TOPLEFT", filter, "BOTTOMLEFT", 20, -24)
strength:SetWidth(200)
strength.type = CONTROLTYPE_SLIDER
strength.cvar = "hdColorblindStrength"
colors.options.hdColorblindStrength = {text = "Adjust Strength", minValue = 0, maxValue = 100, valueStep = 5}
WotlkHDColorsPanelStrengthLow:SetText("0%")
WotlkHDColorsPanelStrengthHigh:SetText("100%")
strength:HookScript("OnValueChanged", function(self, value)
    SetCVar("hdColorblindStrength", tostring(math.floor(value + 0.5)))
end)
BlizzardOptionsPanel_RegisterControl(strength, colors)
