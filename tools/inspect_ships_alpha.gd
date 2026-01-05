extends SceneTree

func _init() -> void:
	var path := "res://client/graphics/ships/ships.png"
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		push_error("Failed to read bytes: %s" % path)
		quit(1)
		return

	var img := Image.new()
	var err := img.load_png_from_buffer(bytes)
	if err != OK:
		push_error("Failed to decode PNG: %s (err=%d)" % [path, err])
		quit(1)
		return

	var fmt := img.get_format()
	print("ships.png: size=", img.get_width(), "x", img.get_height(), " format=", fmt)

	# Sample a few pixels that should be 'background' inside a typical 10x32 grid sheet.
	# We use corners of the top-left frame cell.
	var cell_w := int(img.get_width() / 10)
	var cell_h := int(img.get_height() / 32)
	print("derived cell size: ", cell_w, "x", cell_h)

	var samples := [
		Vector2i(0, 0),
		Vector2i(cell_w - 1, 0),
		Vector2i(0, cell_h - 1),
		Vector2i(cell_w - 1, cell_h - 1),
		Vector2i(cell_w / 2, cell_h / 2),
	]

	for p in samples:
		var c := img.get_pixelv(p)
		print("sample ", p, ": rgba=", c)

	# Lightweight alpha scan: step through image with a stride.
	var min_a := 1.0
	var max_a := 0.0
	var stride := 8
	for y in range(0, img.get_height(), stride):
		for x in range(0, img.get_width(), stride):
			var a := img.get_pixel(x, y).a
			min_a = minf(min_a, a)
			max_a = maxf(max_a, a)

	print("alpha range (stride ", stride, "): min=", min_a, " max=", max_a)
	quit(0)
