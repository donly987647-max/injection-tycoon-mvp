class_name ConfirmSheet
extends ColorRect
## Success / settlement bottom sheet.

signal closed()

@onready var _title: Label = $Center/Card/VBox/Title
@onready var _body: Label = $Center/Card/VBox/Body
@onready var _ok: Button = $Center/Card/VBox/Ok

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ok.pressed.connect(_on_ok)
	GameState.settlement_requested.connect(show_result)

func show_result(result: Dictionary) -> void:
	_title.text = str(result.get("title", "Notice"))
	_body.text = str(result.get("body", ""))
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_ok.grab_focus()

func _on_ok() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	closed.emit()
