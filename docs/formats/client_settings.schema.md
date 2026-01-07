# Client Settings Schema (v1)

This document describes the persistent client settings file stored at `user://settings.json`.

This file is treated as a strict, versioned JSON contract:

- Files MUST include `format` and `schema_version`.
- Loaders MUST refuse to load unknown `format` values.
- Unknown `schema_version` values MUST fail loudly (no silent fallback).

## Identity

- `format`: `driftline.client_settings`
- `schema_version`: `1`

## Upgrading from pre-v1

Older builds may have created a `user://settings.json` without `format` / `schema_version`.
These files are now rejected by the loader.

To reset locally:

- Delete `user://settings.json` and relaunch the game.

## Top-level shape

```json
{
	"format": "driftline.client_settings",
	"schema_version": 1,
	"audio": {
		"master_db": 0.0,
		"sfx_db": 0.0,
		"music_db": 0.0,
		"ui_db": 0.0
	},
	"ui": {
		"show_minimap": true,
		"help_ticker_enabled": true
	},
	"controls": {
		"bindings": {
			"<action_id>": [
				{"type": "key", "device": -1, "keycode": 0, "physical_keycode": 87, "shift": false, "ctrl": false, "alt": false, "meta": false},
				{"type": "mouse_button", "device": 0, "button_index": 1, "shift": false, "ctrl": false, "alt": false, "meta": false}
			]
		}
	}
}
```

Notes:

- Output is canonicalized (stable key ordering) to make diffs and hashing reliable.
- `controls.bindings` is a map from action id (string) to an array of serialized input events.
- If an action exists in `controls.bindings` with an empty array (`[]`), the action is intentionally unbound.
- If an action is missing from `controls.bindings`, defaults from `res://client/input/actions.gd` apply.

## Audio

- Values are bus volume dB floats.
- Non-finite values (NaN/Inf) are clamped to safe defaults by the loader.

## UI

- `show_minimap`: toggles minimap visibility.
- `help_ticker_enabled`: toggles the help/training ticker.

## Serialized Input Events

Each entry in `controls.bindings[<action_id>]` is a JSON object with a `type` discriminator.

### Keyboard

```json
{
	"type": "key",
	"device": -1,
	"keycode": 0,
	"physical_keycode": 87,
	"shift": false,
	"ctrl": false,
	"alt": false,
	"meta": false
}
```

### Mouse button

```json
{
	"type": "mouse_button",
	"device": 0,
	"button_index": 1,
	"shift": false,
	"ctrl": false,
	"alt": false,
	"meta": false
}
```

### Joypad button

```json
{
	"type": "joypad_button",
	"device": 0,
	"button_index": 0
}
```

### Joypad axis

Axis binds persist only the axis and sign (not the raw analog value):

```json
{
	"type": "joypad_motion",
	"device": 0,
	"axis": 0,
	"sign": 1
}
```
