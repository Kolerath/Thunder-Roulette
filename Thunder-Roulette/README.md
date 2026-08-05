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
a valid War Thunder BR stage (`.0`, `.3`, or `.7`) inside that range. BR stages
use a persistent shuffled sequence and do not repeat until the range is exhausted.

The built-in challenge deck contains structured objectives and rewards. Challenges
do not repeat until that profile has exhausted its own deck.

The separate fun-mode deck draws lineup and playstyle constraints, such as light
tanks only, derp guns, aggressive SPAA, or a same-vehicle squad. It also uses an
independent no-repeat deck for every profile.

Use **ROLL SESSION** to draw a nation, battle rating, challenge, and fun mode in
one click. Every category can still be rerolled individually afterward.
The Manage window's **Roll Session** tab controls which modules that button rolls
for each profile.
The BR result can be cleared from the profile settings in Manage without changing
the configured range.

After drawing a challenge, use **START SESSION** to open its live tracker.
Challenges can use **Detailed trackers**, which generate counters and checkboxes,
or **Simple success / failed**, which records only the chosen outcome. **Success**
captures the attempt note, applies the configured BR or weapon-stage reward, and
resets the tracker for the next round. **Failed** applies the challenge's configured
punishment: stay at the current stage, drop one BR stage, or drop one weapon stage.
Drops clamp safely at the lowest valid stage. **End session** writes the complete
run to the selected profile's history. Detailed history preserves each attempt's
actual counter values, including totals above the target, plus notes and BR or
weapon-stage movement.

Use **Manage** to create, rename, or delete profiles and configure their BR range
and exit behavior. Selecting a profile on the main screen immediately switches
to that person's saved sequence. The final remaining profile cannot be deleted.
Deleted profile data is retained under `Data/DeletedProfiles` in case it needs to
be recovered manually.

Manage also provides persistent editors for the Challenge and Fun Mode libraries.
Cards can be added, edited, or deleted; either library can be restored to its
shipped defaults. Resetting a deck only clears the selected profile's draw order
and does not alter the card library.

The Progression tab provides editable Air, Ground, and Naval campaigns with
separate Gun, Rocket, and Missile tracks. Exact diameters and user-defined ranges
can be added, reordered, enabled, disabled, or restored from the shipped catalog.

For illustrated instructions, open `Thunder-Roulette-v1.4-User-Guide.pdf`.

## Launch the packaged app

Double-click `Thunder-Roulette.exe`.

The executable is not digitally signed, so Windows may display an
unknown-publisher or Microsoft Defender SmartScreen warning on first launch.

## Run from source

If you downloaded the source code instead of a packaged release, double-click
`Start-Thunder-Roulette.cmd`, or run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\Thunder-Roulette.ps1
```

All paths are based on the app folder, so the entire `Thunder-Roulette` directory can
be moved anywhere. Runtime state is created in `Data` on first launch.
