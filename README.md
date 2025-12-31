# driftline

A small Godot 4 project with an authoritative server tick, a client with prediction/reconciliation, and a built-in tile map editor.

## Project Layout

- `client/`: Godot client scenes and scripts
- `server/`: headless/host server scripts and run scripts
- `shared/`: deterministic shared simulation + network packet types
- `tools/`: one-off utility scripts

## Versioning

Project version is stored in `VERSION` as:

- `MAJOR.MINOR.REVISION`

Rules:

- **REVISION**: small changes/fixes
- **MINOR**: large feature additions
- **MAJOR**: huge milestones

Bump helper:

- `powershell -NoProfile -ExecutionPolicy Bypass -File tools/bump_version.ps1 -Part revision`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools/bump_version.ps1 -Part minor`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools/bump_version.ps1 -Part major`

## Running

### Server

From VS Code you can run the provided task:

- `run server (ctrl+c to stop)`

Or directly:

- `server/run_server.ps1`
- `server/run_server.cmd`

### Client

Open the project in the Godot editor and run.

In-game:

- `Esc`: toggle the in-game menu (non-blocking)
- In the menu: "Back to Menu" returns to the connection screen

## Map Editor

Open the in-project map editor with `M` from the client.

Controls (editor):

- Mouse: move cursor (tile under mouse)
- `LMB` drag: rectangle fill
- `Shift` + `LMB` drag: rectangle outline
- `Space`: place tile at cursor
- `RMB` or `Backspace`: erase tile at cursor
- `WASD`: move camera (cursor remains mouse-controlled)
- `Tab`: cycle layer (`bg` / `solid` / `fg`)
- `Q`: open tile palette (click a tile to select; `Esc` closes)
- `Shift+Q` / `Shift+E`: cycle favorite tiles
- `Ctrl+N`: new map (choose size presets or custom size)
- `Ctrl+S`: save map JSON to `user://maps` and copy the JSON to clipboard (hold `Shift` to also print it)
- `Ctrl+O`: load map (shows a picker if there are multiple)
- `Ctrl+Shift+O`: load newest map directly
- `F`: toggle tile vs entity edit mode
- `1` / `2` / `3`: select entity type (`spawn` / `flag` / `base`)

Entity mode:

- `LMB` or `Space`: place an entity at cursor
- `RMB` or `Backspace`: remove an entity at cursor

Map sizes in the editor UI are in pixels (multiples of 16). Internally the map is stored in tiles.

## Networking / Simulation Notes

- Server runs an authoritative fixed tick.
- Client sends input commands; server broadcasts snapshots.
- Core simulation logic lives in `shared/` so both sides agree on movement/collisions.
- Server spawn locations can come from map `entities` with `type="spawn"`.
- Wall-bounce sound is triggered from shared collision events (client-side audio).

## License

No license specified yet. Add one if/when you want to open-source the project.
