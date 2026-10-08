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
	var h := 62.0 * s
	var gap := 24.0 * s
	var total := (h + gap) * 3.0
	var origin := Vector2(size.x - w - 10 * s, size.y - total - 10 * s)
	draw_rect(Rect2(origin - Vector2(6, 4) * s, Vector2(w + 12 * s, total + 4 * s)), BG)
	var rects: Array[Rect2] = []
	for g in 3:
		rects.append(Rect2(origin + Vector2(0, gap + g * (h + gap) - 6 * s), Vector2(w, h)))

	# Camera lag: distance from the ideal camera position.
	var max_lag := 0.5
	for i in 4:
		if lab.quad or i == lab.active_slot:
			for v in lab.lag_hist[i]:
				max_lag = maxf(max_lag, v)
	_graph_frame(font, s, rects[0], "camera lag [m]  (max %.2f)" % max_lag)
	for i in 4:
		if lab.quad or i == lab.active_slot:
			_plot(lab.lag_hist[i], rects[0], 0.0, max_lag, lab.SLOT_COLORS[i], 1.6 * s)

	var max_spd := 1.0
	for v in lab.speed_hist:
		max_spd = maxf(max_spd, v)
	_graph_frame(font, s, rects[1], "player speed [m/s]  (max %.1f)" % max_spd)
	_plot(lab.speed_hist, rects[1], 0.0, max_spd, Color(1, 1, 1), 1.6 * s)

	# Roll is signed: zero line in the middle, +-1.5x the max target angle.
	var lim: float = lab.ROLL_MAX_DEG * 1.5
	_graph_frame(font, s, rects[2], "camera roll [deg]  (target +-%.0f)" % lab.ROLL_MAX_DEG)
	var mid := rects[2].get_center().y
	draw_line(Vector2(rects[2].position.x, mid), Vector2(rects[2].end.x, mid), Color(1, 1, 1, 0.25), 1.0)
	for sign in [-1.0, 1.0]:
		var y: float = mid - sign * rects[2].size.y * 0.5 * lab.ROLL_MAX_DEG / lim
		draw_dashed_line(Vector2(rects[2].position.x, y), Vector2(rects[2].end.x, y), Color(1, 1, 1, 0.2), 1.0, 4.0 * s)
	_plot(lab.roll_hist, rects[2], -lim, lim, Color(1.0, 0.6, 1.0), 1.6 * s)


func _graph_frame(font: Font, s: float, rect: Rect2, title: String) -> void:
	draw_string(font, rect.position - Vector2(0, 4 * s), title, HORIZONTAL_ALIGNMENT_LEFT, -1, int(12 * s), DIM)
	draw_rect(rect, Color(1, 1, 1, 0.15), false, 1.0)


func _plot(buf: PackedFloat32Array, rect: Rect2, min_v: float, max_v: float, col: Color, width: float) -> void:
	var n := buf.size()
	var pts := PackedVector2Array()
	pts.resize(n)
	for k in n:
		var v := clampf((buf[(lab.hist_head + k) % n] - min_v) / (max_v - min_v), 0.0, 1.0)
		pts[k] = rect.position + Vector2(rect.size.x * k / (n - 1), rect.size.y * (1.0 - v))
	draw_polyline(pts, col, width, true)


func _draw_status(font: Font, s: float, fs: int) -> void:
	var lines := [
		"MOVE [M]: %s   %s" % [LabPlayer.MOVE_NAMES[lab.player.move], LabPlayer.MOVE_FORMULAS[lab.player.move]],
		"TICK [F]: %d Hz%s   AUTOPILOT [P]: %s" % [lab.tick_hz,
				"  (per-frame formulas now run 2x faster!)" if lab.tick_hz == 60 else "",
				"ON" if lab.autopilot else "OFF"],
		"ROLL [T]: %s   target = turn*%.0f deg;  w += (-K(r-target) - Cw)dt;  r += w dt   K = %.0f [K/L]  zeta = %.2f [B/N]" % [
				"ON" if lab.roll_enabled else "OFF", lab.ROLL_MAX_DEG, lab.roll_k, lab.roll_zeta],
		"WASD/Arrows move  Space jump  1-6 formula  Q/click select view  Tab single/quad",
		"Z/X main param  C/V spring zeta  R reset  G hide overlay  Esc menu",
	]
	var h := lines.size() * 17.0 * s + 10 * s
	var w := 700.0 * s
	var p := Vector2(10 * s, size.y - h - 10 * s)
	draw_rect(Rect2(p, Vector2(w, h)), BG)
	var y := p.y + 17 * s
	for j in lines.size():
		draw_string(font, Vector2(p.x + 8 * s, y), lines[j], HORIZONTAL_ALIGNMENT_LEFT, w - 12 * s,
				fs, TEXT if j < 3 else DIM)
		y += 17 * s
