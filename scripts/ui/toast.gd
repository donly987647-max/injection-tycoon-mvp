class_name ToastOverlay
extends Control
## Fail/info toasts. Auto-hide.

@onready var _panel: PanelContainer = $Panel
@onready var _label: Label = $Panel/Margin/Label

var _tween: Tween

func _ready() -> void:
	modulate.a = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = true
	GameState.toast_requested.connect(show_toast)

func show_toast(message: String, kind: String = "fail") -> void:
	_label.text = message
	var sb := StyleBoxFlat.new()
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	match kind:
		"fail":
			sb.bg_color = Color(0.72, 0.18, 0.18, 0.95)
		"warn":
			sb.bg_color = Color(0.72, 0.48, 0.10, 0.95)
		_:
			sb.bg_color = Color(0.16, 0.42, 0.32, 0.95)
	_panel.add_theme_stylebox_override("panel", sb)
	if _tween:
		_tween.kill()
	modulate.a = 1.0
	_tween = create_tween()
	_tween.tween_interval(2.2)
	_tween.tween_property(self, "modulate:a", 0.0, 0.4)
