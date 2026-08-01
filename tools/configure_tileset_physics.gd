@tool
extends EditorScript

## Run this once to configure physics collision on the subspace_base tileset.
## Go to File > Run and select this script.

func _run() -> void:
	var tileset_path := "res://client/graphics/tilesets/subspace_base/tileset.tres"
	var tileset: TileSet = load(tileset_path)
	
	if not tileset:
		print("ERROR: Could not load tileset")
		return
	
	# Add physics layer if it doesn't exist
	if tileset.get_physics_layers_count() == 0:
		tileset.add_physics_layer()
		print("Added physics layer 0")
	
	# Get the atlas source
	var source_id := 0
	var atlas: TileSetAtlasSource = tileset.get_source(source_id) as TileSetAtlasSource
	
	if not atlas:
		print("ERROR: Could not get atlas source")
		return
	
	# For each tile in the atlas, add a full 16x16 collision square
	var tile_size := 16
	var collision_polygon := PackedVector2Array([
		Vector2(0, 0),
		Vector2(tile_size, 0),
		Vector2(tile_size, tile_size),
		Vector2(0, tile_size)
	])
	
	var tiles_configured := 0
	
	# Iterate through all tiles in the atlas
	for x in range(19):  # 0-18 columns
		for y in range(20):  # 0-19 rows
			var tile_coord := Vector2i(x, y)
			
			# Check if tile exists
			if not atlas.has_tile(tile_coord):
				continue
			
			# Skip safe zone tile (9,19) - no collision
			if tile_coord == Vector2i(9, 19):
				continue
			
			# Skip empty tile (0,0)
			if tile_coord == Vector2i(0, 0):
				continue
			
			# Add physics polygon for this tile
			var tile_data: TileData = atlas.get_tile_data(tile_coord, 0)
			if tile_data:
				# Add collision polygon on physics layer 0
				tile_data.add_collision_polygon(0)
				tile_data.set_collision_polygon_points(0, 0, collision_polygon)
				tiles_configured += 1
	
	# Save the tileset
	var err := ResourceSaver.save(tileset, tileset_path)
	if err == OK:
		print("✓ Tileset physics configured: %d tiles" % tiles_configured)
		print("✓ Saved: %s" % tileset_path)
	else:
		print("ERROR: Failed to save tileset")
