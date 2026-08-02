## SubSpace-style chat commands and `%` message macros.
##
## Reference: original_content/old assets/SubSpace/SubSpace Client v1.34/HELP/sshelpge41.html
##
## Pure/static by design so the smoke tests can exercise it headless with a synthetic
## context dictionary. The caller (DriftClientMain) builds the context, then applies
## whatever the returned command asks for. Nothing here touches the network or the sim.
##
## Commands that need arenas or accounts (?go, ?arena, ?usage, ?chat=) are deliberately
## absent -- an unrecognised `?word` falls through to public chat, as it does in SubSpace.

class_name DriftChatCommands

# Result kinds returned by parse().
const KIND_NONE: String = "none"      # swallow the input, do nothing
const KIND_SEND: String = "send"      # send `text` to chat as normal
const KIND_LOCAL: String = "local"    # print `lines` client-side; maybe apply `effect`
const KIND_FREQ: String = "freq"      # request a frequency change to `freq`

# Client-side effects a local command can ask for.
const EFFECT_NONE: String = ""
const EFFECT_KILL_FEED: String = "kill_feed"    # toggle kill message display
const EFFECT_CHAT_LINES: String = "chat_lines"  # value = new visible line count
const EFFECT_IGNORE: String = "ignore"          # value = player name to toggle

const CHAT_LINES_MIN: int = 1
const CHAT_LINES_MAX: int = 20

const HELP_LINES: Array[String] = [
	"?help  ?ping  ?packetloss  ?status  ?flags  ?team",
	"?kill (toggle kill messages)  ?lines=N  ?ignore <name>",
	"=NNNN sets your frequency. /t /priv /arena target a channel.",
	"Macros: %coord %area %selfname %freq %bounty %flags %energy",
	"        %shield %super %killer %killed %red %redname %redflags %redbounty",
]


static func parse(raw: String, ctx: Dictionary) -> Dictionary:
	var text: String = String(raw).strip_edges()
	if text.is_empty():
		return {"kind": KIND_NONE}

	# Frequency change: =NNNN (SubSpace requires full energy; the server enforces its own rules).
	if text.begins_with("=") and text.length() > 1:
		var digits: String = text.substr(1).strip_edges()
		if digits.is_valid_int():
			return {"kind": KIND_FREQ, "freq": int(digits)}
		return _local(["Usage: =NNNN (frequency number)"])

	if not text.begins_with("?"):
		return {"kind": KIND_SEND, "text": expand_macros(text, ctx)}

	# Split "?name" from any argument, supporting both "?lines=5" and "?ignore Bob".
	var body: String = text.substr(1)
	var arg: String = ""
	var name: String = body
	var eq: int = body.find("=")
	var sp: int = body.find(" ")
	if eq >= 0 and (sp < 0 or eq < sp):
		name = body.left(eq)
		arg = body.substr(eq + 1).strip_edges()
	elif sp >= 0:
		name = body.left(sp)
		arg = body.substr(sp + 1).strip_edges()
	name = name.strip_edges().to_lower()

	match name:
		"help", "commands":
			return _local(HELP_LINES.duplicate())
		"ping":
			return _local(["Ping: %d ms" % int(ctx.get("ping_ms", 0))])
		"packetloss":
			# ENet reports a single peer-level estimate, not the separate S2C/C2S figures
			# the original client showed; report the one number we actually have.
			return _local(["Packet loss: %.1f%%" % float(ctx.get("loss_pct", 0.0))])
		"status":
			return _local([_format_status(ctx)])
		"flags":
			return _local(_format_list("Flags", ctx.get("flag_holders", []), "No flags are being carried."))
		"team":
			return _local(_format_list("Team", ctx.get("team", []), "No teammates."))
		"kill":
			return _local([], EFFECT_KILL_FEED)
		"lines":
			if not arg.is_valid_int():
				return _local(["Usage: ?lines=N (%d-%d)" % [CHAT_LINES_MIN, CHAT_LINES_MAX]])
			var n: int = clampi(int(arg), CHAT_LINES_MIN, CHAT_LINES_MAX)
			return _local(["Chat lines: %d" % n], EFFECT_CHAT_LINES, n)
		"ignore":
			if arg.is_empty():
				return _local(["Usage: ?ignore <name>"])
			return _local([], EFFECT_IGNORE, arg)

	# Unknown command: behave like SubSpace and let it go out as normal chat.
	return {"kind": KIND_SEND, "text": expand_macros(text, ctx)}


static func expand_macros(text: String, ctx: Dictionary) -> String:
	# `%%` is the literal-percent escape (see original_content/Tips.txt). Split on it first so
	# an escaped token like %%coord survives instead of being expanded.
	var out: PackedStringArray = PackedStringArray()
	for segment in String(text).split("%%", true):
		out.append(_expand_segment(segment, ctx))
	return "%".join(out)


static func area_label(normalized: Vector2) -> String:
	# Nine-region description used by %area, e.g. "upper left".
	var vertical: Array[String] = ["upper", "middle", "lower"]
	var horizontal: Array[String] = ["left", "center", "right"]
	var col: int = clampi(int(floor(normalized.x * 3.0)), 0, 2)
	var row: int = clampi(int(floor(normalized.y * 3.0)), 0, 2)
	if col == 1 and row == 1:
		return "center"
	if col == 1:
		return vertical[row]
	if row == 1:
		return horizontal[col]
	return "%s %s" % [vertical[row], horizontal[col]]


static func _expand_segment(segment: String, ctx: Dictionary) -> String:
	# Longest tokens first so %redname is not eaten by %red.
	var tokens: Array = [
		["%redbounty", str(int(ctx.get("red_bounty", 0)))],
		["%redflags", str(int(ctx.get("red_flags", 0)))],
		["%redname", String(ctx.get("red_name", "none"))],
		["%selfname", String(ctx.get("name", ""))],
		["%tickname", String(ctx.get("tick_name", ""))],
		["%killed", String(ctx.get("killed", "nobody"))],
		["%killer", String(ctx.get("killer", "nobody"))],
		["%bounty", str(int(ctx.get("bounty", 0)))],
		["%energy", str(int(ctx.get("energy", 0)))],
		["%shield", "%.1fs" % float(ctx.get("shield_s", 0.0))],
		["%coord", String(ctx.get("coord", ""))],
		["%flags", str(int(ctx.get("flags", 0)))],
		["%super", "%.1fs" % float(ctx.get("super_s", 0.0))],
		["%area", String(ctx.get("area", ""))],
		["%freq", str(int(ctx.get("freq", 0)))],
		["%red", "%s (%d flags, %d bty)" % [
			String(ctx.get("red_name", "none")),
			int(ctx.get("red_flags", 0)),
			int(ctx.get("red_bounty", 0)),
		]],
	]
	var out: String = segment
	for pair in tokens:
		out = out.replace(String(pair[0]), String(pair[1]))
	return out


static func _format_status(ctx: Dictionary) -> String:
	# Upgrade progress as a percentage of the maximum obtainable upgrades, matching what
	# ?status reports in SubSpace (Recharge, Thruster, Speed, Rotation, Shrapnel).
	var s: Dictionary = ctx.get("status", {}) if typeof(ctx.get("status")) == TYPE_DICTIONARY else {}
	return "Recharge:%d%% Thruster:%d%% Speed:%d%% Rotation:%d%% Shrapnel:%d" % [
		int(s.get("recharge", 0)),
		int(s.get("thruster", 0)),
		int(s.get("speed", 0)),
		int(s.get("rotation", 0)),
		int(s.get("shrapnel", 0)),
	]


static func _format_list(label: String, values: Variant, empty_text: String) -> Array[String]:
	var items: Array = values as Array if typeof(values) == TYPE_ARRAY else []
	if items.is_empty():
		return [empty_text]
	var lines: Array[String] = []
	var row: PackedStringArray = PackedStringArray()
	for item in items:
		row.append(String(item))
		if row.size() == 4:
			lines.append("%s: %s" % [label, ", ".join(row)])
			row = PackedStringArray()
	if row.size() > 0:
		lines.append("%s: %s" % [label, ", ".join(row)])
	return lines


static func _local(lines: Array, effect: String = EFFECT_NONE, value: Variant = null) -> Dictionary:
	return {"kind": KIND_LOCAL, "lines": lines, "effect": effect, "value": value}
