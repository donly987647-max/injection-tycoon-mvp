class_name OrderBoardPanel
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
	if GameState.board_orders.is_empty():
		var empty := Label.new()
		empty.text = "No orders. Advance a cycle."
		_list.add_child(empty)
		return
	for order in GameState.board_orders:
		_list.add_child(_row(order))

func _row(order: OrderData) -> Control:
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.18, 0.28, 1)
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
	var near := order.is_near_deadline(GameState.cycle)
	var tag := order.margin_tag_str().to_upper()
	title.text = "%s  [%s]%s" % [order.item, tag, "  ⚠ NEAR DEADLINE" if near else ""]
	title.add_theme_font_size_override("font_size", 18)
	v.add_child(title)
	var meta := Label.new()
	meta.text = "Qty %d   due C%d (%d left)   $%d   pen $%d" % [
		order.quantity, order.deadline, order.remaining_cycles(GameState.cycle),
		order.reward, order.penalty,
	]
	meta.modulate = Color(0.8, 0.85, 0.9)
	v.add_child(meta)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	v.add_child(actions)
	var locked := not GameState.can_interact()
	var accept := Button.new()
	accept.text = "Accept"
	accept.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	accept.disabled = locked
	var oid := order.id
	accept.pressed.connect(func() -> void: _on_accept(oid))
	actions.add_child(accept)
	var reject := Button.new()
	reject.text = "Reject"
	reject.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reject.disabled = locked
	reject.pressed.connect(func() -> void: _on_reject(oid))
	actions.add_child(reject)
	return box

func _on_accept(order_id: String) -> void:
	if not GameState.can_interact():
		return
	GameState.try_accept_order(order_id)

func _on_reject(order_id: String) -> void:
	if not GameState.can_interact():
		return
	GameState.try_reject_order(order_id)
