extends Control
## Title menu: pick which demo to run.

const DEMOS := [
	["Curl Noise Lock-on Laser", "res://main.tscn",
		"Sweep to lock on, release to fire homing lasers bent by curl noise."],
	["Camera / Spring / Inertia Lab", "res://camera_lab.tscn",
		"Compare 1996-era follow-camera and momentum formulas side by side."],
]


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)

	var title := Label.new()
	title.text = "GODOT 3D DEMOS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.4, 0.95, 1.0))
	box.add_child(title)

	for d in DEMOS:
		var b := Button.new()
		b.text = d[0]
		b.custom_minimum_size = Vector2(460, 64)
		b.add_theme_font_size_override("font_size", 24)
		b.pressed.connect(get_tree().change_scene_to_file.bind(d[1]))
		box.add_child(b)
		var note := Label.new()
		note.text = d[2]
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
		box.add_child(note)

	var hint := Label.new()
	hint.text = "Esc in a demo returns here"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	box.add_child(hint)
	(box.get_child(1) as Button).grab_focus()
