extends Node3D

# Credits menu. Copy this scene and this script together.
# Save, load, pause, and confirm also need scripts/slot_rules.gd.
# Settings also needs scripts/prefs_rules.gd.

const SlotRules = preload("res://scripts/slot_rules.gd")
const PrefsRules = preload("res://scripts/prefs_rules.gd")
const CHOICES: PackedStringArray = ["Back"]
const FRONT := "res://scenes/menus/front_board.tscn"
const PLAY := "res://scenes/play_yard.tscn"
const HALT := "res://scenes/menus/halt_board.tscn"
const PREFS := "res://scenes/menus/prefs_board.tscn"
const THANKS := "res://scenes/menus/thanks_board.tscn"
const KEEP := "res://scenes/menus/keep_board.tscn"
const RECALL := "res://scenes/menus/recall_board.tscn"
const CONFIRM := "res://scenes/menus/confirm_board.tscn"

var slots: RefCounted
var prefs: RefCounted
var index := 0
var notice := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	slots = SlotRules.new()
	prefs = PrefsRules.new()
	_boot_prefs()
	var eye : Node = get_node_or_null("RigEye")
	if eye is Camera3D:
		(eye as Camera3D).current = true
	_prepare()
	if _row_disabled(CHOICES[index]):
		_step(1)
	else:
		_refresh()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_mouse_pick(event.position)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("stride_north"):
		_step(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("stride_south"):
		_step(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("primary"):
		_activate(CHOICES[index])
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("halt"):
		_halt_choice()
		get_viewport().set_input_as_handled()

func _refresh() -> void:
	for i in CHOICES.size():
		var choice := CHOICES[i]
		_paint(choice, i == index, _row_disabled(choice))
		_set_caption(choice, _caption(choice))
	var note : Node = get_node_or_null("Notice")
	if note is Label3D:
		note.text = notice

func _paint(panel_name: String, active: bool, blocked: bool) -> void:
	var panel : Node = get_node_or_null(panel_name)
	if not (panel is MeshInstance3D):
		return
	var mat := StandardMaterial3D.new()
	if blocked:
		mat.albedo_color = Color(0.16, 0.16, 0.16)
	elif active:
		mat.albedo_color = Color(0.86, 0.7, 0.24)
	else:
		mat.albedo_color = Color(0.24, 0.3, 0.38)
	(panel as MeshInstance3D).material_override = mat

func _set_caption(panel_name: String, caption: String) -> void:
	var panel : Node = get_node_or_null(panel_name)
	if panel == null:
		return
	var label : Node = panel.get_node_or_null("Caption")
	if label is Label3D:
		label.text = caption

func _mouse_pick(point: Vector2) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var best := -1
	var best_dist := 90.0
	for i in CHOICES.size():
		if _row_disabled(CHOICES[i]):
			continue
		var panel : Node = get_node_or_null(CHOICES[i])
		if not (panel is Node3D):
			continue
		if cam.is_position_behind((panel as Node3D).global_position):
			continue
		var screen := cam.unproject_position((panel as Node3D).global_position)
		var dist := screen.distance_to(point)
		if dist < best_dist:
			best_dist = dist
			best = i
	if best < 0:
		return
	index = best
	_activate(CHOICES[best])
func _boot_prefs() -> void:
	prefs.recall_prefs()
	_push_guard()
	_apply_window()

func _push_guard() -> void:
	var guard: Node = get_node_or_null("/root/BootGuard")
	if guard != null:
		guard.set_loudness(prefs.loudness)

func _apply_window() -> void:
	if OS.has_feature("headless") or DisplayServer.get_name() == "headless":
		return
	var mode := DisplayServer.WINDOW_MODE_WINDOWED
	if prefs.fullscreen:
		mode = DisplayServer.WINDOW_MODE_FULLSCREEN
	if DisplayServer.window_get_mode() == mode:
		return
	DisplayServer.window_set_mode(mode)

func _step(delta: int) -> void:
	var guard := 0
	while guard < CHOICES.size():
		index = _wrap(index + delta, CHOICES.size())
		if not _row_disabled(CHOICES[index]):
			break
		guard += 1
	_refresh()

func _wrap(value: int, size: int) -> int:
	var mod := value % size
	if mod < 0:
		mod += size
	return mod

func _go(next_path: String) -> void:
	if get_tree().paused:
		get_tree().paused = false
	get_tree().change_scene_to_file(next_path)

func _handoff(next_path: String) -> void:
	var host := get_parent()
	if SlotRules.from_pause and host != null and host.has_method("open_overlay"):
		host.open_overlay(next_path)
		return
	_go(next_path)

func _leave() -> void:
	var host := get_parent()
	if SlotRules.from_pause and host != null and host.has_method("open_overlay"):
		var back := SlotRules.return_scene
		if back == "":
			back = HALT
		host.open_overlay(back)
		return
	var back_path := SlotRules.back_scene
	if back_path == "":
		back_path = FRONT
	_go(back_path)

func _after_confirm() -> void:
	var host := get_parent()
	if SlotRules.from_pause and host != null and host.has_method("open_overlay"):
		var back := SlotRules.confirm_return
		if back == "":
			back = SlotRules.return_scene
		if back == "":
			back = HALT
		host.open_overlay(back)
		return
	var back_path := SlotRules.back_scene
	if back_path == "":
		back_path = FRONT
	_go(back_path)

func _loudness() -> float:
	var guard: Node = get_node_or_null("/root/BootGuard")
	if guard != null and "loudness" in guard:
		return float(guard.loudness)
	return prefs.loudness

func _seconds() -> int:
	var host := get_parent()
	if host != null and host.has_method("played_seconds"):
		return int(host.played_seconds())
	return 0

func _slot_index(choice: String) -> int:
	if not choice.begins_with("Slot"):
		return -1
	return int(choice.substr(4))

func _halt_choice() -> void:
	if CHOICES.find("Back") >= 0:
		_activate("Back")
	elif CHOICES.find("Resume") >= 0:
		_activate("Resume")
	elif CHOICES.find("No") >= 0:
		_activate("No")
	else:
		_activate("Quit")
func _activate(choice: String) -> void:
	if choice == "Back":
		_leave()

func _prepare() -> void:
	pass

func _caption(choice: String) -> String:
	return choice

func _row_disabled(_choice: String) -> bool:
	return false

