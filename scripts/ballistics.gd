extends RefCounted
## Flight of a pollen through the air: gravity, drag, and the Magnus force from its spin.
## Shared by the real balls (scripts/pollen.gd), the aim preview and the automatic hood, so all three agree.

const G := 9.8

## Acceleration (m/s^2) of a ball moving at `vel` with spin `spin` (rad/s, world axis), besides gravity.
## k_drag and k_lift are 0.5 * air density * frontal area / mass, times the drag coefficient / 1.
static func air_accel(vel: Vector3, spin: Vector3, radius: float, k_drag: float, k_area: float, lift_max: float) -> Vector3:
	var speed := vel.length()
	if speed < 0.05:
		return Vector3.ZERO
	var a := -k_drag * speed * vel
	var w := spin.length()
	if w > 0.01:
		# Lift coefficient grows with the spin ratio (surface speed / flight speed) up to a cap.
		var lift := minf(radius * w / speed, lift_max)
		var dir := spin.cross(vel)
		if dir.length() > 1e-6:
			a += k_area * lift * speed * speed * dir.normalized()
	return a

## Step a shot forward until it has travelled `dist` metres horizontally (or hits the floor / times out).
## Returns [height at that distance, vertical speed there, reached: bool].
static func height_at(start: Vector3, vel: Vector3, spin: Vector3, dist: float, radius: float, k_drag: float, k_area: float, lift_max: float) -> Array:
	var p := start
	var v := vel
	var dt := 0.01
	var flat0 := Vector2(start.x, start.z)
	for i in 400:
		var a := Vector3(0, -G, 0) + air_accel(v, spin, radius, k_drag, k_area, lift_max)
		var v2 := v + a * dt
		var p2 := p + (v + v2) * 0.5 * dt
		var d2 := Vector2(p2.x, p2.z).distance_to(flat0)
		if d2 >= dist:
			var d1 := Vector2(p.x, p.z).distance_to(flat0)
			var t := (dist - d1) / maxf(d2 - d1, 1e-6)
			return [lerpf(p.y, p2.y, t), lerpf(v.y, v2.y, t), true]
		if p2.y < 0.0:
			return [0.0, v2.y, false]
		p = p2
		v = v2
	return [p.y, v.y, false]
