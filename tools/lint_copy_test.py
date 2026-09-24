"""Both sides of the copy rule: what ns.L may say, and where a literal may be passed."""

import unittest

from lint_copy import literal_calls, strings_table, value_problems
from lint_multivalue import tokenize


def tokens(source: str):
    return tokenize(source)[0]


class ValueTests(unittest.TestCase):
    def test_format_strings_pass(self):
        for value in ["%d quests near your level", "Chapter %d of %d", "%s · %d min", "%.1f yards", "%-5s"]:
            self.assertEqual(value_problems(value), [], value)

    def test_banned(self):
        cases = {
            "50% done": "a literal percent sign",
            "100%% done": "a literal percent sign",
            "Ends in %": "a literal percent sign",
            "Gain XP": "banned word 'XP'",
            "The fast way": "banned word 'fast'",
            "Fastest route": "banned word 'Fastest'",
            "The optimal order": "banned word 'optimal'",
            "You must go": "banned word 'You must'",
            "?": '"?" as a value',
        }
        for value, problem in cases.items():
            self.assertIn(problem, value_problems(value), value)

    def test_words_are_whole(self):
        self.assertEqual(value_problems("Breakfast at Expo"), [])


class TableTests(unittest.TestCase):
    def test_entries(self):
        source = """
            ns.L = {
                A = "one %d",
                B = "joined " .. 'across lines',
                C = CLIENT_GLOBAL or "fallback",
                D = { nested = "x" },
            }
            ns.L.E = "outside"
        """
        entries = [(key, value) for _, key, value in strings_table(tokens(source))]
        self.assertEqual(entries, [("A", "one %d"), ("B", "joined across lines"), ("C", "fallback"), ("D", "x")])


class CallTests(unittest.TestCase):
    def test_flagged(self):
        for source in [
            'label:SetText("optional")',
            'label:SetText(("Steps: %d"):format(n))',
            'button:SetText(p and ns.L.GO or "Set waypoint")',
            'menu:CreateButton("More settings", function() end)',
            'block:AddObjective(1, "Turn in")',
            'GameTooltip_SetTitle(tooltip, "Title")',
            'GameTooltip_AddNormalLine(tooltip, ("[%d] %s"):format(level, title))',
        ]:
            self.assertEqual(len(literal_calls(tokens(source))), 1, source)

    def test_passed(self):
        for source in [
            "label:SetText(ns.L.OPTIONAL)",
            'label:SetText("")',
            'label:SetText(ns.L.STEP_COUNT:format(n)) -- SetText("comment")',
            'block:AddObjective("key", ns.L.NEXT:format(title))',
            'menu:CreateButton(ns.L.MORE, function() ns.Setting("showTracker") end)',
            "GameTooltip_Hide()",
            'print("SetText(\\"not a call\\")")',
        ]:
            self.assertEqual(literal_calls(tokens(source)), [], source)


if __name__ == "__main__":
    unittest.main()
