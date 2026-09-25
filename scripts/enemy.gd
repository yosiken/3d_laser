extends Node3D
## A floating target that drifts along the curl-noise flow field.

const CurlNoise = preload("res://scripts/curl_noise.gd")

var curl: CurlNoise
var area_center := Vector3.ZERO
var area_extents := Vector3.ONE
var base_color := Color(1.0, 0.35, 0.2)

var alive := true
## Lasers currently flying toward this enemy.
var pending := 0
var velocity := Vector3.ZERO

var _flash := 0.0
var _appear := 1.0
var _respawn_timer := 0.0
var _spin_axis := Vector3.UP
var _spin_speed := 1.0
var _body_mat: StandardMaterial3D
var _ring: MeshInstance3D
var _age := 0.0


func _ready() -> void:
	_spin_axis = Vector3(randf_range(-1, 1), 1.0, randf_range(-1, 1)).normalized()
	_spin_speed = randf_range(0.8, 2.2)
	_age = randf() * 100.0

	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = base_color.darkened(0.6)
	_body_mat.emission_enabled = true
	_body_mat.emission = base_color
	_body_mat.emission_energy_multiplier = 1.2
	_body_mat.metallic = 0.6
	_body_mat.roughness = 0.35

	# Octahedron (a 4-sided sphere with 2 rings).
	var body_mesh := SphereMesh.new()
	body_mesh.radius = 0.9
	body_mesh.height = 2.2
	body_mesh.radial_segments = 4
	body_mesh.rings = 2
	var body := MeshInstance3D.new()
	body.mesh = body_mesh
	body.material_override = _body_mat
	add_child(body)

	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = base_color.lightened(0.3)
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 1.25
	ring_mesh.outer_radius = 1.38
	ring_mesh.rings = 32
	ring_mesh.ring_segments = 6
	_ring = MeshInstance3D.new()
	_ring.mesh = ring_mesh
	_ring.material_override = ring_mat
	add_child(_ring)


func _process(delta: float) -> void:
	if not alive:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_respawn()
		return

	_age += delta
	# Follow the flow field, with a soft spring that keeps us in the play area.
	var flow := curl.sample(position * 0.6, _age * 0.2) * 7.0
	var d := (position - area_center) / area_extents
	var home := Vector3.ZERO
	if d.length() > 0.7:
		home = -d.normalized() * (d.length() - 0.7) * 25.0
	var desired := flow + home
	velocity = velocity.lerp(desired, 1.0 - exp(-delta * 1.2))
	position += velocity * delta

	rotate(_spin_axis, delta * _spin_speed)
	_ring.rotate_object_local(Vector3.RIGHT, delta * 3.0)

	_flash = maxf(_flash - delta * 4.0, 0.0)
	_body_mat.emission_energy_multiplier = 1.2 + _flash * 8.0
	_appear = minf(_appear + delta * 2.0, 1.0)
	var s := ease(_appear, 0.4) * (1.0 + _flash * 0.35)
	scale = Vector3.ONE * maxf(s, 0.001)


func lockable() -> bool:
	return alive and pending == 0 and _appear > 0.6


func on_locked() -> void:
	_flash = 1.0


## Called when a laser reaches us. Returns true when this hit destroyed us.
func take_hit() -> bool:
	pending = maxi(pending - 1, 0)
	_flash = 1.0
	if pending == 0 and alive:
		alive = false
		visible = false
		_respawn_timer = randf_range(1.0, 2.5)
		return true
	return false


func _respawn() -> void:
	position = area_center + Vector3(
		randf_range(-1, 1) * area_extents.x,
		randf_range(-1, 1) * area_extents.y,
		-area_extents.z * randf_range(0.6, 1.0))
	velocity = Vector3.ZERO
	pending = 0
	alive = true
	visible = true
	_appear = 0.0
