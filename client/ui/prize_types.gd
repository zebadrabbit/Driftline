## Logical prize types (client-facing taxonomy).
##
## This is NOT a mapping of UI assets; it is a stable set of gameplay concepts.
## Each type *may* map to presentation metadata (icon, short label, sound id).

class_name DriftPrizeTypes
extends RefCounted

const DriftTypes := preload("res://shared/drift_types.gd")
const DriftUiIconAtlas := preload("res://client/ui/ui_icon_atlas.gd")

# PrizeType is intentionally smaller than DriftTypes.PrizeKind.
# Do not add additional members unless explicitly requested.

enum PrizeType {
	GUN_UPGRADE,
	BOMB_UPGRADE,
	MULTISHOT,
	BOUNCING,
	PROXIMITY,
	SHRAPNEL,
	BURST,
	REPEL,
	DECOY,
	THOR,
	BRICK,
	ROCKET,
	TELEPORT,
	ENERGY,
	FULL_CHARGE,
	STEALTH,
	XRADAR,
	ANTIWARP,
}


static func prize_type_from_prize_kind(kind: int) -> int:
	# Returns -1 if the kind has no mapped PrizeType.
	match int(kind):
		DriftTypes.PrizeKind.Gun:
			return int(PrizeType.GUN_UPGRADE)
		DriftTypes.PrizeKind.Bomb:
			return int(PrizeType.BOMB_UPGRADE)
		DriftTypes.PrizeKind.MultiFire:
			return int(PrizeType.MULTISHOT)
		DriftTypes.PrizeKind.BouncingBullets:
			return int(PrizeType.BOUNCING)
		DriftTypes.PrizeKind.Proximity:
			return int(PrizeType.PROXIMITY)
		DriftTypes.PrizeKind.Shrapnel:
			return int(PrizeType.SHRAPNEL)
		DriftTypes.PrizeKind.Burst:
			return int(PrizeType.BURST)
		DriftTypes.PrizeKind.Repel:
			return int(PrizeType.REPEL)
		DriftTypes.PrizeKind.Decoy:
			return int(PrizeType.DECOY)
		DriftTypes.PrizeKind.Thor:
			return int(PrizeType.THOR)
		DriftTypes.PrizeKind.Brick:
			return int(PrizeType.BRICK)
		DriftTypes.PrizeKind.Rocket:
			return int(PrizeType.ROCKET)
		DriftTypes.PrizeKind.Portal:
			return int(PrizeType.TELEPORT)
		DriftTypes.PrizeKind.Energy:
			return int(PrizeType.ENERGY)
		DriftTypes.PrizeKind.QuickCharge:
			return int(PrizeType.FULL_CHARGE)
		DriftTypes.PrizeKind.Stealth:
			return int(PrizeType.STEALTH)
		DriftTypes.PrizeKind.XRadar:
			return int(PrizeType.XRADAR)
		DriftTypes.PrizeKind.AntiWarp:
			return int(PrizeType.ANTIWARP)
		_:
			return -1


static func label_for_type(prize_type: int) -> String:
	match int(prize_type):
		PrizeType.GUN_UPGRADE:
			return "Gun"
		PrizeType.BOMB_UPGRADE:
			return "Bomb"
		PrizeType.MULTISHOT:
			return "Multi"
		PrizeType.BOUNCING:
			return "Bounce"
		PrizeType.PROXIMITY:
			return "Prox"
		PrizeType.SHRAPNEL:
			return "Shrap"
		PrizeType.BURST:
			return "Burst"
		PrizeType.REPEL:
			return "Repel"
		PrizeType.DECOY:
			return "Decoy"
		PrizeType.THOR:
			return "Thor"
		PrizeType.BRICK:
			return "Brick"
		PrizeType.ROCKET:
			return "Rocket"
		PrizeType.TELEPORT:
			return "Teleport"
		PrizeType.ENERGY:
			return "Energy"
		PrizeType.FULL_CHARGE:
			return "Full"
		PrizeType.STEALTH:
			return "Stealth"
		PrizeType.XRADAR:
			return "XRadar"
		PrizeType.ANTIWARP:
			return "AntiWarp"
		_:
			return ""


static func label_for_prize_kind(kind: int) -> String:
	# Prefer PrizeType when mapped.
	var t: int = prize_type_from_prize_kind(kind)
	if t >= 0:
		return label_for_type(t)

	# Fallback labels for PrizeKind values that are intentionally *not* part of
	# the stable PrizeType taxonomy, but still deserve player-visible feedback.
	match int(kind):
		DriftTypes.PrizeKind.Rotation:
			return "Rot"
		DriftTypes.PrizeKind.Cloak:
			return "Cloak"
		DriftTypes.PrizeKind.Warp:
			return "Warp"
		DriftTypes.PrizeKind.Thruster:
			return "Thrust"
		DriftTypes.PrizeKind.TopSpeed:
			return "Speed"
		DriftTypes.PrizeKind.Recharge:
			return "Rech"
		DriftTypes.PrizeKind.Glue:
			return "Glue"
		DriftTypes.PrizeKind.AllWeapons:
			return "All"
		DriftTypes.PrizeKind.Shields:
			return "Shields"
		DriftTypes.PrizeKind.MultiPrize:
			return "Multi"
		_:
			return ""


static func sound_id_for_type(prize_type: int) -> String:
	# Identifier only; no loading logic.
	# Leaving this as a single shared id keeps behavior deterministic.
	match int(prize_type):
		PrizeType.GUN_UPGRADE:
			return "prize_pickup"
		PrizeType.BOMB_UPGRADE:
			return "prize_pickup"
		PrizeType.MULTISHOT:
			return "prize_pickup"
		PrizeType.BOUNCING:
			return "prize_pickup"
		PrizeType.PROXIMITY:
			return "prize_pickup"
		PrizeType.SHRAPNEL:
			return "prize_pickup"
		PrizeType.BURST:
			return "prize_pickup"
		PrizeType.REPEL:
			return "prize_pickup"
		PrizeType.DECOY:
			return "prize_pickup"
		PrizeType.THOR:
			return "prize_pickup"
		PrizeType.BRICK:
			return "prize_pickup"
		PrizeType.ROCKET:
			return "prize_pickup"
		PrizeType.TELEPORT:
			return "prize_pickup"
		PrizeType.ENERGY:
			return "prize_pickup"
		PrizeType.FULL_CHARGE:
			return "prize_pickup"
		PrizeType.STEALTH:
			return "prize_pickup"
		PrizeType.XRADAR:
			return "prize_pickup"
		PrizeType.ANTIWARP:
			return "prize_pickup"
		_:
			return ""


static func sound_id_for_prize_kind(kind: int) -> String:
	# Identifier only; keep behavior deterministic.
	# Use a shared pickup id for any prize kind we can label.
	var label: String = label_for_prize_kind(int(kind))
	if label != "":
		return "prize_pickup"
	return ""


static func icon_contract_rc_for_type(prize_type: int) -> Vector2i:
	# Returns Vector2i(row, col) in contract coordinates, or (-1,-1) if none.
	match int(prize_type):
		# Weapon-affecting prizes use representative weapon icons.
		PrizeType.GUN_UPGRADE:
			return Vector2i(0, 1) # gun L2 (no bounce), representative
		PrizeType.MULTISHOT:
			return Vector2i(0, 3) # gun L1 multishot enabled
		PrizeType.BOUNCING:
			return Vector2i(1, 0) # gun L1 bounce
		PrizeType.BOMB_UPGRADE:
			return Vector2i(2, 1) # bomb L2 base, representative
		PrizeType.PROXIMITY:
			return Vector2i(2, 3) # bomb L1 prox
		PrizeType.SHRAPNEL:
			return Vector2i(2, 6) # bomb L1 shrap

		# Inventory prizes.
		PrizeType.BURST:
			return Vector2i(3, 3)
		PrizeType.REPEL:
			return Vector2i(3, 4)
		PrizeType.DECOY:
			return Vector2i(4, 4)
		PrizeType.THOR:
			return Vector2i(4, 5)
		PrizeType.BRICK:
			return Vector2i(4, 6)
		PrizeType.ROCKET:
			return Vector2i(4, 8)
		PrizeType.TELEPORT:
			return Vector2i(5, 1)

		# Toggles.
		PrizeType.STEALTH:
			return Vector2i(3, 7) # stealth on
		PrizeType.XRADAR:
			return Vector2i(4, 0) # xradar on
		PrizeType.ANTIWARP:
			return Vector2i(4, 2) # antiwarp on

		# No contracted icon yet.
		PrizeType.ENERGY:
			return Vector2i(-1, -1)
		PrizeType.FULL_CHARGE:
			return Vector2i(-1, -1)
		_:
			return Vector2i(-1, -1)


static func icon_atlas_coords_for_type(prize_type: int) -> Vector2i:
	# Returns Godot atlas coords Vector2i(col,row), or (-1,-1) if none.
	var rc: Vector2i = icon_contract_rc_for_type(prize_type)
	if rc.x < 0 or rc.y < 0:
		return Vector2i(-1, -1)
	var atlas: Vector2i = DriftUiIconAtlas.rc(int(rc.x), int(rc.y))
	if not DriftUiIconAtlas.coords_is_renderable(atlas):
		push_error("PrizeType icon mapped to non-renderable tile: type=%s rc=%s" % [str(prize_type), str(rc)])
		return Vector2i(-1, -1)
	return atlas


static func icon_atlas_coords_for_prize_kind(kind: int) -> Vector2i:
	var t: int = prize_type_from_prize_kind(kind)
	if t >= 0:
		return icon_atlas_coords_for_type(t)
	# Fallback icon for select kinds not in PrizeType taxonomy.
	match int(kind):
		DriftTypes.PrizeKind.Thruster:
			# Use the contracted inventory thruster icon.
			return DriftUiIconAtlas.inventory_icon_coords(&"thruster")
		_:
			return Vector2i(-1, -1)
