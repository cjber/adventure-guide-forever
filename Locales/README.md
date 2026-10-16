# Translations

The guide is written in English, and every line it shows goes through `ns.L`, so a line nobody has translated just
stays English.

It ships in every language the WoW: Forever client has besides English: deDE, esES, esMX, frFR, koKR, ptBR, ruRU, zhCN
and zhTW (the client has no Italian). Those files are machine translated, using the game's own words for the quest
log, quest givers, flight paths, the objective tracker and the rest, and say so on their first line. A human line
always wins over a machine one.

To correct a line, change the text on the right in `<locale>.lua`. In a file that is all machine translated, the first
correction makes it mixed: every line you didn't touch then ends `-- mt`, so a later machine pass only ever replaces
marked lines. Keep every `%d` and `%s`, in the same order. Then open a pull request, or paste the lines into the
[translation form](https://github.com/cjber/adventure-guide-forever/issues/new?template=translation.yml) and I'll add
them. Some NPC and town names come from the guide's bundled route data rather than the game, so those stay in English.

New lines land in `phrases.txt` (`python3 tools/phrases.py > Locales/phrases.txt`), the template with every line's key
and its English text. `python3 tools/check_locales.py` checks each file against it and prints each language's coverage.
