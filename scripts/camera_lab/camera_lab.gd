extends Node3D
## Camera / spring / momentum comparison lab.
##
## Up to four follow cameras watch the same character, each driven by a
## different formula, so their lag, overshoot and integer artifacts can be
## compared side by side. Game logic runs on a fixed tick (30 Hz by default,
## like most 1996 console games); toggling 60 Hz shows which formulas were
## frame-rate dependent.

const FollowCam = preload("res://scripts/camera_lab/follow_cam.gd")
const LabPlayer = preload("res://scripts/camera_lab/lab_player.gd")
const LabHud = preload("res://scripts/camera_lab/lab_hud.gd")

const SLOT_COLORS: Array[Color] = [
	Color(1.0, 0.45, 0.35),
	Color(0.35, 0.85, 1.0),
	Color(1.0, 0.85, 0.3),
	Color(0.6, 1.0, 0.45),
]
const HISTORY := 300
const CAM_BACK := 6.5
const CAM_UP := 3.0
const AUTO_IDLE_DELAY := 3.0
## Camera roll (bank) toward the turn direction at full left/right input.
const ROLL_MAX_DEG := 12.0

var player: LabPlayer
var cams: Array[FollowCam] = []
var cameras: Array[Camera3D] = []
var containers: Array[SubViewportContainer] = []
var viewports: Array[SubViewport] = []
var hud: LabHud

var active_slot := 0
var quad := true
var tick_hz := 30
var time := 0.0
var autopilot := true
var show_overlay := true

## Roll spring (shared by all views): left/right input sets the target angle,
## a damped spring pulls the roll toward it, so tapping a turn key makes the
## camera lean in, overshoot slightly and settle back.
var roll_enabled := true
var roll_k := 60.0
var roll_zeta := 0.3
var roll := 0.0
var _roll_vel := 0.0
var roll_hist := PackedFloat32Array()

## Graph data (ring buffers, newest at _hist_head - 1).
var lag_hist: Array[PackedFloat32Array] = []
var speed_hist := PackedFloat32Array()
var hist_head := 0

var _accum := 0.0
var _idle := AUTO_IDLE_DELAY
var _jump_queued := false
var _waypoint := Vector3.ZERO
var _pause := 0.0
var _auto_jump := false


func _ready() -> void:
	randomize()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_world()

	player = LabPlayer.new()
	add_child(player)

	var views := Control.new()
	views.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	views.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(views)

	var world := get_viewport().find_world_3d()
	var defaults := [FollowCam.Algo.DIRECT, FollowCam.Algo.ASYMPTOTIC,
			FollowCam.Algo.INT_DIVISOR, FollowCam.Algo.SPRING]
	for i in 4:
		var c := SubViewportContainer.new()
		c.stretch = true
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		views.add_child(c)
		var sv := SubViewport.new()
		sv.world_3d = world
		sv.msaa_3d = Viewport.MSAA_2X
		c.add_child(sv)
		var cam3 := Camera3D.new()
		cam3.fov = 65.0
		sv.add_child(cam3)
		var fc := FollowCam.new()
		fc.set_algo(defaults[i])
		cams.append(fc)
		cameras.append(cam3)
		containers.append(c)
		viewports.append(sv)
		var h := PackedFloat32Array()
		h.resize(HISTORY)
		lag_hist.append(h)
	speed_hist.resize(HISTORY)
	roll_hist.resize(HISTORY)

	hud = LabHud.new()
	hud.lab = self
	layer.add_child(hud)

	_reset_cameras()
	get_viewport().size_changed.connect(_layout)
	_layout()
	_pick_waypoint()


# --------------------------------------------------------------------------
# Layout

func slot_rect(i: int) -> Rect2:
	var size := get_viewport().get_visible_rect().size
	if not quad:
		return Rect2(Vector2.ZERO, size)
	var half := (size / 2.0).floor()
	return Rect2(Vector2(i % 2, i / 2) * half, half)


func _layout() -> void:
	for i in 4:
		var show := quad or i == active_slot
		containers[i].visible = show
		viewports[i].render_target_update_mode = (
				SubViewport.UPDATE_ALWAYS if show else SubViewport.UPDATE_DISABLED)
		var r := slot_rect(i)
		containers[i].position = r.position
		containers[i].size = r.size


# --------------------------------------------------------------------------
# Input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if quad:
			for i in 4:
				if slot_rect(i).has_point(event.position):
					active_slot = i
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key: Key = event.keycode
	if key >= KEY_1 and key <= KEY_6:
		cams[active_slot].set_algo(key - KEY_1)
	match key:
		KEY_TAB:
			quad = not quad
			_layout()
		KEY_Q:
			active_slot = (active_slot + 1) % 4
			_layout()
		KEY_Z:
			FollowCam.adjust(cams[active_slot].algo, -1)
		KEY_X:
			FollowCam.adjust(cams[active_slot].algo, 1)
		KEY_C:
			FollowCam.zeta = clampf(FollowCam.zeta - 0.05, 0.0, 2.0)
		KEY_V:
			FollowCam.zeta = clampf(FollowCam.zeta + 0.05, 0.0, 2.0)
		KEY_M:
			player.set_move((player.move + 1) % LabPlayer.MOVE_NAMES.size())
		KEY_F:
			tick_hz = 60 if tick_hz == 30 else 30
		KEY_R:
			_reset_cameras()
		KEY_T:
			roll_enabled = not roll_enabled
		KEY_K:
			roll_k = clampf(roll_k * 0.8, 4.0, 800.0)
		KEY_L:
			roll_k = clampf(roll_k * 1.25, 4.0, 800.0)
		KEY_B:
			roll_zeta = clampf(roll_zeta - 0.05, 0.0, 2.0)
		KEY_N:
			roll_zeta = clampf(roll_zeta + 0.05, 0.0, 2.0)
		KEY_G:
			show_overlay = not show_overlay
		KEY_P:
			autopilot = not autopilot
		KEY_SPACE:
			_jump_queued = true
			_idle = 0.0
		KEY_ESCAPE:
			get_tree().change_scene_to_file("res://menu.tscn")


func _read_manual() -> Vector2:
	var fwd := Input.get_axis(&"ui_down", &"ui_up")
	var turn := Input.get_axis(&"ui_right", &"ui_left")
	if Input.is_physical_key_pressed(KEY_W):
		fwd += 1.0
	if Input.is_physical_key_pressed(KEY_S):
		fwd -= 1.0
	if Input.is_physical_key_pressed(KEY_A):
		turn += 1.0
	if Input.is_physical_key_pressed(KEY_D):
		turn -= 1.0
	return Vector2(clampf(fwd, -1, 1), clampf(turn, -1, 1))


# --------------------------------------------------------------------------
# Simulation

func _process(delta: float) -> void:
	time += delta
	var manual := _read_manual()
	if manual != Vector2.ZERO:
		_idle = 0.0
	else:
		_idle += delta

	_accum += minf(delta, 0.25)
	var dt := 1.0 / tick_hz
	while _accum >= dt:
		_accum -= dt
		_tick(dt, manual)

	# The dt-correct reference runs every rendered frame.
	var ideal := _ideal()
	for fc in cams:
		if not fc.runs_per_tick():
			fc.step(ideal[0], ideal[1], delta)

	for i in 4:
		cameras[i].global_position = cams[i].pos
		if not cams[i].pos.is_equal_approx(cams[i].look):
			cameras[i].look_at(cams[i].look, Vector3.UP)
		# Roll about the view axis (local +Z points back at the viewer).
		cameras[i].rotate_object_local(Vector3.BACK, roll)


func _tick(dt: float, manual: Vector2) -> void:
	var input := manual
	var jump := _jump_queued
	_jump_queued = false
	if autopilot and _idle > AUTO_IDLE_DELAY:
		input = _autopilot(dt)
		jump = _auto_jump
		_auto_jump = false
	player.tick(dt, input.x, input.y, jump)
	_step_roll(dt, input.y)

	var ideal := _ideal()
	for i in 4:
		var fc := cams[i]
		if fc.runs_per_tick():
			fc.step(ideal[0], ideal[1], dt)
		lag_hist[i][hist_head] = fc.pos.distance_to(ideal[0])
	var v := player.velocity
	speed_hist[hist_head] = Vector2(v.x, v.z).length()
	roll_hist[hist_head] = rad_to_deg(roll)
	hist_head = (hist_head + 1) % HISTORY


## Semi-implicit Euler spring-damper on the roll angle:
##   target = turn * ROLL_MAX;  w += (-K (roll - target) - C w) dt;  roll += w dt
## with C = 2 zeta sqrt(K). Uses dt, so it behaves the same at 30 and 60 Hz.
func _step_roll(dt: float, turn: float) -> void:
	var target := deg_to_rad(ROLL_MAX_DEG) * turn if roll_enabled else 0.0
	var c := 2.0 * roll_zeta * sqrt(roll_k)
	_roll_vel += (-roll_k * (roll - target) - c * _roll_vel) * dt
	roll += _roll_vel * dt


## Returns [ideal camera position, ideal look-at point].
func _ideal() -> Array[Vector3]:
	var f := player.forward()
	var p := player.position
	return [p - f * CAM_BACK + Vector3.UP * CAM_UP, p + Vector3.UP * 1.2 + f * 2.0]


func _reset_cameras() -> void:
	var ideal := _ideal()
	for fc in cams:
		fc.snap(ideal[0], ideal[1])
	roll = 0.0
	_roll_vel = 0.0


## Wander between random waypoints, with stops and jumps, so the different
## behaviours (start-up lag, overshoot on stop, sharp turns) keep showing.
func _autopilot(dt: float) -> Vector2:
	if _pause > 0.0:
		_pause -= dt
		return Vector2.ZERO
	var to := _waypoint - player.position
	to.y = 0.0
	if to.length() < 2.5:
		_pause = randf_range(0.6, 1.6) if randf() < 0.6 else 0.0
		_pick_waypoint()
		return Vector2.ZERO
	var f := player.forward()
	var ang := f.signed_angle_to(to.normalized(), Vector3.UP)
	var turn := clampf(ang * 2.5, -1.0, 1.0)
	var fwd := 1.0 if absf(ang) < 1.0 else 0.25
	if randf() < 0.004:
		_auto_jump = true
	return Vector2(fwd, turn)


func _pick_waypoint() -> void:
	var a := randf() * TAU
	var r := randf_range(8.0, LabPlayer.ARENA_RADIUS - 6.0)
	_waypoint = Vector3(cos(a) * r, 0, sin(a) * r)


# --------------------------------------------------------------------------
# World

func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.7, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.65, 0.75)
	env.ambient_light_energy = 0.8
	env.fog_enabled = true
	env.fog_light_color = Color(0.55, 0.7, 0.9)
	env.fog_density = 0.012
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.1
	add_child(sun)

	var shader := Shader.new()
	shader.code = """
shader_type spatial;
uniform vec3 base_a : source_color = vec3(0.32, 0.55, 0.3);
uniform vec3 base_b : source_color = vec3(0.28, 0.5, 0.27);
uniform vec3 line_color : source_color = vec3(0.9, 0.95, 0.85);
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 g = wpos.xz / 2.0;
	vec2 cell = floor(g);
	float checker = mod(cell.x + cell.y, 2.0);
	vec2 f = abs(fract(g - 0.5) - 0.5) / fwidth(g);
	float line = 1.0 - min(min(f.x, f.y), 1.0);
	vec3 col = mix(base_a, base_b, checker);
	ALBEDO = mix(col, line_color, line * 0.35);
	ROUGHNESS = 0.9;
}
"""
	var floor_mat := ShaderMaterial.new()
	floor_mat.shader = shader
	var plane := PlaneMesh.new()
	plane.size = Vector2(140, 140)
	var floor_mi := MeshInstance3D.new()
	floor_mi.mesh = plane
	floor_mi.material_override = floor_mat
	add_child(floor_mi)

	# Pillars and blocks as reference points for judging camera motion.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1996
	var palette := [Color(0.85, 0.85, 0.9), Color(0.9, 0.6, 0.3), Color(0.4, 0.55, 0.95), Color(0.85, 0.4, 0.5)]
	for i in 70:
		var a := rng.randf() * TAU
		var r := rng.randf_range(6.0, 62.0)
		var h := rng.randf_range(0.6, 7.0)
		var w := rng.randf_range(0.6, 2.2)
		var box := BoxMesh.new()
		box.size = Vector3(w, h, w)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = palette[i % palette.size()]
		var mi := MeshInstance3D.new()
		mi.mesh = box
		mi.material_override = mat
		mi.position = Vector3(cos(a) * r, h * 0.5, sin(a) * r)
		mi.rotation.y = rng.randf() * TAU
		add_child(mi)
