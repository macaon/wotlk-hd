-- wotlk-hd: retail options that dinput8.dll adds to the client (cvars from client/controls.c and
-- client/effects.cpp), on the pages where retail has them: Mouseover Cast on Controls, Lock Cursor to
-- Window on Mouse, and Accessibility > Colors for the colorblind filter. The controls are the client's
-- own kind (BlizzardOptionsPanel), so Defaults and Okay treat them like the page's others.

-- A checkbox bound to a cvar, set up by its page on PLAYER_ENTERING_WORLD (from page.options).
local function check(page, cvar, label, tooltip, anchor, x, y)
    local c = CreateFrame("CheckButton", page:GetName() .. cvar, page, "InterfaceOptionsCheckButtonTemplate")
    c:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x, y)
    c.type = CONTROLTYPE_CHECKBOX
    c.cvar = cvar
    page.options[cvar] = {text = label, tooltip = tooltip}
    BlizzardOptionsPanel_RegisterControl(c, page)
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
    dd.type = CONTROLTYPE_DROPDOWN
    dd.defaultValue = GetCVarDefault(cvar)
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
    dd:RefreshValue()
    BlizzardOptionsPanel_RegisterControl(dd, page)
    return dd
end

-- [[ Controls: Mouseover Cast ]] --

local controls = InterfaceOptionsControlsPanel
local mouseover = check(controls, "hdMouseoverCast", "Mouseover Cast",
    "Action bar spells go to the unit under your mouse when they can, instead of your target.",
    InterfaceOptionsControlsPanelAutoLootKeyDropDown, 13, -16)
local mouseoverKey = dropdown(controls, "hdMouseoverCastKey", "Mouseover Cast Key",
    {{"0", NONE_KEY}, {"1", ALT_KEY}, {"2", CTRL_KEY}, {"3", SHIFT_KEY}}, mouseover, -13, -24)
BlizzardOptionsPanel_SetupDependentControl(mouseover, mouseoverKey)

-- [[ Mouse: Lock Cursor to Window ]] --

check(InterfaceOptionsMousePanel, "hdLockCursor", "Lock Cursor to Window",
    "Keeps the cursor inside the game window while it has focus.", InterfaceOptionsMousePanelWoWMouse, 0, -8)

-- [[ Accessibility: Colors ]] --

local colors = CreateFrame("Frame", "WotlkHDColorsPanel", UIParent)
colors.name = COLORS
colors.options = {}
colors:Hide()
BlizzardOptionsPanel_OnLoad(colors)
colors:SetScript("OnShow", BlizzardOptionsPanel_Refresh) -- not one of the client's categories: nothing else refreshes it
WotlkHD_AccessibilityPages = {colors}

local sub = colors:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
sub:SetPoint("TOPLEFT", 16, -16)
sub:SetText("A colour filter over the whole screen, for colour vision deficiency.")
local filter = dropdown(colors, "hdColorblind", "Color Filter",
    {{"0", NONE}, {"1", "Protanopia"}, {"2", "Deuteranopia"}, {"3", "Tritanopia"}}, sub, -16, -32)

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
