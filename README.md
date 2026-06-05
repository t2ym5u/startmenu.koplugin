# startmenu.koplugin

A startup menu plugin for [KOReader](https://github.com/koreader/koreader).

## Concept

Each time KOReader opens its file manager, a small dialog asks what you want to
do: go straight to reading, or jump directly into one of the installed game
plugins. One tap and you are there — no menu diving required.

## Features

- **Startup prompt** — appears automatically when the KOReader file manager loads
- **Read shortcut** — dismiss the dialog and stay in the file manager
- **Direct game launch** — tap any listed game to open it immediately
- **Configurable game list** — choose which games appear via the Tools menu
- **Enable / disable** — turn the automatic prompt off without uninstalling the plugin
- **Manual trigger** — re-open the menu at any time from Tools → Startup Menu

## Installation

1. Download `startmenu.koplugin.zip` from the [latest release](../../releases/latest).
2. Extract into the `plugins/` folder of your KOReader data directory
   (e.g. `/mnt/us/extensions/` on Kindle, `koreader/plugins/` on Kobo).
3. Restart KOReader.

The startup menu appears automatically on the next launch.

## Configuration

Open **Tools → Startup Menu** to adjust the following settings:

| Setting | Description |
|---------|-------------|
| Show startup menu now | Re-display the dialog immediately |
| Enable on startup | Toggle automatic display on / off |
| Individual game entries | Check or uncheck each game to show or hide it |

**Games enabled by default:** Sudoku, 2048, Minesweeper, Mastermind.

All other installed game plugins (Futoshiki, Hitori, Kakuro, KenKen, Nonogram,
NumberLink, Nurikabe) can be added from the same settings screen.

## Requirements

Each game that appears in the startup menu must be installed as its own plugin.
If a selected game plugin is missing or inactive, tapping its button shows a
brief notice rather than crashing.

## License

GPL-3.0
