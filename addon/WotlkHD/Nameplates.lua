-- wotlk-hd: retail nameplates. 3.3.5's nameplates are unnamed children of WorldFrame that the client
-- builds and updates itself (NamePlateFrame.cpp): a health bar and a cast bar (StatusBars) plus loose
-- regions for the name, level, border and icons. We keep the client's frames, which stay clickable and
-- up to date, give the health bar retail's look, add our own cast bar, and strip the client's own art.

local ATLAS = WotlkHD_Atlas
local FONT = "Fonts\\FRIZQT__.TTF"
local WIDTH, HEIGHT, CAST_HEIGHT = 100, 10, 9
-- Retail's distance scaling (nameplateMaxScale/MinScale and their distances, nameplateSelectedScale).
local NEAR, FAR, NEAR_SCALE, FAR_SCALE, TARGET_SCALE = 10, 40, 1, 0.8, 1.2
local MAX_AURAS, AURA_SIZE = 6, 14
local CLASSIFICATION = {
    elite = "nameplates-icon-elite-gold",
    worldboss = "nameplates-icon-elite-gold",
    rareelite = "nameplates-icon-elite-silver",
    rare = "nameplates-icon-elite-silver",
}

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
    p.name:ClearAllPoints() -- off screen: our label, inside the bar, shows its text
    p.name:SetPoint("TOPRIGHT", WorldFrame, "TOPLEFT", -1000, 0)
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
    local c = CreateFrame("Frame", nil, p.body)
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

-- [[ Auras ]] --
-- Your debuffs on the unit, as retail shows them: square icons in a row above the bar's left end, each
-- with its time left.

local function auraIcon(p, i)
    local a = p.auras[i]
    if a then
        return a
    end
    a = CreateFrame("Frame", nil, p.body)
    a:SetWidth(AURA_SIZE)
    a:SetHeight(AURA_SIZE)
    if i == 1 then
        a:SetPoint("BOTTOMLEFT", p.health, "TOPLEFT", 0, 4)
    else
        a:SetPoint("LEFT", p.auras[i - 1], "RIGHT", 4, 0)
    end
    local edge = a:CreateTexture(nil, "BACKGROUND")
    edge:SetPoint("TOPLEFT", -1, 1)
    edge:SetPoint("BOTTOMRIGHT", 1, -1)
    edge:SetTexture(0, 0, 0)
    a.icon = a:CreateTexture(nil, "ARTWORK")
    a.icon:SetAllPoints()
    a.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    a.cooldown = CreateFrame("Cooldown", nil, a, "CooldownFrameTemplate")
    a.cooldown:SetAllPoints()
    a.cooldown:SetReverse(true)
    a.count = a:CreateFontString(nil, "OVERLAY")
    a.count:SetFont(FONT, 8, "OUTLINE")
    a.count:SetPoint("BOTTOMRIGHT", 2, -1)
    a.timer = a:CreateFontString(nil, "OVERLAY")
    a.timer:SetFont(FONT, 8, "OUTLINE")
    a.timer:SetPoint("CENTER", 0, 1)
    p.auras[i] = a
    return a
end

local function auraCheck(p, unit)
    local n = 0
    for i = 1, unit and 40 or 0 do
        local name, _, icon, count, _, duration, expires = UnitAura(unit, i, "HARMFUL|PLAYER")
        if not name or n == MAX_AURAS then
            break
        end
        n = n + 1
        local a = auraIcon(p, n)
        a.icon:SetTexture(icon)
        a.count:SetText(count > 1 and count or "")
        local left = expires > 0 and expires - GetTime() or 0
        a.timer:SetText(left <= 0 and "" or left >= 60 and math.ceil(left / 60) .. "m" or math.ceil(left))
        if a.expires ~= expires then
            a.expires = expires
            if duration > 0 then
                a.cooldown:SetCooldown(expires - duration, duration)
            else
                a.cooldown:Hide()
            end
        end
        a:Show()
    end
    for i = n + 1, #p.auras do
        p.auras[i]:Hide()
    end
end

-- [[ Setup and refresh ]] --

local function setup(plate)
    local health, cast = plate:GetChildren()
    local p = {plate = plate, health = health, cast = cast, auras = {}}
    -- Everything we show hangs off one frame, scaled by distance; the client's frame keeps its size.
    p.body = CreateFrame("Frame", nil, plate)
    p.body:SetAllPoints()
    health:SetParent(p.body)
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
    cast:SetAlpha(0)

    health:SetStatusBarTexture(ATLAS["nameplates-bar-fill"][1])
    p.edge = health:CreateTexture(nil, "BACKGROUND")
    p.edge:SetPoint("TOPLEFT", -1, 1)
    p.edge:SetPoint("BOTTOMRIGHT", 1, -1)
    p.edge:SetTexture(1, 1, 1)
    local bg = health:CreateTexture(nil, "BORDER")
    bg:SetAllPoints()
    bg:SetTexture(0.1, 0.1, 0.1, 0.85)
    local over = CreateFrame("Frame", nil, health) -- above the bar's fill
    over:SetAllPoints()
    over:SetFrameLevel(health:GetFrameLevel() + 2)
    p.label = over:CreateFontString(nil, "OVERLAY")
    p.label:SetFont(FONT, 7)
    p.label:SetTextColor(1, 1, 1)
    p.label:SetShadowOffset(1, -1)
    p.label:SetJustifyH("LEFT")
    p.label:SetPoint("LEFT", 3, 0)
    p.label:SetPoint("RIGHT", -3, 0)
    p.label:SetHeight(HEIGHT)
    p.class = health:CreateTexture(nil, "OVERLAY")
    p.class:SetWidth(14)
    p.class:SetHeight(14)
    p.class:SetPoint("RIGHT", health, "LEFT", -1, 0)

    castBar(p)
    layout(p)
    plate:HookScript("OnShow", function() layout(p) end)
    plates[plate] = p
end

-- Size by distance, name, casts, border (thicker and white on the target, the client's threat colour,
-- else near black), classification and auras.
local function refresh(p, plate)
    local unit = unitOf(p, plate)
    castCheck(p, unit)
    local target = unit and UnitIsUnit(unit, "target")
    local d = unit and WotlkHD_UnitDistance and WotlkHD_UnitDistance(unit)
    local scale = target and TARGET_SCALE or not d and NEAR_SCALE
        or NEAR_SCALE + (FAR_SCALE - NEAR_SCALE) * math.min(math.max((d - NEAR) / (FAR - NEAR), 0), 1)
    if p.scale ~= scale then
        p.scale = scale
        p.body:SetScale(scale)
        p.body:SetFrameLevel(plate:GetFrameLevel() + (target and 20 or 1)) -- the target's on top, as on retail
    end
    local w = target and 2 or 1 -- the target's border is thicker
    p.edge:SetPoint("TOPLEFT", -w, w)
    p.edge:SetPoint("BOTTOMRIGHT", w, -w)
    if target then
        p.edge:SetVertexColor(1, 1, 1)
    elseif p.threat:IsShown() then
        p.edge:SetVertexColor(p.threat:GetVertexColor())
    else
        p.edge:SetVertexColor(0.12, 0.12, 0.12)
    end
    p.label:SetText(p.name:GetText())
    local class = unit and UnitClassification(unit)
    if not class then
        class = (p.elite:IsShown() or p.boss:IsShown()) and "elite"
    end
    if CLASSIFICATION[class] then
        p.class:SetAtlas(CLASSIFICATION[class])
        p.class:Show()
    else
        p.class:Hide()
    end
    auraCheck(p, unit)
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
