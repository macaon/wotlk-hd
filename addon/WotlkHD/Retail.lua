-- wotlk-hd: retail UI art on 3.3.5 frames. Atlas.lua (written by ui.py) maps retail atlas names to our
-- textures; this file adds Texture:SetAtlas, retail's metal panel frame, and retail skins for the
-- Blizzard option controls (checkboxes, sliders, dropdowns), which keep their own behaviour.

local ATLAS = WotlkHD_Atlas
local Retail = {}
WotlkHD_Retail = Retail

local function size(region, w, h)
    region:SetWidth(w)
    region:SetHeight(h)
end
Retail.size = size

local function SetAtlas(tex, name, useAtlasSize)
    local a = ATLAS[strlower(name)]
    if not a then
        return false
    end
    tex:SetTexture(a[1])
    tex:SetTexCoord(a[4], a[5], a[6], a[7])
    if useAtlasSize then
        size(tex, a[2], a[3])
    end
    return true
end
getmetatable(CreateFrame("Frame"):CreateTexture()).__index.SetAtlas = SetAtlas

function Retail.AtlasSize(name)
    local a = ATLAS[strlower(name)]
    return a[2], a[3]
end

-- A texture holder that repeats an atlas along its length ("_" names across, "!" names down); 3.3.5
-- only tiles whole textures, so each repeat is its own texture and the last one is cut short.
local function FillTiles(holder)
    local a = ATLAS[holder.atlas]
    local across = holder.across
    local len = across and holder:GetWidth() or holder:GetHeight()
    local step = across and a[2] or a[3]
    if not len or len <= 0 then
        return
    end
    local n = math.ceil(len / step)
    holder.tiles = holder.tiles or {}
    for i = 1, math.max(n, #holder.tiles) do
        local t = holder.tiles[i]
        if i > n then
            t:Hide()
        else
            if not t then
                t = holder:CreateTexture(nil, "OVERLAY")
                t:SetTexture(a[1])
                holder.tiles[i] = t
            end
            local part = math.min(step, len - (i - 1) * step) / step
            t:ClearAllPoints()
            if across then
                t:SetPoint("TOPLEFT", (i - 1) * step, 0)
                t:SetPoint("BOTTOMLEFT", (i - 1) * step, 0)
                t:SetWidth(step * part)
                t:SetTexCoord(a[4], a[4] + (a[5] - a[4]) * part, a[6], a[7])
            else
                t:SetPoint("TOPLEFT", 0, -(i - 1) * step)
                t:SetPoint("TOPRIGHT", 0, -(i - 1) * step)
                t:SetHeight(step * part)
                t:SetTexCoord(a[4], a[5], a[6], a[6] + (a[7] - a[6]) * part)
            end
            t:Show()
        end
    end
end

function Retail.Tiles(parent, name)
    local holder = CreateFrame("Frame", nil, parent)
    holder.atlas = strlower(name)
    holder.across = ATLAS[holder.atlas][8]
    holder:SetScript("OnSizeChanged", FillTiles)
    holder:SetScript("OnShow", FillTiles)
    return holder
end

-- Retail's ButtonFrameTemplateNoPortrait NineSlice: the metal frame around a panel; with portrait,
-- PortraitFrameTemplate's, whose top left corner rings a 60x60 portrait (returned second).
function Retail.MetalFrame(frame, portrait)
    local border = CreateFrame("Frame", nil, frame)
    border:SetAllPoints()
    border:SetFrameLevel(frame:GetFrameLevel() + 10)
    local function corner(atlas, point, x, y)
        local t = border:CreateTexture(nil, "OVERLAY")
        t:SetAtlas(atlas, true)
        t:SetPoint(point, x, y)
        return t
    end
    local tl = portrait and corner("UI-Frame-PortraitMetal-CornerTopLeft", "TOPLEFT", -13, 16)
        or corner("UI-Frame-Metal-CornerTopLeft", "TOPLEFT", -8, 16)
    local tr = corner("UI-Frame-Metal-CornerTopRight", "TOPRIGHT", 4, 16)
    local bl = corner("UI-Frame-Metal-CornerBottomLeft", "BOTTOMLEFT", portrait and -13 or -8, -3)
    local br = corner("UI-Frame-Metal-CornerBottomRight", "BOTTOMRIGHT", 4, -3)
    local function edge(atlas, a1, r1, p1, a2, r2, p2)
        local e = Retail.Tiles(border, atlas)
        local w, h = Retail.AtlasSize(atlas)
        e:SetPoint(a1, r1, p1)
        e:SetPoint(a2, r2, p2)
        if e.across then
            e:SetHeight(h)
        else
            e:SetWidth(w)
        end
    end
    edge("_UI-Frame-Metal-EdgeTop", "TOPLEFT", tl, "TOPRIGHT", "TOPRIGHT", tr, "TOPLEFT")
    edge("_UI-Frame-Metal-EdgeBottom", "BOTTOMLEFT", bl, "BOTTOMRIGHT", "BOTTOMRIGHT", br, "BOTTOMLEFT")
    edge("!UI-Frame-Metal-EdgeLeft", "TOPLEFT", tl, "BOTTOMLEFT", "BOTTOMLEFT", bl, "TOPLEFT")
    edge("!UI-Frame-Metal-EdgeRight", "TOPRIGHT", tr, "BOTTOMRIGHT", "BOTTOMRIGHT", br, "TOPRIGHT")
    if portrait then
        local p = border:CreateTexture(nil, "ARTWORK")
        p:SetWidth(60)
        p:SetHeight(60)
        p:SetPoint("TOPLEFT", -5, 7)
        return border, p
    end
    return border
end

-- An atlas drawn as left cap, stretched middle and right cap (retail slices these with
-- SetTextureSliceMargins, which 3.3.5 lacks).
function Retail.ThreeSlice(parent, layer, name, left, right)
    local a = ATLAS[strlower(name)]
    local du = (a[5] - a[4]) / a[2]
    local parts = {}
    for i = 1, 3 do
        parts[i] = parent:CreateTexture(nil, layer)
        parts[i]:SetTexture(a[1])
    end
    parts[1]:SetWidth(left)
    parts[1]:SetTexCoord(a[4], a[4] + left * du, a[6], a[7])
    parts[3]:SetWidth(right)
    parts[3]:SetTexCoord(a[5] - right * du, a[5], a[6], a[7])
    parts[2]:SetTexCoord(a[4] + left * du, a[5] - right * du, a[6], a[7])
    parts[2]:SetPoint("TOPLEFT", parts[1], "TOPRIGHT")
    parts[2]:SetPoint("BOTTOMRIGHT", parts[3], "BOTTOMLEFT")
    function parts.SetAtlas(_, other)
        local b = ATLAS[strlower(other)]
        local bu = (b[5] - b[4]) / b[2]
        parts[1]:SetTexCoord(b[4], b[4] + left * bu, b[6], b[7])
        parts[2]:SetTexCoord(b[4] + left * bu, b[5] - right * bu, b[6], b[7])
        parts[3]:SetTexCoord(b[5] - right * bu, b[5], b[6], b[7])
    end
    return parts
end

-- A StatusBar filled with an atlas, as retail's are: the fill is cut from the atlas part (a StatusBar
-- would stretch its whole texture), and the bar's own texture is cleared.
local function FillBar(bar)
    local a, fill = bar.wotlkhdAtlas, bar.wotlkhdFill
    local lo, hi = bar:GetMinMaxValues()
    local frac = hi > lo and math.min(math.max((bar:GetValue() - lo) / (hi - lo), 0), 1) or 0
    if frac == 0 then
        fill:Hide()
        return
    end
    fill:SetWidth(bar:GetWidth() * frac)
    fill:SetTexCoord(a[4], a[4] + (a[5] - a[4]) * frac, a[6], a[7])
    fill:Show()
end

function Retail.AtlasBar(bar, atlas)
    if not bar.wotlkhdFill then
        bar:SetStatusBarTexture("Interface\\AddOns\\WotlkHD\\Art\\clear")
        local fill = bar:CreateTexture(nil, "ARTWORK")
        fill:SetPoint("TOPLEFT")
        fill:SetPoint("BOTTOMLEFT")
        bar.wotlkhdFill = fill
        bar:HookScript("OnValueChanged", FillBar)
        bar:HookScript("OnMinMaxChanged", FillBar)
        bar:HookScript("OnSizeChanged", FillBar)
    end
    bar.wotlkhdAtlas = ATLAS[strlower(atlas)]
    bar.wotlkhdFill:SetTexture(bar.wotlkhdAtlas[1])
    FillBar(bar)
end

-- Retail's SearchBoxTemplate: the box, the magnifying glass, "Search" while empty and a clear button
-- while not; onChange(text) runs on every change. The caller places and sizes it (height 20).
function Retail.SearchBox(parent, name, onChange)
    local search = CreateFrame("EditBox", name, parent)
    search:SetAutoFocus(false)
    search:SetFontObject("ChatFontNormal")
    search:SetHeight(20)
    search:SetTextInsets(20, 20, 0, 0)
    local parts = Retail.ThreeSlice(search, "BACKGROUND", "common-search-border-middle", 8, 8)
    parts[1]:SetAtlas("common-search-border-left")
    parts[1]:SetPoint("TOPLEFT", -5, 10)
    parts[1]:SetPoint("BOTTOMLEFT", -5, -10)
    parts[3]:SetAtlas("common-search-border-right")
    parts[3]:SetPoint("TOPRIGHT", 5, 10)
    parts[3]:SetPoint("BOTTOMRIGHT", 5, -10)
    parts[2]:SetTexCoord(unpack(ATLAS["common-search-border-middle"], 4, 7))
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
    clear:SetNormalTexture(ATLAS["common-search-clearbutton"][1])
    clear:GetNormalTexture():SetAtlas("common-search-clearbutton")
    clear:Hide()
    clear:SetScript("OnClick", function()
        search:SetText("")
        search:ClearFocus()
    end)
    search:SetScript("OnEscapePressed", search.ClearFocus)
    search:SetScript("OnEnterPressed", search.ClearFocus)
    search:SetScript("OnTextChanged", function(self)
        if self:GetText() == "" then
            hint:Show()
            clear:Hide()
        else
            hint:Hide()
            clear:Show()
        end
        onChange(self:GetText())
    end)
    return search
end

-- An atlas drawn as nine slices over a region: corners of margin x margin kept, edges and middle
-- stretched (retail's slice margins; 3.3.5 has none).
function Retail.NineSlice(parent, layer, name, margin)
    local a = ATLAS[strlower(name)]
    local du, dv = (a[5] - a[4]) / a[2], (a[7] - a[6]) / a[3]
    local u = {a[4], a[4] + margin * du, a[5] - margin * du, a[5]}
    local v = {a[6], a[6] + margin * dv, a[7] - margin * dv, a[7]}
    local parts = {}
    for row = 1, 3 do
        for col = 1, 3 do
            local t = parent:CreateTexture(nil, layer)
            t:SetTexture(a[1])
            t:SetTexCoord(u[col], u[col + 1], v[row], v[row + 1])
            parts[(row - 1) * 3 + col] = t
        end
    end
    function parts.SetPoints(_, region, left, top, right, bottom)
        local p = parts
        for i, c in ipairs({"TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT"}) do
            local t = p[({1, 3, 7, 9})[i]]
            t:SetWidth(margin)
            t:SetHeight(margin)
            t:SetPoint(c, region, c, (c:find("LEFT") and -left or right), (c:find("TOP") and top or -bottom))
        end
        p[2]:SetPoint("TOPLEFT", p[1], "TOPRIGHT")
        p[2]:SetPoint("BOTTOMRIGHT", p[3], "BOTTOMLEFT")
        p[8]:SetPoint("TOPLEFT", p[7], "TOPRIGHT")
        p[8]:SetPoint("BOTTOMRIGHT", p[9], "BOTTOMLEFT")
        p[4]:SetPoint("TOPLEFT", p[1], "BOTTOMLEFT")
        p[4]:SetPoint("BOTTOMRIGHT", p[7], "TOPRIGHT")
        p[6]:SetPoint("TOPLEFT", p[3], "BOTTOMLEFT")
        p[6]:SetPoint("BOTTOMRIGHT", p[9], "TOPRIGHT")
        p[5]:SetPoint("TOPLEFT", p[1], "BOTTOMRIGHT")
        p[5]:SetPoint("BOTTOMRIGHT", p[9], "TOPLEFT")
    end
    return parts
end

-- [[ Skins for the Blizzard option controls ]] --

local function atlasTexture(button, setter, getter, atlas)
    if button[setter] then
        button[setter](button, ATLAS[strlower(atlas)][1])
        button[getter](button):SetAtlas(atlas)
    end
end

function Retail.SkinCheckButton(cb)
    atlasTexture(cb, "SetNormalTexture", "GetNormalTexture", "checkbox-minimal")
    atlasTexture(cb, "SetPushedTexture", "GetPushedTexture", "checkbox-minimal")
    atlasTexture(cb, "SetCheckedTexture", "GetCheckedTexture", "checkmark-minimal")
    atlasTexture(cb, "SetDisabledCheckedTexture", "GetDisabledCheckedTexture", "checkmark-minimal-disabled")
    atlasTexture(cb, "SetHighlightTexture", "GetHighlightTexture", "checkbox-minimal")
    local highlight = cb:GetHighlightTexture()
    highlight:SetBlendMode("ADD")
    highlight:SetAlpha(0.25)
end

function Retail.SkinSlider(s)
    s:SetBackdrop(nil)
    local left = s:CreateTexture(nil, "BACKGROUND")
    left:SetAtlas("Minimal_SliderBar_Left", true)
    left:SetPoint("LEFT", 0, 0)
    local right = s:CreateTexture(nil, "BACKGROUND")
    right:SetAtlas("Minimal_SliderBar_Right", true)
    right:SetPoint("RIGHT", 0, 0)
    local middle = s:CreateTexture(nil, "BACKGROUND")
    middle:SetAtlas("_Minimal_SliderBar_Middle")
    middle:SetPoint("TOPLEFT", left, "TOPRIGHT")
    middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
    s:SetThumbTexture(ATLAS["minimal_sliderbar_button"][1])
    s:GetThumbTexture():SetAtlas("Minimal_SliderBar_Button", true)
end

-- UIDropDownMenuTemplate: the old box art (Left/Middle/Right, 64 high around a 32 high frame) gives way to
-- retail's dropdown button over the same box, clickable all over as in retail.
function Retail.SkinDropDown(dd)
    local name = dd:GetName()
    local l, m, r, button = _G[name .. "Left"], _G[name .. "Middle"], _G[name .. "Right"], _G[name .. "Button"]
    l:SetAlpha(0)
    m:SetAlpha(0)
    r:SetAlpha(0)
    local bg = Retail.ThreeSlice(dd, "ARTWORK", "common-dropdown-b-button", 8, 26)
    bg[1]:SetPoint("TOPLEFT", l, "LEFT", 16, 14)
    bg[1]:SetPoint("BOTTOMLEFT", l, "LEFT", 16, -12)
    bg[3]:SetPoint("TOPRIGHT", r, "RIGHT", -16, 14)
    bg[3]:SetPoint("BOTTOMRIGHT", r, "RIGHT", -16, -12)
    for _, get in ipairs({"GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture"}) do
        local t = button[get](button)
        if t then
            t:SetAlpha(0)
        end
    end
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", bg[1])
    button:SetPoint("BOTTOMRIGHT", bg[3])
    button:HookScript("OnEnter", function() bg:SetAtlas("common-dropdown-b-button-hover") end)
    button:HookScript("OnLeave", function() bg:SetAtlas("common-dropdown-b-button") end)
end

local function isDropDown(frame)
    local name = frame:GetName()
    return name and _G[name .. "Button"] and _G[name .. "Middle"] and _G[name .. "Text"]
end

-- Every option control under a frame, once.
function Retail.SkinControls(frame)
    for _, child in ipairs({frame:GetChildren()}) do
        if not child.wotlkhdSkinned then
            child.wotlkhdSkinned = true
            local kind = child:GetObjectType()
            if kind == "CheckButton" and child:GetNormalTexture() then
                Retail.SkinCheckButton(child)
            elseif kind == "Slider" and child:GetThumbTexture() then
                Retail.SkinSlider(child)
            elseif kind == "Frame" and isDropDown(child) then
                Retail.SkinDropDown(child)
            end
            Retail.SkinControls(child)
        end
    end
end
