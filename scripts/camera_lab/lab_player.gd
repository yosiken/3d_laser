extends Node3D
## Tank-control character whose ground movement uses one of several
## momentum / inertia models. Stepped once per fixed game tick.

enum Move { SM64, QUAKE, NO_INERTIA }

const MOVE_NAMES: Array[String] = ["SM64 walk", "Quake friction+accel", "No inertia"]
const MOVE_FORMULAS: Array[String] = [
	"v += 1.1 - v/43 (per frame), v -= 1 when no input, max 48",
	"drop = max(spd, stop)*fric*dt; add = min(accel*dt*wish, wish - v.dir)",
	"v = input * 8 m/s",
]

## SM64 runs at 30 fps with speeds in units/frame; this maps 32 u/f to ~5.8 m/s.
const SM64_SCALE := 0.006
## Quake: 320 units/s maxspeed -> 8 m/s.
const QUAKE_SCALE := 0.025
const Q_MAXSPEED := 320.0
const Q_ACCEL := 10.0
const Q_FRICTION := 4.0
const Q_STOPSPEED := 100.0

const TURN_SPEED := 2.8
const GRAVITY := 22.0
const JUMP_SPEED := 8.0
const ARENA_RADIUS := 48.0

var move := Move.SM64
var yaw := 0.0
var velocity := Vector3.ZERO  # m/s, horizontal part used for display/graph
var _sm64_v := 0.0            # units/frame
var _q_vel := Vector3.ZERO    # Quake units/s (horizontal)
var _vy := 0.0
var _on_ground := true
var _body: Node3D


func _ready() -> void:
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.95, 0.35, 0.25)
	body_mat.roughness = 0.5
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.45
	capsule.height = 1.6
	_body = Node3D.new()
	add_child(_body)
	var body := MeshInstance3D.new()
	body.mesh = capsule
	body.material_override = body_mat
	body.position.y = 0.8
	_body.add_child(body)

	var nose_mat := StandardMaterial3D.new()
	nose_mat.albedo_color = Color(1, 0.9, 0.3)
	nose_mat.emission_enabled = true
	nose_mat.emission = Color(1, 0.8, 0.2)
	var nose_mesh := BoxMesh.new()
	nose_mesh.size = Vector3(0.3, 0.25, 0.5)
	var nose := MeshInstance3D.new()
	nose.mesh = nose_mesh
	nose.material_override = nose_mat
	nose.position = Vector3(0, 1.15, -0.45)
	_body.add_child(nose)

	# Blob shadow (stays on the ground).
	var shadow_mat := StandardMaterial3D.new()
	shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_mat.albedo_color = Color(0, 0, 0, 0.45)
	var disc := CylinderMesh.new()
	disc.top_radius = 0.55
	disc.bottom_radius = 0.55
	disc.height = 0.01
	var shadow := MeshInstance3D.new()
	shadow.name = "Shadow"
	shadow.mesh = disc
	shadow.material_override = shadow_mat
	add_child(shadow)


func forward() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func set_move(m: int) -> void:
	move = m
	# Carry the current speed over so switching models doesn't jolt.
	_sm64_v = maxf(velocity.dot(forward()), 0.0) / SM64_SCALE / 30.0
	_q_vel = velocity / QUAKE_SCALE


## fwd_in, turn_in in [-1, 1]. `dt` is the tick length; the SM64 model is
## intentionally per-frame, so it moves faster when the tick rate doubles.
func tick(dt: float, fwd_in: float, turn_in: float, jump: bool) -> void:
	yaw += turn_in * TURN_SPEED * dt
	var f := forward()

	match move:
		Move.SM64:
			if fwd_in > 0.1 and _on_ground:
				var target := 32.0 * fwd_in
				if _sm64_v <= 0.0:
					_sm64_v += 1.1
				elif _sm64_v <= target:
					_sm64_v += 1.1 - _sm64_v / 43.0
				else:
					_sm64_v -= 1.0
			elif _on_ground:
				_sm64_v = maxf(_sm64_v - 1.0, 0.0)
			_sm64_v = minf(_sm64_v, 48.0)
			# units/frame -> meters per tick (one frame per tick).
			var step := f * _sm64_v * SM64_SCALE
			position += step
			velocity = step / dt
		Move.QUAKE:
			if _on_ground:
				_q_friction(dt)
				var wishdir := f * signf(fwd_in)
				_q_accelerate(wishdir, Q_MAXSPEED * absf(fwd_in), Q_ACCEL, dt)
			velocity = _q_vel * QUAKE_SCALE
			position += velocity * dt
		Move.NO_INERTIA:
			velocity = f * fwd_in * 8.0
			position += velocity * dt

	if _on_ground and jump:
		_vy = JUMP_SPEED
		_on_ground = false
	if not _on_ground:
		_vy -= GRAVITY * dt
		position.y += _vy * dt
		if position.y <= 0.0:
			position.y = 0.0
			_vy = 0.0
			_on_ground = true

	var flat := Vector2(position.x, position.z)
	if flat.length() > ARENA_RADIUS:
		flat = flat.normalized() * ARENA_RADIUS
		position.x = flat.x
		position.z = flat.y

	_body.rotation.y = yaw
	var shadow: Node3D = get_node("Shadow")
	shadow.global_position = Vector3(position.x, 0.02, position.z)


func _q_friction(dt: float) -> void:
	var speed := _q_vel.length()
	if speed < 1.0:
		_q_vel = Vector3.ZERO
		return
	var control := maxf(speed, Q_STOPSPEED)
	var newspeed := maxf(speed - control * Q_FRICTION * dt, 0.0)
	_q_vel *= newspeed / speed


func _q_accelerate(wishdir: Vector3, wishspeed: float, accel: float, dt: float) -> void:
	if wishspeed <= 0.0:
		return
	var addspeed := wishspeed - _q_vel.dot(wishdir)
	if addspeed <= 0.0:
		return
	var accelspeed := minf(accel * dt * wishspeed, addspeed)
	_q_vel += wishdir * accelspeed
