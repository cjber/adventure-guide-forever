"""Regression cases for the art lint: what it must flag, what stays clean, and the waiver comment."""

import unittest

from tools.lint_art import check


class ArtTest(unittest.TestCase):
    def test_flagged(self):
        cases = [
            'icon:SetAtlas("QuestNormal")\nicon:SetSize(14, 20)',
            "icon:SetTexture(file)",
            'button:SetNormalAtlas("RedButton-Expand")',
            'button:SetHighlightTexture("Interface\\\\Buttons\\\\UI-Common-MouseHilight")',
            'local mark = CreateAtlasMarkup("QuestNormal", 12, 20)',
            'local MARK = "|A:QuestNormal:12:20|a "',
            'return ("|T%d:14:20|t"):format(texture)',
        ]
        for source in cases:
            with self.subTest(source=source):
                findings = check(source)
                self.assertEqual(len(findings), 1, findings)
                self.assertTrue(findings[0][1].startswith("art-raw:"), findings)

    def test_clean(self):
        cases = [
            'Art.Fit(icon, "QuestNormal", 14, 14)',
            "Art.Icon(icon, file, 14)",
            'icon:SetAtlas("questlog-icon-setting", true)',
            "fill:SetColorTexture(0, 0, 0, 1)",
            "art:SetAtlas(CARD_ART) -- art-ok: nine-slice, margins set below",
            "-- art-ok: a square map tile, sized square below\ntexture:SetTexture(tile)",
            '-- icon:SetAtlas("QuestNormal") was here',
            'local text = "A|cffffffffB|r"',
        ]
        for source in cases:
            with self.subTest(source=source):
                self.assertEqual(check(source), [])

    def test_waiver_must_earn_its_place(self):
        self.assertTrue(check("local x = 1 -- art-ok: nothing here")[0][1].startswith("art-unused:"))
        findings = check('icon:SetAtlas("QuestNormal") -- art-ok:')
        self.assertEqual([message.split(":")[0] for _, message in findings], ["art-raw", "art-unused"])

    def test_xml(self):
        flagged = '<Texture parentKey="Icon" atlas="QuestNormal" setAllPoints="true"/>'
        self.assertEqual(len(check(flagged, xml=True)), 1)
        self.assertEqual(check('<Texture atlas="QuestNormal" useAtlasSize="true"/>', xml=True), [])
        self.assertEqual(check("<!-- art-ok: a square atlas on a square pin -->\n" + flagged, xml=True), [])
        self.assertEqual(check('<Texture parentKey="Fill"><Color r="0" g="0" b="0"/></Texture>', xml=True), [])


if __name__ == "__main__":
    unittest.main()
