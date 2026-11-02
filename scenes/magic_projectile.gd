extends Node3D

@export var speed: float = 4.5
@export var lifetime: float = 4.0
@export var radius: float = 0.18
var direction := Vector3.FORWARD
var caster_id := 0
var active := false
var age := 0.0
var excluded: Array[RID] = []
var sphere := SphereShape3D.new()

func launch(origin: Vector3, target: Vector3, caster: CharacterBody3D, shot_speed: float) -> void:
	global_position = origin
	reset_physics_interpolation()
	direction = (target - origin).normalized()
	speed = shot_speed
	caster_id = caster.get_instance_id()
	excluded = [caster.get_rid()]
	sphere.radius = radius
	active = true

func _physics_process(delta: float) -> void:
	if not active:
		return
	age += delta
	if age >= lifetime:
		cancel()
		return
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, global_position)
	query.collision_mask = 3 # Terrain (including the closed gate) and Player.
	query.collide_with_areas = false
	query.exclude = excluded
	query.margin = 0.001
	# cast_motion alone ignores objects already overlapping the starting shape.
	var overlaps := space.intersect_shape(query, 8)
	if not overlaps.is_empty():
		impact(overlaps)
		return
	var motion := direction * speed * delta
	query.motion = motion
	var fractions := space.cast_motion(query)
	if fractions[0] < 1.0:
		var start := global_position
		global_position = start + motion * fractions[0]
		# Query just inside the earliest contact, not at the end of the step.
		var epsilon := 0.0005 / maxf(motion.length(), 0.0005)
		query.transform.origin = start + motion * minf(fractions[1] + epsilon, 1.0)
		query.motion = Vector3.ZERO
		var hits := space.intersect_shape(query, 8)
		impact(hits)
		return
	global_position += motion
	$Core.rotation.z += delta * 8.0

func impact(hits: Array) -> void:
	if not active:
		return
	active = false
	hide()
	queue_free()
	# A wall at the first contact wins over a player touching its other side.
	for hit in hits:
		if not hit.collider.is_in_group("Player"):
			return
	for hit in hits:
		if hit.collider.is_in_group("Player") and not hit.collider.is_dead:
			hit.collider.hit()
			return

func cancel() -> void:
	active = false
	hide()
	queue_free()
