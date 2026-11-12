extends Control
class_name App

# The main scene: the menu screens and the game. Menus are a stack (open()
# pushes, back() pops); starting a game replaces the stack with the game,
# and leaving it brings back Main menu > Play, so the next game is one tap
# away and back still leads to the main menu.

const GameScene := preload("res://scenes/game/game.tscn")

var _stack: Array[MenuScreen] = []
var _game: GameManager

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	open(MainMenu.new())

func open(screen: MenuScreen) -> void:
	if not _stack.is_empty():
		_stack.back().visible = false
	screen.app = self
	_stack.append(screen)
	add_child(screen)

func back() -> void:
	if not can_go_back():
		return
	_stack.pop_back().queue_free()
	_stack.back().visible = true

func can_go_back() -> bool:
	return _stack.size() > 1

func start_game(setup: GameSetup) -> void:
	_clear_stack()
	_game = GameScene.instantiate() as GameManager
	_game.setup = setup
	_game.exit_requested.connect(_on_game_exit_requested)
	add_child(_game)

func _on_game_exit_requested() -> void:
	# The in-game options panel pauses the tree while it's open.
	get_tree().paused = false
	Selection.deselect()
	Selection.set_cells([])
	_game.queue_free()
	_game = null
	open(MainMenu.new())
	open(PlayMenu.new())

func _clear_stack() -> void:
	for screen in _stack:
		screen.queue_free()
	_stack.clear()

# Android's back button / gesture: back through the menus, and out of the
# app from the main menu. In a game, the game handles it (options panel).
func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST:
		return
	if _game != null:
		_game.toggle_options()
	elif can_go_back():
		back()
	else:
		get_tree().quit()
