extends RefCounted
## Follow-camera state driven by one of several smoothing formulas used in
## mid-90s 3D games (plus two references: a spring-damper and the modern
## frame-rate independent exponential).
##
## The same formula smooths both the camera position and its look-at point.

enum Algo { DIRECT, ASYMPTOTIC, INT_DIVISOR, FIXED_SHIFT, SPRING, EXP_DECAY }

const COUNT := 6

const NAMES: Array[String] = [
	"DIRECT",
	"ASYMPTOTIC (float)",
	"INTEGER DIVISOR",
	"FIXED-POINT SHIFT",
	"SPRING-DAMPER",
	"EXP DECAY (dt-correct)",
]

const ORIGINS: Array[String] = [
	"Quake chase.c: camera snaps to the target",
	"Super Mario 64 approach_f32_asymptotic()",
	"Tomb Raider camera: chase_speed = 12",
	"PS1/Saturn style: 4096 = 1.0, divide by shift",
	"Hooke + damping, semi-implicit Euler",
	"Modern reference, independent of tick rate",
]

## Integer world units per meter for INT_DIVISOR (coarse, like TR's 1024/sector).
const INT_UNITS := 256
## Fixed-point fraction bits for FIXED_SHIFT (PS1 GTE style: 1.0 = 4096).
const FIX_BITS := 12

## Tunable parameters, shared by every camera using the same formula.
static var k := 0.15
static var divisor := 12
static var shift := 3
static var spring_k := 40.0
static var zeta := 0.35
static var lam := 5.0

var algo := Algo.ASYMPTOTIC
var pos := Vector3.ZERO
var look := Vector3.ZERO
var _vel := Vector3.ZERO
var _look_vel := Vector3.ZERO
var _ipos := Vector3i.ZERO
var _ilook := Vector3i.ZERO


static func formula(a: int) -> String:
	match a:
		Algo.DIRECT:
			return "pos = ideal"
		Algo.ASYMPTOTIC:
			return "pos += (ideal - pos) * k        k = %.3f / tick" % k
		Algo.INT_DIVISOR:
			return "pos += (ideal - pos) / n  [int]  n = %d" % divisor
		Algo.FIXED_SHIFT:
			return "pos += (ideal - pos) >> s  [20.12]  s = %d  (1/%d)" % [shift, 1 << shift]
		Algo.SPRING:
			return "v += (-K(x-t) - Cv)dt;  x += v dt   K = %.0f  zeta = %.2f" % [spring_k, zeta]
		Algo.EXP_DECAY:
			return "pos = lerp(pos, ideal, 1 - exp(-L dt))   L = %.1f" % lam
	return ""


## Z/X keys: nudge the main parameter of formula `a`.
static func adjust(a: int, dir: int) -> void:
	match a:
		Algo.ASYMPTOTIC:
			k = clampf(k * (1.25 if dir > 0 else 0.8), 0.01, 1.0)
		Algo.INT_DIVISOR:
			divisor = clampi(divisor + dir, 1, 64)
		Algo.FIXED_SHIFT:
			shift = clampi(shift + dir, 0, 8)
		Algo.SPRING:
			spring_k = clampf(spring_k * (1.25 if dir > 0 else 0.8), 2.0, 600.0)
		Algo.EXP_DECAY:
			lam = clampf(lam * (1.25 if dir > 0 else 0.8), 0.3, 60.0)


## Everything except EXP_DECAY runs once per fixed game tick, like the
## originals did; EXP_DECAY runs every rendered frame with the real delta.
func runs_per_tick() -> bool:
	return algo != Algo.EXP_DECAY


func set_algo(a: int) -> void:
	algo = a
	_vel = Vector3.ZERO
	_look_vel = Vector3.ZERO
	_sync_int()


func snap(ideal_pos: Vector3, ideal_look: Vector3) -> void:
	pos = ideal_pos
	look = ideal_look
	_vel = Vector3.ZERO
	_look_vel = Vector3.ZERO
	_sync_int()


func step(ideal_pos: Vector3, ideal_look: Vector3, dt: float) -> void:
	match algo:
		Algo.DIRECT:
			pos = ideal_pos
			look = ideal_look
		Algo.ASYMPTOTIC:
			pos += (ideal_pos - pos) * k
			look += (ideal_look - look) * k
		Algo.INT_DIVISOR:
			# Integer division truncates toward zero, so the camera stalls up
			# to (n - 1) units short of the target: a typical 90s artifact.
			_ipos += (_to_int(ideal_pos, INT_UNITS) - _ipos) / divisor
			_ilook += (_to_int(ideal_look, INT_UNITS) - _ilook) / divisor
			pos = Vector3(_ipos) / INT_UNITS
			look = Vector3(_ilook) / INT_UNITS
		Algo.FIXED_SHIFT:
			# Arithmetic shift rounds toward -infinity, so the residual error is
			# asymmetric: it settles exactly from one side but not the other.
			_ipos = _add_shifted(_ipos, _to_int(ideal_pos, 1 << FIX_BITS) - _ipos)
			_ilook = _add_shifted(_ilook, _to_int(ideal_look, 1 << FIX_BITS) - _ilook)
			pos = Vector3(_ipos) / float(1 << FIX_BITS)
			look = Vector3(_ilook) / float(1 << FIX_BITS)
		Algo.SPRING:
			var c := 2.0 * zeta * sqrt(spring_k)
			_vel += (-spring_k * (pos - ideal_pos) - c * _vel) * dt
			pos += _vel * dt
			_look_vel += (-spring_k * (look - ideal_look) - c * _look_vel) * dt
			look += _look_vel * dt
		Algo.EXP_DECAY:
			var t := 1.0 - exp(-lam * dt)
			pos = pos.lerp(ideal_pos, t)
			look = look.lerp(ideal_look, t)


func _sync_int() -> void:
	var units := INT_UNITS if algo == Algo.INT_DIVISOR else (1 << FIX_BITS)
	_ipos = _to_int(pos, units)
	_ilook = _to_int(look, units)


static func _to_int(v: Vector3, units: int) -> Vector3i:
	return Vector3i(roundi(v.x * units), roundi(v.y * units), roundi(v.z * units))


func _add_shifted(cur: Vector3i, diff: Vector3i) -> Vector3i:
	return cur + Vector3i(diff.x >> shift, diff.y >> shift, diff.z >> shift)
