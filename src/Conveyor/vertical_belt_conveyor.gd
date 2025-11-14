@tool
class_name VerticalBeltConveyor
extends ResizableNode3D

signal speed_changed

enum ConvTexture {
	STANDARD,
	ALTERNATE
}

@export var belt_color: Color = Color(1, 1, 1, 1):
	set(value):
		belt_color = value
		_update_material_color()

@export var belt_texture: ConvTexture = ConvTexture.STANDARD:
	set(value):
		belt_texture = value
		_update_material_texture()

@export_custom(PROPERTY_HINT_NONE, "suffix:m/s") var speed: float = 2:
	set(value):
		if value == speed:
			return
		speed = value
		_update_speed()
		_update_belt_material_scale()
		speed_changed.emit()

		if _register_running_tag_ok and _running_tag_group_init:
			OIPComms.write_bit(running_tag_group_name, running_tag_name, value != 0.0)

@export var belt_physics_material: PhysicsMaterial:
	get:
		var sb_node := get_node_or_null("StaticBody3D") as StaticBody3D
		if sb_node:
			return sb_node.physics_material_override
		return null
	set(value):
		var sb_node := get_node_or_null("StaticBody3D") as StaticBody3D
		if sb_node:
			sb_node.physics_material_override = value

@onready var _sb: StaticBody3D = get_node("StaticBody3D")
@onready var _mesh: MeshInstance3D = get_node("MeshInstance3D")
var _belt_material: Material
var _belt_position: float = 0.0
var _register_speed_tag_ok: bool = false
var _register_running_tag_ok: bool = false
var _speed_tag_group_init: bool = false
var _running_tag_group_init: bool = false
var _speed_tag_group_original: String
var _running_tag_group_original: String
var _original_collision_layer: int = 1
var _original_collision_mask: int = 1
var _enable_comms_changed: bool = false:
	set(value):
		notify_property_list_changed()

@export_category("Communications")
@export var enable_comms: bool = false
@export var speed_tag_group_name: String
@export_custom(0, "tag_group_enum") var speed_tag_groups:
	set(value):
		speed_tag_group_name = value
		speed_tag_groups = value
@export var speed_tag_name: String = ""
@export var running_tag_group_name: String
@export_custom(0, "tag_group_enum") var running_tag_groups:
	set(value):
		running_tag_group_name = value
		running_tag_groups = value
@export var running_tag_name: String = ""


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


func _get_constrained_size(new_size: Vector3) -> Vector3:
	# Vertical conveyor: height is primary dimension, width and depth are secondary
	# Ensure minimum height for proper operation
	new_size.y = max(new_size.y, 0.5)
	return new_size


func _init() -> void:
	super._init()
	size_default = Vector3(1.524, 2.0, 0.5)


func _enter_tree() -> void:
	super._enter_tree()

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


func _ready() -> void:
	_setup_references()
	_setup_materials()
	_setup_collision_shape()
	_update_material_texture()
	_update_material_color()
	_update_speed()
	_update_physics_material()
	_on_size_changed()


func _physics_process(delta: float) -> void:
	if SimulationEvents.simulation_running:
		# Vertical conveyor moves items along the Y axis (up/down)
		var local_up := _sb.global_transform.basis.y.normalized()
		var velocity := local_up * speed
		_sb.constant_linear_velocity = velocity
		if not SimulationEvents.simulation_paused:
			_belt_position += speed * delta
		if speed != 0:
			(_belt_material as ShaderMaterial).set_shader_parameter("BeltPosition", _belt_position * sign(speed))
		if _belt_position >= 1.0:
			_belt_position = 0.0


func _exit_tree() -> void:
	SimulationEvents.simulation_started.disconnect(_on_simulation_started)
	SimulationEvents.simulation_ended.disconnect(_on_simulation_ended)
	OIPComms.tag_group_initialized.disconnect(_tag_group_initialized)
	OIPComms.tag_group_polled.disconnect(_tag_group_polled)
	super._exit_tree()


func fix_material_overrides() -> void:
	# This is necessary because the editor's duplication action will overwrite our materials after we've initialized them.
	if _mesh.get_surface_override_material(0) != _belt_material:
		_mesh.set_surface_override_material(0, _belt_material)


func _setup_references() -> void:
	# BoxMesh only has one surface, so we just use the belt material
	if _mesh and _mesh.mesh:
		_belt_material = _mesh.get_surface_override_material(0)
		if not _belt_material:
			_belt_material = _mesh.mesh.surface_get_material(0)

	# Store original collision settings
	if _sb:
		_original_collision_layer = _sb.collision_layer
		_original_collision_mask = _sb.collision_mask


func _setup_materials() -> void:
	# Get existing material from the scene or create a default
	if _mesh.get_surface_override_material(0):
		_belt_material = _mesh.get_surface_override_material(0).duplicate() as Material
	elif _mesh.mesh and _mesh.mesh.surface_get_material(0):
		_belt_material = _mesh.mesh.surface_get_material(0).duplicate() as Material
	
	if _belt_material:
		_mesh.set_surface_override_material(0, _belt_material)


func _setup_collision_shape() -> void:
	var collision_shape_node := _sb.get_node("CollisionShape3D") as CollisionShape3D
	if collision_shape_node and collision_shape_node.shape:
		collision_shape_node.shape = collision_shape_node.shape.duplicate() as BoxShape3D


func _update_material_texture() -> void:
	if not _belt_material:
		return
	_belt_material.set_shader_parameter("BlackTextureOn", belt_texture == ConvTexture.STANDARD)
	fix_material_overrides()


func _update_material_color() -> void:
	if not _belt_material:
		return
	_belt_material.set_shader_parameter("ColorMix", belt_color)
	fix_material_overrides()


func _update_speed() -> void:
	pass


func _update_physics_material() -> void:
	if not _sb:
		return


func _update_belt_material_scale() -> void:
	if not _belt_material or not _sb or speed == 0:
		return
	var BASE_RADIUS: float = clamp(round((size.z - 0.01) * 100.0) / 100.0, 0.01, 0.25)
	var collision_shape := _sb.get_node("CollisionShape3D").shape as BoxShape3D
	var belt_height := collision_shape.size.y
	var BASE_BELT_LENGTH: float = PI * BASE_RADIUS
	var belt_scale: float = belt_height / BASE_BELT_LENGTH
	(_belt_material as ShaderMaterial).set_shader_parameter("Scale", belt_scale * sign(speed))
	fix_material_overrides()


func _on_size_changed() -> void:
	var width := size.x
	var height := size.y
	var depth := size.z

	var middle_body := _sb
	var middle_mesh := _mesh
	var middle_collision_shape := get_node_and_resource("StaticBody3D/CollisionShape3D:shape")[1] as BoxShape3D
	if not (is_instance_valid(middle_body)
			and is_instance_valid(middle_mesh)
			and is_instance_valid(middle_collision_shape)):
		return

	var middle_size := Vector3(width, height, depth)
	var middle_mesh_base_size := Vector3(2, 1, 0.5)
	middle_mesh.scale = middle_size / middle_mesh_base_size
	middle_collision_shape.size = Vector3(width, height, depth)

	_update_belt_material_scale()

	# Position the mesh and body at the center
	var base_pos := Vector3(0, 0, 0)
	middle_mesh.position = base_pos
	middle_body.position = base_pos


func _on_simulation_started() -> void:
	if enable_comms:
		_register_speed_tag_ok = OIPComms.register_tag(speed_tag_group_name, speed_tag_name, 1)
		_register_running_tag_ok = OIPComms.register_tag(running_tag_group_name, running_tag_name, 1)


func _on_simulation_ended() -> void:
	_belt_position = 0.0
	if _belt_material:
		(_belt_material as ShaderMaterial).set_shader_parameter("BeltPosition", _belt_position)
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
