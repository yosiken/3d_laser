extends Node3D
## Entry point: builds the scene in code and handles lock-on / fire input.

const CurlNoise = preload("res://scripts/curl_noise.gd")
const EnemyScript = preload("res://scripts/enemy.gd")
const LaserSystem = preload("res://scripts/laser_system.gd")
const Hud = preload("res://scripts/hud.gd")

const ENEMY_COUNT := 22
const MAX_LOCKS := 24
const MAX_LOCKS_PER_ENEMY := 4
const LOCK_RADIUS := 70.0
const RELOCK_INTERVAL := 0.12
const FIRE_INTERVAL := 0.03
const AUTO_IDLE_DELAY := 3.0

const ENEMY_AREA_CENTER := Vector3(0, 2, -38)
const ENEMY_AREA_EXTENTS := Vector3(24, 11, 14)

const LASER_COLORS: Array[Color] = [
	Color(0.2, 0.8, 1.0),
	Color(0.4, 0.5, 1.0),
	Color(0.9, 0.3, 1.0),
	Color(0.2, 1.0, 0.7),
]

var curl := CurlNoise.new(7, 0.07)
var camera: Camera3D
var ship: Node3D
var lasers: LaserSystem
var hud: Hud
var enemies: Array[Node3D] = []

## Enemies in lock order; an enemy appears once per lock on it.
var locks: Array[Node3D] = []
var aiming := false
var cursor := Vector2.ZERO
var score := 0
var time := 0.0
var auto_mode := true
var curl_enabled := true

var _relock_at := {}
var _fire_queue: Array[Node3D] = []
var _fire_timer := 0.0
var _idle := AUTO_IDLE_DELAY
var _auto_active := false
var _auto_targets: Array[Node3D] = []
var _auto_wait := 1.0
var _auto_dwell := 0.0
var _spark_mesh: QuadMesh
var _cam_base: Transform3D


func _ready() -> void:
	randomize()
	cursor = get_viewport().get_visible_rect().size * 0.5
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_build_environment()
	_build_camera_and_ship()
	_build_grid()
	_build_starfield()
	_build_spark_mesh()

	lasers = LaserSystem.new()
	lasers.curl = curl
	lasers.camera = camera
	lasers.laser_hit.connect(_on_laser_hit)
	add_child(lasers)

	var palette := [Color(1.0, 0.35, 0.2), Color(1.0, 0.7, 0.15), Color(1.0, 0.2, 0.5)]
	for i in ENEMY_COUNT:
		var e: Node3D = EnemyScript.new()
		e.curl = curl
		e.area_center = ENEMY_AREA_CENTER
		e.area_extents = ENEMY_AREA_EXTENTS
		e.base_color = palette[i % palette.size()]
		e.position = ENEMY_AREA_CENTER + Vector3(
			randf_range(-1, 1) * ENEMY_AREA_EXTENTS.x,
			randf_range(-1, 1) * ENEMY_AREA_EXTENTS.y,
			randf_range(-1, 1) * ENEMY_AREA_EXTENTS.z) * 0.8
		add_child(e)
		enemies.append(e)

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	hud.main = self
	layer.add_child(hud)


func ui_scale() -> float:
	return get_viewport().get_visible_rect().size.y / 720.0


# --------------------------------------------------------------------------
# Input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		cursor = event.position
		_user_activity()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		cursor = event.position
		_user_activity()
		if event.pressed:
			_begin_aim()
		else:
			_release()
	elif event is InputEventKey and not event.echo:
		match event.keycode:
			KEY_SPACE:
				_user_activity()
				if event.pressed:
					_begin_aim()
				else:
					_release()
			KEY_A:
				if event.pressed:
					auto_mode = not auto_mode
			KEY_C:
				if event.pressed:
					curl_enabled = not curl_enabled
					lasers.curl_enabled = curl_enabled


func _user_activity() -> void:
	_idle = 0.0
	if _auto_active:
		# The user took over: drop the auto sequence.
		_auto_active = false
		aiming = false
		locks.clear()


func _begin_aim() -> void:
	aiming = true
	locks.clear()
	_relock_at.clear()


func _release() -> void:
	if not aiming:
		return
	aiming = false
	for e in locks:
		e.pending += 1
		_fire_queue.append(e)
	locks.clear()
	_relock_at.clear()


# --------------------------------------------------------------------------
# Frame update

func _process(delta: float) -> void:
	time += delta
	_idle += delta

	if auto_mode and not aiming and not _auto_active and _idle > AUTO_IDLE_DELAY:
		_auto_wait -= delta
		if _auto_wait <= 0.0:
			_start_auto()
	if _auto_active:
		_update_auto(delta)

	if aiming:
		_try_lock()

	_fire_timer -= delta
	while not _fire_queue.is_empty() and _fire_timer <= 0.0:
		var e: Node3D = _fire_queue.pop_front()
		var from := ship.global_position + ship.global_transform.basis * Vector3(randf_range(-0.8, 0.8), 0.3, -0.5)
		lasers.spawn(from, e, LASER_COLORS.pick_random())
		_fire_timer += FIRE_INTERVAL
	if _fire_queue.is_empty():
		_fire_timer = maxf(_fire_timer, 0.0)

	_update_camera(delta)


func _try_lock() -> void:
	var r := LOCK_RADIUS * ui_scale()
	for e in enemies:
		if locks.size() >= MAX_LOCKS:
			return
		if not e.lockable() or camera.is_position_behind(e.global_position):
			continue
		if camera.unproject_position(e.global_position).distance_to(cursor) > r:
			continue
		if locks.count(e) >= MAX_LOCKS_PER_ENEMY or _relock_at.get(e, 0.0) > time:
			continue
		locks.append(e)
		_relock_at[e] = time + RELOCK_INTERVAL
		e.on_locked()


func _update_camera(delta: float) -> void:
	# Parallax: camera and ship lean toward the cursor.
	var vp := get_viewport().get_visible_rect().size
	var n := (cursor / vp - Vector2(0.5, 0.5)) * 2.0
	var target := _cam_base.rotated_local(Vector3.UP, -n.x * 0.08).rotated_local(Vector3.RIGHT, -n.y * 0.05)
	target.origin += Vector3(sin(time * 0.4) * 0.3, cos(time * 0.3) * 0.2, 0)
	camera.transform = camera.transform.interpolate_with(target, 1.0 - exp(-delta * 4.0))

	var ship_target := Vector3(n.x * 2.5, -1.2 - n.y * 0.8, 1.5)
	ship.position = ship.position.lerp(ship_target, 1.0 - exp(-delta * 5.0))
	ship.rotation = Vector3(-n.y * 0.2, 0, -n.x * 0.4 + sin(time * 1.3) * 0.05)


# --------------------------------------------------------------------------
# Auto demo: sweep the reticle across a handful of targets, then fire.

func _start_auto() -> void:
	var candidates: Array[Node3D] = []
	for e in enemies:
		if e.lockable() and not camera.is_position_behind(e.global_position):
			candidates.append(e)
	if candidates.is_empty():
		_auto_wait = 0.5
		return
	candidates.shuffle()
	# Sort by screen x so the sweep looks natural.
	_auto_targets = candidates.slice(0, randi_range(5, 12))
	var left_to_right := randf() < 0.5
	_auto_targets.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		var ax := camera.unproject_position(a.global_position).x
		var bx := camera.unproject_position(b.global_position).x
		return ax < bx if left_to_right else ax > bx)
	_auto_active = true
	_auto_dwell = 0.0
	_begin_aim()


func _update_auto(delta: float) -> void:
	while not _auto_targets.is_empty() and not _auto_targets[0].lockable():
		_auto_targets.pop_front()
	if _auto_targets.is_empty() or locks.size() >= MAX_LOCKS:
		_auto_active = false
		_release()
		_auto_wait = randf_range(1.2, 2.2)
		return
	var goal := camera.unproject_position(_auto_targets[0].global_position)
	cursor = cursor.lerp(goal, 1.0 - exp(-delta * 14.0))
	if cursor.distance_to(goal) < LOCK_RADIUS * ui_scale() * 0.5:
		_auto_dwell += delta
		if _auto_dwell > randf_range(0.15, 0.4):
			_auto_dwell = 0.0
			_auto_targets.pop_front()


# --------------------------------------------------------------------------
# Hits and effects

func _on_laser_hit(target: Node3D, pos: Vector3, color: Color) -> void:
	_spawn_burst(pos, color.lerp(Color.WHITE, 0.3), 10, 0.3, 7.0, 0.18)
	if is_instance_valid(target) and target.alive and target.take_hit():
		var col: Color = target.base_color
		_spawn_burst(pos, col, 70, 0.9, 20.0, 0.35)
		_spawn_burst(pos, Color(1, 1, 1), 20, 0.5, 10.0, 0.25)
		_spawn_shockwave(pos, col)
		score += 100 * (1 + _count_recent_kills())


var _recent_kills: Array[float] = []

func _count_recent_kills() -> int:
	_recent_kills.append(time)
	_recent_kills = _recent_kills.filter(func(k: float) -> bool: return time - k < 1.0)
	return _recent_kills.size() - 1


func _spawn_burst(pos: Vector3, color: Color, amount: int, lifetime: float, speed: float, size: float) -> void:
	var p := CPUParticles3D.new()
	p.mesh = _spark_mesh
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 180.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = speed * 0.3
	p.initial_velocity_max = speed
	p.damping_min = speed * 0.8
	p.damping_max = speed * 1.6
	p.scale_amount_min = size * 0.5
	p.scale_amount_max = size
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(color, 0.0))
	grad.add_point(0.25, color)
	p.color_ramp = grad
	p.emitting = false
	p.position = pos  # parent is at the origin; set before entering the tree
	add_child(p)
	p.restart()
	get_tree().create_timer(lifetime + 0.3).timeout.connect(p.queue_free)


func _spawn_shockwave(pos: Vector3, color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(color, 0.8)
	mat.disable_fog = true
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.9
	mesh.outer_radius = 1.0
	mesh.rings = 48
	mesh.ring_segments = 4
	var ring := MeshInstance3D.new()
	ring.mesh = mesh
	ring.material_override = mat
	add_child(ring)
	ring.global_position = pos
	ring.look_at(camera.global_position, Vector3.UP)
	ring.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	ring.scale = Vector3.ONE * 0.3
	var tw := create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3.ONE * 5.0, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.5)
	tw.chain().tween_callback(ring.queue_free)


# --------------------------------------------------------------------------
# Scene construction

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.012, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.3, 0.5)
	env.ambient_light_energy = 0.6
	env.glow_enabled = true
	env.glow_intensity = 1.0
	env.glow_bloom = 0.15
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.fog_enabled = true
	env.fog_light_color = Color(0.03, 0.04, 0.1)
	env.fog_density = 0.012
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.light_color = Color(0.8, 0.85, 1.0)
	sun.light_energy = 1.2
	add_child(sun)


func _build_camera_and_ship() -> void:
	camera = Camera3D.new()
	camera.fov = 70.0
	camera.far = 400.0
	add_child(camera)
	camera.position = Vector3(0, 1.5, 8)
	camera.look_at(Vector3(0, 1.5, -30), Vector3.UP)
	_cam_base = camera.transform

	ship = Node3D.new()
	add_child(ship)
	ship.position = Vector3(0, -1.2, 1.5)

	var hull_mat := StandardMaterial3D.new()
	hull_mat.albedo_color = Color(0.6, 0.7, 0.85)
	hull_mat.metallic = 0.8
	hull_mat.roughness = 0.3
	var hull_mesh := PrismMesh.new()
	hull_mesh.size = Vector3(1.6, 2.6, 0.35)
	var hull := MeshInstance3D.new()
	hull.mesh = hull_mesh
	hull.material_override = hull_mat
	hull.rotation_degrees = Vector3(-90, 0, 0)
	ship.add_child(hull)

	var engine_mat := StandardMaterial3D.new()
	engine_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	engine_mat.albedo_color = Color(0.4, 0.9, 1.0)
	var engine_mesh := SphereMesh.new()
	engine_mesh.radius = 0.18
	engine_mesh.height = 0.36
	for x in [-0.4, 0.4]:
		var eng := MeshInstance3D.new()
		eng.mesh = engine_mesh
		eng.material_override = engine_mat
		eng.position = Vector3(x, 0, 1.2)
		ship.add_child(eng)


func _build_grid() -> void:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;
uniform vec3 grid_color : source_color = vec3(0.15, 0.35, 1.0);
uniform float cell = 4.0;
uniform float speed = 10.0;
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 g = vec2(wpos.x, wpos.z + TIME * speed) / cell;
	vec2 f = abs(fract(g - 0.5) - 0.5) / fwidth(g);
	float line = 1.0 - min(min(f.x, f.y), 1.0);
	float fade = exp(-abs(wpos.z + 20.0) * 0.025) * smoothstep(90.0, 30.0, abs(wpos.x));
	ALBEDO = grid_color * line * fade;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var plane := PlaneMesh.new()
	plane.size = Vector2(240, 240)
	var floor_mi := MeshInstance3D.new()
	floor_mi.mesh = plane
	floor_mi.material_override = mat
	floor_mi.position = Vector3(0, -12, -60)
	add_child(floor_mi)


func _build_starfield() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.disable_fog = true
	var quad := QuadMesh.new()
	quad.size = Vector2(0.12, 0.12)
	quad.material = mat

	var stars := CPUParticles3D.new()
	stars.mesh = quad
	stars.amount = 500
	stars.lifetime = 4.0
	stars.preprocess = 4.0
	stars.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	stars.emission_box_extents = Vector3(80, 40, 10)
	stars.direction = Vector3(0, 0, 1)
	stars.spread = 0.0
	stars.gravity = Vector3.ZERO
	stars.initial_velocity_min = 25.0
	stars.initial_velocity_max = 45.0
	stars.color = Color(0.6, 0.75, 1.0, 0.8)
	stars.position = Vector3(0, 0, -120)
	add_child(stars)


func _build_spark_mesh() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.disable_fog = true
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	grad.add_point(0.35, Color(1, 1, 1, 0.5))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	mat.albedo_texture = tex
	_spark_mesh = QuadMesh.new()
	_spark_mesh.size = Vector2.ONE
	_spark_mesh.material = mat
