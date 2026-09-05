class_name ConfirmSheet
extends ColorRect
## Success / settlement bottom sheet.

signal closed()

@onready var _title: Label = $Center/Card/VBox/Title
@onready var _body: Label = $Center/Card/VBox/Body
@onready var _ok: Button = $Center/Card/VBox/Ok

var _closing: bool = false

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ok.pressed.connect(_on_ok)
	GameState.settlement_requested.connect(show_result)

func show_result(result: Dictionary) -> void:
	# Mash-safe: while already open, refresh content but ignore re-entrant OK spam.
	_closing = false
	_title.text = str(result.get("title", "알림"))
	_body.text = str(result.get("body", ""))
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	GameState.sheet_open = true
	_ok.disabled = false
	_ok.grab_focus()
	# Re-disable board/mold actions while sheet is up.
	GameState.state_changed.emit()

func _on_ok() -> void:
	if _closing or not visible:
		return
	_closing = true
	_ok.disabled = true
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameState.sheet_open = false
	closed.emit()
	# Re-enable Accept/Swap after sheet closes.
	GameState.state_changed.emit()
	_closing = false
