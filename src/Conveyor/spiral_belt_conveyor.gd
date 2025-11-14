@tool
class_name SpiralBeltConveyor
extends Node3D

signal size_changed

enum ConvTexture {
	STANDARD,
	ALTERNATE
}

const SIZE_DEFAULT: Vector3 = Vector3(2.0, 3.0, 2.0)  # diameter, height, diameter

@export var spiral_radius: float = 1.0:
	set(value):
		spiral_radius = max(0.3, value)
		_mesh_regeneration_needed = true
		_update_calculated_size()
		_update_all_components()

@export var vertical_height: float = 3.0:
	set(value):
		vertical_height = max(0.5, value)
		_mesh_regeneration_needed = true
		_update_calculated_size()
		_update_all_components()

@export var belt_width: float = 0.5:
	set(value):
		belt_width = max(0.1, value)
		_mesh_regeneration_needed = true
		_update_calculated_size()
		_update_all_components()

@export_range(0.5, 10.0, 0.25) var number_of_turns: float = 1.5:
	set(value):
		number_of_turns = clamp(value, 0.5, 10.0)
		_mesh_regeneration_needed = true
		_update_all_components()

@export var clockwise: bool = true:
	set(value):
		clockwise = value
		_mesh_regeneration_needed = true
		_update_all_components()

## Calculated automatically - not directly editable
var size: Vector3:
	get:
		return _calculated_size
	set(_value):
		pass

var _calculated_size: Vector3 = SIZE_DEFAULT

func _update_calculated_size() -> void:
	var outer_diameter = (spiral_radius + belt_width) * 2.0
	var old_size = _calculated_size
	_calculated_size = Vector3(outer_diameter, vertical_height, outer_diameter)
	
	if old_size != _calculated_size:
		size_changed.emit()

@export var belt_color: Color = Color(1, 1, 1, 1):
	set(value):
		belt_color = value
		if _belt_material:
			(_belt_material as ShaderMaterial).set_shader_parameter("ColorMix", belt_color)

@export var belt_texture = ConvTexture.STANDARD:
	set(value):
		belt_texture = value
		if _belt_material:
			(_belt_material as ShaderMaterial).set_shader_parameter("BlackTextureOn", belt_texture == ConvTexture.STANDARD)

@export var speed: float = 2.0:
	set(value):
		if value == speed:
			return
		speed = value
		_update_belt_material_scale()
		if _register_running_tag_ok and _running_tag_group_init:
			OIPComms.write_bit(running_tag_group_name, running_tag_name, value != 0.0)

@export var belt_physics_material: PhysicsMaterial:
	get:
		var sb_node = get_node_or_null("StaticBody3D") as StaticBody3D
		if sb_node:
			return sb_node.physics_material_override
		return null
	set(value):
		var sb_node = get_node_or_null("StaticBody3D") as StaticBody3D
		if sb_node:
			sb_node.physics_material_override = value

var _belt_material: Material
var _metal_material: Material
var belt_position: float = 0.0

@onready var _sb: StaticBody3D = get_node("StaticBody3D")
@onready var spiral_mesh: MeshInstance3D = $MeshInstance3D

var _mesh_regeneration_needed: bool = true
var _last_size: Vector3 = Vector3.ZERO

var _register_speed_tag_ok: bool = false
var _register_running_tag_ok: bool = false
var _speed_tag_group_init: bool = false
var _running_tag_group_init: bool = false
var _speed_tag_group_original: String
var _running_tag_group_original: String
var _enable_comms_changed: bool = false:
	set(value):
		notify_property_list_changed()

@export_category("Communications")
@export var enable_comms := false
@export var speed_tag_group_name: String
@export_custom(0, "tag_group_enum") var speed_tag_groups:
	set(value):
		speed_tag_group_name = value
		speed_tag_groups = value
@export var speed_tag_name := ""
@export var running_tag_group_name: String
@export_custom(0, "tag_group_enum") var running_tag_groups:
	set(value):
		running_tag_group_name = value
		running_tag_groups = value
@export var running_tag_name := ""

func _validate_property(property: Dictionary) -> void:
	if property.name == "enable_comms":
		property.usage = PROPERTY_USAGE_DEFAULT if OIPComms.get_enable_comms() else PROPERTY_USAGE_STORAGE
	elif property.name == "speed_tag_group_name":
		property.usage = PROPERTY_USAGE_STORAGE
	elif property.name == "speed_tag_groups":
		property.usage = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_NO_INSTANCE_STATE if OIPComms.get_enable_comms() else PROPERTY_USAGE_NONE
	elif property.name == "speed_tag_name":
		property.usage = PROPERTY_USAGE_DEFAULT if OIPComms.get_enable_comms() else PROPERTY_USAGE_STORAGE
	elif property.name == "running_tag_group_name":
		property.usage = PROPERTY_USAGE_STORAGE
	elif property.name == "running_tag_groups":
		property.usage = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_NO_INSTANCE_STATE if OIPComms.get_enable_comms() else PROPERTY_USAGE_NONE
	elif property.name == "running_tag_name":
		property.usage = PROPERTY_USAGE_DEFAULT if OIPComms.get_enable_comms() else PROPERTY_USAGE_STORAGE


func _property_can_revert(property: StringName) -> bool:
	return property == "speed_tag_groups" or property == "running_tag_groups"


func _property_get_revert(property: StringName) -> Variant:
	if property == "speed_tag_groups":
		return _speed_tag_group_original
	elif property == "running_tag_groups":
		return _running_tag_group_original
	else:
		return null


func _init() -> void:
	set_notify_local_transform(true)
	_update_calculated_size()


func _ready() -> void:
	var collision_shape = _sb.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape and collision_shape.shape:
		collision_shape.shape = collision_shape.shape.duplicate()
	
	var main_mesh_instance = get_node_or_null("MeshInstance3D") as MeshInstance3D
	if main_mesh_instance and main_mesh_instance.mesh:
		main_mesh_instance.mesh = main_mesh_instance.mesh.duplicate()

	_mesh_regeneration_needed = true
	update_visible_meshes()
	_update_belt_material_scale()


func _update_all_components() -> void:
	if not is_inside_tree():
		return
	
	update_visible_meshes()


func update_visible_meshes() -> void:
	if not is_inside_tree():
		return
	
	if _mesh_regeneration_needed:
		_create_spiral_mesh()
		_setup_collision_shape()
		_mesh_regeneration_needed = false
		_last_size = size


func _create_spiral_mesh() -> void:
	# Number of segments per full rotation
	var segments_per_turn := 30
	var total_segments: int = int(number_of_turns * segments_per_turn)
	
	var mesh_instance: = ArrayMesh.new()
	
	_setup_materials()
	
	var surfaces = _create_surfaces()
	var all_vertices = _create_spiral_vertices(total_segments)
	
	_build_belt_surfaces(surfaces, all_vertices, total_segments)
	
	_add_surfaces_to_mesh(surfaces, mesh_instance)
	
	spiral_mesh.mesh = mesh_instance


func _setup_materials() -> void:
	_belt_material = ShaderMaterial.new()
	_belt_material.shader = load("res://assets/3DModels/Shaders/BeltShader.tres") as Shader
	_belt_material.set_shader_parameter("ColorMix", belt_color)
	_belt_material.set_shader_parameter("BlackTextureOn", belt_texture == ConvTexture.STANDARD)
	_update_belt_material_scale()
	
	_metal_material = ShaderMaterial.new()
	_metal_material.shader = load("res://assets/3DModels/Shaders/MetalShader.tres") as Shader
	_metal_material.set_shader_parameter("Color", Color("#56a7c8"))
	_metal_material.set_shader_parameter("Scale", 1.0)
	_metal_material.set_shader_parameter("Scale2", 1.0)


func _create_surfaces() -> Dictionary:
	var surfaces = {
		"top": {
			"vertices": PackedVector3Array(),
			"normals": PackedVector3Array(),
			"uvs": PackedVector2Array(),
			"indices": PackedInt32Array(),
		},
		"bottom": {
			"vertices": PackedVector3Array(),
			"normals": PackedVector3Array(),
			"uvs": PackedVector2Array(),
			"indices": PackedInt32Array(),
		},
		"sides": {
			"vertices": PackedVector3Array(),
			"normals": PackedVector3Array(),
			"uvs": PackedVector2Array(),
			"indices": PackedInt32Array(),
		}
	}
	return surfaces


func _create_spiral_vertices(total_segments: int) -> Array:
	var all_vertices = []
	var belt_height = 0.15  # Belt thickness
	
	# Direction multiplier for clockwise/counter-clockwise
	var dir = -1.0 if clockwise else 1.0
	
	for i in range(total_segments + 1):
		var t = float(i) / total_segments
		var angle: float = t * number_of_turns * TAU * dir
		var y_pos: float = t * vertical_height - vertical_height / 2.0
		
		var sin_a: float = sin(angle)
		var cos_a: float = cos(angle)
		
		# Inner and outer edges of the belt
		var inner_radius = spiral_radius - belt_width / 2.0
		var outer_radius = spiral_radius + belt_width / 2.0
		
		var inner_top = Vector3(cos_a * inner_radius, y_pos + belt_height / 2.0, sin_a * inner_radius)
		var outer_top = Vector3(cos_a * outer_radius, y_pos + belt_height / 2.0, sin_a * outer_radius)
		var inner_bottom = Vector3(cos_a * inner_radius, y_pos - belt_height / 2.0, sin_a * inner_radius)
		var outer_bottom = Vector3(cos_a * outer_radius, y_pos - belt_height / 2.0, sin_a * outer_radius)
		
		all_vertices.append({
			"inner_top": inner_top,
			"outer_top": outer_top,
			"inner_bottom": inner_bottom,
			"outer_bottom": outer_bottom,
			"t": t,
			"angle": angle
		})
	
	return all_vertices


func _build_belt_surfaces(surfaces: Dictionary, all_vertices: Array, total_segments: int) -> void:
	_build_top_and_bottom_surfaces(surfaces, all_vertices)
	_create_surface_triangles(surfaces, total_segments)
	_create_side_walls(surfaces, all_vertices, total_segments)


func _build_top_and_bottom_surfaces(surfaces: Dictionary, all_vertices: Array) -> void:
	# Top surface
	for i in range(len(all_vertices)):
		var vertex_data = all_vertices[i]
		surfaces.top.vertices.append_array([vertex_data.inner_top, vertex_data.outer_top])
		surfaces.top.normals.append_array([Vector3.UP, Vector3.UP])
		surfaces.top.uvs.append_array([Vector2(0, vertex_data.t), Vector2(1, vertex_data.t)])
	
	# Bottom surface
	for i in range(len(all_vertices)):
		var vertex_data = all_vertices[i]
		surfaces.bottom.vertices.append_array([vertex_data.inner_bottom, vertex_data.outer_bottom])
		surfaces.bottom.normals.append_array([Vector3.DOWN, Vector3.DOWN])
		surfaces.bottom.uvs.append_array([Vector2(0, vertex_data.t), Vector2(1, vertex_data.t)])


func _create_surface_triangles(surfaces: Dictionary, total_segments: int) -> void:
	# Top surface triangles
	for i in range(total_segments):
		var idx = i * 2
		_add_double_sided_triangle(surfaces.top.indices, idx, idx + 1, idx + 3)
		_add_double_sided_triangle(surfaces.top.indices, idx, idx + 3, idx + 2)
	
	# Bottom surface triangles
	for i in range(total_segments):
		var idx = i * 2
		_add_double_sided_triangle(surfaces.bottom.indices, idx, idx + 2, idx + 3)
		_add_double_sided_triangle(surfaces.bottom.indices, idx, idx + 3, idx + 1)


func _create_side_walls(surfaces: Dictionary, all_vertices: Array, total_segments: int) -> void:
	# Inner wall
	for i in range(len(all_vertices)):
		var vertex_data = all_vertices[i]
		var normal: Vector3 = Vector3(-cos(vertex_data.angle), 0, -sin(vertex_data.angle)).normalized()
		
		surfaces.sides.vertices.append_array([vertex_data.inner_top, vertex_data.inner_bottom])
		surfaces.sides.normals.append_array([normal, normal])
		surfaces.sides.uvs.append_array([Vector2(vertex_data.t, 0), Vector2(vertex_data.t, 1)])
	
	for i in range(total_segments):
		var idx = i * 2
		_add_double_sided_triangle(surfaces.sides.indices, idx, idx + 2, idx + 3)
		_add_double_sided_triangle(surfaces.sides.indices, idx, idx + 3, idx + 1)
	
	# Outer wall
	var outer_wall_start_idx = surfaces.sides.vertices.size()
	for i in range(len(all_vertices)):
		var vertex_data = all_vertices[i]
		var normal: Vector3 = Vector3(cos(vertex_data.angle), 0, sin(vertex_data.angle)).normalized()
		
		surfaces.sides.vertices.append_array([vertex_data.outer_top, vertex_data.outer_bottom])
		surfaces.sides.normals.append_array([normal, normal])
		surfaces.sides.uvs.append_array([Vector2(vertex_data.t, 0), Vector2(vertex_data.t, 1)])
	
	for i in range(total_segments):
		var idx = outer_wall_start_idx + i * 2
		_add_double_sided_triangle(surfaces.sides.indices, idx, idx + 3, idx + 2)
		_add_double_sided_triangle(surfaces.sides.indices, idx, idx + 1, idx + 3)


func _add_double_sided_triangle(array_indices: PackedInt32Array, a: int, b: int, c: int) -> void:
	array_indices.append_array([a, b, c, c, b, a])


func _add_surfaces_to_mesh(surfaces: Dictionary, mesh_instance: ArrayMesh) -> void:
	for pair in [["top", 0], ["bottom", 1], ["sides", 2]]:
		var surface_name: String = pair[0]
		var surface_index: int = pair[1]
		var surface: Dictionary = surfaces[surface_name]
		
		if surface.vertices.size() == 0:
			continue
		
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = surface.vertices
		arrays[Mesh.ARRAY_NORMAL] = surface.normals
		arrays[Mesh.ARRAY_TEX_UV] = surface.uvs
		arrays[Mesh.ARRAY_INDEX] = surface.indices
		mesh_instance.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		
		var material_to_use = _belt_material
		if surface_name == "sides":
			material_to_use = _metal_material
		mesh_instance.surface_set_material(surface_index, material_to_use)


func _setup_collision_shape() -> void:
	var collision_shape: CollisionShape3D = $StaticBody3D.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if not collision_shape:
		return
	
	var all_verts: PackedVector3Array = PackedVector3Array()
	var all_indices: PackedInt32Array = PackedInt32Array()
	
	var mesh_instance = spiral_mesh.mesh
	for surface_idx in range(mesh_instance.get_surface_count()):
		var surface = mesh_instance.surface_get_arrays(surface_idx)
		var base_index = all_verts.size()
		all_verts.append_array(surface[Mesh.ARRAY_VERTEX])
		
		for i in surface[Mesh.ARRAY_INDEX]:
			all_indices.append(base_index + i)
	
	var triangle_verts: PackedVector3Array = PackedVector3Array()
	for i in range(0, all_indices.size(), 3):
		if i + 2 >= all_indices.size():
			break
		triangle_verts.append_array([
			all_verts[all_indices[i]],
			all_verts[all_indices[i + 1]],
			all_verts[all_indices[i + 2]]
		])
	
	var shape: ConcavePolygonShape3D = collision_shape.shape
	shape.data = triangle_verts
	collision_shape.scale = Vector3.ONE


func _enter_tree() -> void:
	_speed_tag_group_original = speed_tag_group_name
	_running_tag_group_original = running_tag_group_name
	
	if speed_tag_group_name.is_empty() and OIPComms.get_tag_groups().size() > 0:
		speed_tag_group_name = OIPComms.get_tag_groups()[0]
	if running_tag_group_name.is_empty() and OIPComms.get_tag_groups().size() > 0:
		running_tag_group_name = OIPComms.get_tag_groups()[0]
	
	speed_tag_groups = speed_tag_group_name
	running_tag_groups = running_tag_group_name
	
	SimulationEvents.simulation_started.connect(_on_simulation_started)
	SimulationEvents.simulation_ended.connect(_on_simulation_ended)
	OIPComms.tag_group_initialized.connect(_tag_group_initialized)
	OIPComms.tag_group_polled.connect(_tag_group_polled)
	OIPComms.enable_comms_changed.connect(func() -> void: _enable_comms_changed = OIPComms.get_enable_comms())


func _exit_tree() -> void:
	SimulationEvents.simulation_started.disconnect(_on_simulation_started)
	SimulationEvents.simulation_ended.disconnect(_on_simulation_ended)
	OIPComms.tag_group_initialized.disconnect(_tag_group_initialized)
	OIPComms.tag_group_polled.disconnect(_tag_group_polled)


func _physics_process(delta: float) -> void:
	if SimulationEvents.simulation_running:
		# Move items along the spiral path using linear velocity
		# The direction is tangent to the spiral at each point
		var local_forward := _sb.global_transform.basis.z.normalized()
		var velocity := local_forward * speed
		_sb.constant_linear_velocity = velocity
		
		if not SimulationEvents.simulation_paused:
			belt_position += speed * delta
		
		if speed != 0 and _belt_material:
			(_belt_material as ShaderMaterial).set_shader_parameter("BeltPosition", belt_position * sign(speed))
		
		if belt_position >= 1.0:
			belt_position = 0.0


func _update_belt_material_scale() -> void:
	if _belt_material:
		var spiral_length = sqrt(pow(2.0 * PI * spiral_radius * number_of_turns, 2) + pow(vertical_height, 2))
		var scale_factor = spiral_length / (PI * 0.5)  # Normalize to belt texture
		(_belt_material as ShaderMaterial).set_shader_parameter("Scale", scale_factor * sign(speed))


func _on_simulation_started() -> void:
	if enable_comms:
		_register_speed_tag_ok = OIPComms.register_tag(speed_tag_group_name, speed_tag_name, 1)
		_register_running_tag_ok = OIPComms.register_tag(running_tag_group_name, running_tag_name, 1)


func _on_simulation_ended() -> void:
	belt_position = 0.0
	if _belt_material and _belt_material is ShaderMaterial:
		(_belt_material as ShaderMaterial).set_shader_parameter("BeltPosition", belt_position)
	
	if _sb:
		_sb.constant_linear_velocity = Vector3.ZERO


func _tag_group_initialized(tag_group_name_param: String) -> void:
	if tag_group_name_param == speed_tag_group_name:
		_speed_tag_group_init = true
	if tag_group_name_param == running_tag_group_name:
		_running_tag_group_init = true


func _tag_group_polled(tag_group_name_param: String) -> void:
	if not enable_comms:
		return
	
	if tag_group_name_param == speed_tag_group_name and _speed_tag_group_init:
		speed = OIPComms.read_float32(speed_tag_group_name, speed_tag_name)
