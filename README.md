# StoryDub

A Roblox party game where you **write a story, draw it, and your friends dub it**.
Every round, each player owns one storyboard. Depending on the mode, the premise,
the cast, the drawings and the dialogue are written by you, or get swapped around
the table so your friends finish what you started. Then everyone watches every
story back while the dubbers perform their lines over voice chat, and hands out awards.

## Modes

| Mode | Flow | Who dubs |
|------|------|----------|
| **CLASSIC** | Premise → Cast → Claim roles → Draw 1 panel → Write lines | Whoever claimed each character |
| **COMIC** | Premise → Cast → Claim roles → Draw 4 panels → Write lines | Whoever claimed each character |
| **STORY SWAP** | Premise → Cast → Claim roles → *swap* → Draw 3 panels → Write lines | Whoever claimed each character |
| **SCRIPT SWAP** | Cast → Claim roles → Script → *swap* → Draw to their script | Whoever claimed each character performs the writer's lines |
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

## Lobby and matchmaking

The lobby is a walkable 3D hub. There are two ways into a match, and many matches run at once:

- **Matchmaking UI.** Press **Play**. Create a room as **Public** or **Friends Only** (only the
  host's Roblox friends can see or join it), or join an open room from the list. Members vote on
  a mode; the host starts. Host migrates if the host leaves.
- **Platforms.** Walk onto one of the glowing pads. When enough players are standing on it a
  countdown starts, shown on the billboard above the pad and in a banner on screen where you
  can vote for a mode. Step off to leave.

When a match starts, its players are teleported into a private studio far from the hub, so
proximity voice chat only carries their own group. They return to the hub when it ends.

## Cross-platform

Phone, tablet and PC share one UI. Screens narrower than about 820px switch to a stacked layout
with the drawing canvas on top and everything else scrolling below. Touch drawing is supported,
tap targets grow on touch devices, and during a match the thumbstick, jump button and character
movement are disabled so nothing gets in the way. See `docs/DESIGN.md` for the full rules.

## Round flow

1. **Match forms** from a room or a platform (see above).
2. **Phases.** The server runs the mode's phases in order, assigning each project to a worker
   and sending them only what they should see. Timers are synchronized with server time.
   Players can submit early and keep editing; the server applies the latest submission when
   the timer ends.
3. **Showcase.** Every story plays back in sync for everyone, one line at a time. When a
   line comes up, its voice actor gets an on-air panel with a mic toggle, a level meter and
   a Next Line button, and everyone else sees who is speaking. Lines auto-advance after a
   few seconds if the actor doesn't press Next.

## Skipping and removing

- **Skip story.** During the showcase anyone can press Skip this story. Once more than half
  the group has voted, the showcase jumps to the next story.
- **Remove player.** The host of a room can remove a player from the room view in the lobby,
  or from the players menu (👥) during a match. Removed players are sent back to the hub and
  can't rejoin that room. Platform matches have no host, so there is no kick there.

## Roles and live dubbing

Right after the cast is written, everyone claims the characters they want to voice (up to
two per story, never your own story). Unclaimed roles are handed out automatically. During
the dub phase you write lines only for your characters, and in the showcase you perform them.

StoryDub is a **voice chat game**. Roblox does not allow experiences to record the microphone,
so dubbing is always live over Roblox voice chat, and players without voice chat enabled
cannot create or join rooms or form a platform match (the lobby tells them why). Enable
Voice Chat in Game Settings → Communication. Speech bubbles stay on screen as subtitles.
Studio solo testing is exempt from the voice requirement because voice doesn't run there.

Every player draws in every mode: each player owns one story and every draw phase assigns
exactly one story per player.
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
  Main.server.lua            Routes client messages, builds the hub, refreshes room lists
  Rooms.lua                  Matchmaking: UI rooms (public / friends only) and pad rooms; runs a Round per room
  Pads.lua                   Builds the platforms and scans who is standing on them
  Round.lua                  Phase runner, assignment, showcase, voting, scoring
  Projects.lua               Storyboard state and all untrusted-input handling
  Filter.lua                 TextService filtering for every player-written string
src/client/
  Main.client.lua            Router: lobby vs match state, mounts screens, auto-submits
  UI/Responsive.lua          Compact vs regular detection, UI scale, touch sizes
  UI/Layout.lua              split() = side-by-side on regular, stacked on compact
  UI/Controls.lua            Disables movement / touch controls during a match
  UI/Canvas.lua              Normalized-coordinate drawing surface (draw + playback)
  UI/Hud.lua                 Phase title, countdown, submit button (bottom bar on compact)
  UI/Make.lua, Theme.lua     Declarative UI builder and palette
  UI/ModeGrid.lua            Mode cards with vote counts
  UI/StoryInfo.lua           Premise/cast/script reference panel
  Screens/Lobby.lua          Hub UI: Play button, Join/Create/Your Room panel, pad banner
  Screens/                   TextPhases (premise/cast/script/caption), Draw, Dub,
                             Showcase, Vote, Results
plugin/StoryDubSync.lua      Studio plugin: pull from GitHub and install into the open place
scripts/sync.sh, sync.ps1    git pull + rojo serve / rojo build
docs/DESIGN.md               The brief this build follows
```

## Getting it into Roblox Studio

Two options. Both put the same code in the same places.

### Option A: Rojo (live sync, best for development)

You need [Rojo](https://rojo.space) 7 on your PATH and the Rojo plugin in Studio
(Studio → Plugins → Manage Plugins → search "Rojo"). Then, from a clone of this repo:

```sh
./scripts/sync.sh          # macOS / Linux: git pull, then rojo serve
.\scripts\sync.ps1         # Windows PowerShell
```

In Studio open any place, click **Rojo → Connect**, and the game appears under
ReplicatedStorage, ServerScriptService, StarterPlayer and Workspace. Every `git pull`
is reflected live while `rojo serve` is running. To produce a standalone place file instead:

```sh
./scripts/sync.sh build    # writes StoryDub.rbxl
```

### Option B: the StoryDub Sync plugin (no clone, no Rojo)

`plugin/StoryDubSync.lua` is a Studio plugin that downloads the repo from GitHub and
installs it directly into the open place, using the same `default.project.json` mapping.

1. In Studio: **Plugins → Plugins Folder**. Copy `StoryDubSync.lua` into that folder and
   restart Studio. (Or paste the file into a Script, right click → **Save as Local Plugin**.)
2. Click **StoryDub → Sync from GitHub** on the Plugins toolbar.
3. Repo is prefilled as `Vaericcc/Rblx`, branch as `claude/lucid-bardeen-xi7ati`. For a
   private repo paste a GitHub personal access token with **Contents: read**.
4. Press **Sync into this place**. The sync is one undo step.

If Studio reports that HTTP requests are not enabled, turn on
**Game Settings → Security → Allow HTTP Requests** and sync again.

### After either option

Enable **Voice Chat** in Game Settings → Communication (needed for live dubbing; everything
else works without it), then run a local server with 2 or more players
(Test → Clients and Servers). Use the Device emulator to check phone and tablet layouts.

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
