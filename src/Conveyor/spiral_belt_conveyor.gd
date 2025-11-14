@tool
class_name SpiralBeltConveyor
extends Node3D

signal size_changed

enum ConvTexture {
	STANDARD,
	ALTERNATE
}

const BASE_INNER_RADIUS: float = 1.0
const BASE_CONVEYOR_WIDTH: float = 1.524
const BASE_HEIGHT_PER_REVOLUTION: float = 2.0

const SIZE_DEFAULT: Vector3 = Vector3(4.048, 2.0, 4.048)

@export var inner_radius: float = BASE_INNER_RADIUS:
	set(value):
		inner_radius = max(0.5, value)
		_mesh_regeneration_needed = true
		_update_calculated_size()
		_update_all_components()

@export var conveyor_width: float = BASE_CONVEYOR_WIDTH:
	set(value):
		conveyor_width = max(0.3, value)
		_mesh_regeneration_needed = true
		_update_calculated_size()
		_update_all_components()

@export var height_per_revolution: float = BASE_HEIGHT_PER_REVOLUTION:
	set(value):
		height_per_revolution = max(0.5, value)
		_mesh_regeneration_needed = true
		_update_calculated_size()
		_update_all_components()

@export_range(0.5, 4.0, 0.25) var num_revolutions: float = 1.0:
	set(value):
		num_revolutions = max(0.25, value)
		_mesh_regeneration_needed = true
		_update_calculated_size()
		_update_all_components()

## Calculated automatically from parameters - not directly editable
var size: Vector3:
	get:
		return _calculated_size
	set(_value):
		pass

var _calculated_size: Vector3 = SIZE_DEFAULT

func _update_calculated_size() -> void:
	var outer_radius = inner_radius + conveyor_width
	var diameter = outer_radius * 2.0
	var total_height = height_per_revolution * num_revolutions
	var old_size = _calculated_size
	_calculated_size = Vector3(diameter, total_height, diameter)
	
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

@export var speed: float = 2:
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

var mesh: MeshInstance3D
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

	if _belt_material:
		(_belt_material as ShaderMaterial).set_shader_parameter("ColorMix", belt_color)

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
	# Create a spiral helix conveyor belt
	var segments_per_revolution := 32
	var total_segments := int(segments_per_revolution * num_revolutions)
	
	var radius_inner: float = inner_radius
	var radius_outer: float = inner_radius + conveyor_width
	var total_height: float = height_per_revolution * num_revolutions
	
	var mesh_instance: = ArrayMesh.new()
	
	_setup_materials()
	
	var surfaces = _create_surfaces()
	var all_vertices = _create_spiral_vertices(total_segments, radius_inner, radius_outer, total_height)
	
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

func _create_spiral_vertices(total_segments: int, radius_inner: float, radius_outer: float, total_height: float) -> Array:
	var all_vertices = []
	var belt_thickness = 0.2
	
	for i in range(total_segments + 1):
		var t = float(i) / total_segments
		var angle: float = t * num_revolutions * TAU  # TAU = 2*PI
		var height: float = t * total_height - total_height / 2.0  # Center vertically
		
		var sin_a: float = sin(angle)
		var cos_a: float = cos(angle)
		
		# Create vertices for the spiral
		var inner_top = Vector3(cos_a * radius_inner, height + belt_thickness/2, sin_a * radius_inner)
		var outer_top = Vector3(cos_a * radius_outer, height + belt_thickness/2, sin_a * radius_outer)
		var inner_bottom = Vector3(cos_a * radius_inner, height - belt_thickness/2, sin_a * radius_inner)
		var outer_bottom = Vector3(cos_a * radius_outer, height - belt_thickness/2, sin_a * radius_outer)
		
		all_vertices.append({
			"inner_top": inner_top,
			"outer_top": outer_top,
			"inner_bottom": inner_bottom,
			"outer_bottom": outer_bottom,
			"t": t,
			"angle": angle
		})
	return all_vertices

func _build_belt_surfaces(surfaces: Dictionary, all_vertices: Array, segments: int) -> void:
	_build_top_and_bottom_surfaces(surfaces, all_vertices)
	_create_surface_triangles(surfaces, segments)
	_create_side_walls(surfaces, all_vertices, segments)

func _build_top_and_bottom_surfaces(surfaces: Dictionary, all_vertices: Array) -> void:
	for i in range(len(all_vertices)):
		var vertex_data = all_vertices[i]
		
		# Top surface
		surfaces.top.vertices.append_array([vertex_data.inner_top, vertex_data.outer_top])
		surfaces.top.normals.append_array([Vector3.UP, Vector3.UP])
		surfaces.top.uvs.append_array([Vector2(1, vertex_data.t), Vector2(0, vertex_data.t)])
		
		# Bottom surface
		surfaces.bottom.vertices.append_array([vertex_data.inner_bottom, vertex_data.outer_bottom])
		surfaces.bottom.normals.append_array([Vector3.DOWN, Vector3.DOWN])
		surfaces.bottom.uvs.append_array([Vector2(0, vertex_data.t), Vector2(1, vertex_data.t)])

func _create_surface_triangles(surfaces: Dictionary, segments: int) -> void:
	for i in range(segments):
		var idx = i * 2
		# Top surface triangles
		surfaces.top.indices.append_array([idx, idx + 1, idx + 3])
		surfaces.top.indices.append_array([idx, idx + 3, idx + 2])
		
		# Bottom surface triangles
		surfaces.bottom.indices.append_array([idx, idx + 2, idx + 3])
		surfaces.bottom.indices.append_array([idx, idx + 3, idx + 1])

func _create_side_walls(surfaces: Dictionary, all_vertices: Array, segments: int) -> void:
	# Inner and outer walls
	for i in range(len(all_vertices)):
		var vertex_data = all_vertices[i]
		var radial_dir = Vector3(cos(vertex_data.angle), 0, sin(vertex_data.angle))
		
		# Inner wall
		var inner_normal = -radial_dir
		surfaces.sides.vertices.append_array([vertex_data.inner_top, vertex_data.inner_bottom])
		surfaces.sides.normals.append_array([inner_normal, inner_normal])
		surfaces.sides.uvs.append_array([Vector2(0, vertex_data.t), Vector2(1, vertex_data.t)])
		
		# Outer wall
		var outer_normal = radial_dir
		surfaces.sides.vertices.append_array([vertex_data.outer_top, vertex_data.outer_bottom])
		surfaces.sides.normals.append_array([outer_normal, outer_normal])
		surfaces.sides.uvs.append_array([Vector2(0, vertex_data.t), Vector2(1, vertex_data.t)])
	
	# Create triangles for side walls
	for i in range(segments):
		var inner_idx = i * 4
		var outer_idx = i * 4 + 2
		
		# Inner wall triangles
		surfaces.sides.indices.append_array([inner_idx, inner_idx + 1, inner_idx + 5])
		surfaces.sides.indices.append_array([inner_idx, inner_idx + 5, inner_idx + 4])
		
		# Outer wall triangles
		surfaces.sides.indices.append_array([outer_idx, outer_idx + 4, outer_idx + 5])
		surfaces.sides.indices.append_array([outer_idx, outer_idx + 5, outer_idx + 1])

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
	if not shape:
		shape = ConcavePolygonShape3D.new()
		collision_shape.shape = shape
	shape.data = triangle_verts

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
		if not SimulationEvents.simulation_paused:
			belt_position += speed * delta
		if speed != 0:
			(_belt_material as ShaderMaterial).set_shader_parameter("BeltPosition", belt_position * sign(speed))
		if belt_position >= 1.0:
			belt_position = 0.0

func _update_belt_material_scale() -> void:
	if _belt_material:
		# Scale based on spiral length
		var avg_radius = (inner_radius + (inner_radius + conveyor_width)) / 2.0
		var spiral_length = num_revolutions * TAU * avg_radius
		var scale_factor = spiral_length / 4.0
		(_belt_material as ShaderMaterial).set_shader_parameter("Scale", scale_factor * sign(speed))

func _on_simulation_started() -> void:
	if enable_comms:
		_register_speed_tag_ok = OIPComms.register_tag(speed_tag_group_name, speed_tag_name, 1)
		_register_running_tag_ok = OIPComms.register_tag(running_tag_group_name, running_tag_name, 1)

func _on_simulation_ended() -> void:
	belt_position = 0.0
	if _belt_material and _belt_material is ShaderMaterial:
		(_belt_material as ShaderMaterial).set_shader_parameter("BeltPosition", belt_position)

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
