"""Exercise Lua's expansion rules, including lexical lookalikes and nesting."""

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from lint_multivalue import LuaSyntaxError, check


class MultiValueTests(unittest.TestCase):
    def test_expanding_positions(self):
        cases = [
            "f(select(2, UnitClass(u)))",
            "f((select)(2, UnitClass(u)))",
            "return ((select))(2, g())",
            "f(x, select(2, g()))",
            "obj:method(select(1, ...))",
            "return select(2, g())",
            "return first, select(2, g());",
            "local t = {select(2, g())}",
            "local t = {first, select(2, g()),}",
            "local t = {first; select(2, g());}",
            "f(\n select(2, g())\n)",
            "local function f(...) return select(1, ...) end",
            "local f = function(...) return select(1, ...) end",
            "if x then return select(1, g()) elseif y then f(select(1, g())) end",
            "repeat f(select(1, g())) until done",
            "for k, v in pairs(t) do f(select(1, g())) end",
            "for i = 1, 3 do f(select(1, g())) end",
            "while ready do f(select(1, g())) end",
            "do f(select(1, g())) end",
            "f(g(select(2, h())), x)",
        ]
        for source in cases:
            with self.subTest(source=source):
                self.assertTrue(check(source))

    def test_scalar_positions(self):
        cases = [
            "f((select(2, UnitClass(u))))",
            "f(((select)(2, UnitClass(u))))",
            "local x = select(2, g()); f(x)",
            "f(select(2, g()), x)",
            "return (select(2, g()))",
            "return select(2, g()), x",
            "local t = {(select(2, g()))}",
            "local t = {select(2, g()), x}",
            "local t = {key = select(2, g())}",
            "local t = {[select(2, g())] = select(2, h())}",
            "local t = {select(2, g()), key = x}",
            "f(select(2, g()) + 1)",
            "f(not select(2, g()))",
            "f(true and select(2, g()))",
            "f(select(2, g()).value)",
            "f(select(2, g())())",
            "f(object.select(2, g()))",
            "f(object:select(2, g()))",
        ]
        for source in cases:
            with self.subTest(source=source):
                self.assertEqual(check(source), [])

    def test_strings_and_comments(self):
        source = """
-- f(select(2, g()))
--[==[ return select(2, g()) ]==]
local a = "f(select(2, g())) \\\""
local b = 'return select(2, g())'
local c = [=[ {select(2, g())} ]=]
f --[[a comment]] ( (select --[[another]] (2, g())) )
f "select(2, g())"
f [==[select(2, g())]==]
"""
        self.assertEqual(check(source), [])
        self.assertEqual(check("--[=[\ncomment\n]=]\nf(select(1, g()))")[0][0], 4)

    def test_intentional_expansion(self):
        for source in [
            "f(select(2, ...)) -- multi-value: forward the remaining arguments",
            "return select(2, ...) -- multi-value: preserve the tail",
            "local t = {select(2, ...)} -- multi-value: collect the tail",
            "local t = {\nselect(2, ...), -- multi-value: collect the tail\n}",
            "f(select(2, ...) -- multi-value: forward the tail\n)",
        ]:
            with self.subTest(source=source):
                self.assertEqual(check(source), [])
        for comment in ["-- multi-value:", "-- unrelated", "--[[ multi-value: not a trailing line comment ]]"]:
            self.assertTrue(check("f(select(2, ...)) " + comment))
        self.assertTrue(check("-- multi-value: unrelated previous line\nf(select(2, ...))"))
        self.assertTrue(check('f(select(2, ...)); local s = "-- multi-value: only a string"'))

    def test_cli_status_and_locations(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "probe.lua"
            path.write_text("-- first line\nf(select(2, g()))\n")
            command = [sys.executable, str(Path(__file__).with_name("lint_multivalue.py")), str(path)]
            result = subprocess.run(command, capture_output=True, text=True, check=False)
            self.assertEqual(result.returncode, 1)
            self.assertIn(f"{path}:2: multi-value:", result.stdout)
            path.write_text("f((select(2, g())))\n")
            self.assertEqual(subprocess.run(command, capture_output=True, check=False).returncode, 0)

    def test_malformed_input_fails_closed(self):
        for source in ['f("unterminated)', "--[=[unclosed", "f(select(2, g())", "return )"]:
            with self.subTest(source=source):
                with self.assertRaises(LuaSyntaxError):
                    check(source)


if __name__ == "__main__":
    unittest.main()
