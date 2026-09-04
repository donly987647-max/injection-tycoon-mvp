extends Control
## Factory view + HUD + panels. Art Bible palette + SVG placeholders.
## Colors: docs/ART_BIBLE.md §3. Sprites: res://assets/art/

const COL_IDLE := Color(0.278, 0.337, 0.420)   # machine_idle #47566B
const COL_RUN := Color(0.290, 0.624, 0.831)    # machine_run  #4A9FD4
const COL_SWAP := Color(0.878, 0.659, 0.227)   # machine_swap #E0A83A
const COL_COOL := Color(0.769, 0.361, 0.361)   # machine_cool #C45C5C
const COL_MOLD_CAP := Color(0.494, 0.769, 0.941)   # #7EC4F0
const COL_MOLD_CASE := Color(0.365, 0.831, 0.627)  # #5DD4A0
const COL_MOLD_TOY := Color(0.878, 0.545, 0.753)   # #E08BC0
const COL_HOPPER := Color(0.239, 0.549, 0.345)     # #3D8C58
const COL_BIN_EMPTY := Color(0.165, 0.200, 0.251)  # #2A3340
const COL_BIN_GOOD := Color(0.227, 0.494, 0.769)   # #3A7EC4

## Base layout insets before device Safe Area (matches scene defaults).
const HUD_BASE_H := 118.0
const BOTTOM_BASE_H := 210.0
const PANEL_TOP_BASE := 130.0
const PANEL_BOTTOM_BASE := 220.0
const TOAST_TOP_BASE := 126.0
const TOAST_BOTTOM_BASE := 190.0

@onready var hud: PanelContainer = $HUD
@onready var hud_order: Label = %HudOrder
@onready var hud_defect: Label = %HudDefect
@onready var hud_balance: Label = %HudBalance
@onready var hud_cycle: Label = %HudCycle
@onready var hud_mat: Label = %HudMat
@onready var factory: Control = $Factory
@onready var bottom: PanelContainer = $Bottom
@onready var line_status: Label = %LineStatus
@onready var heat_bar: ProgressBar = %HeatBar
@onready var machine: ColorRect = %Machine
@onready var mold_block: ColorRect = %MoldBlock
@onready var hopper: ColorRect = %Hopper
@onready var output_bin: ColorRect = %OutputBin
@onready var order_board: OrderBoardPanel = %OrderBoard
@onready var mold_panel: MoldSwapPanel = %MoldPanel
@onready var help_label: Label = %HelpLabel
@onready var toast: Control = %Toast

func _ready() -> void:
	# Mobile HUD lock: only order / defect / balance on the strip.
	hud_cycle.visible = false
	hud_mat.visible = false
	GameState.state_changed.connect(_refresh)
	GameState.cycle_advanced.connect(func(_c: int) -> void: _pulse_machine())
	resized.connect(_on_resized)
	machine.resized.connect(_center_machine_pivot)
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()
	_center_machine_pivot()
	_refresh()

func _on_resized() -> void:
	_apply_safe_area()
	_center_machine_pivot()

func _center_machine_pivot() -> void:
	machine.pivot_offset = machine.size * 0.5

## Map DisplayServer safe area into viewport pixels and pad main chrome.
func _apply_safe_area() -> void:
	var margins := _safe_area_margins()
	var top := margins.y
	var bottom_m := margins.w
	var left := margins.x
	var right := margins.z

	hud.offset_left = left
	hud.offset_right = -right
	hud.offset_top = top
	hud.offset_bottom = top + HUD_BASE_H

	bottom.offset_left = left
	bottom.offset_right = -right
	bottom.offset_top = -(BOTTOM_BASE_H + bottom_m)
	bottom.offset_bottom = -bottom_m

	factory.offset_left = left
	factory.offset_right = -right
	factory.offset_top = top + HUD_BASE_H
	factory.offset_bottom = -(BOTTOM_BASE_H + bottom_m)

	order_board.offset_left = 16.0 + left
	order_board.offset_right = -(16.0 + right)
	order_board.offset_top = top + PANEL_TOP_BASE
	order_board.offset_bottom = -(PANEL_BOTTOM_BASE + bottom_m)

	mold_panel.offset_left = 16.0 + left
	mold_panel.offset_right = -(16.0 + right)
	mold_panel.offset_top = top + PANEL_TOP_BASE
	mold_panel.offset_bottom = -(PANEL_BOTTOM_BASE + bottom_m)

	toast.offset_left = left
	toast.offset_right = -right
	toast.offset_top = top + TOAST_TOP_BASE
	toast.offset_bottom = top + TOAST_BOTTOM_BASE

## Returns Vector4(left, top, right, bottom) in viewport coordinates.
func _safe_area_margins() -> Vector4:
	var safe := DisplayServer.get_display_safe_area()
	var win := DisplayServer.window_get_size()
	if win.x <= 0 or win.y <= 0:
		return Vector4.ZERO
	var view_size := get_viewport().get_visible_rect().size
	if view_size.x <= 0.0 or view_size.y <= 0.0:
		return Vector4.ZERO
	var sx := view_size.x / float(win.x)
	var sy := view_size.y / float(win.y)
	var left := maxf(0.0, float(safe.position.x) * sx)
	var top := maxf(0.0, float(safe.position.y) * sy)
	var right := maxf(0.0, float(win.x - safe.position.x - safe.size.x) * sx)
	var bottom_m := maxf(0.0, float(win.y - safe.position.y - safe.size.y) * sy)
	return Vector4(left, top, right, bottom_m)

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
	# Cycle / Resin stay off the mobile HUD strip (nodes remain for debug if unhidden).
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
			machine.color = COL_RUN
		LineState.Status.SWAPPING:
			machine.color = COL_SWAP
		LineState.Status.COOLING:
			machine.color = COL_COOL
		_:
			machine.color = COL_IDLE
	mold_block.visible = mold != null
	if mold:
		mold_block.color = COL_MOLD_CAP if mold.id == "mold_cap" else (
			COL_MOLD_CASE if mold.id == "mold_case" else COL_MOLD_TOY
		)
	var mat_t := clampf(float(GameState.materials) / 250.0, 0.15, 1.0)
	hopper.color = Color(COL_HOPPER, mat_t)
	if GameState.active_order:
		var p := clampf(float(GameState.active_order.good_units_produced) / float(maxi(GameState.active_order.quantity, 1)), 0.2, 1.0)
		output_bin.color = Color(COL_BIN_GOOD, p)
		help_label.text = _hint_for_order()
	else:
		output_bin.color = COL_BIN_EMPTY
		help_label.text = "Open Orders → Accept → Molds → Swap → Inject → Cycle → Deliver"

func _hint_for_order() -> String:
	var o := GameState.active_order
	var mold := GameState.current_mold()
	if GameState.line.status == LineState.Status.SWAPPING:
		return "Swapping… advance cycles (%d left)." % GameState.line.swap_remaining
	if mold == null or mold.item != o.item:
		return "Swap to the %s mold, then Inject." % o.item
	if o.good_units_produced >= o.quantity:
		return "Quota met. Deliver before cycle %d." % o.deadline
	if GameState.line.is_running():
		return "Injecting… advance cycles. Stop if heat spikes."
	return "Start Inject, then advance cycles until %d good." % o.quantity

func _pulse_machine() -> void:
	var tw := create_tween()
	tw.tween_property(machine, "scale", Vector2(1.03, 1.03), 0.08)
	tw.tween_property(machine, "scale", Vector2.ONE, 0.12)

func _on_orders() -> void:
	if GameState.sheet_open or GameState.is_settling():
		return
	mold_panel.visible = false
	order_board.open()

func _on_molds() -> void:
	if GameState.sheet_open or GameState.is_settling():
		return
	order_board.visible = false
	mold_panel.open()

func _on_inject() -> void:
	if GameState.sheet_open or GameState.is_settling():
		return
	GameState.try_start_injection()

func _on_stop() -> void:
	if GameState.sheet_open or GameState.is_settling():
		return
	GameState.try_stop_injection()

func _on_deliver() -> void:
	if GameState.sheet_open or GameState.is_settling():
		return
	GameState.try_deliver()

func _on_cycle() -> void:
	GameState.advance_cycle()

func _on_buy() -> void:
	GameState.buy_materials()

func _on_reset() -> void:
	GameState.reset_game()
