class_name InfoVfx
extends Control
## P0 info feedback — tweens only, no particles/shaders. See docs/VFX_P0.md.

const GOOD_PIP := preload("res://assets/art/factory/good_pip.svg")
const DEFECT_PIP := preload("res://assets/art/factory/defect_pip.svg")
const COL_PAPER := Color(0.957, 0.945, 0.918)  # #F4F1EA
const COL_OK := Color(0.365, 0.831, 0.627)     # #5DD4A0
const COL_DEFECT := Color(0.886, 0.357, 0.290) # #E25B4A
const COL_COOL := Color(0.769, 0.361, 0.361)   # #C45C5C
const DUR := 0.2  # 180–220ms

var _machine: Control
var _mold: Control
var _bin: Control
var _balance: Control
var _mold_base_modulate: Color = Color.WHITE
var _machine_base_modulate: Color = Color.WHITE

func setup(machine: Control, mold: Control, bin: Control, balance: Control) -> void:
	_machine = machine
	_mold = mold
	_bin = bin
	_balance = balance
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _mold:
		_mold_base_modulate = _mold.modulate
	if _machine:
		_machine_base_modulate = _machine.modulate

func play_shot(good: int, bad: int) -> void:
	if good > 0:
		_inject_success()
	if bad > 0:
		_defect()

func play_overheat() -> void:
	if _machine == null:
		return
	var tw := create_tween()
	# Pulse ×2 toward machine_cool #C45C5C (~150ms per pulse)
	for _i in 2:
		tw.tween_property(_machine, "modulate", COL_COOL, 0.075)
		tw.tween_property(_machine, "modulate", _machine_base_modulate, 0.075)

func play_delivery(ok: bool) -> void:
	if ok:
		_balance_punch()
	else:
		_machine_dim()

func _inject_success() -> void:
	if _mold == null:
		return
	# White flash on mold
	var flash := ColorRect.new()
	flash.color = COL_PAPER
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mold.add_child(flash)
	# good_pip float
	var pip := TextureRect.new()
	pip.texture = GOOD_PIP
	pip.modulate = COL_OK
	pip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pip.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pip.custom_minimum_size = Vector2(64, 64)
	pip.size = Vector2(64, 64)
	add_child(pip)
	var center: Vector2 = _mold.global_position + _mold.size * 0.5 - Vector2(32, 32)
	pip.global_position = center
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(flash, "modulate:a", 0.0, 0.05)
	tw.tween_property(pip, "position:y", pip.position.y - 24.0, DUR)
	tw.tween_property(pip, "modulate:a", 0.0, DUR)
	tw.chain().tween_callback(func() -> void:
		if is_instance_valid(flash):
			flash.queue_free()
		if is_instance_valid(pip):
			pip.queue_free()
	)

func _defect() -> void:
	if _bin == null:
		return
	var pip := TextureRect.new()
	pip.texture = DEFECT_PIP
	pip.modulate = COL_DEFECT
	pip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pip.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pip.custom_minimum_size = Vector2(48, 48)
	pip.size = Vector2(48, 48)
	add_child(pip)
	var top: Vector2 = _bin.global_position + Vector2(_bin.size.x * 0.5 - 24.0, -8.0)
	pip.global_position = top
	var base: Vector2 = _bin.position
	var tw := create_tween()
	# Shake ±3px ×2
	tw.tween_property(_bin, "position:x", base.x + 3.0, 0.04)
	tw.tween_property(_bin, "position:x", base.x - 3.0, 0.04)
	tw.tween_property(_bin, "position:x", base.x + 3.0, 0.04)
	tw.tween_property(_bin, "position:x", base.x, 0.04)
	var tw2 := create_tween()
	tw2.tween_property(pip, "modulate:a", 0.0, DUR)
	tw2.tween_callback(func() -> void:
		if is_instance_valid(pip):
			pip.queue_free()
	)

func _balance_punch() -> void:
	if _balance == null:
		return
	_balance.pivot_offset = _balance.size * 0.5
	var tw := create_tween()
	tw.tween_property(_balance, "scale", Vector2(1.12, 1.12), 0.1)
	tw.tween_property(_balance, "scale", Vector2.ONE, 0.1)

func _machine_dim() -> void:
	if _machine == null:
		return
	var tw := create_tween()
	tw.tween_property(_machine, "modulate", Color(0.45, 0.45, 0.45, 1.0), 0.08)
	tw.tween_property(_machine, "modulate", _machine_base_modulate, 0.16)
