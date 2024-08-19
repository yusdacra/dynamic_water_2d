@tool

extends Node2D
class_name DynamicWater2D

## controls which node to use for pulling the top left corner of the water from.
@export var top_left_marker: Node2D
## controls which node to use for pulling the bottom right corner of the water from.
@export var bottom_right_marker: Node2D

@export_group("visuals")
## controls the thickness of the surface water.
@export var surface_thickness: float = 6.0
## controls the color of the water on the surface.
@export var surface_color: Color = Color("2c998e66")
## controls the color of the water below the surface.
@export var water_color: Color = Color("87e0d733")

@export_group("waves")
## enables or disables passive waves.
@export var waves_enabled: bool = true
## controls how high the passive waves are.
@export var wave_height: float = 4.0
## controls how quick the passive waves are.
@export var wave_speed: float = 4.0
## controls how wide the passive waves are.
@export var wave_width: float = 16.0
## controls how many times forces should be calculated between neighbouring points per frame.
## higher values means waves travel faster.
@export var wave_spread_amount: int = 4

@export_group("points")
## controls how many surface points are created per nth unit of distance.
## this is basically the "resolution" of the surface water.
@export_range(2, 32, 2) var point_per_distance: int = 8
## controls the damping that will be applied to all points each frame.
## lower value will cause motion to die out quicker.
@export_range(0.0, 1.0) var point_damping = 0.98
## controls the stiffness between a point and it's resting y pos.
@export var point_independent_stiffness: float = 1.0
## controls the stiffness between neighbouring points.
## higher values mean motion is transferred between points quicker.
@export var point_neighbouring_stiffness: float = 2.0

var top_left_point: Vector2
var top_right_point: Vector2
var bottom_right_point: Vector2
var bottom_left_point: Vector2
var extents_valid: bool = false

var points_positions: PackedVector2Array = PackedVector2Array([])
var points_motions: PackedVector2Array = PackedVector2Array([])

func point_add(pos: Vector2) -> void:
	points_positions.append(pos)
	points_motions.append(Vector2.ZERO)

func points_size() -> int:
	return points_positions.size()

func points_clear() -> void:
	points_positions.clear()
	points_motions.clear()

func point_global_pos(point_idx: int) -> Vector2:
	return position + points_positions[point_idx]

## add some motion (force) to a given point.
func point_add_motion(point_idx: int, d: Vector2) -> Vector2:
	var motion := points_motions[point_idx]; motion += d
	points_motions[point_idx] = motion
	return d

func _point_calc_motion(point_idx: int, target_y: float, stiffness: float) -> void:
	var target_point := Vector2(point_global_pos(point_idx).x, target_y)
	var motion := (target_point - point_global_pos(point_idx)) * stiffness
	points_motions[point_idx] += motion

func _point_calc_physics(point_idx: int, delta: float) -> void:
	var motion := points_motions[point_idx]
	var pos := points_positions[point_idx]
	pos += motion * delta
	motion *= point_damping
	points_motions[point_idx] = motion
	points_positions[point_idx] = pos

func _points_get_circle(origin: Vector2, radius: float) -> Array[int]:
	var results: Array[int] = []
	# convert global coords to local coords
	var local_pos := to_local(origin)
	# find the furthest positions that could be affected to the left and right
	var left_most := local_pos.x - radius
	var right_most := local_pos.x + radius
	# convert those local positions to indices in the "points" array
	var left_most_index := _get_index_from_local_pos(left_most)
	var right_most_index := _get_index_from_local_pos(right_most)
	# test which points are in the circle provided
	for idx in range(left_most_index, right_most_index + 1):
		var point_pos := points_positions[idx]
		var dx := absf(point_pos.x - origin.x)
		var dy := absf(point_pos.y - origin.y)
		if dx + dy <= radius:
			results.append(idx); continue
		if dx ** 2 + dy ** 2 <= radius ** 2:
			results.append(idx); continue
	return results


func _ready() -> void:
	calc_extents()
	calc_surface_points()


## calculates the extents of the water.
func calc_extents() -> void:
	top_left_point = top_left_marker.position
	bottom_right_point = bottom_right_marker.position
	extents_valid = _validate_extents()
	if not extents_valid:
		push_error("invalid extents: top left corner cannot be bigger or equal on the X or Y axis than the bottom right corner")
		return
	top_right_point = Vector2(bottom_right_point.x, top_left_point.y)
	bottom_left_point = Vector2(top_left_point.x, bottom_right_point.y)


func _validate_extents() -> bool:
	var is_x_axis_valid := top_left_point.x < bottom_right_point.x
	var is_y_axis_valid := top_left_point.y < bottom_right_point.y
	return is_x_axis_valid and is_y_axis_valid


## calculates surface points.
func calc_surface_points() -> void:
	points_clear()
	if not extents_valid: return
	# populate the points arrays
	var point_amount := int(floor((top_right_point.x - top_left_point.x) / point_per_distance))
	for i in range(point_amount):
		var pos := Vector2(top_left_point.x + (point_per_distance * (i + 0.5)), top_left_point.y)
		point_add(pos)


func _process(delta: float) -> void:
	# update extents and recalculate surface points if any of our size markers change position
	if (not top_left_point.is_equal_approx(top_left_marker.position)
		or not bottom_right_point.is_equal_approx(bottom_right_marker.position)):
		calc_extents()
		calc_surface_points()
	# only process if extents are valid
	if not extents_valid: return
	
	var target_y := global_position.y + top_left_point.y
	var points_len := points_size()
	for idx in range(points_len):
		# calculate motion for point
		_point_calc_motion(idx, target_y, point_independent_stiffness)
		# add the passive wave if enabled
		if waves_enabled:
			var time := fmod(float(Time.get_ticks_msec()) / 1000.0, PI * 2.0)
			point_add_motion(idx, Vector2.UP * sin(((idx / float(points_len)) * wave_width) + (time * wave_speed)) * wave_height)
		# calculate and apply spring forces between neighbouring points
		for j in range(wave_spread_amount):
			var apply_nforce: Callable = func(nidx: int) -> void:
				_point_calc_motion(idx, point_global_pos(nidx).y, point_neighbouring_stiffness)
			# to the left
			if idx - 1 >= 0: apply_nforce.call(idx - 1)
			# to the right
			if idx + 1 < points_len: apply_nforce.call(idx + 1)
	
	# run surface point physics
	for idx in range(points_len):
		_point_calc_physics(idx, delta)
	
	queue_redraw()


## apply some force to provided position.
## will be applied as a circle, all points in the radius will be affected.
func apply_force(pos: Vector2, force: Vector2, radius: float = 16.0) -> void:
	# ignore if position outside of area
	if (point_global_pos(0).x - radius * 2) > pos.x or (point_global_pos(points_size() - 1).x + radius * 2) < pos.x:
		return
	var local_pos := to_local(pos)
	# get points around the pos
	var idxs := _points_get_circle(pos, radius)
	for idx in idxs:
		# direct force to the point
		force *= local_pos.direction_to(points_positions[idx])
		point_add_motion(idx, force)


func _get_index_from_local_pos(x: float) -> int:
	# returns an index of the "points" array on water's surface to the local pos
	var index = floor((abs(top_left_point.x - x) / (top_right_point.x - top_left_point.x)) * points_size())
	# ensure the index is a possible index of the array
	return int(clamp(index, 0, points_size() - 1))


func _draw() -> void:
	if not extents_valid: return
	
	var surface := PackedVector2Array([top_left_point])
	var polygon := PackedVector2Array([top_left_point])
	var colors := PackedColorArray([water_color])
	for idx in range(points_size()):
		surface.append(points_positions[idx])
		polygon.append(points_positions[idx])
		colors.append(water_color)
	
	surface.append(top_right_point)
	
	for p in [top_right_point, bottom_right_point, bottom_left_point]:
		polygon.append(p)
		colors.append(water_color)
	
	draw_polygon(polygon, colors)
	draw_polyline(surface, surface_color, surface_thickness, true)
