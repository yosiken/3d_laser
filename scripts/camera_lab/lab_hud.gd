extends Control
## Overlay for the camera lab: per-view labels, graphs and help text.

const FollowCam = preload("res://scripts/camera_lab/follow_cam.gd")
const LabPlayer = preload("res://scripts/camera_lab/lab_player.gd")

var lab: Node  # camera_lab.gd

const BG := Color(0, 0, 0, 0.55)
const TEXT := Color(1, 1, 1, 0.95)
const DIM := Color(1, 1, 1, 0.7)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	if size.y <= 0.0:
		return
	var s := size.y / 720.0
	var fs := int(13 * s)

	for i in 4:
		if not lab.quad and i != lab.active_slot:
			continue
		var r: Rect2 = lab.slot_rect(i)
		var fc = lab.cams[i]
		var col: Color = lab.SLOT_COLORS[i]
		var lines := [
			"[%d] %s" % [fc.algo + 1, FollowCam.NAMES[fc.algo]],
			FollowCam.formula(fc.algo),
			FollowCam.ORIGINS[fc.algo] + ("" if fc.runs_per_tick() else "  (per frame)"),
		]
		var box := Rect2(r.position + Vector2(6, 6) * s, Vector2(r.size.x - 12 * s, 58 * s))
		draw_rect(box, BG)
		draw_rect(Rect2(box.position, Vector2(4 * s, box.size.y)), col)
		var y := box.position.y + 18 * s
		for j in lines.size():
			draw_string(font, Vector2(box.position.x + 12 * s, y), lines[j],
					HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 16 * s,
					int((16 if j == 0 else 13) * s), col if j == 0 else (TEXT if j == 1 else DIM))
			y += 18 * s
		var border := 3.0 * s if i == lab.active_slot else 1.0
		draw_rect(r.grow(-border * 0.5), col if i == lab.active_slot else Color(0, 0, 0, 0.6), false, border)

	if lab.show_overlay:
		_draw_graphs(font, s)
		_draw_status(font, s, fs)
	else:
		draw_string(font, Vector2(10, size.y - 10) , "[G] show graphs / help", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, DIM)


func _draw_graphs(font: Font, s: float) -> void:
	var w := 300.0 * s
	var h := 90.0 * s
	var origin := Vector2(size.x - w - 10 * s, size.y - (h * 2 + 46 * s) - 10 * s)
	var lag_rect := Rect2(origin + Vector2(0, 16 * s), Vector2(w, h))
	var spd_rect := Rect2(lag_rect.position + Vector2(0, h + 26 * s), Vector2(w, h))
	draw_rect(Rect2(origin - Vector2(6, 4) * s, Vector2(w + 12 * s, h * 2 + 54 * s)), BG)

	# Camera lag: distance from the ideal camera position.
	var max_lag := 0.5
	for i in 4:
		if lab.quad or i == lab.active_slot:
			for v in lab.lag_hist[i]:
				max_lag = maxf(max_lag, v)
	draw_string(font, origin + Vector2(0, 12 * s), "camera lag [m]  (max %.2f)" % max_lag,
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(12 * s), DIM)
	draw_rect(lag_rect, Color(1, 1, 1, 0.15), false, 1.0)
	for i in 4:
		if lab.quad or i == lab.active_slot:
			_plot(lab.lag_hist[i], lag_rect, max_lag, lab.SLOT_COLORS[i], 1.6 * s)

	var max_spd := 1.0
	for v in lab.speed_hist:
		max_spd = maxf(max_spd, v)
	draw_string(font, spd_rect.position - Vector2(0, 4 * s),
			"player speed [m/s]  (max %.1f)" % max_spd, HORIZONTAL_ALIGNMENT_LEFT, -1, int(12 * s), DIM)
	draw_rect(spd_rect, Color(1, 1, 1, 0.15), false, 1.0)
	_plot(lab.speed_hist, spd_rect, max_spd, Color(1, 1, 1), 1.6 * s)


func _plot(buf: PackedFloat32Array, rect: Rect2, max_v: float, col: Color, width: float) -> void:
	var n := buf.size()
	var pts := PackedVector2Array()
	pts.resize(n)
	for k in n:
		var v := buf[(lab.hist_head + k) % n]
		pts[k] = rect.position + Vector2(rect.size.x * k / (n - 1), rect.size.y * (1.0 - clampf(v / max_v, 0.0, 1.0)))
	draw_polyline(pts, col, width, true)


func _draw_status(font: Font, s: float, fs: int) -> void:
	var lines := [
		"MOVE [M]: %s   %s" % [LabPlayer.MOVE_NAMES[lab.player.move], LabPlayer.MOVE_FORMULAS[lab.player.move]],
		"TICK [F]: %d Hz%s   AUTOPILOT [P]: %s" % [lab.tick_hz,
				"  (per-frame formulas now run 2x faster!)" if lab.tick_hz == 60 else "",
				"ON" if lab.autopilot else "OFF"],
		"WASD/Arrows move  Space jump  1-6 formula  Q/click select view  Tab single/quad",
		"Z/X main param  C/V spring zeta  R reset  G hide overlay  Esc menu",
	]
	var h := lines.size() * 17.0 * s + 10 * s
	var w := 640.0 * s
	var p := Vector2(10 * s, size.y - h - 10 * s)
	draw_rect(Rect2(p, Vector2(w, h)), BG)
	var y := p.y + 17 * s
	for j in lines.size():
		draw_string(font, Vector2(p.x + 8 * s, y), lines[j], HORIZONTAL_ALIGNMENT_LEFT, w - 12 * s,
				fs, TEXT if j < 2 else DIM)
		y += 17 * s
