# Dubble Take: handoff brief for a bug-testing agent

Read this first. Everything below is current as of the latest commit on the branch named here.

## What this is

A Roblox voice-chat party game, Luau, built with Rojo. Players write a premise and cast, draw it on a
shared canvas, claim roles, and dub it live. Modes: Classic, Comic, Story Swap, Script Swap, VS Comic
(teams), Blind Dub, Broken Telephone. Points persist in a DataStore; a Hall of Fame board shows the
top 10 with the champion's avatar.

## Repository and branch

- GitHub: `Vaericcc/Rblx`
- Branch: `claude/lucid-bardeen-xi7ati` (this is the default and only branch; commit and push here)
- Local clone used by the owner: `C:\Users\armaa\Documents\Storydub`

## Connecting it to Roblox Studio

Tooling is pinned in `rokit.toml` (Rojo 7.7.0). The Rojo Studio plugin must be the same version
(`rojo plugin install` after `rokit install`).

```
cd C:\Users\armaa\Documents\Storydub
.\scripts\sync.ps1          # git pull + rojo serve on port 34872
.\scripts\sync.ps1 build    # pull + build DubbleTake.rbxl instead
```

Then in Studio: Plugins -> Rojo -> Connect. Press Play. The hub (map) is built by the server at
Play start, so map changes need a stop/start, not just a sync. Client UI changes hot-sync.

The project tree is `default.project.json`:

| Studio location | Folder |
|---|---|
| ReplicatedFirst | `src/first` (boot loading screen) |
| ReplicatedStorage/Shared | `src/shared` |
| ServerScriptService/Server | `src/server` |
| StarterPlayer/StarterPlayerScripts/Client | `src/client` |

Studio specifics: `Config.SOLO_TESTING` is true in Studio, so matches start with 1 player, voice chat
is not required, text filtering is bypassed, and matches run in sealed rooms 500 studs up instead of
teleporting (TeleportService does not work in Studio). To test DataStore points, enable
"Enable Studio Access to API Services" in Game Settings -> Security.

## Running the UI tour and capturing screenshots

The client has a tour (Studio only) that walks every screen with sample data: press F8 in the play
window or type `/tour` in chat. Each step prints `TOUR: <step>` to Output.

`scripts/capture.ps1` tails the Studio log, takes one screenshot of the Studio window per step and
writes a labelled contact sheet plus the Studio logs to `screenshots\<name>\`. Start it first, then
press F8:

```
.\scripts\capture.ps1 -Name run1
.\scripts\compare.ps1 -Before run1 -After run2   # side-by-side sheets
```

Use the Studio Device emulator (iPhone XR landscape and portrait) for phone layouts.

Studio logs live in `%LOCALAPPDATA%\Roblox\logs`. Script errors appear there as well as in Output.

## Code map

```
src/shared/Config.lua      tuning constants (players, timing, points, brush)
src/shared/Modes.lua       modes as data: phases with kind/offset/duration/count/panels/blind/roles
src/shared/Net.lua         one RemoteEvent; Net.S2C and Net.C2S action name tables
src/shared/Strokes.lua     stroke sanitizing and transform maths (shared by client and server)

src/server/Main.server.lua   entry: detects match server vs hub; routes C2S actions
src/server/Hub.lua           builds the courtyard map, lighting, spawns, removes template Baseplate
src/server/Pads.lua          the four pads that auto-form matches
src/server/Rooms.lua         rooms, visibility, teams, start (teleport or in-server), kick, leave
src/server/Round.lua         phase runner, assignments, live strokes, showcase, vote, results
src/server/Projects.lua      per-story data: premise, cast, roles, panels, lines, captions
src/server/MatchServer.lua   reserved-server side: gathers party, runs round, sends home
src/server/Points.lua        DataStore + OrderedDataStore
src/server/Leaderboard.lua   Hall of Fame board + champion avatar
src/server/Studios.lua       in-server match rooms (Studio fallback)
src/server/VoiceIsolation.lua, Filter.lua

src/client/Main.client.lua   router: lobby vs match, HUD, overlays, pause menu, keyboard avoidance, tour hotkey
src/client/UI/               Menu (Persona-style), AvatarStage, Canvas, ColorPicker, Hud, Make, Theme,
                             Responsive (compact/stacked/inset), Layout, Icons, Mic, Settings, ModeGrid
src/client/Screens/          Lobby, Draw, TextPhases, Claim, Dub, Wait, Showcase, Vote, Results, Tour
src/first/Boot.client.lua    first-frame loading screen
```

Conventions: every file is `--!strict`. Syntax-check with `luau-compile --binary <file>` if you have
Luau tools; otherwise watch Output. Stroke format and the RemoteEvent protocol are documented at the
top of `Strokes.lua` and `Net.lua`.

## Gotchas already learned (do not re-break these)

- UIStroke on text must use `ApplyStrokeMode.Border`; `Make()` sets this automatically.
- GUI input goes to the topmost object only; handles need their own InputBegan.
- Sparse numeric keys do not survive RemoteEvents; use string keys.
- Translucent strokes render inside a CanvasGroup to avoid dot patterns.
- A CanvasGroup's own UIStroke is not faded by GroupTransparency; tween it by hand.
- Workspace.Terrain is a BasePart; never Destroy() it.
- The Baseplate template's top is at y=0, the flagstone plane; the hub deletes it at build.
- The camera viewport is not ready on the first frame; `Responsive.waitUntilReady()`.
- Rojo leaves unknown Workspace children alone; stale instances in the place file persist.

## Known open items

- The owner wants the map to look much better (voxel-style rebuild to a Minecraft-like reference was
  proposed; not started).
- Lean pose on the join screen is hand-posed blind; needs tuning from screenshots (R6 and R15 paths).
- Icon asset IDs in `UI/Icons.lua` and two menu sound IDs in `UI/Theme.lua` are placeholders.
- Untested on a published place: reserved-server teleports, DataStore points, voice access lists.
- Portrait phone layout has had fewer eyes on it than landscape.

## What to test, in priority order

1. Fresh join: boot screen -> join screen with avatar -> hub with UI (top-left banner, MENU/PLAY).
2. Hub: floor clean (no white flicker), four pads with "STAND HERE TO PLAY", sign floating over the dais,
   Hall of Fame board on the north wall, spawn in a corner, no falling.
3. Stand on a pad: loading screen, then a full Classic round through to results and back to the hub.
4. UI rooms: create (Public / Friends / Pro), join, vote mode, teams on VS Comic, kick, leave.
5. Draw tools, including Transform handles, fill with outline, airbrush fade, opacity, lasso.
6. Menus open/close animations on desktop and phone; pause menu; settings sliders.
7. Phone (landscape and portrait): nothing off-screen, keyboard does not cover text boxes, check button.
8. Run the tour with capture and read the Studio log for red lines after every run.

Report each bug with: step to reproduce, what you expected, screenshot or sheet, and the red Output
lines. Keep fixes minimal and commit to the branch above with clear messages.
