# Translations

The guide is in English. If you'd like it in your language, I'd welcome a translation.

1. Copy `phrases.txt` to `<locale>.lua` here (`deDE.lua`, `frFR.lua`, `zhCN.lua` and so on) and change `"deDE"` near the top to your locale.
2. Translate the text on the right of each line. Keep every `%d` and `%s`, and delete any line you leave in English.
3. Add `Locales\<locale>.lua` to `AdventureGuideForever.toc`, on the line after `Locales\enUS.lua`.

Send it as a pull request, or paste the file into an issue and I'll add it. Some quest, NPC and town names come from the bundled quest data rather than the game, so those stay in English.
