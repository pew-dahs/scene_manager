@tool
extends MarginContainer
## Editor manager for generating necessary files and getting scene information.
##
## Handles UI callbacks for modifying data and writes the scene.gd file which
## stores all the scene information in the project.

# Project Settings property name
const SETTINGS_PROPERTY_NAME := "scene_manager/scenes/scenes_path"
const ROOT_ADDRESS = "res://"

# scene.gd autogen file tags
const SCENE_DATA_HEADER: String = "#\n\
# This file is autogenerated by the Scene Manager plugin.\n\
# DO NOT EDIT.\n\
#\n\
@tool\n\
extends Node\n\n"
const SCENE_DATA_ENUM: String = "# [Scene Enum]"
const SCENE_DATA_DICTIONARY: String = "# [Scene Dictionary]"

# scene item, include item
const SCENE_INCLUDE_ITEM = preload("res://addons/scene_manager/editor/deletable_item.tscn")
const SCENE_LIST_ITEM = preload("res://addons/scene_manager/editor/scene_list.tscn")

# icons
const ICON_HIDE_BUTTON_CHECKED = preload("res://addons/scene_manager/icons/GuiChecked.svg")
const ICON_HIDE_BUTTON_UNCHECKED = preload("res://addons/scene_manager/icons/GuiCheckedDisabled.svg")
const ICON_FOLDER_BUTTON_CHECKED = preload("res://addons/scene_manager/icons/FolderActive.svg")
const ICON_FOLDER_BUTTON_UNCHECKED = preload("res://addons/scene_manager/icons/Folder.svg")

@onready var _include_list: Node = self.find_child("include_list")
# add save, refresh
@onready var _save_button: Button = self.find_child("save")
@onready var _refresh_button: Button = self.find_child("refresh")
@onready var _auto_save_button: Button = self.find_child("auto_save")
@onready var _auto_refresh_button: Button = self.find_child("auto_refresh")
# add list
@onready var _add_subsection_button: Button = self.find_child("add_subsection")
@onready var _add_section_button: Button = self.find_child("add_section")
@onready var _section_name_line_edit: LineEdit = self.find_child("section_name")
# add include
@onready var _address_line_edit: LineEdit = self.find_child("address")
@onready var _file_dialog: FileDialog = self.find_child("file_dialog")
@onready var _hide_button: Button = self.find_child("hide")
@onready var _hide_unhide_button: Button = self.find_child("hide_unhide")
@onready var _add_button: Button = self.find_child("add")
# containers
@onready var _tab_container: TabContainer = self.find_child("tab_container")
@onready var _include_container: Node = self.find_child("includes")
@onready var _include_panel_container: Node = self.find_child("include_panel")

# A dictionary which contains every scenes exact addresses as key and an array 
# assigned as values which categories every section name the scene is part of
#
# Example: { "res://demo/scene3.tscn": ["Character", "Menu"] }
var _sections: Dictionary = {}
var reserved_keys: Array = ["none"]
var _autosave_timer: Timer = null ## Timer for autosave when the key changes
var _just_saved_timer: Timer = null ## Keep track of if the file just changed to prevent the tab from reloading when unnecessary

# UI signal callbacks
signal include_child_deleted(node: Node, address: String)
signal item_renamed(node: Node)
signal item_visibility_changed(node: Node, visibility: bool)
signal item_added_to_list(node: Node, list_name: String)
signal item_removed_from_list(node: Node, list_name: String)
signal sub_section_removed(node: Node)
signal section_removed(node: Node, section_name: String)
signal added_to_sub_section(node: Node, sub_section: Node)


# Refreshes the whole UI
func _ready() -> void:
	_on_refresh_button_up()
	
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(_filesystem_changed)
	self.include_child_deleted.connect(_on_include_child_deleted)
	self.item_renamed.connect(_on_item_renamed)
	self.item_visibility_changed.connect(_on_item_visibility_changed)
	self.item_added_to_list.connect(_on_added_to_list)
	self.item_removed_from_list.connect(_on_item_removed_from_list)
	self.sub_section_removed.connect(_on_sub_section_removed)
	self.section_removed.connect(_on_section_removed)
	self.added_to_sub_section.connect(_on_added_to_sub_section)

	# Create a new Timer node to write to the scenes.gd file when the timer ends
	_autosave_timer = Timer.new()
	_autosave_timer.wait_time = 0.5
	_autosave_timer.one_shot = true
	add_child(_autosave_timer)
	_autosave_timer.timeout.connect(_on_timer_timeout)

	# Create a Timer for keeping track of when the scenes was just saved
	_just_saved_timer = Timer.new()
	_just_saved_timer.wait_time = 0.5
	_just_saved_timer.one_shot = true
	add_child(_just_saved_timer)

#region Signal Callbacks

func _on_data_changed() -> void:
	if _auto_save_button.get_meta("enabled", false):
		_save_all()


func _on_added_to_sub_section(node: Node, sub_section: Node) -> void:
	_on_data_changed()


func _on_section_removed(node: Node, section_name: String) -> void:
	_on_data_changed()


func _on_sub_section_removed(node: Node) -> void:
	_on_data_changed()


func _on_timer_timeout() -> void:
	_on_data_changed()


func _on_item_renamed(node: Node) -> void:
	if _auto_save_button.get_meta("enabled", false):
		_autosave_timer.wait_time = 0.5
		_autosave_timer.start()


func _on_item_visibility_changed(node: Node, visibility: bool) -> void:
	_on_data_changed()


func _on_added_to_list(node: Node, list_name: String) -> void:
	_on_data_changed()


func _on_item_removed_from_list(node: Node, list_name: String) -> void:
	_on_data_changed()


# When an include item remove button clicks
func _on_include_child_deleted(node: Node, address: String) -> void:
	node.queue_free()
	await node.tree_exited

	_on_data_changed()
	call_deferred("_on_refresh_button_up")


# Gets called by filesystem changes
func _filesystem_changed() -> void:
	if Engine.is_editor_hint() and is_inside_tree():
		# If the timer is active, then the scene.gd was just generated from saving
		# and there's no actual scene change in the filesystem.
		if not _just_saved_timer.is_stopped():
			return
		
		if _auto_refresh_button.get_meta("enabled", true):
			_on_refresh_button_up()
			await get_tree().process_frame
			_on_data_changed()


# Returns absolute current working directory
func _absolute_current_working_directory() -> String:
	return ProjectSettings.globalize_path(EditorPlugin.new().get_current_directory())


# Merges two dictionaries together
func _merge_dict(dest: Dictionary, source: Dictionary) -> void:
	for key in source:
		if dest.has(key):
			var dest_value = dest[key]
			var source_value = source[key]
			if typeof(dest_value) == TYPE_DICTIONARY:
				if typeof(source_value) == TYPE_DICTIONARY:
					_merge_dict(dest_value, source_value)
				else:
					dest[key] = source_value
			else:
				dest[key] = source_value
		else:
			dest[key] = source[key]


# Returns names of all lists from UI
func get_all_lists_names_except(excepts: Array = [""]) -> Array:
	var arr: Array = []
	for i in range(len(excepts)):
		excepts[i] = excepts[i].capitalize()
	for node in _get_lists_nodes():
		if node.name in excepts:
			continue
		arr.append(node.name)
	return arr


# Returns names of all sublists from UI and active tab
func get_all_sublists_names_except(excepts: Array = [""]) -> Array:
	var section = _tab_container.get_child(_tab_container.current_tab)
	return section.get_all_sublists()


# Returns all scenes from the included directories.
func _get_scenes(includes: Array) -> Dictionary:
	# Loop through the includes and recursively get all files from the directories.
	# If it's a file, add the file directly.
	var files: Dictionary = {}

	for include_dir: String in includes:
		var dir := DirAccess.open(include_dir)
		if not dir: # If it's a file
			if (!FileAccess.file_exists(include_dir)):
				print ("Couldn't open ", include_dir)
			else:
				if include_dir.get_extension() == "tscn":
					files[include_dir.get_basename().get_file()] = include_dir
				else:
					# Any other file extension isn't handled
					continue
		else:
			var new_files = _get_scenes_helper(include_dir)
			if len(new_files) != 0:
				_merge_dict(files, new_files)
	
	return files


# Helper recursive function to traversing a directory recursively to storing all relevant files.
func _get_scenes_helper(root_path: String) -> Dictionary:
	var files: Dictionary = {}
	var folders: Array = []
	var dir := DirAccess.open(root_path)
	var original_root_path = root_path
	
	if root_path[len(root_path) - 1] != "/":
		root_path = root_path + "/"
	 
	if dir:
		dir.list_dir_begin() # TODOGODOT4 fill missing arguments https://github.com/godotengine/godot/pull/40547

		if dir.file_exists(root_path + ".gdignore"):
			return files
		
		var file_folder = dir.get_next()
		while file_folder != "":
			var exact_address = root_path + file_folder
			if dir.current_is_dir():
				folders.append(file_folder)
			elif file_folder.get_extension() == "tscn":
				files[file_folder.get_basename().get_file()] = exact_address
			
			file_folder = dir.get_next()

		dir.list_dir_end()

		for folder in folders:
			var new_files: Dictionary = _get_scenes_helper(root_path + folder)
			if len(new_files) != 0:
				_merge_dict(files, new_files)

	return files


# Clears scenes inside a UI list
func _clear_scenes_list(name: String) -> void:
	var list: Node = _get_one_list_node_by_name(name)
	if list != null:
		list.clear_list()


# Clears scenes inside all UI lists
func _clear_all_lists() -> void:
	_sections = {}
	for list in _get_lists_nodes():
		list.clear_list()


# Removes all tabs in scene manager
func _delete_all_tabs() -> void:
	for node in _get_lists_nodes():
		node.free()


# Returns nodes of all section lists from UI in `Scene Manager` tool
func _get_lists_nodes() -> Array:
	return _tab_container.get_children()


# Returns node of a specific list in UI
func _get_one_list_node_by_name(name: String) -> Node:
	for node in _get_lists_nodes():
		if name.capitalize() == node.name:
			return node
	return null


# Removes a scene from a specific list
func remove_scene_from_list(section_name: String, scene_name: String, scene_address: String) -> void:
	var list: Node = _get_one_list_node_by_name(section_name)
	list.remove_item(scene_name, scene_address)
	_section_remove(scene_address, section_name)

	# Removes and add in `All` section too so that it updates its place in list
	var all_list = _get_one_list_node_by_name("All")
	var setting = all_list.get_node_by_scene_address(scene_address).get_setting()
	all_list.remove_item(scene_name, scene_address)
	setting.categorized = has_sections(scene_address)
	await all_list.add_item(scene_name, scene_address, setting)


# Adds the scene to the UI list of scenes
func _add_scene_to_ui_list(list_name: String, scene_name: String, scene_address: String, setting: ItemSetting) -> void:
	var list: Node = _get_one_list_node_by_name(list_name)
	if list == null:
		return
	await list.add_item(scene_name, scene_address, setting)
	_sections_add(scene_address, list_name)


## Adds an item to a list
##
## This function is used in `scene_item.gd` script and plus doing what it is supposed
## to do, removes and again adds the item in `All` section so that it can be placed
## in correct place in correct section.
func add_scene_to_list(list_name: String, scene_name: String, scene_address: String, setting: ItemSetting) -> void:
	_add_scene_to_ui_list(list_name, scene_name, scene_address, setting)

	# Removes and add in `All` section too so that it updates its place in list
	var all_list = _get_one_list_node_by_name("All")
	setting = all_list.get_node_by_scene_address(scene_address).get_setting()
	all_list.remove_item(scene_name, scene_address)
	setting.categorized = has_sections(scene_address)
	await all_list.add_item(scene_name, scene_address, setting)


# Adds an address to the include list
func _add_include_ui_item(address: String) -> void:
	var item := SCENE_INCLUDE_ITEM.instantiate()
	item.set_address(address)
	_include_list.add_child(item)


# Removes the UI element with the address from the include list
func _remove_include_item(address: String) -> void:
	var remove_item: Node = null
	for node in _include_list.get_children():
		if node.get_address() == address:
			remove_item = node
			break
	
	if remove_item:
		_include_list.remove_child(remove_item)
		remove_item.free()


# Clears all tabs, UI lists and include list
func _clear_all() -> void:
	_delete_all_tabs()
	_clear_all_lists()
	_clear_include_ui_list()


# Reloads all scenes in UI and in this script
func _reload_ui_scenes() -> void:
	var scenes_data: Dictionary = _load_scenes()
	var scenes: Dictionary = _get_scenes(_load_includes())
	var scenes_values: Array = scenes.values()
	
	# Reloads all scenes in `Scenes` script in UI and in this script
	for key in scenes_data:
		var scene = scenes_data[key]
		if key == "_auto_refresh":
			_change_auto_refresh_state(scene)
			continue
		
		if key == "_auto_save":
			_change_auto_save_state(scene)
			continue
		
		if key == "_includes_visible":
			_hide_unhide_includes_list(scene)
			continue
		
		var keys = scene.keys()
		assert (("value" in keys) && ("sections" in keys), "Scene Manager Error: this format is not supported. Every scene item has to have 'value' and 'sections' field inside them.'")
		if !(scene["value"] in scenes_values):
			continue
		
		# Need to get a copy of the sections array so it doesn't loop forever
		for section in scene["sections"].duplicate():
			var setting: ItemSetting = null
			if "settings" in keys && section in scene["settings"].keys():
				setting = ItemSetting.dictionary_to_item_setting(scene["settings"][section])
			else:
				setting = ItemSetting.default()
			_add_scene_to_ui_list(section, key, scene["value"], setting)
		
		var setting: ItemSetting = null
		if "settings" in keys && "All" in scene["settings"].keys():
			setting = ItemSetting.dictionary_to_item_setting(scene["settings"]["All"])
		else:
			setting = ItemSetting.default()
		setting.categorized = has_sections(scene["value"])
		_add_scene_to_ui_list("All", key, scene["value"], setting)
	
	# Add scenes that are new and are not into `Scenes` script
	var data_values: Array = []
	var data_dics = scenes_data.values()
	if scenes_data:
		for i in range(len(data_dics)):
			if typeof(data_dics[i]) == TYPE_DICTIONARY:
				data_values.append(data_dics[i]["value"])
	for key in scenes:
		if !(scenes[key] in data_values):
			var setting = ItemSetting.default()
			_add_scene_to_ui_list("All", key, scenes[key], setting)


# Reloads include list in UI and in this script
func _reload_ui_includes() -> void:
	var includes: Array = _load_includes()
	_set_includes(includes)


# Reloads tabs in UI
func _reload_ui_tabs() -> void:
	var sections: Array = _load_sections()
	if _get_one_list_node_by_name("All") == null:
		_add_scene_ui_list("All")
	for section in sections:
		var found = false
		for list in _get_lists_nodes():
			if list.name == section:
				found = true
		if !found:
			_add_scene_ui_list(section)


# Refresh button
func _on_refresh_button_up() -> void:
	_clear_all()
	_reload_ui_tabs()
	_reload_ui_scenes()
	_reload_ui_includes()


#region `_sections` variable Manager

# Adds passed `section_name` to array value of passed `scene_address` key in `_sections` variable
func _sections_add(scene_address: String, section_name: String) -> void:
	if section_name == "All":
		return
	if !_sections.has(scene_address):
		_sections[scene_address] = []
	if !(section_name in _sections[scene_address]):
		_sections[scene_address].append(section_name)


# Removes passed `section_name` from array value of passed `scene_address` key
func _section_remove(scene_address: String, section_name: String) -> void:
	if !_sections.has(scene_address):
		return
	if section_name in _sections[scene_address]:
		_sections[scene_address].erase(section_name)
	if len(_sections[scene_address]) == 0:
		_sections.erase(scene_address)


## Returns all sections of passed `scene_address`.
func get_sections(scene_address: String) -> Array:
	if !_sections.has(scene_address):
		return []
	return _sections[scene_address]


## Returns true or false if passed `scene_address` has sections.
func has_sections(scene_address: String) -> bool:
	return _sections.keys().has(scene_address) && _sections[scene_address] != []


# Cleans `_sections` variable from `All` section
func _clean_sections() -> void:
	var scenes: Array = get_all_lists_names_except(["All"])
	for key in _sections:
		var will_be_deleted: Array = []
		for section in _sections[key]:
			if !(section in scenes):
				will_be_deleted.append(section)
		for section in will_be_deleted:
			_sections[key].erase(section)

# End Of `_sections` variable Manager


## Gets called by other nodes in UI
##
## Updates name of all scene_key.
func update_all_scene_with_key(scene_key: String, scene_new_key: String, value: String, setting: ItemSetting, except_list: Array = []):
	for list in _get_lists_nodes():
		if list not in except_list:
			list.update_scene_with_key(scene_key, scene_new_key, value, setting)


## Checks for duplications in scenes of lists
func check_duplication():
	var list: Array = _get_one_list_node_by_name("All").check_duplication()
	for node in _get_lists_nodes():
		node.set_reset_theme_for_all()
		if list:
			node.set_duplicate_theme(list)


# Saves all data in `scenes` variable of `scenes.gd` file
func _save_all() -> void:
	var data := _create_save_dic()
	var file := FileAccess.open(ProjectSettings.get_setting(SETTINGS_PROPERTY_NAME, SceneManagerConstants.DEFAULT_PATH_TO_SCENES), FileAccess.WRITE)

	# Generates the scene.gd file with all the scene data
	var write_data: String = SCENE_DATA_HEADER

	# Convert the keys of the dictionary into an enum
	write_data += SCENE_DATA_ENUM + "\n"
	write_data += "enum SceneName \\\n{ NONE = -1, "

	# Keep track of invalid enums so there aren't blank names that make the generated enum invalid
	var invalid_name := "INVALID"
	var num_invalid: int = 0
	for key: String in data[SceneManagerConstants.SCENE_DATA_KEY].keys():
		if key == "":
			write_data += "%s%d, " % [invalid_name, num_invalid]
			num_invalid += 1
		else:
			write_data += "%s, " % key.to_upper()
	
	write_data += "}\n\n"

	write_data += SCENE_DATA_DICTIONARY + "\n"
	write_data += "var scenes: Dictionary = \\\n"
	write_data += JSON.new().stringify(data) + "\n"

	file.store_string(write_data)

	# Set the timer so the file system doesn't reload everything on save.
	_just_saved_timer.wait_time = 0.5
	_just_saved_timer.start()


# Returns all data in `scenes` variable of `scenes.gd` file
func _load_all() -> Dictionary:
	var data: Dictionary = {}

	if FileAccess.file_exists(ProjectSettings.get_setting(SETTINGS_PROPERTY_NAME, SceneManagerConstants.DEFAULT_PATH_TO_SCENES)):
		var file := FileAccess.open(ProjectSettings.get_setting(SETTINGS_PROPERTY_NAME, SceneManagerConstants.DEFAULT_PATH_TO_SCENES), FileAccess.READ)

		while not file.eof_reached():
			var line := file.get_line()
			if line == SCENE_DATA_DICTIONARY:
				file.get_line() # Skip the variable declaration
				line = file.get_line().strip_escapes()

				var json = JSON.new()
				var err = json.parse(line)
				assert (err == OK, "Scene Manager Error: `scenes.gd` File is corrupted.")
				data = json.data
	
	return data


# Loads and returns just scenes from `scenes` variable of `scenes.gd` file
func _load_scenes() -> Dictionary:
	return _load_all()[SceneManagerConstants.SCENE_DATA_KEY]


# Loads and returns just array value of `_include_list` key from `scenes` variable of `scenes.gd` file
func _load_includes() -> Array:
	var dic: Dictionary = _load_all()
	if dic.has("_include_list"):
		return dic["_include_list"]
	return []


# Loads and returns just array value of `_sections` key from `scenes` variable of `scenes.gd` file
func _load_sections() -> Array:
	var dic: Dictionary = _load_all()
	if dic.has("_sections"):
		return dic["_sections"]
	return []


# Returns all scenes data from UI view in a dictionary
func _get_scenes_from_ui() -> Dictionary:
	var list: Node = _get_one_list_node_by_name("All")
	var data: Dictionary = {}

	if list == null:
		return data

	for node in list.get_list_nodes():
		var address = node.get_value()
		var sections = get_sections(address)
		var settings = {}
		for section in sections:
			var li = _get_one_list_node_by_name(section)
			if li == null:
				continue
			var specific_node = li.get_node_by_scene_address(address)
			var setting = specific_node.get_setting()
			settings[section] = setting.as_dictionary()
		var setting = node.get_setting()
		settings["All"] = setting.as_dictionary()
		data[node.get_key()] = {
			"value": address,
			"sections": sections,
			"settings": settings,
		}
	return data


# Returns all scenes nodes from `All` UI list and returns in an array
#
# Unused method
func _get_scene_nodes_from_view() -> Array:
	var list: Node = _get_one_list_node_by_name("All")
	var nodes: Array = []
	for i in range(list.get_child_count()):
		var node: Node = list.get_child(i)
		nodes.append(node)
	return nodes


# Gathers all data from UI and returns it
func _create_save_dic() -> Dictionary:
	var data: Dictionary = {}
	data["_include_list"] = _get_includes_in_include_ui()
	data["_sections"] = get_all_lists_names_except(["All"])
	data["_auto_refresh"] = _auto_refresh_button.get_meta("enabled", false)
	data["_auto_save"] = _auto_save_button.get_meta("enabled", false)
	data["_includes_visible"] = _include_container.visible
	data[SceneManagerConstants.SCENE_DATA_KEY] = _get_scenes_from_ui()
	return data


# Save button
func _on_save_button_up():
	_clean_sections()
	_save_all()


# Returns array of include nodes from UI view
func _get_nodes_in_include_ui() -> Array:
	return _include_list.get_children()


# Returns array of addresses to include
func _get_includes_in_include_ui() -> Array:
	var arr: Array = []
	for node in _include_list.get_children():
		arr.append(node.get_address())
	return arr


# Sets current passed list of includes into UI instead of others
func _set_includes(list :Array) -> void:
	_clear_include_ui_list()
	for text in list:
		_add_include_ui_item(text)


# Clears includes from UI
func _clear_include_ui_list() -> void:
	for node in _include_list.get_children():
		node.free()


# Returns true if passed address exists in include list
func _include_exists_in_list(address: String) -> bool:
	for node in _get_nodes_in_include_ui():
		if node.get_address() == address or address.begins_with(node.get_address()):
			return true
	return false


# Include list Add button up
func _on_add_button_up():
	if _include_exists_in_list(_address_line_edit.text):
		_address_line_edit.text = ""
		return
	
	_add_include_ui_item(_address_line_edit.text)

	_address_line_edit.text = ""
	_add_button.disabled = true

	_on_data_changed()
	_on_refresh_button_up()


# Pops up file dialog to select a folder to include
func _on_file_dialog_button_button_up():
	_file_dialog.popup_centered(Vector2(600, 600))


# When a file or a dir selects by file dialog
func _on_file_dialog_dir_file_selected(path):
	_address_line_edit.text = path
	_on_address_text_changed(path)


# When include address bar text changes
func _on_address_text_changed(new_text: String) -> void:
	if new_text != "":
		if DirAccess.dir_exists_absolute(new_text) || FileAccess.file_exists(new_text) && new_text.begins_with("res://"):
			_add_button.disabled = false
		else:
			_add_button.disabled = true
	else:
		_add_button.disabled = true


# Adds a new list to the tab container
func _add_scene_ui_list(text: String) -> void:
	var list = SCENE_LIST_ITEM.instantiate()
	list.name = text.capitalize()
	_tab_container.add_child(list)


# Adds the new section to the tab container and to the manager data
func _on_add_section_button_up():
	if _section_name_line_edit.text != "":
		_add_scene_ui_list(_section_name_line_edit.text)
		_section_name_line_edit.text = ""
		_add_subsection_button.disabled = true
		_add_section_button.disabled = true

		_on_data_changed()


# When section name text changes
func _on_section_name_text_changed(new_text):
	if new_text != "" && !(new_text.capitalize() in get_all_lists_names_except()):
		_add_section_button.disabled = false
	else:
		_add_section_button.disabled = true

	if new_text != "" && _tab_container.get_child(_tab_container.current_tab).name != "All" && !(new_text.capitalize() in get_all_sublists_names_except()):
		_add_subsection_button.disabled = false
	else:
		_add_subsection_button.disabled = true


func _hide_unhide_includes_list(value: bool) -> void:
	if value:
		_hide_button.icon = ICON_HIDE_BUTTON_CHECKED
		_hide_unhide_button.icon = ICON_HIDE_BUTTON_CHECKED
		_include_container.visible = true
		_include_panel_container.visible = true
		_hide_unhide_button.visible = false
	else:
		_hide_button.icon = ICON_HIDE_BUTTON_UNCHECKED
		_hide_unhide_button.icon = ICON_HIDE_BUTTON_UNCHECKED
		_include_container.visible = false
		_include_panel_container.visible = false
		_hide_unhide_button.visible = true


# Hide Button
func _on_hide_button_up():
	_hide_unhide_includes_list(!_include_container.visible)
	_save_all()


# Tab changes
func _on_tab_container_tab_changed(tab: int):
	_on_section_name_text_changed(_section_name_line_edit.text)


# Add SubSection Button
func _on_add_subsection_button_up():
	if _section_name_line_edit.text != "":
		var section = _tab_container.get_child(_tab_container.current_tab)
		section.add_subsection(_section_name_line_edit.text)
		_section_name_line_edit.text = ""
		_add_subsection_button.disabled = true
		_add_section_button.disabled = true


func _change_auto_save_state(value: bool) -> void:
	if !value:
		_save_button.disabled = false
		_auto_save_button.set_meta("enabled", false)
		_auto_save_button.icon = ICON_HIDE_BUTTON_UNCHECKED
	else:
		_auto_save_button.set_meta("enabled", true)
		_auto_save_button.icon = ICON_HIDE_BUTTON_CHECKED
	_save_button.disabled = _auto_refresh_button.get_meta("enabled", true) and _auto_save_button.get_meta("enabled", true)


func _on_auto_save_button_up():
	_change_auto_save_state(!_auto_save_button.get_meta("enabled", false))
	_save_all()


func _change_auto_refresh_state(value: bool) -> void:
	if !value:
		_auto_refresh_button.set_meta("enabled", false)
		_auto_refresh_button.icon = ICON_FOLDER_BUTTON_UNCHECKED
	else:
		_auto_refresh_button.set_meta("enabled", true)
		_auto_refresh_button.icon = ICON_FOLDER_BUTTON_CHECKED
	_save_button.disabled = _auto_refresh_button.get_meta("enabled", true) and _auto_save_button.get_meta("enabled", true)


func _on_auto_refresh_button_up():
	_change_auto_refresh_state(!_auto_refresh_button.get_meta("enabled", true))
	_save_all()
