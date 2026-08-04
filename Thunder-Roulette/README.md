# Thunder Roulette

A portable PowerShell/WPF War Thunder session director for nations, battle
ratings, challenges, and fun modes.

The nation emblems are an original AI-assisted embroidered patch set created for
Thunder Roulette. App-ready transparent copies live under `Assets/NationIcons`.
The abstract navy-and-gold application background is also an original AI-assisted
asset created specifically for this project.

Each sequence contains every nation exactly once in a shuffled order. Every
player profile has its own queue and **Clear sequence on exit** preference, and
the app remembers the last selected profile.

Each profile also stores a minimum and maximum battle rating. **Roll BR** chooses
a valid War Thunder BR stage (`.0`, `.3`, or `.7`) inside that range.

The built-in challenge deck contains structured objectives and rewards. Challenges
do not repeat until that profile has exhausted its own deck.

The separate fun-mode deck draws lineup and playstyle constraints, such as light
tanks only, derp guns, aggressive SPAA, or a same-vehicle squad. It also uses an
independent no-repeat deck for every profile.

Use **Manage** to create, rename, or delete profiles and configure their BR range
and exit behavior. Selecting a profile on the main screen immediately switches
to that person's saved sequence. The final remaining profile cannot be deleted.
Deleted profile data is retained under `Data/DeletedProfiles` in case it needs to
be recovered manually.

Manage also provides persistent editors for the Challenge and Fun Mode libraries.
Cards can be added, edited, or deleted; either library can be restored to its
shipped defaults. Resetting a deck only clears the selected profile's draw order
and does not alter the card library.

## Run it

Double-click `Start-Thunder-Roulette.cmd`, or run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\Thunder-Roulette.ps1
```

All paths are based on the app folder, so the entire `Thunder-Roulette` directory can
be moved anywhere. Runtime state is created in `Data` on first launch.
