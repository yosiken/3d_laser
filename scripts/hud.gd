extends Control
## 2D overlay: aiming reticle, lock-on markers, and status text.

var main: Node  # main.gd

const COL_IDLE := Color(0.7, 0.85, 1.0, 0.55)
const COL_AIM := Color(0.3, 1.0, 1.0, 0.95)
const COL_LOCK := Color(1.0, 0.25, 0.45, 1.0)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var cam: Camera3D = main.camera
	var t: float = main.time
	var s: float = main.ui_scale()

	# Lock markers (one rotating diamond per locked enemy, count next to it).
	var counts := {}
	for e in main.locks:
		counts[e] = counts.get(e, 0) + 1
	for e: Node3D in counts:
		if not e.alive or cam.is_position_behind(e.global_position):
			continue
		var sp := cam.unproject_position(e.global_position)
		var n: int = counts[e]
		var r := (26.0 + n * 4.0) * s
		var pts := PackedVector2Array()
		for i in 5:
			var a := t * 2.5 + i * PI * 0.5
			pts.append(sp + Vector2(cos(a), sin(a)) * r)
		draw_polyline(pts, COL_LOCK, 2.0 * s, true)
		draw_arc(sp, r * 0.55, 0.0, TAU, 24, Color(COL_LOCK, 0.6), 1.5 * s, true)
		draw_string(font, sp + Vector2(r + 4.0 * s, -r * 0.4), "x%d" % n,
				HORIZONTAL_ALIGNMENT_LEFT, -1, int(18 * s), COL_LOCK)

	# Targets already under fire get small brackets.
	for e: Node3D in main.enemies:
		if not e.alive or e.pending == 0 or cam.is_position_behind(e.global_position):
			continue
		var sp := cam.unproject_position(e.global_position)
		var r := 18.0 * s
		var c := Color(1.0, 0.8, 0.3, 0.8)
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var p: Vector2 = sp + corner * r
			draw_line(p, p - Vector2(corner.x * r * 0.5, 0), c, 1.5 * s)
			draw_line(p, p - Vector2(0, corner.y * r * 0.5), c, 1.5 * s)

	# Reticle.
	var c: Vector2 = main.cursor
	var aiming: bool = main.aiming
	var col := COL_AIM if aiming else COL_IDLE
	var R: float = main.LOCK_RADIUS * s
	var spin := t * (4.0 if aiming else 1.2)
	for i in 3:
		var a0 := spin + i * TAU / 3.0
		draw_arc(c, R, a0, a0 + TAU / 3.0 * 0.6, 20, col, 2.0 * s, true)
	draw_arc(c, R * 0.18, 0.0, TAU, 16, col, 1.5 * s, true)
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(c + d * R * 0.35, c + d * R * 0.6, col, 1.5 * s)

	# Lock gauge under the reticle.
	var nlock: int = main.locks.size()
	if aiming or nlock > 0:
		var gw := R * 2.0
		var gp := c + Vector2(-R, R + 12.0 * s)
		draw_rect(Rect2(gp, Vector2(gw, 5.0 * s)), Color(col, 0.25))
		draw_rect(Rect2(gp, Vector2(gw * nlock / main.MAX_LOCKS, 5.0 * s)), COL_LOCK)
		draw_string(font, gp + Vector2(0, 22.0 * s), "LOCK %d/%d" % [nlock, main.MAX_LOCKS],
				HORIZONTAL_ALIGNMENT_LEFT, -1, int(15 * s), col)

	# Status text.
	var fs := int(16 * s)
	var x := 18.0 * s
	var y := 30.0 * s
	var info := Color(0.8, 0.9, 1.0, 0.9)
	draw_string(font, Vector2(x, y), "CURL NOISE LOCK-ON LASER", HORIZONTAL_ALIGNMENT_LEFT, -1, int(22 * s), COL_AIM)
	y += 28.0 * s
	draw_string(font, Vector2(x, y), "SCORE  %06d" % main.score, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, info)
	y += 22.0 * s
	draw_string(font, Vector2(x, y), "LASERS %d" % main.lasers.active_count(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, info)

	var help := [
		"HOLD  Left mouse / Touch / Space : sweep to lock on",
		"RELEASE : fire homing lasers",
		"[A] auto demo: %s    [C] curl: %s" % ["ON" if main.auto_mode else "OFF", "ON" if main.curl_enabled else "OFF"],
	]
	var hy := size.y - 18.0 * s - (help.size() - 1) * 20.0 * s
	for line: String in help:
		draw_string(font, Vector2(x, hy), line, HORIZONTAL_ALIGNMENT_LEFT, -1, int(14 * s), Color(info, 0.7))
		hy += 20.0 * s
