class_name ConfirmSheet
extends ColorRect
## Success / settlement bottom sheet.

signal closed()

@onready var _title: Label = $Center/Card/VBox/Title
@onready var _body: Label = $Center/Card/VBox/Body
@onready var _ok: Button = $Center/Card/VBox/Ok
@onready var _card: PanelContainer = $Center/Card

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
	_tint_card(result)
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	GameState.sheet_open = true
	_ok.disabled = false
	_ok.grab_focus()
	# Re-disable board/mold actions while sheet is up.
	GameState.state_changed.emit()

func _tint_card(result: Dictionary) -> void:
	var sb := StyleBoxFlat.new()
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 8
	sb.content_margin_bottom = 12
	var kind := str(result.get("kind", ""))
	if kind == "settlement" and bool(result.get("ok", false)):
		sb.bg_color = Color(0.365, 0.831, 0.627, 0.22)  # ok #5DD4A0 tint
	elif kind == "settlement":
		sb.bg_color = Color(0.886, 0.357, 0.290, 0.18)
	else:
		sb.bg_color = Color(0.14, 0.18, 0.24, 1.0)
	_card.add_theme_stylebox_override("panel", sb)

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
