@tool
extends HBoxContainer

const DUPLICATE_LINE_EDIT: StyleBox = preload("res://addons/scene_manager/themes/line_edit_duplicate.tres")

# Nodes
@onready var _root: Node = self
@onready var _popup_menu: PopupMenu = find_child("popup_menu")
@onready var _key_edit: LineEdit = get_node("key")
@onready var _key: String = get_node("key").text

var _setting: ItemSetting
var _sub_section: Control
var _list: Control
var _mouse_is_over_value: bool
var _previous_value: String

# Finds and fills `_root` variable properly
func _ready() -> void:
	_previous_value = _key
	while true:
		if _root == null:
			## If we are here, we are running in editor, so get out
			break
		elif _root.name == "Scene Manager" || _root.name == "menu":
			break
		_root = _root.get_parent()


# Sets value of `key`
func set_key(text: String) -> void:
	# Normalize the key to be lower case without symbols and replacing spaces with underscores
	text = SceneManagerUtils.normalize_key_string(text)
	get_node("key").text = text
	name = text
	_key = text


# Sets value of `value`
func set_value(text: String) -> void:
	get_node("value").text = text


# Return `key` string value
func get_key() -> String:
	return get_node("key").text


# Return `value` string value
func get_value() -> String:
	return get_node("value").text


# Returns `key` node
func get_key_node() -> Node:
	return get_node("key")


# Returns `_setting.visibility` value
func get_visibility() -> bool:
	return _setting.visibility


# Sets value of `_setting.visibility`
func set_visibility(input: bool) -> void:
	_setting.visibility = input
	self.visible = _list.determine_item_visibility(_setting)


# Returns `_setting`
func get_setting() -> ItemSetting:
	return _setting


# Sets `_setting`
func set_setting(setting: ItemSetting) -> void:
	_setting = setting


# Sets subsection for current item
func set_subsection(node: Control) -> void:
	_sub_section = node


# Sets passed theme to normal theme of `key` LineEdit
func custom_set_theme(theme: StyleBox) -> void:
	get_key_node().add_theme_stylebox_override("normal", theme)


# Removes added custom theme for `key` LineEdit
func remove_custom_theme() -> void:
	get_key_node().remove_theme_stylebox_override("normal")


# Popup Button
func _on_popup_button_button_up():
	var i: int = 0
	var sections: Array = _root.get_all_lists_names_except()
	_popup_menu.clear()
	_popup_menu.add_separator("Categories")
	i += 1

	# Categories have id of 0
	for section in sections:
		if section == "All":
			continue
		_popup_menu.add_check_item(section)
		_popup_menu.set_item_id(i, 0)
		_popup_menu.set_item_checked(i, section in _root.get_sections(get_value()))
		i += 1
	
	_popup_menu.add_separator("General")
	i += 1

	# Generals have id of 1
	_popup_menu.add_check_item("Visible")
	_popup_menu.set_item_checked(i, _setting.visibility)
	_popup_menu.set_item_id(i, 1)
	i += 1
	
	var popup_size = _popup_menu.size
	_popup_menu.popup(Rect2(get_global_mouse_position(), popup_size))


# Happens when open scene button clicks
func _on_open_scene_button_up():
	# Open it
	EditorPlugin.new().get_editor_interface().open_scene_from_path(get_value())
	# Show in FileSystem
	EditorInterface.get_file_system_dock().navigate_to_path(get_value())


# Happens on input on the value element
func _on_value_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.is_released() and event.button_index == MOUSE_BUTTON_LEFT and _mouse_is_over_value:
		EditorPlugin.new().get_editor_interface().get_file_system_dock().navigate_to_path(get_value())


# Happens when mouse is over value input
func _on_value_mouse_entered():
	_mouse_is_over_value = true


# Happens when mouse is out of value input
func _on_value_mouse_exited():
	_mouse_is_over_value = false


# Happens when an item is selected
func _on_popup_menu_index_pressed(index: int):
	var id = _popup_menu.get_item_id(index)
	var checked = _popup_menu.is_item_checked(index)
	var text = _popup_menu.get_item_text(index)
	_popup_menu.set_item_checked(index, !checked)

	if id == 0:
		if !checked:
			_root.add_scene_to_list(text, get_key(), get_value(), ItemSetting.default())
			_root.item_added_to_list.emit(self, text)
		else:
			_root.remove_scene_from_list(text, get_key(), get_value())
			_root.item_removed_from_list.emit(self, text)
	elif id == 1:
		if text == "Visible":
			var new_visibility = !get_visibility()
			set_visibility(new_visibility)
			_root.item_visibility_changed.emit(self, new_visibility)


# Runs by hand in `_on_key_gui_input` function when text of key LineEdit
# changes and key event of it was released
func _on_key_value_text_changed() -> void:
	_root.update_all_scene_with_key(_key, get_key(), get_value(), _setting, [get_parent().get_parent()])


# Called by the UI when the text changes
func _on_key_text_changed(new_text: String) -> void:
	set_key(new_text)
	_key_edit.caret_column = _key.length()


# Called by the UI when focus is off of the line edit
func _on_key_focus_exited() -> void:
	_submit_key()


func _on_key_text_submitted(new_text:String) -> void:
	_submit_key()


# Checks to see if the key is something invalid for an enum value.
func _check_invalid_values() -> void:
	if _key == "":
		custom_set_theme(DUPLICATE_LINE_EDIT)


# When a gui_input happens on LineEdit, this function triggers
func _on_key_gui_input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.is_pressed():
			return
		
		# Runs when InputEventKey is released
		_root.check_duplication()
		_check_invalid_values()


# Emits a signal if the key value is different than it was at the start
func _submit_key() -> void:
	if _previous_value != _key:
		_previous_value = _key
		_root.item_renamed.emit(self)


# When added
func _on_tree_entered():
	if _sub_section:
		_sub_section.child_entered()


# When deleted
func _on_tree_exited():
	if _sub_section:
		_sub_section.child_exited()


# Returns grab data
func _get_drag_data(at_position: Vector2) -> Variant:
	return {
		"node": self,
		"parent": _sub_section,
	}
