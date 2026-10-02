# StoryDub design brief

This is the brief the current build was made from. It is the sharpened version of
the original idea ("draw a storyboard and your friends dub over it").

## Brief

Build **StoryDub**, a cross-platform (phone, tablet, PC) voice-chat party game for Roblox.
Players write a premise and cast, draw a storyboard, claim roles and voice the result live.
Seven modes are pure data (an ordered list of phases plus a seat offset): Classic, Comic,
Story Swap, Script Swap, Co-op Comic, Blind Dub and Broken Telephone.

**Hub and matchmaking.** The hub is a walkable plaza. Matches form from rooms (Public,
Friends Only, or Pro, which needs 10,000 persistent points) or by standing on a platform.
When a match starts, the party is **teleported to a reserved server** of the same place
(like Doors), plays there alone, and is teleported back to a public hub server afterwards.
Studio cannot teleport, so there the match runs inside the hub server with voice access
lists for isolation.

**Drawing.** The canvas has brush, eraser, rectangle, circle, fill, mirror, transform and
lasso tools. Every stroke streams to the server as it happens so nothing is lost on a
disconnect; the server only commits a panel when the artist submits or the timer ends.
Players with nothing to draw watch the artists live.

**Progression.** Round scores accumulate in a DataStore. Totals show in the hub and gate
Pro rooms.

**Presentation.** The menu reads like a comic page: cream paper, heavy ink borders, a pop
colour for emphasis. The hub is a floating stone island at golden hour.

## Private match servers

- `Rooms.startMatch` calls `TeleportService:ReserveServer(game.PlaceId)` and teleports the
  party with TeleportData `{ modeId, memberIds }`.
- A server with `PrivateServerId ~= ""` and `PrivateServerOwnerId == 0` is a match server.
  `Main.server.lua` detects this and hands off to `MatchServer.lua`, which gathers the
  party (up to `MATCH_SERVER_GATHER_SECONDS`), runs one Round, and teleports everyone back.
- Falls back to an in-server match if reservation or teleport fails.

## Live drawing

- Client sends `Stroke { panel, op, stroke | strokes }` for add / undo / clear / set.
- `Round.onStroke` validates and keeps a per-artist buffer; spectators get `LiveStroke`.
- At phase end the explicit submission wins; otherwise the buffer is used.

## Player caps

| What | Cap | Where |
|------|-----|-------|
| Hub server | Roblox default 50 | Game Settings → Places → Max Players (30 to 50 recommended) |
| Room / party | 10 | `Config.MAX_PLAYERS` |
| Match server | the party only | reserved per match |

## Roles and the dubbing moment

- A **claim** phase follows the cast phase. All players see every story's cast and tap to
  claim characters (max two per story, not your own). Claims are live and server-arbitrated;
  unclaimed roles are filled automatically, preferring players with the fewest roles.
- The **dub** phase with `roles = true` sends each player only the stories they have roles
  in, and the server only accepts lines for characters they hold.
- The **showcase** is paced line by line by the server. Each line names an actor; that actor
  gets an on-air panel (mic toggle via their own AudioDeviceInput, a level meter via
  AudioAnalyzer, and a Next Line button that tells the server to advance). Lines auto-advance
  after `SHOWCASE_LINE_SECONDS`.
- Microphone audio cannot be recorded in Roblox, so there is no record-and-replay. Live voice
  chat is the dub; text bubbles are the fallback.

## Cross-platform rules

| Concern | Decision |
|--------|----------|
| Layout | `Responsive.isCompact()` (viewport under 820x480) switches every screen from side-by-side to stacked via `Layout.split`. The client waits for a believable viewport before measuring, since the startup camera reports a tiny one |
| Scale | A `UIScale` of `clamp(min(vX/1280, vY/720), 0.8, 1.8)` on regular screens, so 4K monitors scale up; compact layouts are designed at native size. Match content is capped at 1240px wide and centered |
| Touch | Canvas frame is `Active` so touches never pan the camera; tap targets are 48px on touch devices, 40px with a mouse |
| Controls | During a match the PlayerModule controls, thumbstick and jump button are disabled and the humanoid is frozen so nobody drifts off a pad |
| Safe areas | The ScreenGui respects the GUI inset; padding is 10px on compact, 16px otherwise |
| Submit | On compact the submit button is a full-width bottom bar; on regular it sits in the top HUD |

## Server protocol

All traffic is one RemoteEvent whose first argument is an action name (see `src/shared/Net.lua`).

Client → server: `Hello`, `CreateRoom`, `JoinRoom`, `LeaveRoom`, `StartRoom`, `VoteMode`, `Submit`, `Vote`.

Server → client: `LobbyInit`, `RoomList`, `RoomState`, `PadState`, `Phase`, `Showcase`, `ShowcaseFocus`, `Vote`, `Results`, `MatchEnd`, `SubmitAck`, `Toast`.

## Not yet verified in Studio

This build has been checked with the Luau compiler and by review, not by running
in Roblox Studio. Expect to tune spacing and font sizes on a real phone, and confirm
voice chat permissions for the live dubbing step.
