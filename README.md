# Thunder Roulette

Thunder Roulette is a portable PowerShell/WPF session director for game nights
with War Thunder. It can roll nations and battle ratings, draw challenges and
fun-mode constraints, and preserve independent decks and settings for multiple
player profiles.

## Features

- No-repeat nation, challenge, and fun-mode decks
- Per-profile battle-rating ranges and saved state
- Profile creation, renaming, archival deletion, and deck management
- Persistent editors for custom challenges and fun modes
- Original nation-emblem set and application background
- Portable PowerShell/WPF interface with no external runtime dependencies beyond
  Windows PowerShell

## Run from source

Double-click `Thunder-Roulette/Start-Thunder-Roulette.cmd`, or run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\Thunder-Roulette\Thunder-Roulette.ps1
```

Runtime profiles and edited content are created under `Thunder-Roulette/Data`
and are intentionally excluded from version control.

## Disclaimer

Thunder Roulette is an unofficial fan-made tool. It is not affiliated with,
endorsed by, or sponsored by Gaijin Entertainment. War Thunder is a trademark of
its respective owner.

The application artwork is original AI-assisted imagery created specifically for
this project and does not contain extracted game assets.
