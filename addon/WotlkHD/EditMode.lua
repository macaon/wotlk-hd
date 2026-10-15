-- wotlk-hd: retail's Edit Mode. From the game menu: a grid, a selection box over each movable part of
-- the UI (drag to move, snapping to the grid and to the other boxes' edges; click for its settings:
-- size, reset), and a panel with the grid and snap options, Revert and Save. Positions are kept
-- account-wide in WotlkHD_Saved.editMode as an anchor on the nearest screen corner (with each frame's
-- default), and applied at login. Out of combat only, as the client's frames are protected in combat.

local Retail = WotlkHD_Retail
local GRID_DEFAULT = 100 -- retail's

-- [[ Systems ]] --
-- frame: what moves. last: the frame whose bottom right ends the box (party frames). size: a fixed box
-- (for frames that are empty or hidden most of the time), from the frame's `anchor` corner.
local SYSTEMS = {
    {key = "player", label = "Player Frame", frame = "PlayerFrame", scale = true},
    {key = "target", label = "Target Frame", frame = "TargetFrame", scale = true},
    {key = "focus", label = "Focus Frame", frame = "FocusFrame", scale = true},
    {key = "party", label = "Party Frames", frame = "PartyMemberFrame1", last = "PartyMemberFrame4", scale = true},
    {key = "raid", label = "Raid Frames", frame = "WotlkHDRaidFrames", size = {72, 180}, anchor = "TOPLEFT",
        raid = true},
    {key = "castbar", label = "Cast Bar", frame = "CastingBarFrame", scale = true, managed = true},
    {key = "minimap", label = "Minimap", frame = "MinimapCluster", scale = true},
    {key = "buffs", label = "Buffs", frame = "ConsolidatedBuffs", size = {340, 90}, anchor = "TOPRIGHT",
        scale = true},
    {key = "quests", label = "Objective Tracker", frame = "WatchFrame", keepSize = true},
    -- Action bars (ActionBars.lua, which leaves moved ones where they are); optional: boxed only while shown.
    {key = "bar1", label = "Action Bar 1", frame = "WotlkHDMainBar", scale = true},
    {key = "bar2", label = "Action Bar 2", frame = "WotlkHDBar2", scale = true, optional = true},
    {key = "bar3", label = "Action Bar 3", frame = "WotlkHDBar3", scale = true, optional = true},
    {key = "bar4", label = "Action Bar 4", frame = "WotlkHDBar4", scale = true, optional = true},
    {key = "bar5", label = "Action Bar 5", frame = "WotlkHDBar5", scale = true, optional = true},
    {key = "bar6", label = "Action Bar 6", frame = "WotlkHDBar6", scale = true, optional = true},
    {key = "bar7", label = "Action Bar 7", frame = "WotlkHDBar7", scale = true, optional = true},
    {key = "bar8", label = "Action Bar 8", frame = "WotlkHDBar8", scale = true, optional = true},
    {key = "stance", label = "Stance Bar", frame = "WotlkHDStanceBar", scale = true, optional = true},
    {key = "pet", label = "Pet Bar", frame = "WotlkHDPetBar", scale = true, optional = true},
}


local saved -- WotlkHD_Saved.editMode
-- Whether a system's box shows: not ticked off in the panel, and for optional ones only while shown.
local function boxShown(sys)
    return not saved.hidden[sys.key] and (not sys.optional or _G[sys.frame]:IsShown())
end

local function frameOf(sys)
    return _G[sys.frame]
end

local function ratio(f) -- frame units -> UIParent units
    return f:GetEffectiveScale() / UIParent:GetEffectiveScale()
end

-- The frame's position as an offset from the nearest screen corner, in the frame's own units.
local function anchorOf(f)
    local s = ratio(f)
    local l, r, t, b = f:GetLeft() * s, f:GetRight() * s, f:GetTop() * s, f:GetBottom() * s
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    local horiz = (l + r) / 2 < w / 2 and "LEFT" or "RIGHT"
    local vert = (t + b) / 2 < h / 2 and "BOTTOM" or "TOP"
    local x = horiz == "LEFT" and l or r - w
    local y = vert == "BOTTOM" and b or t - h
    return {point = vert .. horiz, x = x / s, y = y / s}
end

local function place(sys, a)
    local f = frameOf(sys)
    if sys.keepSize and not a.height then
        a.width, a.height = f:GetWidth(), f:GetHeight()
    end
    f:ClearAllPoints()
    f:SetPoint(a.point, UIParent, a.point, a.x, a.y)
    if a.height then
        f:SetWidth(a.width)
        f:SetHeight(a.height)
    end
    f:SetMovable(true)
    f:SetUserPlaced(true)
end

-- A frame's default anchor, scale and size: where it is just before its first move, so after whatever
-- else places it at login (Titan Panel pushes frames down). Kept while it stays moved, as the client
-- then restores it from its layout cache before we could see the default again.
local function remember(sys)
    local f = frameOf(sys)
    if saved.frames[sys.key] then
        return
    end
    local d = {scale = f:GetScale(), points = {}}
    for i = 1, f:GetNumPoints() do
        local p, rel, rp, x, y = f:GetPoint(i)
        d.points[i] = {p, rel and rel:GetName() or "UIParent", rp, x, y}
    end
    if sys.keepSize then
        d.width, d.height = f:GetWidth(), f:GetHeight()
    end
    saved.defaults[sys.key] = d
end

local function setScale(sys, scale)
    local f = frameOf(sys)
    remember(sys)
    local a = anchorOf(f)
    local old = f:GetScale()
    f:SetScale(scale)
    a.x, a.y = a.x * old / scale, a.y * old / scale -- keep the corner where it was
    place(sys, a)
    a.scale = scale
    saved.frames[sys.key] = a
end

local function reset(sys)
    local f, d = frameOf(sys), saved.defaults[sys.key]
    saved.frames[sys.key] = nil
    if sys.raid then
        WotlkHD_RaidFrames.SetSize(72, 36)
    end
    if not d then
        return
    end
    f:SetScale(d.scale)
    f:ClearAllPoints()
    for _, p in ipairs(d.points) do
        f:SetPoint(p[1], _G[p[2]] or UIParent, p[3], p[4], p[5])
    end
    if d.height then
        f:SetWidth(d.width)
        f:SetHeight(d.height)
    end
    if f:IsMovable() then
        f:SetUserPlaced(false)
    end
    UIParent_ManageFramePositions()
end

local function applySaved()
    for _, sys in ipairs(SYSTEMS) do
        local a = frameOf(sys) and saved.frames[sys.key]
        if a then
            if a.scale then
                frameOf(sys):SetScale(a.scale)
            end
            place(sys, a)
        end
    end
end

-- [[ Grid ]] --

local grid = CreateFrame("Frame", nil, UIParent)
grid:SetAllPoints()
grid:SetFrameStrata("BACKGROUND")
grid:Hide()
grid.lines = {}

local function drawGrid()
    for _, l in ipairs(grid.lines) do
        l:Hide()
    end
    local spacing, n = saved.spacing, 0
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    local function line(vertical, offset, center)
        n = n + 1
        local l = grid.lines[n] or grid:CreateTexture(nil, "BACKGROUND")
        grid.lines[n] = l
        l:ClearAllPoints()
        if vertical then
            l:SetPoint("TOP", grid, "TOP", offset, 0)
            l:SetPoint("BOTTOM", grid, "BOTTOM", offset, 0)
            l:SetWidth(1)
        else
            l:SetPoint("LEFT", grid, "LEFT", 0, offset)
            l:SetPoint("RIGHT", grid, "RIGHT", 0, offset)
            l:SetHeight(1)
        end
        if center then
            l:SetTexture(0.75, 0.2, 0.2, 0.6)
        else
            l:SetTexture(0.6, 0.6, 0.6, 0.25)
        end
        l:Show()
    end
    for i = 0, math.floor(w / 2 / spacing) do
        line(true, i * spacing, i == 0)
        if i > 0 then
            line(true, -i * spacing)
        end
    end
    for i = 0, math.floor(h / 2 / spacing) do
        line(false, i * spacing, i == 0)
        if i > 0 then
            line(false, -i * spacing)
        end
    end
end

-- Snapping, as retail's: a box's edges go to a grid line or another box's edge within SNAP of them.
local SNAP = 10

-- The shift (UIParent units) that puts edge lo or hi on the nearest of lines, or 0 if none is close.
local function snapShift(lo, hi, lines)
    local best, shift = SNAP, 0
    for _, v in ipairs(lines) do
        for _, e in ipairs({lo, hi}) do
            if math.abs(v - e) < best then
                best, shift = math.abs(v - e), v - e
            end
        end
    end
    return shift
end

local function gridLines(size)
    local lines, c = {}, size / 2
    for i = -math.floor(c / saved.spacing), math.floor(c / saved.spacing) do
        tinsert(lines, c + i * saved.spacing)
    end
    return lines
end

-- [[ Selection boxes ]] --

local overlays, selected = {}, nil
local settings -- the selected system's settings dialog, below
local markDirty -- below: there are changes to save or revert

local function nineSlice(parent, kind)
    local t = {}
    local function piece(atlas, layer)
        local x = parent:CreateTexture(nil, layer or "BORDER")
        x:SetAtlas(atlas)
        tinsert(t, x)
        return x
    end
    local center = piece("editmode-actionbar-" .. kind .. "-nineslice-center", "BACKGROUND")
    center:SetPoint("TOPLEFT", 4, -4)
    center:SetPoint("BOTTOMRIGHT", -4, 4)
    local a = WotlkHD_Atlas["editmode-actionbar-" .. kind .. "-nineslice-corner"]
    local corners = {
        TOPLEFT = {a[4], a[5], a[6], a[7]}, TOPRIGHT = {a[5], a[4], a[6], a[7]},
        BOTTOMLEFT = {a[4], a[5], a[7], a[6]}, BOTTOMRIGHT = {a[5], a[4], a[7], a[6]},
    }
    for point, c in pairs(corners) do
        local x = piece("editmode-actionbar-" .. kind .. "-nineslice-corner")
        x:SetTexCoord(c[1], c[2], c[3], c[4])
        x:SetWidth(16)
        x:SetHeight(16)
        x:SetPoint(point)
        corners[point] = x
    end
    local e = WotlkHD_Atlas["_editmode-actionbar-" .. kind .. "-nineslice-edgetop"]
    local top = piece("_editmode-actionbar-" .. kind .. "-nineslice-edgetop")
    top:SetPoint("TOPLEFT", corners.TOPLEFT, "TOPRIGHT")
    top:SetPoint("BOTTOMRIGHT", corners.TOPRIGHT, "BOTTOMLEFT")
    local bottom = piece("_editmode-actionbar-" .. kind .. "-nineslice-edgetop")
    bottom:SetTexCoord(e[4], e[5], e[7], e[6])
    bottom:SetPoint("TOPLEFT", corners.BOTTOMLEFT, "TOPRIGHT")
    bottom:SetPoint("BOTTOMRIGHT", corners.BOTTOMRIGHT, "BOTTOMLEFT")
    local v = WotlkHD_Atlas["!editmode-actionbar-" .. kind .. "-nineslice-edgeleft"]
    local left = piece("!editmode-actionbar-" .. kind .. "-nineslice-edgeleft")
    left:SetPoint("TOPLEFT", corners.TOPLEFT, "BOTTOMLEFT")
    left:SetPoint("BOTTOMRIGHT", corners.BOTTOMLEFT, "TOPRIGHT")
    local right = piece("!editmode-actionbar-" .. kind .. "-nineslice-edgeleft")
    right:SetTexCoord(v[5], v[4], v[6], v[7])
    right:SetPoint("TOPLEFT", corners.TOPRIGHT, "BOTTOMLEFT")
    right:SetPoint("BOTTOMRIGHT", corners.BOTTOMRIGHT, "TOPRIGHT")
    function t.Show()
        for _, x in ipairs(t) do
            x:Show()
        end
    end
    function t.Hide()
        for _, x in ipairs(t) do
            x:Hide()
        end
    end
    return t
end

local function fit(o)
    local sys, f = o.sys, frameOf(o.sys)
    o:ClearAllPoints()
    if sys.size then
        o:SetPoint(sys.anchor, f, sys.anchor)
        o:SetWidth(sys.size[1])
        o:SetHeight(sys.size[2])
    else
        o:SetPoint("TOPLEFT", f, "TOPLEFT")
        o:SetPoint("BOTTOMRIGHT", _G[sys.last or sys.frame], "BOTTOMRIGHT")
    end
end

local function selectOverlay(o)
    selected = o
    for _, x in pairs(overlays) do
        if x == o then
            x.highlight.Hide()
            x.selection.Show()
        else
            x.selection.Hide()
            x.highlight.Show()
        end
    end
    settings:Open(o)
end

local function dragUpdate(o)
    local sys = o.sys
    local left, top = o:GetLeft(), o:GetTop()
    if saved.snap then
        local xs = saved.grid and gridLines(UIParent:GetWidth()) or {}
        local ys = saved.grid and gridLines(UIParent:GetHeight()) or {}
        for _, x in pairs(overlays) do
            if x ~= o and x:IsShown() then
                tinsert(xs, x:GetLeft())
                tinsert(xs, x:GetRight())
                tinsert(ys, x:GetTop())
                tinsert(ys, x:GetBottom())
            end
        end
        left = left + snapShift(left, left + o:GetWidth(), xs)
        top = top + snapShift(top - o:GetHeight(), top, ys)
    end
    local s = ratio(frameOf(sys))
    local a = o.start
    place(sys, {point = a.point, x = a.x + (left - o.startLeft) / s, y = a.y + (top - o.startTop) / s,
        width = a.width, height = a.height})
end

local function overlay(sys)
    local o = CreateFrame("Frame", nil, UIParent)
    o.sys = sys
    o:SetFrameStrata("HIGH")
    o:EnableMouse(true)
    o:SetMovable(true)
    o:SetClampedToScreen(true)
    o:RegisterForDrag("LeftButton")
    o.highlight = nineSlice(o, "highlight")
    o.selection = nineSlice(o, "selected")
    o.selection.Hide()
    local label = o:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    label:SetPoint("CENTER")
    label:SetText(sys.label)
    o:SetScript("OnMouseDown", selectOverlay)
    o:SetScript("OnDragStart", function(self)
        selectOverlay(self)
        local f = frameOf(sys)
        remember(sys)
        self.start = anchorOf(f)
        if sys.keepSize then
            self.start.width, self.start.height = f:GetWidth(), f:GetHeight()
        end
        self.startLeft, self.startTop = self:GetLeft(), self:GetTop()
        self:StartMoving()
        self:SetScript("OnUpdate", dragUpdate)
    end)
    o:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self:SetScript("OnUpdate", nil)
        dragUpdate(self)
        local a = anchorOf(frameOf(sys))
        a.scale = frameOf(sys):GetScale()
        if sys.keepSize then
            a.width, a.height = self.start.width, self.start.height
        end
        saved.frames[sys.key] = a
        markDirty()
        fit(self)
        settings:Open(self)
    end)
    o:Hide()
    return o
end

-- [[ Panels ]] --

-- Retail's dark dialog with the gold rim, and its red close button.
local function dialog(name, w, h)
    local d = CreateFrame("Frame", name, UIParent)
    d:SetWidth(w)
    d:SetHeight(h)
    d:SetFrameStrata("DIALOG")
    d:EnableMouse(true)
    d:SetBackdrop({bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32,
        insets = {left = 11, right = 12, top = 12, bottom = 11}})
    d.title = d:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    d.title:SetPoint("TOP", 0, -16)
    d:Hide()
    return d
end

local function closeButton(parent, onClick)
    local c = CreateFrame("Button", nil, parent)
    c:SetWidth(24)
    c:SetHeight(24)
    c:SetPoint("TOPRIGHT", -6, -6)
    for _, t in ipairs({{"SetNormalTexture", "GetNormalTexture", "RedButton-Exit"},
        {"SetPushedTexture", "GetPushedTexture", "RedButton-exit-pressed"},
        {"SetHighlightTexture", "GetHighlightTexture", "RedButton-Highlight"}}) do
        c[t[1]](c, WotlkHD_Atlas[strlower(t[3])][1])
        c[t[2]](c):SetAtlas(t[3])
    end
    c:SetScript("OnClick", onClick)
    return c
end

local checkboxes = 0
local function checkbox(parent, text, x, y, get, set)
    checkboxes = checkboxes + 1
    local c = CreateFrame("CheckButton", "WotlkHDEditModeCheck" .. checkboxes, parent, "InterfaceOptionsCheckButtonTemplate")
    c:SetPoint("TOPLEFT", x, y)
    _G[c:GetName() .. "Text"]:SetText(text)
    Retail.SkinCheckButton(c)
    c:SetScript("OnShow", function(self) self:SetChecked(get()) end)
    c:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    return c
end

-- A slider; with no text, retail's inline kind: no label, the value on its right.
local sliders = 0
local function slider(parent, text, x, y, low, high, step, get, set, format, width)
    sliders = sliders + 1
    local name = "WotlkHDEditModeSlider" .. sliders
    local s = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", x, y)
    s:SetWidth(width or 180)
    s:SetMinMaxValues(low, high)
    s:SetValueStep(step)
    _G[name .. "Low"]:SetText("")
    _G[name .. "High"]:SetText("")
    Retail.SkinSlider(s)
    local value = _G[name .. "Text"]
    if not text then
        value:ClearAllPoints()
        value:SetPoint("LEFT", s, "RIGHT", 8, 0)
        value:SetFontObject("GameFontNormalSmall")
    end
    local function label(v)
        v = format and format(v) or v
        value:SetText(text and text .. ": " .. v or v)
    end
    s:SetScript("OnShow", function(self)
        self.loading = true
        self:SetValue(get())
        label(get())
        self.loading = nil
    end)
    s:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v / step + 0.5) * step
        label(v)
        if not self.loading then
            set(v)
        end
    end)
    return s
end

local function button(parent, text, w)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetWidth(w or 120)
    b:SetHeight(22)
    b:SetText(text)
    return b
end

-- The selected system's settings.
settings = dialog("WotlkHDEditModeSettings", 250, 150)
closeButton(settings, function() settings:Hide() end)
local percent = function(v) return v .. "%" end
local scaleSlider = slider(settings, "Frame Size", 34, -54, 50, 200, 5,
    function() return math.floor(frameOf(selected.sys):GetScale() * 100 + 0.5) end,
    function(v) setScale(selected.sys, v / 100); fit(selected); markDirty() end, percent)
local raidWidth = slider(settings, "Frame Width", 34, -54, 50, 150, 2,
    function() return WotlkHD_Saved.raidFrameWidth or 72 end,
    function(v) WotlkHD_RaidFrames.SetSize(v, WotlkHD_Saved.raidFrameHeight or 36); markDirty() end)
local raidHeight = slider(settings, "Frame Height", 34, -92, 20, 80, 2,
    function() return WotlkHD_Saved.raidFrameHeight or 36 end,
    function(v) WotlkHD_RaidFrames.SetSize(WotlkHD_Saved.raidFrameWidth or 72, v); markDirty() end)
local raidParty = checkbox(settings, "Use Raid-Style Party Frames", 24, -116,
    function() return GetCVar("hdRaidStyleParty") == "1" end,
    function(on) SetCVar("hdRaidStyleParty", on and "1" or "0") end)
local resetButton = button(settings, "Reset To Default Position", 190)
resetButton:SetPoint("BOTTOM", 0, 18)
resetButton:SetScript("OnClick", function()
    reset(selected.sys)
    markDirty()
    fit(selected)
    settings:Open(selected)
end)

function settings:Open(o)
    local raid = o.sys.raid
    self.title:SetText(o.sys.label)
    self:SetHeight(raid and 200 or 140)
    for _, c in ipairs({raidWidth, raidHeight, raidParty}) do
        c:Hide()
        if raid then
            c:Show()
        end
    end
    scaleSlider:Hide()
    if o.sys.scale then
        scaleSlider:Show()
    end
    self:ClearAllPoints()
    if o:GetRight() + 260 < UIParent:GetWidth() then
        self:SetPoint("TOPLEFT", o, "TOPRIGHT", 8, 0)
    else
        self:SetPoint("TOPRIGHT", o, "TOPLEFT", -8, 0)
    end
    self:Show()
end

-- The Edit Mode panel, as retail's HUD Edit Mode: grid and snap, which boxes show, Revert and Save.
local manager = dialog("WotlkHDEditMode", 340, 0)
manager:SetPoint("TOP", 0, -80)
manager.title:SetText("HUD Edit Mode")
tinsert(UISpecialFrames, "WotlkHDEditMode")
closeButton(manager, function() manager:Hide() end)
checkbox(manager, "Show Grid", 20, -38, function() return saved.grid end, function(on)
    saved.grid = on
    if on then
        grid:Show()
    else
        grid:Hide()
    end
end)
slider(manager, nil, 130, -44, 20, 200, 10, function() return saved.spacing end, function(v)
    saved.spacing = v
    drawGrid()
end, nil, 150)
checkbox(manager, "Snap to Elements", 20, -64, function() return saved.snap end, function(on) saved.snap = on end)

-- Which boxes show: two columns of the systems.
local list = CreateFrame("Frame", nil, manager)
list:SetPoint("TOPLEFT", 18, -94)
list:SetPoint("RIGHT", -18, 0)
list:SetHeight(math.ceil(#SYSTEMS / 2) * 24 + 10)
list:SetBackdrop({edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12})
list:SetBackdropBorderColor(0.6, 0.6, 0.6)
for i, sys in ipairs(SYSTEMS) do
    checkbox(list, sys.label, i % 2 == 1 and 6 or 154, -5 - math.floor((i - 1) / 2) * 24,
        function() return not saved.hidden[sys.key] end,
        function(on)
            saved.hidden[sys.key] = not on or nil
            local o = overlays[sys.key]
            if o and on and boxShown(sys) then
                o:Show()
            elseif o then
                o:Hide()
            end
        end)
end
manager:SetHeight(94 + list:GetHeight() + 50)

local snapshot -- saved.frames and the raid frame size at the last save, for Revert
local dirty, leavingForCombat

local revert = button(manager, "Revert All Changes", 140)
revert:SetPoint("BOTTOMLEFT", 18, 18)
local save = button(manager, SAVE or "Save", 140)
save:SetPoint("BOTTOMRIGHT", -18, 18)

function markDirty()
    dirty = true
    revert:Enable()
    save:Enable()
end

local function copy(t)
    local c = {}
    for k, v in pairs(t) do
        c[k] = v
    end
    return c
end

local function commit()
    snapshot = {frames = copy(saved.frames), raidWidth = WotlkHD_Saved.raidFrameWidth or 72,
        raidHeight = WotlkHD_Saved.raidFrameHeight or 36}
    dirty = nil
    revert:Disable()
    save:Disable()
end

local function revertAll()
    for _, sys in ipairs(SYSTEMS) do
        if frameOf(sys) and saved.frames[sys.key] ~= snapshot.frames[sys.key] then
            reset(sys)
        end
    end
    saved.frames = copy(snapshot.frames)
    WotlkHD_RaidFrames.SetSize(snapshot.raidWidth, snapshot.raidHeight)
    applySaved()
    for _, o in pairs(overlays) do
        fit(o)
    end
    settings:Hide()
    commit()
end
revert:SetScript("OnClick", revertAll)
save:SetScript("OnClick", commit)

StaticPopupDialogs["WOTLKHD_EDITMODE_UNSAVED"] = {
    text = "You have unsaved changes.",
    button1 = "Save and Exit",
    button2 = "Exit",
    OnAccept = commit,
    OnCancel = function(_, _, reason)
        if reason == "clicked" then
            revertAll()
        else
            commit() -- closed some other way (combat): keep what's on screen
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = false,
}

-- [[ Entering and leaving ]] --

function WotlkHD_EnterEditMode()
    if InCombatLockdown() then
        UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, 1, 0.1, 0.1)
        return
    end
    commit()
    drawGrid()
    if saved.grid then
        grid:Show()
    end
    for _, sys in ipairs(SYSTEMS) do
        if frameOf(sys) then
            overlays[sys.key] = overlays[sys.key] or overlay(sys)
            local o = overlays[sys.key]
            fit(o)
            o.selection.Hide()
            o.highlight.Show()
            if boxShown(sys) then
                o:Show()
            else
                o:Hide()
            end
        end
    end
    manager:Show()
end

manager:SetScript("OnHide", function()
    grid:Hide()
    settings:Hide()
    for _, o in pairs(overlays) do
        o:Hide()
    end
    selected = nil
    if dirty then
        if InCombatLockdown() or leavingForCombat then
            commit() -- the frames are locked: keep what's on screen
        else
            StaticPopup_Show("WOTLKHD_EDITMODE_UNSAVED")
        end
    end
end)

-- The game menu's Edit Mode button, under Options as on retail.
local menuButton = CreateFrame("Button", "GameMenuButtonEditMode", GameMenuFrame, "GameMenuButtonTemplate")
menuButton:SetText("Edit Mode")
menuButton:SetPoint("TOP", GameMenuButtonOptions, "BOTTOM", 0, -1)
GameMenuButtonKeybindings:ClearAllPoints()
GameMenuButtonKeybindings:SetPoint("TOP", menuButton, "BOTTOM", 0, -1)
GameMenuFrame:SetHeight(GameMenuFrame:GetHeight() + menuButton:GetHeight() + 1)
menuButton:SetScript("OnClick", function()
    PlaySound("igMainMenuOption")
    HideUIPanel(GameMenuFrame)
    WotlkHD_EnterEditMode()
end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        leavingForCombat = true
        manager:Hide() -- the frames lock in combat
        leavingForCombat = nil
        return
    end
    WotlkHD_Saved = WotlkHD_Saved or {}
    WotlkHD_Saved.editMode = WotlkHD_Saved.editMode or {frames = {}, grid = true, snap = true, spacing = GRID_DEFAULT}
    saved = WotlkHD_Saved.editMode
    saved.defaults = saved.defaults or {}
    saved.hidden = saved.hidden or {}
    applySaved()
    if WotlkHD_Saved.raidFrameWidth then
        WotlkHD_RaidFrames.SetSize(WotlkHD_Saved.raidFrameWidth, WotlkHD_Saved.raidFrameHeight)
    end
end)

-- The client's layout code (UIParent_ManageFramePositions) places the cast bar itself, ignoring
-- user-placed; a moved one goes back after it. (Taking it off UIPARENT_MANAGED_FRAME_POSITIONS would be
-- addon code writing the client's table, which taints the layout code that also moves protected bars.)
hooksecurefunc("UIParent_ManageFramePositions", function()
    for _, sys in ipairs(SYSTEMS) do
        local a = sys.managed and saved and saved.frames[sys.key]
        if a then
            place(sys, a)
        end
    end
end)
