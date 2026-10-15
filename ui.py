"""Retail UI art for the WotlkHD addon: the atlas textures ATLASES use, as DXT5 BLPs in
addon/WotlkHD/Art/, and their coordinates in addon/WotlkHD/Atlas.lua (WotlkHD_Atlas, read by the
addon's SetAtlas).

usage: ui.py

Retail looks an atlas up by its element name (UiTextureAtlasElement); an element has a member per
resolution (UiTextureAtlasMember), and a "-2x" member is drawn at half its pixel size. We take the
largest member and the smallest drawn size. Names starting "_" tile horizontally and "!"
vertically (member flags 4 and 2); the addon repeats those itself.
"""
import csv
import os

import blp
import fetch

ROOT = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.join(ROOT, "addon", "WotlkHD")
ART = "Interface\\\\AddOns\\\\WotlkHD\\\\Art\\\\"

ATLASES = """
Options_InnerFrame Options_CategoryHeader_1 Options_List_Active Options_List_Hover Options_HorizontalDivider
Options_Tab_Left Options_Tab_Middle Options_Tab_Right
Options_Tab_Active_Left Options_Tab_Active_Middle Options_Tab_Active_Right
UI-Frame-Metal-CornerTopLeft UI-Frame-Metal-CornerTopRight UI-Frame-Metal-CornerBottomLeft
UI-Frame-Metal-CornerBottomRight _UI-Frame-Metal-EdgeTop _UI-Frame-Metal-EdgeBottom
!UI-Frame-Metal-EdgeLeft !UI-Frame-Metal-EdgeRight
uiframebackground-nineslice-cornerbottomleft uiframebackground-nineslice-cornerbottomright
RedButton-Exit RedButton-exit-pressed RedButton-Highlight RedButton-Exit-Disabled
checkbox-minimal checkmark-minimal checkmark-minimal-disabled
Minimal_SliderBar_Left _Minimal_SliderBar_Middle Minimal_SliderBar_Right Minimal_SliderBar_Button
common-dropdown-b-button common-dropdown-b-button-hover common-dropdown-b-button-pressed
common-dropdown-b-button-open common-dropdown-bg
nameplates-bar-fill nameplates-icon-elite-gold nameplates-icon-elite-silver nameplates-InterruptShield
UI-CastingBar-Background UI-CastingBar-Filling-Standard UI-CastingBar-Filling-Channel UI-CastingBar-Uninterruptable UI-CastingBar-Pip
RaidFrame-Hp-Fill RaidFrame-Hp-Bg RaidFrame-TargetFrame RaidFrame-AgroFrame RaidFrame-DispelHighlight
RaidFrame-Icon-DebuffMagic RaidFrame-Icon-DebuffCurse RaidFrame-Icon-DebuffDisease RaidFrame-Icon-DebuffPoison
roleicon-tiny-tank roleicon-tiny-healer roleicon-tiny-dps
editmode-actionbar-highlight-nineslice-corner _editmode-actionbar-highlight-nineslice-edgetop
!editmode-actionbar-highlight-nineslice-edgeleft editmode-actionbar-highlight-nineslice-center
editmode-actionbar-selected-nineslice-corner _editmode-actionbar-selected-nineslice-edgetop
!editmode-actionbar-selected-nineslice-edgeleft editmode-actionbar-selected-nineslice-center
UI-HUD-UnitFrame-Player-PortraitOn UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana
UI-HUD-UnitFrame-Player-PortraitOn-Bar-Rage UI-HUD-UnitFrame-Player-PortraitOn-Bar-Energy
UI-HUD-UnitFrame-Player-PortraitOn-Bar-Focus UI-HUD-UnitFrame-Player-PortraitOn-Bar-RunicPower
UI-HUD-UnitFrame-Player-PortraitOn-InCombat UI-HUD-UnitFrame-Player-PortraitOn-Status
UI-HUD-UnitFrame-Player-PortraitOn-CornerEmbellishment UI-HUD-UnitFrame-Player-CombatIcon
UI-HUD-UnitFrame-Player-Group-LeaderIcon UI-HUD-UnitFrame-Player-PortraitOn-Vehicle
UI-HUD-UnitFrame-Target-PortraitOn UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health UI-HUD-UnitFrame-Target-PortraitOn-Bar-Mana
UI-HUD-UnitFrame-Target-PortraitOn-Bar-Rage UI-HUD-UnitFrame-Target-PortraitOn-Bar-Energy
UI-HUD-UnitFrame-Target-PortraitOn-Bar-Focus UI-HUD-UnitFrame-Target-PortraitOn-Bar-RunicPower
UI-HUD-UnitFrame-Target-PortraitOn-Type UI-HUD-UnitFrame-Target-PortraitOn-InCombat
UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold-Winged
UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Star
UI-HUD-UnitFrame-Target-HighLevelTarget_Icon
UI-HUD-UnitFrame-Player-PVP-AllianceIcon UI-HUD-UnitFrame-Player-PVP-HordeIcon UI-HUD-UnitFrame-Player-PVP-FFAIcon
ui-hud-unitframe-target-portraiton-boss-rare-silver UI-HUD-UnitFrame-Target-Rare-PortraitOn
UI-HUD-UnitFrame-TargetofTarget-PortraitOn UI-HUD-UnitFrame-TargetofTarget-PortraitOn-Bar-Health
UI-HUD-UnitFrame-TargetofTarget-PortraitOn-Bar-Mana
UI-HUD-UnitFrame-TargetofTarget-PortraitOn-Bar-Rage UI-HUD-UnitFrame-TargetofTarget-PortraitOn-Bar-Energy
UI-HUD-UnitFrame-TargetofTarget-PortraitOn-Bar-Focus UI-HUD-UnitFrame-TargetofTarget-PortraitOn-Bar-RunicPower
UI-HUD-UnitFrame-TargetofTarget-PortraitOn-InCombat UI-HUD-UnitFrame-TargetofTarget-PortraitOn-Status
UI-HUD-UnitFrame-Party-PortraitOn UI-HUD-UnitFrame-Party-PortraitOn-Bar-Health UI-HUD-UnitFrame-Party-PortraitOn-Bar-Mana
UI-HUD-UnitFrame-Party-PortraitOn-Bar-Rage UI-HUD-UnitFrame-Party-PortraitOn-Bar-Energy
UI-HUD-UnitFrame-Party-PortraitOn-Bar-Focus UI-HUD-UnitFrame-Party-PortraitOn-Bar-RunicPower
UI-HUD-UnitFrame-Party-PortraitOn-InCombat UI-HUD-UnitFrame-Party-PortraitOn-Vehicle
UI-CastingBar-Frame UI-CastingBar-TextBox UI-CastingBar-Shield UI-CastingBar-Interrupted
UI-Frame-PortraitMetal-CornerTopLeft bags-item-slot64 common-search-border-left common-search-border-middle
common-search-border-right common-search-magnifyingglass common-search-clearbutton
UI-HUD-ActionBar-IconFrame UI-HUD-ActionBar-IconFrame-Down UI-HUD-ActionBar-IconFrame-Mouseover
ui-hud-actionbar-iconframe-slot UI-HUD-ActionBar-IconFrame-Border UI-HUD-ActionBar-IconFrame-Flash
UI-HUD-ActionBar-Gryphon-Left UI-HUD-ActionBar-Gryphon-Right UI-HUD-ActionBar-Wyvern-Left UI-HUD-ActionBar-Wyvern-Right
UI-HUD-ActionBar-PageUpArrow-Up UI-HUD-ActionBar-PageUpArrow-Down UI-HUD-ActionBar-PageUpArrow-Mouseover
UI-HUD-ActionBar-PageUpArrow-Disabled UI-HUD-ActionBar-PageDownArrow-Up UI-HUD-ActionBar-PageDownArrow-Down
UI-HUD-ActionBar-PageDownArrow-Mouseover UI-HUD-ActionBar-PageDownArrow-Disabled


UI-HUD-MicroMenu-ButtonBG-Up UI-HUD-MicroMenu-ButtonBG-Down UI-HUD-MicroMenu-SpellbookAbilities-Up UI-HUD-MicroMenu-SpellbookAbilities-Down
UI-HUD-MicroMenu-SpellbookAbilities-Mouseover UI-HUD-MicroMenu-SpellbookAbilities-Disabled
UI-HUD-MicroMenu-SpecTalents-Up UI-HUD-MicroMenu-SpecTalents-Down
UI-HUD-MicroMenu-SpecTalents-Mouseover UI-HUD-MicroMenu-SpecTalents-Disabled
UI-HUD-MicroMenu-Achievements-Up UI-HUD-MicroMenu-Achievements-Down
UI-HUD-MicroMenu-Achievements-Mouseover UI-HUD-MicroMenu-Achievements-Disabled
UI-HUD-MicroMenu-Questlog-Up UI-HUD-MicroMenu-Questlog-Down UI-HUD-MicroMenu-Questlog-Mouseover
UI-HUD-MicroMenu-Questlog-Disabled UI-HUD-MicroMenu-GuildCommunities-Up
UI-HUD-MicroMenu-GuildCommunities-Down UI-HUD-MicroMenu-GuildCommunities-Mouseover
UI-HUD-MicroMenu-GuildCommunities-Disabled UI-HUD-MicroMenu-Groupfinder-Up
UI-HUD-MicroMenu-Groupfinder-Down UI-HUD-MicroMenu-Groupfinder-Mouseover
UI-HUD-MicroMenu-Groupfinder-Disabled UI-HUD-MicroMenu-GameMenu-Up UI-HUD-MicroMenu-GameMenu-Down
UI-HUD-MicroMenu-GameMenu-Mouseover UI-HUD-MicroMenu-GameMenu-Disabled bag-main bag-main-highlight
bag-border bag-border-highlight bag-border-empty


""".split()


# Whole retail textures (not atlas parts), by path: copied as they are, under their file name.
FILES = """
Interface/Common/WhiteIconFrame.blp
""".split()


def main():
    elements = {r["Name"].lower(): r["ID"] for r in csv.DictReader(open(fetch.table("UiTextureAtlasElement")))}
    members = {}
    for r in csv.DictReader(open(fetch.table("UiTextureAtlasMember"))):
        members.setdefault(r["UiTextureAtlasElementID"], []).append(r)
    atlases = {r["ID"]: r for r in csv.DictReader(open(fetch.table("UiTextureAtlas")))}

    os.makedirs(os.path.join(ADDON, "Art"), exist_ok=True)
    written, lines = set(), []
    for name in ATLASES:
        rows = members.get(elements.get(name.lower()))
        if not rows:
            raise SystemExit(f"no atlas {name}")
        scale = [2 if r["CommittedName"].lower().endswith("-2x") else 1 for r in rows]
        best = max(range(len(rows)), key=lambda i: int(rows[i]["Width"]))
        m, atlas = rows[best], atlases[rows[best]["UiTextureAtlasID"]]
        w = min(int(r["OverrideWidth"]) or int(r["Width"]) // s for r, s in zip(rows, scale))
        h = min(int(r["OverrideHeight"]) or int(r["Height"]) // s for r, s in zip(rows, scale))
        file = os.path.splitext(os.path.basename(fetch.name(int(atlas["FileDataID"]))))[0]
        if file not in written:
            im = blp.decode(fetch.get(int(atlas["FileDataID"])))
            open(os.path.join(ADDON, "Art", file + ".blp"), "wb").write(blp.encode_dxt5(im))
            written.add(file)
        aw, ah = int(atlas["AtlasWidth"]), int(atlas["AtlasHeight"])
        coords = (int(m["CommittedLeft"]) / aw, int(m["CommittedRight"]) / aw,
                  int(m["CommittedTop"]) / ah, int(m["CommittedBottom"]) / ah)
        flags = int(m["CommittedFlags"])
        lines.append(f'    ["{name.lower()}"] = {{"{ART}{file}", {w}, {h}, '
                     + ", ".join(f"{c:.6g}" for c in coords) + f", {str(bool(flags & 4)).lower()}, "
                     f"{str(bool(flags & 2)).lower()}}},")
    for path in FILES:
        im = blp.decode(fetch.get(fetch.fdid(path)))
        open(os.path.join(ADDON, "Art", os.path.basename(path).lower()), "wb").write(blp.encode_dxt5(im))
    # A clear texture, for hiding a StatusBar's own fill (retail's bar fills are atlas parts, which the
    # addon draws itself).
    from PIL import Image
    open(os.path.join(ADDON, "Art", "clear.blp"), "wb").write(blp.encode_dxt5(Image.new("RGBA", (8, 8))))
    with open(os.path.join(ADDON, "Atlas.lua"), "w") as f:
        f.write("-- Generated by ui.py: retail atlas name -> {file, width, height, left, right, top, bottom,\n"
                "-- tiles horizontally, tiles vertically}.\nWotlkHD_Atlas = {\n" + "\n".join(lines) + "\n}\n")
    print(f"{len(lines)} atlases in {len(written)} textures")


if __name__ == "__main__":
    main()
