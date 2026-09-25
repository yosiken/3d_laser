extends RefCounted
## 3D curl noise.
##
## A vector potential psi = (n1, n2, n3) is built from three independent
## simplex noise fields, and the velocity field is its curl:
##     v = curl(psi) = (dψz/dy - dψy/dz, dψx/dz - dψz/dx, dψy/dx - dψx/dy)
## The result is divergence-free, so particles advected by it swirl
## smoothly without converging to sinks or blowing apart.

var _nx := FastNoiseLite.new()
var _ny := FastNoiseLite.new()
var _nz := FastNoiseLite.new()
var frequency: float
var eps: float

# Offsets decorrelate the three components even if the seeds collide.
const _OFF_Y := Vector3(31.416, -47.853, 12.793)
const _OFF_Z := Vector3(-19.19, 73.07, -55.31)


func _init(seed_value: int = 1, freq: float = 0.08) -> void:
	frequency = freq
	eps = 0.05 / freq  # 5% of a noise cell
	var i := 0
	for n: FastNoiseLite in [_nx, _ny, _nz]:
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.seed = seed_value + i * 1013
		n.frequency = freq
		n.fractal_type = FastNoiseLite.FRACTAL_NONE
		i += 1


func potential(p: Vector3) -> Vector3:
	return Vector3(
		_nx.get_noise_3dv(p),
		_ny.get_noise_3dv(p + _OFF_Y),
		_nz.get_noise_3dv(p + _OFF_Z))


## Returns the curl at p. `t` scrolls the field over time so the flow evolves.
## Output magnitude is roughly O(1) independent of frequency.
func sample(p: Vector3, t: float = 0.0) -> Vector3:
	p += Vector3(t * 0.37, t * 0.21, t * 0.53)
	var dx := Vector3(eps, 0, 0)
	var dy := Vector3(0, eps, 0)
	var dz := Vector3(0, 0, eps)

	var px1 := potential(p + dx)
	var px0 := potential(p - dx)
	var py1 := potential(p + dy)
	var py0 := potential(p - dy)
	var pz1 := potential(p + dz)
	var pz0 := potential(p - dz)

	var curl := Vector3(
		(py1.z - py0.z) - (pz1.y - pz0.y),
		(pz1.x - pz0.x) - (px1.z - px0.z),
		(px1.y - px0.y) - (py1.x - py0.x))
	return curl / (2.0 * eps * frequency)
