#!/usr/bin/env python3
"""Report what the generated data adds, removes and changes since a git revision (default HEAD)."""

from check_generated import DATA, ROOT
from forever_tools import generated

if __name__ == "__main__":
    generated.data_report(ROOT, [name for name in DATA if name.endswith(".lua")])
