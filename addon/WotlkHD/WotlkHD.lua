-- wotlk-hd: an "HD Effects" page under Video Options for the effects in dinput8.dll (client/effects.cpp),
-- which reads these cvars every frame, so changes show at once. Also widens View Distance to the
-- engine's real limit (1583; on the old continents only with farClipOverride, which this sets).

local CVARS = {
    {"check", "hdSMAA", "Anti-aliasing (SMAA)", "1"},
    {"check", "hdSharpen", "Sharpening (CAS)", "1"},
    {"slider", "hdSharpness", "Sharpening strength", "100"},
    {"check", "hdSunshafts", "Sunshafts", "1"},
    {"slider", "hdSunshaftsStrength", "Sunshaft strength", "60"},
    {"check", "hdAO", "Ambient occlusion (softens distant characters)", "0"},
    {"check", "hdHaze", "Distance haze (cools warm zones)", "0"},
}

local panel = CreateFrame("Frame", "WotlkHDOptions", VideoOptionsFramePanelContainer)
panel.name = "HD Effects"
panel:Hide()

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("HD Effects")
local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
sub:SetText("Post-processing by wotlk-hd. Changes apply at once and are saved with your settings.")

local controls, last = {}, sub
for i, entry in ipairs(CVARS) do
    local kind, cvar, label = entry[1], entry[2], entry[3]
    local name = "WotlkHDOptions" .. cvar
    local c
    if kind == "check" then
        c = CreateFrame("CheckButton", name, panel, "OptionsCheckButtonTemplate")
        c:SetPoint("TOPLEFT", last, "BOTTOMLEFT", last == sub and -2 or 0, last == sub and -16 or -8)
        _G[name .. "Text"]:SetText(label)
        c:SetScript("OnClick", function(self) SetCVar(cvar, self:GetChecked() and "1" or "0") end)
    else
        c = CreateFrame("Slider", name, panel, "OptionsSliderTemplate")
        c:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 24, -18)
        c:SetWidth(200)
        c:SetMinMaxValues(0, 100)
        c:SetValueStep(5)
        _G[name .. "Text"]:SetText(label)
        _G[name .. "Low"]:SetText("0")
        _G[name .. "High"]:SetText("100")
        c:SetScript("OnValueChanged", function(self, value) SetCVar(cvar, tostring(math.floor(value + 0.5))) end)
    end
    c.kind, c.cvar, c.defaultValue = kind, cvar, entry[4]
    controls[#controls + 1] = c
    -- sliders sit indented under their checkbox; what follows lines up with the checkboxes again
    last = c
    if kind == "slider" then
        last = CreateFrame("Frame", nil, panel)
        last:SetWidth(1)
        last:SetHeight(1)
        last:SetPoint("TOPLEFT", c, "BOTTOMLEFT", -24, -6)
    end
end

function panel.refresh()
    for _, c in ipairs(controls) do
        local v = GetCVar(c.cvar) or c.defaultValue
        if c.kind == "check" then
            c:SetChecked(v ~= "0")
        else
            c:SetValue(tonumber(v) or tonumber(c.defaultValue))
        end
    end
end
function panel.default()
    for _, c in ipairs(controls) do
        SetCVar(c.cvar, c.defaultValue)
    end
    panel.refresh()
end
function panel.okay() end
function panel.cancel() end
panel:SetScript("OnShow", panel.refresh)

OptionsFrame_AddCategory(VideoOptionsFrame, panel)

-- View Distance: the engine allows up to 1583 yards (AdjustFarClip); the old continents stop at 791
-- unless farClipOverride is set.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    SetCVar("farClipOverride", "1")
    if EffectsPanelOptions and EffectsPanelOptions.farclip then
        EffectsPanelOptions.farclip.maxValue = 1583
    end
    local slider = VideoOptionsEffectsPanelViewDistance
    if slider then
        local low = slider:GetMinMaxValues()
        slider:SetMinMaxValues(low, 1583)
        slider:SetValueStep((1583 - low) / 10)
    end
end)
