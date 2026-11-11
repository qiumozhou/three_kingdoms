extends Polygon2D

const GRID_SIZE := 28

var rest_pose := PackedVector2Array()
var step_phase := 0.0


func _ready() -> void:
	var image_size := texture.get_size()
	var texture_points := PackedVector2Array()
	var faces: Array[PackedInt32Array] = []
	for row in range(GRID_SIZE + 1):
		for column in range(GRID_SIZE + 1):
			var point := Vector2(column, row) * image_size / float(GRID_SIZE)
			texture_points.append(point)
			rest_pose.append(point - image_size * 0.5)
	for row in range(GRID_SIZE):
		for column in range(GRID_SIZE):
			var index := row * (GRID_SIZE + 1) + column
			faces.append(PackedInt32Array([
				index, index + 1, index + GRID_SIZE + 2, index + GRID_SIZE + 1
			]))
	polygon = rest_pose
	uv = texture_points
	polygons = faces


func update_pose(delta: float, horizontal_speed: float, grounded: bool) -> void:
	if not is_zero_approx(horizontal_speed):
		scale.x = absf(scale.x) * signf(horizontal_speed)
	if not grounded or absf(horizontal_speed) < 1.0:
		step_phase = 0.0
		polygon = rest_pose
		return

	step_phase = fmod(step_phase + delta * 14.0, TAU)
	var pose := rest_pose.duplicate()
	for index in range(pose.size()):
		var source := uv[index]
		var leg_weight := smoothstep(1020.0, 1220.0, source.y)
		# Each boot follows its own opposite-phase stride. Only the swing foot lifts.
		var left_weight := exp(-pow((source.x - 415.0) / 120.0, 4.0)) * leg_weight
		var right_weight := exp(-pow((source.x - 735.0) / 125.0, 4.0)) * leg_weight
		pose[index] += _foot_offset(step_phase) * left_weight
		pose[index] += _foot_offset(step_phase + PI) * right_weight
		# Torso and robe settle into the planted leg while the other foot passes.
		pose[index].y -= 16.0 * absf(sin(step_phase)) * (1.0 - leg_weight)
	polygon = pose


func _foot_offset(phase: float) -> Vector2:
	return Vector2(115.0 * cos(phase), -110.0 * maxf(0.0, -sin(phase)))
