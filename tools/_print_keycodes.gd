extends SceneTree

func _initialize() -> void:
	var codes := {
		"KEY_W": KEY_W,
		"KEY_A": KEY_A,
		"KEY_S": KEY_S,
		"KEY_D": KEY_D,
		"KEY_Q": KEY_Q,
		"KEY_E": KEY_E,
		"KEY_T": KEY_T,
		"KEY_V": KEY_V,
		"KEY_O": KEY_O,
		"KEY_N": KEY_N,
		"KEY_1": KEY_1,
		"KEY_2": KEY_2,
		"KEY_3": KEY_3,
		"KEY_SPACE": KEY_SPACE,
		"KEY_SHIFT": KEY_SHIFT,
		"KEY_CTRL": KEY_CTRL,
		"KEY_ALT": KEY_ALT,
		"KEY_META": KEY_META,
		"KEY_CAPSLOCK": KEY_CAPSLOCK,
		"KEY_TAB": KEY_TAB,
		"KEY_BACKSPACE": KEY_BACKSPACE,
		"KEY_MINUS": KEY_MINUS,
		"KEY_EQUAL": KEY_EQUAL,
		"KEY_KP_ADD": KEY_KP_ADD,
		"KEY_KP_SUBTRACT": KEY_KP_SUBTRACT,
		"KEY_ENTER": KEY_ENTER,
		"KEY_ESCAPE": KEY_ESCAPE,
		"KEY_F1": KEY_F1,
		"KEY_F6": KEY_F6,
		"KEY_F10": KEY_F10,
	}
	print(JSON.stringify(codes, "\t", false))
	quit()
