# StoryDub design brief

This is the brief the current build was made from. It is the sharpened version of
the original idea ("draw a storyboard and your friends dub over it").

## Brief

Build a cross-platform Roblox party game (phone, tablet, PC) called **StoryDub**.
Players write a premise and cast, draw a storyboard, and friends dub it. Six modes
are defined as data, so each is an ordered list of phases plus a seat offset that
decides whose story you work on: Classic, Comic, Story Swap, Script Swap, Blind Dub
and Broken Telephone.

The lobby is a walkable 3D hub with two ways to start a match:

1. **Matchmaking UI.** A host creates a room set to *Public* or *Friends Only*.
   Friends-only rooms are visible and joinable only to the host's Roblox friends
   (checked server-side with `Player:IsFriendsWith`). Members vote on a mode and the
   host starts. Host migrates if the host leaves.
2. **Platforms.** Glowing pads in the hub form a match automatically when enough
   players stand on them. A billboard over the pad shows the count and a countdown.
   Standing players vote on a mode from a bottom banner. Stepping off leaves.

Many matches run at once, one per room. Every screen works at phone size (stacked
layout, touch drawing, on-screen controls hidden and the character frozen during a
match) and at desktop size (side-by-side panels). The server validates and filters
all player input. Code is modular: modes are data, layout decisions live in one
place, and the client is a router over server messages.

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
