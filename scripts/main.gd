extends Control
## Factory view + HUD + panels. Desktop-playable ColorRect placeholders.

@onready var hud_order: Label = %HudOrder
@onready var hud_defect: Label = %HudDefect
@onready var hud_balance: Label = %HudBalance
@onready var hud_cycle: Label = %HudCycle
@onready var hud_mat: Label = %HudMat
@onready var line_status: Label = %LineStatus
@onready var heat_bar: ProgressBar = %HeatBar
@onready var machine: ColorRect = %Machine
@onready var mold_block: ColorRect = %MoldBlock
@onready var hopper: ColorRect = %Hopper
@onready var output_bin: ColorRect = %OutputBin
@onready var order_board: OrderBoardPanel = %OrderBoard
@onready var mold_panel: MoldSwapPanel = %MoldPanel
@onready var help_label: Label = %HelpLabel

func _ready() -> void:
	GameState.state_changed.connect(_refresh)
	GameState.cycle_advanced.connect(func(_c: int) -> void: _pulse_machine())
	resized.connect(_center_machine_pivot)
	machine.resized.connect(_center_machine_pivot)
	_center_machine_pivot()
	_refresh()

func _center_machine_pivot() -> void:
	machine.pivot_offset = machine.size * 0.5

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_O:
				_on_orders()
			KEY_M:
				_on_molds()
			KEY_I:
				_on_inject()
			KEY_S:
				_on_stop()
			KEY_D:
				_on_deliver()
			KEY_B:
				GameState.buy_materials()
			KEY_R:
				GameState.reset_game()
			KEY_C, KEY_N:
				GameState.advance_cycle()
			_:
				return
		get_viewport().set_input_as_handled()

func _refresh() -> void:
	hud_order.text = GameState.order_summary()
	hud_defect.text = "Defect  %s" % GameState.hud_defect_text()
	hud_balance.text = "$%d" % GameState.balance
	hud_cycle.text = "Cycle %d" % GameState.cycle
	hud_mat.text = "Resin %d" % GameState.materials
	var mold := GameState.current_mold()
	var mold_name := mold.name if mold else "No mold"
	line_status.text = "%s  |  %s  |  heat %.0f/%.0f" % [
		GameState.line.status_str(), mold_name, GameState.line.heat, GameState.line.max_heat,
	]
	heat_bar.max_value = GameState.line.max_heat
	heat_bar.value = GameState.line.heat
	match GameState.line.status:
		LineState.Status.RUNNING:
			machine.color = Color(0.35, 0.62, 0.85)
		LineState.Status.SWAPPING:
			machine.color = Color(0.85, 0.68, 0.28)
		LineState.Status.COOLING:
			machine.color = Color(0.55, 0.35, 0.35)
		_:
			machine.color = Color(0.28, 0.34, 0.42)
	mold_block.visible = mold != null
	if mold:
		mold_block.color = Color(0.55, 0.75, 0.95) if mold.id == "mold_cap" else (
			Color(0.45, 0.85, 0.65) if mold.id == "mold_case" else Color(0.85, 0.55, 0.75)
		)
	var mat_t := clampf(float(GameState.materials) / 250.0, 0.15, 1.0)
	hopper.color = Color(0.25, 0.55, 0.35, mat_t)
	if GameState.active_order:
		var p := clampf(float(GameState.active_order.good_units_produced) / float(maxi(GameState.active_order.quantity, 1)), 0.2, 1.0)
		output_bin.color = Color(0.2, 0.45, 0.75, p)
		help_label.text = _hint_for_order()
	else:
		output_bin.color = Color(0.18, 0.22, 0.28)
		help_label.text = "Open Orders (O) → Accept → Molds (M) → Swap → Inject (I) → Cycle (C/N) → Deliver (D)"

func _hint_for_order() -> String:
	var o := GameState.active_order
	var mold := GameState.current_mold()
	if GameState.line.status == LineState.Status.SWAPPING:
		return "Swapping… advance cycles (%d left)." % GameState.line.swap_remaining
	if mold == null or mold.item != o.item:
		return "Swap to the %s mold, then Inject." % o.item
	if o.good_units_produced >= o.quantity:
		return "Quota met. Deliver (D) before cycle %d." % o.deadline
	if GameState.line.is_running():
		return "Injecting… advance cycles. Stop (S) if heat spikes."
	return "Start Inject (I), then advance cycles until %d good." % o.quantity

func _pulse_machine() -> void:
	var tw := create_tween()
	tw.tween_property(machine, "scale", Vector2(1.03, 1.03), 0.08)
	tw.tween_property(machine, "scale", Vector2.ONE, 0.12)

func _on_orders() -> void:
	mold_panel.visible = false
	order_board.open()

func _on_molds() -> void:
	order_board.visible = false
	mold_panel.open()

func _on_inject() -> void:
	GameState.try_start_injection()

func _on_stop() -> void:
	GameState.try_stop_injection()

func _on_deliver() -> void:
	GameState.try_deliver()

func _on_cycle() -> void:
	GameState.advance_cycle()

func _on_buy() -> void:
	GameState.buy_materials()

func _on_reset() -> void:
	GameState.reset_game()
