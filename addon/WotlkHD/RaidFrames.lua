-- wotlk-hd: retail's raid frames (CompactUnitFrame) for raids, and for the party in place of the party
-- frames with Use Raid-Style Party Frames (cvar hdRaidStyleParty, from dinput8.dll; off as on retail).
-- Health is green, or class coloured with Display Class Colors (hdRaidClassColors, off as on retail).
-- A SecureGroupHeader lays out SecureUnitButtons (click to target, right-click for the unit menu, both
-- in combat); we draw retail's look on them: health, name and role, dead/offline,
-- target and aggro highlights, your buffs, debuffs, dispellable debuff types, and out-of-range fade.

local FONT = "Fonts\\FRIZQT__.TTF"
local AURA = 12
local MAX_BUFFS, MAX_DEBUFFS, MAX_DISPELS = 3, 3, 3
local ROLE = {"roleicon-tiny-tank", "roleicon-tiny-healer", "roleicon-tiny-dps"}
local DISPEL = {Magic = "raidframe-icon-debuffmagic", Curse = "raidframe-icon-debuffcurse",
    Disease = "raidframe-icon-debuffdisease", Poison = "raidframe-icon-debuffpoison"}

local buttons = {}
local GREEN = {r = 0, g = 1, b = 0} -- retail's health colour without Display Class Colors

-- Frame size, set in Edit Mode (WotlkHD_Saved.raidFrameWidth/Height; retail's 72x36 by default).
local function frameSize()
    local saved = WotlkHD_Saved or {}
    return saved.raidFrameWidth or 72, saved.raidFrameHeight or 36
end

-- [[ Look ]] --

local function auraButton(f, debuff)
    local a = CreateFrame("Frame", nil, f)
    a:SetWidth(AURA)
    a:SetHeight(AURA)
    a.icon = a:CreateTexture(nil, "ARTWORK")
    a.icon:SetAllPoints()
    a.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    if debuff then -- retail's debuff border, coloured by type
        a.border = a:CreateTexture(nil, "OVERLAY")
        a.border:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
        a.border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
        a.border:SetPoint("TOPLEFT", -1, 1)
        a.border:SetPoint("BOTTOMRIGHT", 1, -1)
    end
    a.cooldown = CreateFrame("Cooldown", nil, a, "CooldownFrameTemplate")
    a.cooldown:SetAllPoints()
    a.cooldown:SetReverse(true)
    a.count = a:CreateFontString(nil, "OVERLAY")
    a.count:SetFont(FONT, 8, "OUTLINE")
    a.count:SetPoint("BOTTOMRIGHT", 2, -1)
    a:Hide()
    return a
end

local function build(f)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(0, 0, 0)
    f.health = CreateFrame("StatusBar", nil, f)
    f.health:SetPoint("TOPLEFT", 1, -1)
    f.health:SetPoint("BOTTOMRIGHT", -1, 1)
    f.health:SetStatusBarTexture(WotlkHD_Atlas["raidframe-hp-fill"][1])
    local hbg = f.health:CreateTexture(nil, "BACKGROUND")
    hbg:SetAllPoints()
    hbg:SetAtlas("RaidFrame-Hp-Bg")

    local over = CreateFrame("Frame", nil, f) -- above the health bar
    over:SetAllPoints()
    over:SetFrameLevel(f.health:GetFrameLevel() + 2)
    f.role = over:CreateTexture(nil, "OVERLAY")
    f.role:SetWidth(12)
    f.role:SetHeight(12)
    f.role:SetPoint("TOPLEFT", 3, -3)
    f.name = over:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.name:SetJustifyH("LEFT")
    f.name:SetHeight(12)
    f.name:SetPoint("TOPRIGHT", -3, -3)
    f.status = over:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.status:SetPoint("CENTER", 0, -3)
    f.dispelGlow = over:CreateTexture(nil, "BORDER")
    f.dispelGlow:SetAllPoints()
    f.dispelGlow:SetAtlas("RaidFrame-DispelHighlight")
    f.aggro = over:CreateTexture(nil, "ARTWORK")
    f.aggro:SetAllPoints()
    f.aggro:SetAtlas("RaidFrame-AgroFrame")
    f.selected = over:CreateTexture(nil, "OVERLAY")
    f.selected:SetAllPoints()
    f.selected:SetAtlas("RaidFrame-TargetFrame")

    f.buffs, f.debuffs, f.dispels = {}, {}, {}
    for i = 1, MAX_BUFFS do
        local a = auraButton(over)
        a:SetPoint("BOTTOMRIGHT", over, "BOTTOMRIGHT", -3 - (i - 1) * (AURA + 1), 3)
        f.buffs[i] = a
    end
    for i = 1, MAX_DEBUFFS do
        local a = auraButton(over, true)
        a:SetPoint("BOTTOMLEFT", over, "BOTTOMLEFT", 3 + (i - 1) * (AURA + 2), 3)
        f.debuffs[i] = a
    end
    for i = 1, MAX_DISPELS do
        local t = over:CreateTexture(nil, "OVERLAY")
        t:SetWidth(AURA)
        t:SetHeight(AURA)
        t:SetPoint("TOPRIGHT", over, "TOPRIGHT", -3 - (i - 1) * (AURA + 1), -3)
        f.dispels[i] = t
    end
end

-- [[ Update ]] --

local function auras(list, unit, filter, debuff)
    local n = 0
    for i = 1, 40 do
        if n == #list then
            break
        end
        local name, _, icon, count, kind, duration, expires = UnitAura(unit, i, filter)
        if not name then
            break
        end
        n = n + 1
        local a = list[n]
        a.icon:SetTexture(icon)
        a.count:SetText(count > 1 and count or "")
        if debuff then
            local c = DebuffTypeColor[kind or "none"]
            a.border:SetVertexColor(c.r, c.g, c.b)
        end
        if duration > 0 then
            a.cooldown:SetCooldown(expires - duration, duration)
        else
            a.cooldown:Hide()
        end
        a:Show()
    end
    for i = n + 1, #list do
        list[i]:Hide()
    end
end

local function dispels(f, unit)
    local seen, n = {}, 0
    for i = 1, 40 do
        local name, _, _, _, kind = UnitAura(unit, i, "HARMFUL|RAID") -- the ones you can dispel
        if not name then
            break
        end
        if DISPEL[kind] and not seen[kind] and n < MAX_DISPELS then
            seen[kind] = true
            n = n + 1
            f.dispels[n]:SetAtlas(DISPEL[kind])
            f.dispels[n]:Show()
            if n == 1 then
                local c = DebuffTypeColor[kind]
                f.dispelGlow:SetVertexColor(c.r, c.g, c.b)
            end
        end
    end
    for i = n + 1, MAX_DISPELS do
        f.dispels[i]:Hide()
    end
    if n > 0 then
        f.dispelGlow:Show()
    else
        f.dispelGlow:Hide()
    end
end

local function range(f, unit)
    f:SetAlpha((UnitIsUnit(unit, "player") or UnitInRange(unit)) and 1 or 0.55)
end

local function update(f)
    local unit = f:GetAttribute("unit")
    if not unit or not UnitExists(unit) then
        return
    end
    local _, class = UnitClass(unit)
    local c = GetCVar("hdRaidClassColors") == "1" and RAID_CLASS_COLORS[class] or GREEN
    local online, dead = UnitIsConnected(unit), UnitIsDeadOrGhost(unit)
    f.health:SetMinMaxValues(0, math.max(UnitHealthMax(unit), 1))
    f.health:SetValue(dead and 0 or UnitHealth(unit))
    if online then
        f.health:SetStatusBarColor(c.r, c.g, c.b)
    else
        f.health:SetStatusBarColor(0.5, 0.5, 0.5)
    end
    f.status:SetText(not online and PLAYER_OFFLINE or dead and DEAD or "")

    local tank, healer, dps = UnitGroupRolesAssigned(unit)
    local role = tank and ROLE[1] or healer and ROLE[2] or dps and ROLE[3]
    if role then
        f.role:SetAtlas(role)
        f.role:Show()
        f.name:SetPoint("TOPLEFT", f.role, "TOPRIGHT", 1, 0)
    else
        f.role:Hide()
        f.name:SetPoint("TOPLEFT", 3, -3)
    end
    f.name:SetText(UnitName(unit))

    if UnitIsUnit(unit, "target") then
        f.selected:Show()
    else
        f.selected:Hide()
    end
    local threat = UnitThreatSituation(unit)
    if threat and threat > 0 then
        f.aggro:SetVertexColor(GetThreatStatusColor(threat))
        f.aggro:Show()
    else
        f.aggro:Hide()
    end
    auras(f.buffs, unit, "HELPFUL|PLAYER")
    auras(f.debuffs, unit, "HARMFUL", true)
    dispels(f, unit)
    range(f, unit)
end

-- [[ Header ]] --

local menu = CreateFrame("Frame", "WotlkHDRaidFrameDropDown", UIParent, "UIDropDownMenuTemplate")
UIDropDownMenu_Initialize(menu, function(self)
    local unit = self.unit
    if not unit then
        return
    end
    local which = UnitIsUnit(unit, "player") and "SELF" or UnitInRaid(unit) and "RAID_PLAYER" or "PARTY"
    UnitPopup_ShowMenu(self, which, unit, UnitName(unit), UnitInRaid(unit))
end, "MENU")

local function showMenu(f, unit)
    menu.unit = unit
    ToggleDropDownMenu(1, nil, menu, "cursor")
end

local header = CreateFrame("Frame", "WotlkHDRaidFrames", UIParent, "SecureGroupHeaderTemplate")
header:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -180)
header:SetAttribute("template", "SecureUnitButtonTemplate")
header:SetAttribute("showRaid", true)
header:SetAttribute("showPlayer", true)
header:SetAttribute("groupBy", "GROUP")
header:SetAttribute("groupingOrder", "1,2,3,4,5,6,7,8")
header:SetAttribute("point", "TOP")
header:SetAttribute("unitsPerColumn", 5)
header:SetAttribute("maxColumns", 8)
header:SetAttribute("columnAnchorPoint", "LEFT")
header.initialConfigFunction = function(f)
    local w, h = frameSize()
    f:SetAttribute("initial-width", w)
    f:SetAttribute("initial-height", h)
    f:SetAttribute("*type1", "target")
    f:SetAttribute("*type2", "menu")
    f.menu = showMenu
    f:RegisterForClicks("AnyUp")
    build(f)
    f:HookScript("OnAttributeChanged", function(self, name)
        if name == "unit" then
            update(self)
        end
    end)
    f:HookScript("OnShow", update)
    tinsert(buttons, f)
end
header:Show()

-- For Edit Mode: resize the frames (out of combat) and lay them out again.
WotlkHD_RaidFrames = {header = header}
function WotlkHD_RaidFrames.SetSize(w, h)
    WotlkHD_Saved.raidFrameWidth, WotlkHD_Saved.raidFrameHeight = w, h
    for _, f in ipairs(buttons) do
        f:SetWidth(w)
        f:SetHeight(h)
    end
    header:SetAttribute("unitsPerColumn", 5) -- any attribute change makes the header lay out again
end

-- [[ Events ]] --

local function updateUnit(unit)
    for _, f in ipairs(buttons) do
        if f:IsShown() and f:GetAttribute("unit") and UnitIsUnit(f:GetAttribute("unit"), unit) then
            update(f)
        end
    end
end

local function updateAll()
    for _, f in ipairs(buttons) do
        if f:IsShown() then
            update(f)
        end
    end
end

local events = CreateFrame("Frame")
local applyParty -- below
for _, e in ipairs({"UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_AURA", "UNIT_NAME_UPDATE", "UNIT_FLAGS",
    "UNIT_THREAT_SITUATION_UPDATE"}) do
    events:RegisterEvent(e)
end
for _, e in ipairs({"PLAYER_TARGET_CHANGED", "PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE", "PARTY_MEMBER_ENABLE",
    "PARTY_MEMBER_DISABLE", "PLAYER_ROLES_ASSIGNED", "PLAYER_ENTERING_WORLD"}) do
    events:RegisterEvent(e)
end
events:SetScript("OnEvent", function(self, event, unit)
    if event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent(event)
        applyParty()
    elseif event:find("^UNIT_") then
        if unit then
            updateUnit(unit)
        end
    else
        updateAll()
    end
end)

local elapsed = 0
events:SetScript("OnUpdate", function(_, dt) -- range has no event
    elapsed = elapsed + dt
    if elapsed < 0.2 then
        return
    end
    elapsed = 0
    for _, f in ipairs(buttons) do
        local unit = f:IsShown() and f:GetAttribute("unit")
        if unit and UnitExists(unit) then
            range(f, unit)
        end
    end
end)

-- [[ Raid-style party frames ]] --
-- The party frames go to a hidden parent rather than being hidden: they're secure, and the client shows
-- them on roster changes. Attributes and parents change out of combat only, so a change waits for it.

local hidden = CreateFrame("Frame")
hidden:Hide()

function applyParty()
    if InCombatLockdown() then
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    local on = GetCVar("hdRaidStyleParty") == "1"
    header:SetAttribute("showParty", on)
    for i = 1, MAX_PARTY_MEMBERS do
        _G["PartyMemberFrame" .. i]:SetParent(on and hidden or UIParent) -- its pet frame comes along
    end
    PartyMemberBackground:SetParent(on and hidden or UIParent)
end

hooksecurefunc("SetCVar", function(name)
    if name == "hdRaidStyleParty" then
        applyParty()
    elseif name == "hdRaidClassColors" then
        updateAll()
    end
end)
applyParty()
