class_name MoldSwapPanel
extends PanelContainer

@onready var _list: VBoxContainer = $Margin/VBox/Scroll/List
@onready var _close: Button = $Margin/VBox/Header/Close

func _ready() -> void:
	visible = false
	_close.pressed.connect(func() -> void: visible = false)
	GameState.state_changed.connect(refresh)

func open() -> void:
	if GameState.sheet_open or GameState.is_settling():
		return
	refresh()
	visible = true

func refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var cur := GameState.current_mold()
	info.text = "장착: %s\n라인: %s" % [
		cur.name if cur else "(없음)",
		GameState.line.status_str(),
	]
	_list.add_child(info)
	for mold in GameState.molds:
		_list.add_child(_row(mold))

func _row(mold: MoldData) -> Control:
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.14, 0.16, 0.22, 1)
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	box.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	box.add_child(v)
	var title := Label.new()
	var lock := "" if mold.owned else "  🔒 미보유"
	var on := "  ● 장착됨" if GameState.line.current_mold_id == mold.id else ""
	title.text = "%s  → %s%s%s" % [mold.name, mold.item, lock, on]
	title.add_theme_font_size_override("font_size", 16)
	v.add_child(title)
	var meta := Label.new()
	meta.text = "교체 %d사이클   원료 %d/개   열 +%.0f/사이클" % [
		mold.swap_time, mold.material_per_unit, mold.heat_per_cycle,
	]
	meta.modulate = Color(0.8, 0.85, 0.9)
	v.add_child(meta)
	var btn := Button.new()
	btn.text = "교체" if mold.owned else "잠김"
	btn.custom_minimum_size = Vector2(0, 44)
	var busy := not GameState.can_interact() or GameState.is_swapping()
	btn.disabled = (not mold.owned) or busy
	var mid := mold.id
	btn.pressed.connect(func() -> void: _on_swap(mid))
	v.add_child(btn)
	return box

func _on_swap(mold_id: String) -> void:
	if not GameState.can_interact() or GameState.is_swapping():
		return
	GameState.try_start_swap(mold_id)
