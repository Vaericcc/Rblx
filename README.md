# StoryDub

A Roblox party game where you **write a story, draw it, and your friends dub it**.
Every round, each player owns one storyboard. Depending on the mode, the premise,
the cast, the drawings and the dialogue are written by you, or get swapped around
the table so your friends finish what you started. Then everyone watches every
story back while the dubbers perform their lines over voice chat, and hands out awards.

## Modes

| Mode | Flow | Who dubs |
|------|------|----------|
| **CLASSIC** | Premise → Cast → Draw 1 panel | The next player |
| **COMIC** | Premise → Cast → Draw 4 panels | The next player |
| **STORY SWAP** | Premise → Cast → *swap* → Draw 3 panels | A third player |
| **SCRIPT SWAP** | Cast → Script → *swap* → Draw to their script | The writer performs their own script |
| **BLIND DUB** *(new)* | Premise → Cast → Draw 3 panels | The next player, who **only sees the pictures**. The real premise is revealed after the dub. |
| **BROKEN TELEPHONE** *(new)* | Premise → Draw → Describe → Draw → Describe | Nobody; the showcase plays the whole mutation chain |

The two added modes are built around the dubbing hook. Blind Dub is the one that
produces the funniest showcases, because the dubber's invented story is played first
and the artist's real premise lands as the punchline. Broken Telephone is a proven
party format that fits the same draw/describe engine with zero extra systems.

Modes are **pure data** in `src/shared/Modes.lua`. A mode is an ordered list of phases,
and each phase has an `offset`: 0 means you work on your own story, 1 means the story of
the player to your left, and so on. That single number is what turns a normal mode into
a swap mode, so new variants are a few lines, no new code.

## Round flow

1. **Lobby.** Players vote on a mode. Modes that need more players than are present are locked.
2. **Phases.** The server runs the mode's phases in order, assigning each project to a worker
   and sending them only what they should see. Timers are synchronized with server time.
   Players can submit early and keep editing; the server applies the latest submission when
   the timer ends.
3. **Showcase.** Every story plays back in sync for everyone: title card, then each panel
   with speech bubbles appearing one by one. In live-dub modes the dubber is called up
   on screen so they can voice their lines over Roblox voice chat.
4. **Vote.** Four awards: Funniest, Best Art, Best Dub, Plot Twist. You can't pick your own story.
5. **Results.** Award winners and a leaderboard. Points go to everyone who contributed to a
   winning story (Best Dub goes to the dubber alone).

## Project layout

```
default.project.json         Rojo tree (Workspace floor, Shared, Server, Client)
src/shared/
  Config.lua                 Timers, limits, scoring
  Modes.lua                  Mode definitions (data only)
  Net.lua                    Single RemoteEvent + action names
  Strokes.lua                Stroke format + server-side sanitizer
  Text.lua                   Text trimming/length limits
src/server/
  Main.server.lua            Lobby → vote → round loop
  Round.lua                  Phase runner, assignment, showcase, voting, scoring
  Projects.lua               Storyboard state and all untrusted-input handling
  Filter.lua                 TextService filtering for every player-written string
src/client/
  Main.client.lua            Router: mounts screens from server actions, auto-submits
  UI/Canvas.lua              Normalized-coordinate drawing surface (draw + playback)
  UI/Hud.lua                 Phase title, instructions, countdown, submit button
  UI/Make.lua, Theme.lua     Declarative UI builder and palette
  UI/StoryInfo.lua           Premise/cast/script side panel
  Screens/                   Lobby, TextPhases (premise/cast/script/caption), Draw, Dub,
                             Showcase, Vote, Results
```

## Building

Requires [Rojo](https://rojo.space) 7. With [Rokit](https://github.com/rojo-rbx/rokit):

```sh
rokit install
rojo build -o StoryDub.rbxl      # build a place file
# or, in Studio with the Rojo plugin:
rojo serve
```

Open the place in Roblox Studio, enable **Voice Chat** in Game Settings → Communication
(needed for live dubbing; everything else works without it), and run a local server with
2 or more players (Test → Clients and Servers) to try a round.

## Safety notes

- Every string a player writes is passed through `TextService:FilterStringAsync` before it
  is shown to anyone. If filtering fails, the text is replaced, never leaked.
- Drawings are validated server-side: stroke and point counts are capped, coordinates are
  clamped to the canvas, colors and widths are clamped to safe ranges.
- Clients only ever receive the parts of a story they are supposed to see (telephone
  drawers get just the latest caption; blind dubbers get no premise or cast).

## Tuning

Everything time- or limit-related lives in `src/shared/Config.lua`. Phase durations and
panel counts live on each mode in `src/shared/Modes.lua`.
