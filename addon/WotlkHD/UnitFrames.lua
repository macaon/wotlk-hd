-- wotlk-hd: retail's unit frames and cast bars: player, target, focus, their targets, pet and party
-- (Dragonflight's UI-HUD-UnitFrame and UI-CastingBar art and layout, from Blizzard_UnitFrame and
-- Blizzard_UIPanels_Game). The client's frames stay, with their
-- behaviour; we change their art and move their parts, and again after the client's own code moves
-- them (vehicle art, target classification).

local Retail = WotlkHD_Retail
local ATLAS = WotlkHD_Atlas

local function at(region, point, x, y, relTo, relPoint)
    region:ClearAllPoints()
    region:SetPoint(point, relTo or region:GetParent(), relPoint or point, x, y)
end

local function atlas(tex, name)
    tex:SetAtlas(name, true)
    tex:SetVertexColor(1, 1, 1)
end

-- Power bars take the power type's own atlas, as retail's (the client tints one texture).
local POWER = {[0] = "Mana", [1] = "Rage", [2] = "Focus", [3] = "Energy", [6] = "RunicPower"}

local function powerBar(bar)
    local kind = bar.wotlkhdPower and POWER[UnitPowerType(bar.unit)]
    if kind then
        Retail.AtlasBar(bar, bar.wotlkhdPower .. kind)
        bar.wotlkhdFill:SetVertexColor(1, 1, 1)
    elseif bar.wotlkhdPower then
        Retail.AtlasBar(bar, bar.wotlkhdPower .. "Mana")
        local c = PowerBarColor[UnitPowerType(bar.unit)] or PowerBarColor.MANA
        bar.wotlkhdFill:SetVertexColor(c.r, c.g, c.b)
    end
end
hooksecurefunc("UnitFrameManaBar_UpdateType", powerBar)

-- [[ Player ]] --

local playerCorner = PlayerFrame:CreateTexture(nil, "OVERLAY")
atlas(playerCorner, "UI-HUD-UnitFrame-Player-PortraitOn-CornerEmbellishment")

local function playerLayout()
    local vehicle = PlayerFrame.state == "vehicle"
    atlas(PlayerFrameTexture, "UI-HUD-UnitFrame-Player-PortraitOn")
    at(PlayerFrameTexture, "CENTER", 0, 0, PlayerFrame)
    atlas(PlayerFrameVehicleTexture, "UI-HUD-UnitFrame-Player-PortraitOn-Vehicle")
    at(PlayerFrameVehicleTexture, "CENTER", -2, 0, PlayerFrame)
    PlayerFrameBackground:Hide()
    PlayerPortrait:SetWidth(60)
    PlayerPortrait:SetHeight(60)
    at(PlayerPortrait, "TOPLEFT", 24, -19, PlayerFrame)
    playerCorner:SetPoint("TOPLEFT", PlayerFrame, "TOPLEFT", 58.5, -53.5)

    PlayerName:SetWidth(96)
    PlayerName:SetHeight(12)
    PlayerName:SetJustifyH("LEFT")
    at(PlayerName, "TOPLEFT", 88, -27, PlayerFrame)
    PlayerLevelText:SetJustifyH("RIGHT")
    at(PlayerLevelText, "TOPRIGHT", -24.5, -28, PlayerFrame)
    if vehicle then
        PlayerLevelText:Hide()
    end

    PlayerFrameHealthBar:SetWidth(124)
    PlayerFrameHealthBar:SetHeight(20)
    at(PlayerFrameHealthBar, "TOPLEFT", 85, -40, PlayerFrame)
    PlayerFrameManaBar:SetWidth(124)
    PlayerFrameManaBar:SetHeight(10)
    at(PlayerFrameManaBar, "TOPLEFT", 85, -61, PlayerFrame)
    at(PlayerFrameHealthBarText, "CENTER", 0, 0, PlayerFrameHealthBar)
    at(PlayerFrameManaBarText, "CENTER", 0, 0, PlayerFrameManaBar)

    atlas(PlayerFrameFlash, "UI-HUD-UnitFrame-Player-PortraitOn-InCombat")
    at(PlayerFrameFlash, "CENTER", -1.5, 1, PlayerFrame)
    atlas(PlayerStatusTexture, "UI-HUD-UnitFrame-Player-PortraitOn-Status")
    at(PlayerStatusTexture, "TOPLEFT", 17, -14, PlayerFrame)
    atlas(PlayerAttackIcon, "UI-HUD-UnitFrame-Player-CombatIcon")
    at(PlayerAttackIcon, "TOPLEFT", 64, -62, PlayerFrame)
    PlayerAttackGlow:SetTexture(nil)
    PlayerAttackBackground:SetTexture(nil)
    PlayerRestGlow:SetTexture(nil)
    at(PlayerRestIcon, "TOPLEFT", 64, -6, PlayerFrame)
    atlas(PlayerLeaderIcon, "UI-HUD-UnitFrame-Player-Group-LeaderIcon")
    at(PlayerLeaderIcon, "TOPLEFT", 86, -10, PlayerFrame)
    at(PlayerMasterIcon, "TOPLEFT", 102, -10, PlayerFrame)
    at(PlayerPVPIcon, "TOP", 25, -50, PlayerFrame, "TOPLEFT")
    if PlayerFrameRoleIcon then
        at(PlayerFrameRoleIcon, "TOPLEFT", 196, -27, PlayerFrame)
    end
    at(PlayerHitIndicator, "CENTER", 54, -50, PlayerFrame, "TOPLEFT")
    at(PlayerFrameGroupIndicator, "BOTTOMRIGHT", 210, -29, PlayerFrame, "TOPLEFT")
end

Retail.AtlasBar(PlayerFrameHealthBar, "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health")
PlayerFrameManaBar.wotlkhdPower = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-"
powerBar(PlayerFrameManaBar)
playerLayout()
hooksecurefunc("PlayerFrame_ToPlayerArt", playerLayout)
hooksecurefunc("PlayerFrame_ToVehicleArt", playerLayout)

-- [[ Target and focus ]] --
-- The same template; the name background is retail's reputation bar, the elite dragon its boss frame.

local function targetClassification(self)
    local class = UnitClassification(self.unit)
    atlas(self.borderTexture, (class == "rare" or class == "rareelite") and "UI-HUD-UnitFrame-Target-Rare-PortraitOn"
        or "UI-HUD-UnitFrame-Target-PortraitOn")
    at(self.borderTexture, "CENTER", 0, 0, self)
    if self.threatIndicator then
        atlas(self.threatIndicator, "UI-HUD-UnitFrame-Target-PortraitOn-InCombat")
        at(self.threatIndicator, "CENTER", 0, 2, self)
    end
    local boss = self.wotlkhdBoss
    if class == "worldboss" then
        atlas(boss, "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold-Winged")
        at(boss, "TOPRIGHT", 8, -8, self)
        boss:Show()
    elseif class == "rareelite" then
        atlas(boss, "ui-hud-unitframe-target-portraiton-boss-rare-silver")
        at(boss, "TOPRIGHT", -11, -8, self)
        boss:Show()
    elseif class == "elite" then
        atlas(boss, "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold")
        at(boss, "TOPRIGHT", -11, -8, self)
        boss:Show()
    else
        boss:Hide()
    end
    if class == "rare" or class == "rareelite" then
        self.wotlkhdStar:Show()
    else
        self.wotlkhdStar:Hide()
    end
end

local function targetLayout(self)
    local name = self:GetName()
    local texture = _G[name .. "TextureFrame"]
    _G[name .. "Background"]:Hide()
    self.portrait:SetWidth(58)
    self.portrait:SetHeight(58)
    at(self.portrait, "TOPRIGHT", -26, -19, self)

    local rep = self.nameBackground
    atlas(rep, "UI-HUD-UnitFrame-Target-PortraitOn-Type")
    at(rep, "TOPRIGHT", -75, -25, self)
    self.name:SetWidth(90)
    self.name:SetHeight(12)
    self.name:SetJustifyH("LEFT")
    at(self.name, "TOPLEFT", -106, -1, rep, "TOPRIGHT")
    self.levelText:SetJustifyH("CENTER")
    at(self.levelText, "TOPLEFT", -133, -2, rep, "TOPRIGHT")
    atlas(self.highLevelTexture, "UI-HUD-UnitFrame-Target-HighLevelTarget_Icon")
    at(self.highLevelTexture, "TOPLEFT", 4, 2, self.levelText)

    self.healthbar:SetWidth(126)
    self.healthbar:SetHeight(20)
    at(self.healthbar, "TOPLEFT", 23, -40, self)
    self.manabar:SetWidth(134)
    self.manabar:SetHeight(10)
    at(self.manabar, "TOPLEFT", 23, -61, self)
    at(_G[name .. "TextureFrameHealthBarText"], "CENTER", 0, 0, self.healthbar)
    at(_G[name .. "TextureFrameManaBarText"], "CENTER", -4, 0, self.manabar)
    at(self.deadText, "CENTER", 0, 0, self.healthbar)
    Retail.AtlasBar(self.healthbar, "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health")
    self.manabar.wotlkhdPower = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-"

    atlas(self.leaderIcon, "UI-HUD-UnitFrame-Player-Group-LeaderIcon")
    at(self.leaderIcon, "TOPRIGHT", -85, -8, self)
    at(self.raidTargetIcon, "CENTER", 0, 0, self.portrait, "TOP")
    at(self.pvpIcon, "TOP", -26, -50, self, "TOPRIGHT")

    self.wotlkhdBoss = texture:CreateTexture(nil, "ARTWORK")
    self.wotlkhdStar = texture:CreateTexture(nil, "OVERLAY")
    atlas(self.wotlkhdStar, "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Star")
    at(self.wotlkhdStar, "CENTER", 0, 0, self.portrait, "BOTTOM")
    self.wotlkhdBoss:Hide()
    self.wotlkhdStar:Hide()
end

for _, frame in ipairs({TargetFrame, FocusFrame}) do
    targetLayout(frame)
end
hooksecurefunc("TargetFrame_CheckClassification", function(self)
    if self.wotlkhdBoss then
        targetClassification(self)
    end
end)
-- The client starts the auras 32 up from the frame's bottom (TargetFrame.lua's local AURA_START_Y), on
-- retail's power bar; the first row moves down under it, and the rest follow it.
hooksecurefunc("TargetFrame_UpdateAuras", function(self)
    if not self.wotlkhdBoss then
        return
    end
    for _, kind in ipairs({"Buff1", "Debuff1"}) do
        local aura = _G[self:GetName() .. kind]
        if aura and select(2, aura:GetPoint(1)) == self then
            aura:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 5, 24)
        end
    end
end)
hooksecurefunc("TargetFrame_CheckLevel", function(self) -- the client's level colour on retail's art
    if self.wotlkhdBoss then
        at(self.highLevelTexture, "TOPLEFT", 4, 2, self.levelText)
    end
end)

-- [[ Small frames: target of target, pet, party ]] --
-- Retail's TargetofTarget, PetFrame and PartyMemberFrame layouts: a 37 portrait, the name beside it,
-- a 70x10 health bar and a 74x7 power bar.

local function smallFrame(f, parts, layout)
    local tex, flash = parts.texture, parts.flash
    atlas(tex, layout.art)
    at(tex, layout.artPoint or "CENTER", layout.artX or 0, layout.artY or 0, f)
    if flash then
        atlas(flash, layout.flashArt)
        at(flash, "TOPLEFT", layout.artX or 1, layout.artY or 0, f)
    end
    if parts.background then
        parts.background:Hide()
    end
    parts.portrait:SetWidth(37)
    parts.portrait:SetHeight(37)
    at(parts.portrait, "TOPLEFT", layout.portraitX, layout.portraitY, f)
    parts.name:SetWidth(layout.nameWidth or 68)
    parts.name:SetHeight(10)
    parts.name:SetJustifyH("LEFT")
    at(parts.name, "TOPLEFT", 2, 0, parts.portrait, "TOPRIGHT")
    parts.health:SetWidth(70)
    parts.health:SetHeight(10)
    at(parts.health, "TOPLEFT", layout.healthX, layout.healthY, f)
    Retail.AtlasBar(parts.health, layout.bar .. "Health")
    if parts.mana then
        parts.mana:SetWidth(74)
        parts.mana:SetHeight(7)
        at(parts.mana, "TOPLEFT", -4, -1, parts.health, "BOTTOMLEFT")
        parts.mana.wotlkhdPower = layout.bar
        powerBar(parts.mana)
    end
    for _, key in ipairs({"healthText", "dead"}) do
        if parts[key] then
            at(parts[key], "CENTER", 0, 0, parts.health)
        end
    end
    if parts.manaText then
        at(parts.manaText, "CENTER", 0, 0, parts.mana)
    end
end

local TOT = {art = "UI-HUD-UnitFrame-TargetofTarget-PortraitOn", bar = "UI-HUD-UnitFrame-TargetofTarget-PortraitOn-Bar-",
    portraitX = 5, portraitY = -5, healthX = 44, healthY = -17}

local function totLayout(tot)
    local name = tot:GetName()
    tot:SetWidth(120)
    tot:SetHeight(49)
    tot:ClearAllPoints()
    tot:SetPoint("TOPRIGHT", tot:GetParent(), "BOTTOMRIGHT", 12, 10)
    smallFrame(tot, {texture = _G[name .. "TextureFrameTexture"], portrait = _G[name .. "Portrait"],
        name = _G[name .. "TextureFrameName"], health = _G[name .. "HealthBar"], mana = _G[name .. "ManaBar"],
        background = _G[name .. "Background"], dead = _G[name .. "TextureFrameDeadText"]}, TOT)
end

for _, tot in ipairs({TargetFrameToT, FocusFrameToT}) do
    totLayout(tot)
end
hooksecurefunc("FocusFrame_SetSmallSize", function()
    if not InCombatLockdown() then
        totLayout(FocusFrameToT)
    end
end)

local PET = {art = "UI-HUD-UnitFrame-TargetofTarget-PortraitOn", bar = "UI-HUD-UnitFrame-TargetofTarget-PortraitOn-Bar-",
    flashArt = "UI-HUD-UnitFrame-TargetofTarget-PortraitOn-InCombat", portraitX = 5, portraitY = -5,
    healthX = 44, healthY = -17}

local function petLayout()
    smallFrame(PetFrame, {texture = PetFrameTexture, flash = PetFrameFlash, portrait = PetPortrait, name = PetName,
        health = PetFrameHealthBar, mana = PetFrameManaBar, healthText = PetFrameHealthBarText,
        manaText = PetFrameManaBarText}, PET)
    atlas(PetAttackModeTexture, "UI-HUD-UnitFrame-TargetofTarget-PortraitOn-Status")
    at(PetAttackModeTexture, "TOPLEFT", 0, 1, PetFrame)
end
PetFrame:SetWidth(120)
PetFrame:SetHeight(49)
petLayout()
hooksecurefunc("PetFrame_Update", petLayout) -- it sets the frame texture (with or without mana)

local PARTY = {art = "UI-HUD-UnitFrame-Party-PortraitOn", bar = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-",
    flashArt = "UI-HUD-UnitFrame-Party-PortraitOn-InCombat", artPoint = "TOPLEFT", artX = 1, artY = -2,
    portraitX = 7, portraitY = -6, healthX = 45, healthY = -19, nameWidth = 57}

local function partyLayout(f)
    local name = f:GetName()
    smallFrame(f, {texture = _G[name .. "Texture"], flash = _G[name .. "Flash"], portrait = _G[name .. "Portrait"],
        name = _G[name .. "Name"], health = _G[name .. "HealthBar"], mana = _G[name .. "ManaBar"],
        background = _G[name .. "Background"], healthText = _G[name .. "HealthBarText"],
        manaText = _G[name .. "ManaBarText"]}, PARTY)
    atlas(_G[name .. "VehicleTexture"], "UI-HUD-UnitFrame-Party-PortraitOn-Vehicle")
    at(_G[name .. "VehicleTexture"], "TOPLEFT", 0, 0, f)
    -- The member's pet: retail's PartyMemberPetFrame, the party art at half size.
    local pet = name .. "PetFrame"
    for _, key in ipairs({"Texture", "Flash"}) do
        local t = _G[pet .. key]
        atlas(t, key == "Flash" and "UI-HUD-UnitFrame-Party-PortraitOn-InCombat" or "UI-HUD-UnitFrame-Party-PortraitOn")
        t:SetWidth(t:GetWidth() / 2)
        t:SetHeight(t:GetHeight() / 2)
        at(t, "TOPLEFT", 0, -1, _G[pet])
    end
    local bar = _G[pet .. "HealthBar"]
    bar:SetWidth(35.5)
    bar:SetHeight(5)
    at(bar, "TOPLEFT", 21.5, -9, _G[pet])
    Retail.AtlasBar(bar, "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Health")
end

for i = 1, MAX_PARTY_MEMBERS do
    local f = _G["PartyMemberFrame" .. i]
    f:SetWidth(120)
    partyLayout(f)
end
hooksecurefunc("PartyMemberFrame_ToPlayerArt", partyLayout)
hooksecurefunc("PartyMemberFrame_ToVehicleArt", partyLayout)

-- [[ Cast bars ]] --
-- Retail's: the atlas fill for each state (cast, channel, uninterruptible, interrupted), its frame, the
-- spell name in a text box under the bar, the pip and the shield. The client's colours tell the state.

local function castState(bar)
    local r, g = bar:GetStatusBarColor()
    local shield = bar.wotlkhdShield
    local kind = r > 0.9 and g < 0.2 and "Interrupted" or shield and shield:IsShown() and "Uninterruptable"
        or bar.channeling and "Filling-Channel" or "Filling-Standard"
    Retail.AtlasBar(bar, "UI-CastingBar-" .. kind)
end

local function castBar(bar, w, h)
    local name = bar:GetName()
    bar:SetWidth(w)
    bar:SetHeight(h)
    _G[name .. "Border"]:SetTexture(nil)
    _G[name .. "Flash"]:SetTexture(nil)
    local spark = _G[name .. "Spark"]
    spark:SetAtlas("UI-CastingBar-Pip")
    spark:SetWidth(6)
    spark:SetHeight(h + 8)
    local shield = _G[name .. "BorderShield"]
    if shield then
        shield:SetAtlas("UI-CastingBar-Shield")
        shield:SetWidth(29)
        shield:SetHeight(33)
        at(shield, "TOPLEFT", -27, 4, bar)
        bar.wotlkhdShield = shield
    end
    local icon = _G[name .. "Icon"]
    icon:SetWidth(16)
    icon:SetHeight(16)
    at(icon, "RIGHT", -5, 0, bar, "LEFT")
    local text = _G[name .. "Text"]
    text:SetFontObject("GameFontHighlightSmall")
    text:SetWidth(w - 20)
    text:SetHeight(16)
    at(text, "TOP", 0, -h + 1, bar)
    if not bar.wotlkhdFrame then
        local box = bar:CreateTexture(nil, "BACKGROUND")
        box:SetAtlas("UI-CastingBar-TextBox")
        box:SetPoint("TOPLEFT")
        box:SetPoint("BOTTOMRIGHT", 0, -12)
        local bg = bar:CreateTexture(nil, "BORDER")
        bg:SetAtlas("UI-CastingBar-Background")
        bg:SetPoint("TOPLEFT", -1, 1)
        bg:SetPoint("BOTTOMRIGHT", 1, -1)
        bar.wotlkhdFrame = bar:CreateTexture(nil, "OVERLAY")
        bar.wotlkhdFrame:SetAtlas("UI-CastingBar-Frame")
        bar.wotlkhdFrame:SetPoint("TOPLEFT", -2, 2)
        bar.wotlkhdFrame:SetPoint("BOTTOMRIGHT", 2, -2)
        bar:HookScript("OnEvent", castState)
        bar:HookScript("OnShow", castState)
    end
    castState(bar)
end

castBar(CastingBarFrame, 208, 11)
for _, name in ipairs({"TargetFrameSpellBar", "FocusFrameSpellBar"}) do
    if _G[name] then
        castBar(_G[name], 150, 10)
    end
end
hooksecurefunc("SetTargetSpellbarAspect", function(self) -- the small focus frame's resets its art
    if self.wotlkhdFrame then
        castBar(self, 150, 10)
    end
end)
