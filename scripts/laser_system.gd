extends MeshInstance3D
## Homing lasers whose paths are bent by a curl-noise flow field.
##
## Each laser travels from its launch point to its target in a fixed time.
## Its position is the eased straight-line path plus an "offset" that is
## integrated like a particle: it gets an initial outward kick, is pushed
## around by the curl field, and is damped. The offset is faded out near the
## end of flight so every laser is guaranteed to hit.
##
## All lasers are rendered into one ArrayMesh each frame as camera-facing
## ribbons (a wide glow layer plus a thin hot core) and a flare at the head.

signal laser_hit(target: Node3D, position: Vector3, color: Color)

const CurlNoise = preload("res://scripts/curl_noise.gd")

const TRAIL_LEN := 36
const SUBSTEPS := 3
const CURL_STRENGTH := 50.0
const DAMPING := 2.2
const GLOW_WIDTH := 0.38
const CORE_WIDTH := 0.075
const FLARE_RADIUS := 0.9

var curl: CurlNoise
var camera: Camera3D
## When false, lasers ignore the flow field (for comparison).
var curl_enabled := true

var _lasers: Array[Laser] = []
var _mesh := ArrayMesh.new()
var _time := 0.0

var _verts := PackedVector3Array()
var _colors := PackedColorArray()
var _indices := PackedInt32Array()


class Laser:
	var start: Vector3
	var target: Node3D
	var target_pos: Vector3
	var pos: Vector3
	var offset := Vector3.ZERO
	var offset_vel := Vector3.ZERO
	var t := 0.0
	var duration := 1.0
	var field_shift := Vector3.ZERO
	var trail := PackedVector3Array()
	var color := Color.WHITE
	var arrived := false


func _ready() -> void:
	mesh = _mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.disable_fog = true
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func active_count() -> int:
	return _lasers.size()


func spawn(from: Vector3, target: Node3D, color: Color) -> void:
	var l := Laser.new()
	l.start = from
	l.pos = from
	l.target = target
	l.target_pos = target.global_position
	l.color = color
	var dist := from.distance_to(l.target_pos)
	l.duration = clampf(dist / 40.0, 0.7, 1.5) * randf_range(0.95, 1.35)
	# Kick outward / upward / slightly backward so the volley fans out.
	var kick := Vector3(randf_range(-1.0, 1.0), randf_range(-0.2, 1.0), randf_range(-0.3, 0.5))
	l.offset_vel = kick.normalized() * randf_range(14.0, 24.0)
	# Each laser samples a slightly shifted region of the field so they
	# don't all follow the exact same streamline.
	l.field_shift = Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4))
	l.trail.append(from)
	_lasers.append(l)


func _process(delta: float) -> void:
	_time += delta
	var h := delta / SUBSTEPS

	for l in _lasers:
		if l.arrived:
			# Let the tail catch up with the head.
			var drop := maxi(1, int(TRAIL_LEN * delta * 5.0))
			l.trail = l.trail.slice(mini(drop, l.trail.size()))
			continue

		if is_instance_valid(l.target) and l.target.alive:
			l.target_pos = l.target.global_position

		for s in SUBSTEPS:
			l.t += h
			var u := minf(l.t / l.duration, 1.0)
			var force := curl.sample(l.pos + l.field_shift, _time) if curl_enabled else Vector3.ZERO
			l.offset_vel += force * CURL_STRENGTH * h
			l.offset_vel -= l.offset_vel * DAMPING * h
			l.offset += l.offset_vel * h

			var envelope := 1.0 - smoothstep(0.45, 1.0, u)
			var base := l.start.lerp(l.target_pos, pow(u, 1.7))
			l.pos = base + l.offset * envelope
			l.trail.append(l.pos)

			if u >= 1.0:
				l.arrived = true
				laser_hit.emit(l.target, l.target_pos, l.color)
				break

		if l.trail.size() > TRAIL_LEN:
			l.trail = l.trail.slice(l.trail.size() - TRAIL_LEN)

	_lasers = _lasers.filter(func(l: Laser) -> bool: return not l.arrived or l.trail.size() >= 2)
	_rebuild_mesh()


func _rebuild_mesh() -> void:
	_mesh.clear_surfaces()
	_verts.clear()
	_colors.clear()
	_indices.clear()
	if _lasers.is_empty() or camera == null:
		return

	var cam_pos := camera.global_position
	var cam_basis := camera.global_transform.basis

	for l in _lasers:
		if l.trail.size() < 2:
			continue
		var glow := l.color
		glow.a = 0.45
		_add_ribbon(l.trail, cam_pos, GLOW_WIDTH, glow, 1.6)
		var core := l.color.lerp(Color.WHITE, 0.75)
		core.a = 1.0
		_add_ribbon(l.trail, cam_pos, CORE_WIDTH, core, 1.0)
		if not l.arrived:
			_add_flare(l.pos, cam_basis, FLARE_RADIUS, l.color)

	if _verts.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_INDEX] = _indices
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


## Camera-facing strip; tail (index 0) is thin and transparent, head is full.
func _add_ribbon(pts: PackedVector3Array, cam_pos: Vector3, width: float, color: Color, fade_pow: float) -> void:
	var n := pts.size()
	var first := _verts.size()
	for i in n:
		var p := pts[i]
		var tangent := pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]
		var side := tangent.cross(cam_pos - p)
		if side.length_squared() < 1e-10:
			side = Vector3.UP
		side = side.normalized()
		var k := float(i) / float(n - 1)
		var w := width * (0.2 + 0.8 * k)
		var c := color
		c.a *= pow(k, fade_pow)
		_verts.append(p + side * w)
		_verts.append(p - side * w)
		_colors.append(c)
		_colors.append(c)
	for i in n - 1:
		var a := first + i * 2
		_indices.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])


## Radial glow made of a triangle fan: bright center, transparent rim.
func _add_flare(p: Vector3, cam_basis: Basis, radius: float, color: Color) -> void:
	const SEG := 10
	var center := _verts.size()
	_verts.append(p)
	_colors.append(Color(1, 1, 1, 1))
	var rim := color
	rim.a = 0.0
	var right := cam_basis.x
	var up := cam_basis.y
	for i in SEG:
		var ang := TAU * i / SEG
		_verts.append(p + (right * cos(ang) + up * sin(ang)) * radius)
		_colors.append(rim)
	for i in SEG:
		_indices.append_array([center, center + 1 + i, center + 1 + (i + 1) % SEG])
