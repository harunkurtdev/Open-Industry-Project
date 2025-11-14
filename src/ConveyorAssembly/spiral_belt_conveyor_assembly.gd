@tool
class_name SpiralBeltConveyorAssembly
extends Node3D

const CONVEYOR_CLASS_NAME = "SpiralBeltConveyor"
const PREVIEW_SCENE_PATH: String = "res://parts/assemblies/SpiralBeltConveyorAssembly.tscn"

var _conveyor_script: Script
var _has_instantiated := false
var _cached_conveyor_property_values: Dictionary[StringName, Variant] = {}

func _init() -> void:
	var class_list: Array[Dictionary] = ProjectSettings.get_global_class_list()
	var class_details: Dictionary = class_list[class_list.find_custom(func (item: Dictionary) -> bool: return item["class"] == CONVEYOR_CLASS_NAME)]
	_conveyor_script = load(class_details["path"]) as Script

	# Enable transform notifications
	set_notify_transform(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		if _has_instantiated and is_inside_tree():
			pass  # Future: update attachments if needed
	elif what == NOTIFICATION_ENTER_TREE:
		if _has_instantiated:
			pass  # Future: update attachments if needed


func _get_property_list() -> Array[Dictionary]:
	var conveyor_properties = _get_conveyor_forwarded_properties()
	var filtered_properties: Array[Dictionary] = []
	var found_categories = []

	for prop in conveyor_properties:
		var prop_name = prop[&"name"] as String
		var usage = prop[&"usage"] as int

		if usage & PROPERTY_USAGE_CATEGORY:
			if prop_name == "ResizableNode3D" or prop_name in found_categories:
				continue
			found_categories.append(prop_name)

		if prop_name == "size" or prop_name == "hijack_scale" or prop_name.begins_with("metadata/hijack_scale"):
			continue

		filtered_properties.append(prop)

	return filtered_properties

func _set(property: StringName, value: Variant) -> bool:
	# Allow size property to be handled by ResizableNode3D
	if property == "size":
		return false

	if property not in _get_conveyor_forwarded_property_names():
		return false
	_conveyor_property_cached_set(property, value)
	return true


func _get(property: StringName) -> Variant:
	if property not in _get_conveyor_forwarded_property_names():
		return null
	return _conveyor_property_cached_get(property)


func _property_can_revert(property: StringName) -> bool:
	return property in _get_conveyor_forwarded_property_names()


func _property_get_revert(property: StringName) -> Variant:
	if property not in _get_conveyor_forwarded_property_names():
		return null
	if _has_instantiated:
		if $SpiralConveyor.property_can_revert(property):
			return $SpiralConveyor.property_get_revert(property)
		elif $SpiralConveyor.scene_file_path:
			# Find the property's value in the PackedScene file.
			var scene := load($SpiralConveyor.scene_file_path) as PackedScene
			var scene_state := scene.get_state()
			for prop_idx in range(scene_state.get_node_property_count(0)):
				if scene_state.get_node_property_name(0, prop_idx) == property:
					return scene_state.get_node_property_value(0, prop_idx)
			# Try the script's default instead.
			return $SpiralConveyor.get_script().get_property_default_value(property)
	return _conveyor_script.get_property_default_value(property)


func _ready() -> void:
	if not $SpiralConveyor.property_list_changed.is_connected(notify_property_list_changed):
		$SpiralConveyor.property_list_changed.connect(notify_property_list_changed)

	# Apply cached properties
	for property: StringName in _cached_conveyor_property_values:
		var value: Variant = _cached_conveyor_property_values[property]
		$SpiralConveyor.set(property, value)
	_cached_conveyor_property_values.clear()

	_has_instantiated = true
	notify_property_list_changed()


func _get_conveyor_forwarded_properties() -> Array[Dictionary]:
	var all_properties: Array[Dictionary]
	var has_seen_node3d_category: bool = false
	var has_seen_category_after_node3d: bool = false

	if _has_instantiated:
		all_properties = $SpiralConveyor.get_property_list()
	else:
		all_properties = _conveyor_script.get_script_property_list()
		has_seen_node3d_category = true

	var filtered_properties: Array[Dictionary] = []
	for property in all_properties:
		if not has_seen_node3d_category:
			has_seen_node3d_category = (property[&"name"] == "Node3D"
					and property[&"usage"] == PROPERTY_USAGE_CATEGORY)
			continue
		if not has_seen_category_after_node3d:
			has_seen_category_after_node3d = property[&"usage"] == PROPERTY_USAGE_CATEGORY
		if not has_seen_category_after_node3d:
			continue
		filtered_properties.append(property)
	return filtered_properties


func _get_conveyor_forwarded_property_names() -> Array:
	var result: Array = (_get_conveyor_forwarded_properties()
			.filter(func(property):
				var prop_name := property[&"name"] as String
				var usage := property[&"usage"] as int
				if prop_name in ["size", "original_size", "transform_in_progress", "size_min", "size_default", "hijack_scale"]:
					return false
				if prop_name.begins_with("metadata/hijack_scale"):
					return false
				return (not (usage & PROPERTY_USAGE_CATEGORY
					or usage & PROPERTY_USAGE_GROUP
					or usage & PROPERTY_USAGE_SUBGROUP)
					and usage & PROPERTY_USAGE_STORAGE
					and not prop_name.begins_with("metadata/")))
			.map(func(property): return property[&"name"] as String))
	return result


func _conveyor_property_cached_set(property: StringName, value: Variant) -> void:
	if _has_instantiated:
		$SpiralConveyor.set(property, value)
	else:
		_cached_conveyor_property_values[property] = value


func _conveyor_property_cached_get(property: StringName) -> Variant:
	if _has_instantiated and is_instance_valid($SpiralConveyor):
		var value: Variant = $SpiralConveyor.get(property)
		if value != null:
			return value

	if property in _cached_conveyor_property_values:
		return _cached_conveyor_property_values[property]

	if _conveyor_script:
		return _conveyor_script.get_property_default_value(property)

	return null
