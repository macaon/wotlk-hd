-- wotlk-hd: retail's minimap (Blizzard_Minimap, mainline): a 198 pixel map in retail's frame, the zone
-- name in a bar over it with the clock and calendar beside it, tracking and mail to its left, zoom
-- buttons shown while the mouse is over the map, and the mouse wheel zooming. The client's own widgets,
-- moved and reskinned; none of them is protected.

local Retail = WotlkHD_Retail

MinimapCluster:SetWidth(256)
MinimapCluster:SetHeight(256)

-- The client's border, compass ring, north tag and world map button go; retail has none of them.
for _, region in ipairs({MinimapBorder, MinimapBorderTop, MinimapNorthTag, MinimapCompassTexture}) do
    region:SetTexture(nil)
    region:Hide()
end
MiniMapWorldMapButton:Hide()

-- The map, centered in retail's 215x226 container 30 below the cluster's top.
Minimap:SetWidth(198)
Minimap:SetHeight(198)
Minimap:ClearAllPoints()
Minimap:SetPoint("CENTER", MinimapCluster, "TOP", 10, -30 - 226 / 2)
MinimapBackdrop:ClearAllPoints()
MinimapBackdrop:SetPoint("CENTER", Minimap)
local frame = MinimapBackdrop:CreateTexture(nil, "OVERLAY")
frame:SetAtlas("UI-HUD-Minimap-Frame")
frame:SetWidth(215)
frame:SetHeight(226)
frame:SetPoint("CENTER", Minimap)

-- [[ The zone bar ]] --
-- Retail's BorderTop: a 175x16 bar of the minimap button's nine slices (UniqueCornersLayout).
local bar = CreateFrame("Frame", nil, MinimapCluster)
bar:SetWidth(175)
bar:SetHeight(16)
bar:SetPoint("TOP", 15, -4)
-- The minimap button's nine slices over a frame (the bar, and BotControl's button below).
local function buttonFrame(owner)
    local KIT = "UI-HUD-Minimap-Button-NineSlice-"
    local function piece(atlas, ...)
        local t = owner:CreateTexture(nil, "BACKGROUND")
        t:SetAtlas(atlas, true)
        for i = 1, select("#", ...), 3 do
            local point, rel, relPoint = select(i, ...)
            t:SetPoint(point, rel, relPoint)
        end
        return t
    end
    local tl = piece(KIT .. "CornerTopLeft", "TOPLEFT", owner, "TOPLEFT")
    local tr = piece(KIT .. "CornerTopRight", "TOPRIGHT", owner, "TOPRIGHT")
    local bl = piece(KIT .. "CornerBottomLeft", "BOTTOMLEFT", owner, "BOTTOMLEFT")
    local br = piece(KIT .. "CornerBottomRight", "BOTTOMRIGHT", owner, "BOTTOMRIGHT")
    piece("_" .. KIT .. "EdgeTop", "TOPLEFT", tl, "TOPRIGHT", "TOPRIGHT", tr, "TOPLEFT"):SetWidth(0)
    piece("_" .. KIT .. "EdgeBottom", "BOTTOMLEFT", bl, "BOTTOMRIGHT", "BOTTOMRIGHT", br, "BOTTOMLEFT"):SetWidth(0)
    piece("!" .. KIT .. "EdgeLeft", "TOPLEFT", tl, "BOTTOMLEFT", "BOTTOMLEFT", bl, "TOPLEFT"):SetHeight(0)
    piece("!" .. KIT .. "EdgeRight", "TOPRIGHT", tr, "BOTTOMRIGHT", "BOTTOMRIGHT", br, "TOPRIGHT"):SetHeight(0)
    piece(KIT .. "Center", "TOPLEFT", tl, "BOTTOMRIGHT", "BOTTOMRIGHT", br, "TOPLEFT")
end
buttonFrame(bar)

MinimapZoneTextButton:ClearAllPoints()
MinimapZoneTextButton:SetPoint("LEFT", bar, "LEFT", 4, 0)
MinimapZoneTextButton:SetWidth(135)
MinimapZoneTextButton:SetHeight(12)
MinimapZoneTextButton:SetFrameLevel(bar:GetFrameLevel() + 1)
MinimapZoneText:ClearAllPoints()
MinimapZoneText:SetPoint("CENTER", 0, 1)
MinimapZoneText:SetWidth(130)
MinimapZoneText:SetHeight(12)
MinimapZoneText:SetJustifyH("LEFT")

-- The calendar: retail's page for today's date, right of the bar; the client's day and night icon goes.
GameTimeFrame:SetParent(MinimapCluster)
GameTimeFrame:ClearAllPoints()
GameTimeFrame:SetPoint("TOPLEFT", bar, "TOPRIGHT", 1, 0)
GameTimeFrame:SetWidth(19)
GameTimeFrame:SetHeight(18)
GameTimeTexture:Hide()
GameTimeFrame:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
local function calendar()
    local _, _, day = CalendarGetDate()
    if day and day > 0 then
        GameTimeFrame:GetNormalTexture():SetAtlas("UI-HUD-Calendar-" .. day .. "-Up")
        GameTimeFrame:GetPushedTexture():SetAtlas("UI-HUD-Calendar-" .. day .. "-Down")
        GameTimeFrame:GetHighlightTexture():SetAtlas("UI-HUD-Calendar-" .. day .. "-Mouseover")
    end
    GameTimeFrame:SetText("")
end
hooksecurefunc("GameTimeFrame_SetDate", calendar)

-- The clock, at the bar's right end, without its background (Blizzard_TimeManager, loaded on demand).
local function clock()
    local b = TimeManagerClockButton
    b:SetParent(MinimapCluster)
    b:ClearAllPoints()
    b:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -4, 0)
    b:SetWidth(40)
    b:SetHeight(16)
    b:SetFrameLevel(bar:GetFrameLevel() + 1)
    for _, r in ipairs({b:GetRegions()}) do
        if r:GetObjectType() == "Texture" and r:GetDrawLayer() == "BORDER" then
            r:Hide()
        end
    end
    TimeManagerClockTicker:ClearAllPoints()
    TimeManagerClockTicker:SetPoint("CENTER", 3, 1)
end

-- [[ Tracking and mail ]] --
-- Retail's tracking button left of the bar (its own magnifier, not the tracked kind's icon), mail under it.
MiniMapTracking:ClearAllPoints()
MiniMapTracking:SetPoint("RIGHT", bar, "LEFT", -2, 0)
MiniMapTracking:SetWidth(17)
MiniMapTracking:SetHeight(17)
MiniMapTrackingBackground:SetAtlas("UI-HUD-Minimap-Button")
MiniMapTrackingBackground:ClearAllPoints()
MiniMapTrackingBackground:SetAllPoints()
MiniMapTrackingIcon:SetAlpha(0)
MiniMapTrackingButtonBorder:Hide()
MiniMapTrackingButton:ClearAllPoints()
MiniMapTrackingButton:SetPoint("CENTER")
MiniMapTrackingButton:SetWidth(13)
MiniMapTrackingButton:SetHeight(14)
MiniMapTrackingButton:SetNormalTexture("Interface\\Buttons\\WHITE8X8")
MiniMapTrackingButton:SetPushedTexture("Interface\\Buttons\\WHITE8X8")
MiniMapTrackingButton:GetNormalTexture():SetAtlas("UI-HUD-Minimap-Tracking-Up")
MiniMapTrackingButton:GetPushedTexture():SetAtlas("UI-HUD-Minimap-Tracking-Down")
MiniMapTrackingButton:GetHighlightTexture():SetAtlas("UI-HUD-Minimap-Tracking-Mouseover")
MiniMapTrackingButton:GetHighlightTexture():SetBlendMode("BLEND")
-- The client nudges the icon on press (MiniMapTrackingButton OnMouseDown); the pushed art does that now.
MiniMapTrackingButton:SetScript("OnMouseDown", nil)
MiniMapTrackingButton:SetScript("OnMouseUp", nil)

MiniMapMailFrame:ClearAllPoints()
MiniMapMailFrame:SetPoint("TOPRIGHT", MiniMapTracking, "BOTTOMRIGHT")
MiniMapMailFrame:SetWidth(20)
MiniMapMailFrame:SetHeight(15)
MiniMapMailBorder:Hide()
MiniMapMailIcon:SetAtlas("UI-HUD-Minimap-Mail-Up", true)
MiniMapMailIcon:ClearAllPoints()
MiniMapMailIcon:SetPoint("TOPLEFT")

-- The queue eye, battleground and difficulty flags, which retail moved elsewhere, on the frame's ring.
for _, f in ipairs({MiniMapLFGFrame, MiniMapBattlefieldFrame}) do
    f:ClearAllPoints()
    f:SetPoint("CENTER", Minimap, "CENTER", -76, -76)
end
MiniMapInstanceDifficulty:ClearAllPoints()
MiniMapInstanceDifficulty:SetPoint("CENTER", Minimap, "CENTER", -76, 76)

-- [[ Coordinates ]] --
-- Retail's player position under the map, in the zone's percent; none where the zone has no map (the
-- client gives 0, 0). The world map is put back on the player's zone on zone changes and when it closes
-- (not while it is open, which would change the zone it shows).
local coords = MinimapCluster:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
coords:SetPoint("TOP", Minimap, "BOTTOM", 0, -16)
local elapsed = 0
local ticker = CreateFrame("Frame", nil, MinimapCluster)
ticker:SetScript("OnUpdate", function(_, e)
    elapsed = elapsed + e
    if elapsed < 0.2 then
        return
    end
    elapsed = 0
    local x, y = GetPlayerMapPosition("player")
    if x == 0 and y == 0 then
        coords:SetText("")
    else
        coords:SetFormattedText("%.1f, %.1f", x * 100, y * 100)
    end
end)
local function zone()
    if not WorldMapFrame:IsShown() then
        SetMapToCurrentZone()
    end
end
for _, e in ipairs({"ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD"}) do
    ticker:RegisterEvent(e)
end
ticker:SetScript("OnEvent", zone)
WorldMapFrame:HookScript("OnHide", zone)

-- [[ Zoom ]] --
-- Retail's buttons on the frame's lower right, shown while the mouse is over the map or them.
local zoom = {
    {MinimapZoomIn, "UI-HUD-Minimap-Zoom-In", 17, 17, 88, -68},
    {MinimapZoomOut, "UI-HUD-Minimap-Zoom-Out", 17, 9, 72, -84},
}
for _, z in ipairs(zoom) do
    local b, atlas = z[1], z[2]
    b:SetWidth(z[3])
    b:SetHeight(z[4])
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", z[5], z[6])
    b:GetNormalTexture():SetAtlas(atlas)
    b:GetPushedTexture():SetAtlas(atlas .. "-Down")
    b:GetDisabledTexture():SetAtlas(atlas)
    b:GetDisabledTexture():SetDesaturated(true)
    b:GetHighlightTexture():SetAtlas(atlas .. "-Mouseover")
    b:GetHighlightTexture():SetBlendMode("BLEND")
    b:Hide()
end
local function hover()
    local over = MouseIsOver(Minimap) or MouseIsOver(MinimapZoomIn) or MouseIsOver(MinimapZoomOut)
    for _, b in ipairs({MinimapZoomIn, MinimapZoomOut}) do
        if over then
            b:Show()
        else
            b:Hide()
        end
    end
end
for _, f in ipairs({Minimap, MinimapZoomIn, MinimapZoomOut}) do
    f:HookScript("OnEnter", hover)
    f:HookScript("OnLeave", hover)
end
Minimap:EnableMouseWheel(true)
Minimap:SetScript("OnMouseWheel", function(_, d)
    if d > 0 and Minimap:GetZoom() < Minimap:GetZoomLevels() - 1 then
        Minimap_ZoomInClick()
    elseif d < 0 and Minimap:GetZoom() > 0 then
        Minimap_ZoomOutClick()
    end
end)

-- [[ BotControl ]] --
-- Its button (BotControlMinimapButton, on the map's edge) as retail's minimap buttons: the zone bar's
-- framed tile, lit on hover, its label kept and sized to fit.
local bc = BotControlMinimapButton
if bc then
    bc:SetWidth(24)
    bc:SetHeight(18)
    for _, r in ipairs({bc:GetRegions()}) do
        if r:GetObjectType() == "Texture" then
            r:Hide()
        elseif r:GetObjectType() == "FontString" then
            r:SetFontObject("GameFontNormalSmall")
            r:SetFont(r:GetFont(), 9) -- inside the tile
        end
    end
    buttonFrame(bc) -- framed as the zone bar, so it reads on any terrain
    local lit = bc:CreateTexture(nil, "HIGHLIGHT")
    lit:SetPoint("TOPLEFT", 2, -2)
    lit:SetPoint("BOTTOMRIGHT", -2, 2)
    lit:SetTexture(1, 1, 1, .15)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name == "Blizzard_TimeManager" then
            clock()
        end
    else
        calendar()
        -- Retail always shows the clock; 3.3.5 loads it only for an alarm or the Time Manager window.
        if not TimeManagerClockButton then
            TimeManager_LoadUI()
        end
    end
end)
if TimeManagerClockButton then
    clock()
end
