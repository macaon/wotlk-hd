-- wotlk-hd: retail's player, target and focus frames (Dragonflight's UI-HUD-UnitFrame art and layout, from
-- Blizzard_UnitFrame's PlayerFrame.xml and TargetFrame.xml). The client's frames stay, with their
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
hooksecurefunc("TargetFrame_CheckLevel", function(self) -- the client's level colour on retail's art
    if self.wotlkhdBoss then
        at(self.highLevelTexture, "TOPLEFT", 4, 2, self.levelText)
    end
end)
