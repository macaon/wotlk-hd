-- wotlk-hd: retail nameplates. 3.3.5's nameplates are unnamed children of WorldFrame that the client
-- builds and updates itself (NamePlateFrame.cpp): a health bar and a cast bar (StatusBars) plus loose
-- regions for the name, level, border and icons. We keep the client's frames, which stay clickable and
-- up to date, give the health bar retail's look, add our own cast bar, and strip the client's own art.

local ATLAS = WotlkHD_Atlas
local FONT = "Fonts\\FRIZQT__.TTF"
local WIDTH, HEIGHT, CAST_HEIGHT = 110, 10, 10

-- The client's textures, by path (strings in Wow.exe next to NamePlateFrame.cpp).
local KNOWN = {
    ["interface\\targetingframe\\ui-targetingframe-flash"] = "threat",
    ["interface\\tooltips\\nameplate-border"] = "border",
    ["interface\\tooltips\\nameplate-castbar-shield"] = "shield",
    ["interface\\tooltips\\nameplate-glow"] = "highlight",
    ["interface\\targetingframe\\ui-targetingframe-skull"] = "boss",
    ["interface\\targetingframe\\ui-raidtargetingicons"] = "raid",
    ["interface\\tooltips\\elitenameplateicon"] = "elite",
}

local plates = {} -- WorldFrame child -> our state, or false when it isn't a nameplate

local function isPlate(f)
    if f:GetName() then
        return false
    end
    for _, r in ipairs({f:GetRegions()}) do
        if r:GetObjectType() == "Texture" and KNOWN[strlower(r:GetTexture() or "")] == "border" then
            return true
        end
    end
    return false
end

-- The unit a plate shows: its nameplateN token from dinput8.dll, else target or mouseover when we can
-- tell (stock 3.3.5 nameplates aren't units).
local function unitOf(p, plate)
    if WotlkHD_NamePlateUnit then
        return WotlkHD_NamePlateUnit(plate)
    elseif UnitExists("target") and plate:GetAlpha() > 0.99 and p.name:GetText() == UnitName("target") then
        return "target"
    elseif p.highlight:IsShown() and UnitExists("mouseover") then
        return "mouseover"
    end
end

local function layout(p)
    local health = p.health
    health:ClearAllPoints()
    health:SetPoint("CENTER", p.plate, "CENTER", 0, -2)
    health:SetWidth(WIDTH)
    health:SetHeight(HEIGHT)
    p.name:ClearAllPoints()
    p.name:SetPoint("BOTTOM", health, "TOP", 0, 3)
    p.raid:ClearAllPoints()
    p.raid:SetPoint("LEFT", health, "RIGHT", 4, 0)
    p.raid:SetWidth(20)
    p.raid:SetHeight(20)
end

-- [[ Cast bar ]] --
-- From the plate's unit (UnitCastingInfo, UnitChannelInfo): the client runs its own nameplate cast bar
-- only for the target.

local function castFill(c)
    local frac = math.min(math.max((GetTime() * 1000 - c.start) / (c.finish - c.start), 0), 1)
    if c.channel then
        frac = 1 - frac
    end
    local a = c.atlas
    c.fill:SetWidth(math.max(c:GetWidth() * frac, 0.01))
    c.fill:SetTexCoord(a[4], a[4] + (a[5] - a[4]) * frac, a[6], a[7])
end

local function castCheck(p, unit)
    local c = p.castBar
    local name, icon, start, finish, locked, _
    local channel = false
    if unit then
        name, _, _, icon, start, finish, _, _, locked = UnitCastingInfo(unit)
        if not name then
            name, _, _, icon, start, finish, _, locked = UnitChannelInfo(unit)
            channel = true
        end
    end
    if not name then
        c:Hide()
        return
    end
    c.start, c.finish, c.channel = start, finish, channel
    c.atlas = ATLAS[locked and "ui-castingbar-uninterruptable" or channel and "ui-castingbar-filling-channel"
        or "ui-castingbar-filling-standard"]
    c.fill:SetTexture(c.atlas[1])
    if locked then
        c.shield:Show()
    else
        c.shield:Hide()
    end
    c.text:SetText(name)
    c.icon:SetTexture(icon)
    castFill(c)
    c:Show()
end

local function castBar(p)
    local c = CreateFrame("Frame", nil, p.plate)
    c:SetPoint("TOPLEFT", p.health, "BOTTOMLEFT", 0, -2)
    c:SetPoint("TOPRIGHT", p.health, "BOTTOMRIGHT", 0, -2)
    c:SetHeight(CAST_HEIGHT)
    local bg = c:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetAtlas("UI-CastingBar-Background")
    c.fill = c:CreateTexture(nil, "ARTWORK")
    c.fill:SetPoint("TOPLEFT")
    c.fill:SetPoint("BOTTOMLEFT")
    local pip = c:CreateTexture(nil, "OVERLAY")
    pip:SetAtlas("UI-CastingBar-Pip")
    pip:SetWidth(3)
    pip:SetHeight(CAST_HEIGHT + 4)
    pip:SetPoint("CENTER", c.fill, "RIGHT")
    c.icon = c:CreateTexture(nil, "OVERLAY")
    c.icon:SetWidth(CAST_HEIGHT + 2)
    c.icon:SetHeight(CAST_HEIGHT + 2)
    c.icon:SetPoint("RIGHT", c, "LEFT", -2, 0)
    c.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    c.shield = c:CreateTexture(nil, "OVERLAY")
    c.shield:SetAtlas("nameplates-InterruptShield", true)
    c.shield:SetPoint("CENTER", c, "LEFT", 0, 0)
    c.text = c:CreateFontString(nil, "OVERLAY")
    c.text:SetFont(FONT, 8)
    c.text:SetShadowOffset(1, -1)
    c.text:SetPoint("CENTER", 0, -1)
    c:SetScript("OnUpdate", castFill)
    c:Hide()
    p.castBar = c
end

-- [[ Setup and refresh ]] --

local function setup(plate)
    local health, cast = plate:GetChildren()
    local p = {plate = plate, health = health, cast = cast}
    for _, r in ipairs({plate:GetRegions()}) do
        if r:GetObjectType() == "FontString" then
            if p.name then
                p.level = r
            else
                p.name = r
            end
        else
            local role = KNOWN[strlower(r:GetTexture() or "")]
            if role then
                p[role] = r
            else -- the client's cast bar border and spell icon (which it sets per cast): off screen
                r:ClearAllPoints()
                r:SetPoint("TOPRIGHT", WorldFrame, "TOPLEFT", -1000, 0)
            end
            if role ~= "raid" then
                -- no texture, but still shown, hidden and coloured by the client, which we read (SetAlpha
                -- doesn't hold: the client's SetVertexColor resets it)
                r:SetTexture(nil)
            end
        end
    end
    p.level:ClearAllPoints() -- off screen, as its colour resets alpha too
    p.level:SetPoint("TOPRIGHT", WorldFrame, "TOPLEFT", -1000, 0)
    p.name:SetFont(FONT, 10)
    p.name:SetShadowOffset(1, -1)
    cast:SetAlpha(0)

    health:SetStatusBarTexture(ATLAS["nameplates-bar-fill"][1])
    p.edge = health:CreateTexture(nil, "BACKGROUND")
    p.edge:SetPoint("TOPLEFT", -1, 1)
    p.edge:SetPoint("BOTTOMRIGHT", 1, -1)
    p.edge:SetTexture(1, 1, 1)
    local bg = health:CreateTexture(nil, "BORDER")
    bg:SetAllPoints()
    bg:SetTexture(0.1, 0.1, 0.1, 0.85)
    p.class = health:CreateTexture(nil, "OVERLAY")
    p.class:SetAtlas("nameplates-icon-elite-gold")
    p.class:SetWidth(16)
    p.class:SetHeight(16)
    p.class:SetPoint("RIGHT", health, "LEFT", -1, 0)

    castBar(p)
    layout(p)
    plate:HookScript("OnShow", function() layout(p) end)
    plates[plate] = p
end

-- Casts, selection (white border), threat (the client's glow colour) and elite/boss state.
local function refresh(p, plate)
    local unit = unitOf(p, plate)
    castCheck(p, unit)
    if unit and UnitIsUnit(unit, "target") then
        p.edge:SetVertexColor(1, 1, 1)
    elseif p.threat:IsShown() then
        p.edge:SetVertexColor(p.threat:GetVertexColor())
    else
        p.edge:SetVertexColor(0, 0, 0)
    end
    if p.elite:IsShown() or p.boss:IsShown() then
        p.class:Show()
    else
        p.class:Hide()
    end
end

local seen, elapsed = 0, 0
CreateFrame("Frame"):SetScript("OnUpdate", function(_, dt)
    local n = WorldFrame:GetNumChildren()
    if n ~= seen then
        seen = n
        for _, f in ipairs({WorldFrame:GetChildren()}) do
            if plates[f] == nil then
                if isPlate(f) then
                    setup(f)
                else
                    plates[f] = false
                end
            end
        end
    end
    elapsed = elapsed + dt
    if elapsed >= 0.1 then
        elapsed = 0
        for plate, p in pairs(plates) do
            if p and plate:IsShown() then
                refresh(p, plate)
            end
        end
    end
end)

-- Enemy nameplates on, as retail has them by default: once per account, so turning them off sticks.
local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
login:SetScript("OnEvent", function()
    WotlkHD_Saved = WotlkHD_Saved or {}
    if not WotlkHD_Saved.enemyPlates then
        WotlkHD_Saved.enemyPlates = true
        SetCVar("nameplateShowEnemies", "1")
    end
end)
