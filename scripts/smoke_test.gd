extends Node
## Headless happy-path + fail-branch smoke.
##   godot --headless --path /workspace/injection-tycoon-mvp res://scenes/smoke.tscn

var _fails: PackedStringArray = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	GameState.reset_game()
	_test_order_fails()
	_test_mold_fails()
	_test_injection_fail_stops()
	_test_happy_path()
	_test_delivery_fail_settlement()
	_test_save_exists()
	if _fails.size() > 0:
		push_error("SMOKE FAIL:\n" + "\n".join(_fails))
		print("SMOKE FAIL (%d)" % _fails.size())
		get_tree().quit(1)
	else:
		print("SMOKE OK  cycle=%d  balance=%d  save=%s" % [
			GameState.cycle, GameState.balance, GameState.SAVE_PATH,
		])
		get_tree().quit(0)

func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fails.append(msg)
		print("  FAIL: ", msg)
	else:
		print("  ok: ", msg)

func _test_order_fails() -> void:
	print("-- order fail branches")
	var near := GameState.debug_push_order({
		"item": "Bottle Cap", "quantity": 10, "deadline": GameState.cycle + 1,
		"reward": 100, "margin_tag": "bulk", "penalty": 50,
	})
	var r: Dictionary = GameState.try_accept_order(near.id)
	_check(r.get("ok") == false, "accept fail when deadline <= 1 cycle")
	var good := GameState.debug_push_order({
		"item": "Bottle Cap", "quantity": 20, "deadline": GameState.cycle + 12,
		"reward": 200, "margin_tag": "bulk", "penalty": 80,
	})
	r = GameState.try_accept_order(good.id)
	_check(r.get("ok") == true, "accept when slot free and not near-deadline")
	var extra := GameState.debug_push_order({
		"item": "Phone Case", "quantity": 10, "deadline": GameState.cycle + 10,
		"reward": 200, "margin_tag": "special", "penalty": 80,
	})
	r = GameState.try_accept_order(extra.id)
	_check(r.get("ok") == false, "accept fail when slots full")
	var near2 := GameState.debug_push_order({
		"item": "Phone Case", "quantity": 10, "deadline": GameState.cycle + 0,
		"reward": 100, "margin_tag": "special", "penalty": 50,
	})
	r = GameState.try_reject_order(near2.id)
	_check(r.get("ok") == false, "reject near-deadline is a fail toast")

func _test_mold_fails() -> void:
	print("-- mold fail branches")
	var r: Dictionary = GameState.try_start_swap("mold_toy")
	_check(r.get("ok") == false, "swap fail if mold not owned")
	r = GameState.try_start_swap("mold_cap")
	_check(r.get("ok") == true, "swap start when idle and owned")
	while GameState.line.status == LineState.Status.SWAPPING:
		GameState.advance_cycle()
	_check(GameState.line.current_mold_id == "mold_cap", "swap completes after swap_time")
	r = GameState.try_start_injection()
	_check(r.get("ok") == true, "injection starts with matching owned mold")
	r = GameState.try_start_swap("mold_case")
	_check(r.get("ok") == false, "swap fail if line running")
	GameState.try_stop_injection()

func _test_injection_fail_stops() -> void:
	print("-- injection fail stops")
	# shortage before start
	var saved_mat := GameState.materials
	GameState.materials = 0
	var r: Dictionary = GameState.try_start_injection()
	_check(r.get("ok") == false, "injection fail on material shortage")
	GameState.materials = saved_mat
	# overheat before start
	GameState.line.heat = GameState.line.max_heat
	r = GameState.try_start_injection()
	_check(r.get("ok") == false, "injection fail on overheat")
	GameState.line.heat = 0.0
	# overheat mid-run
	r = GameState.try_start_injection()
	_check(r.get("ok") == true, "injection running for overheat tick")
	GameState.line.heat = GameState.line.max_heat - 1.0
	GameState.advance_cycle()
	_check(GameState.line.status == LineState.Status.COOLING, "overheat fail-stop cools the line")
	GameState.line.heat = 0.0
	GameState.line.status = LineState.Status.IDLE

func _test_happy_path() -> void:
	print("-- happy path to settlement save")
	if GameState.active_order == null:
		var o := GameState.debug_push_order({
			"item": "Bottle Cap", "quantity": 20, "deadline": GameState.cycle + 20,
			"reward": 220, "margin_tag": "bulk", "penalty": 80,
		})
		GameState.try_accept_order(o.id)
	if GameState.line.current_mold_id != "mold_cap":
		GameState.try_start_swap("mold_cap")
		while GameState.line.status == LineState.Status.SWAPPING:
			GameState.advance_cycle()
	if not GameState.line.is_running():
		var start: Dictionary = GameState.try_start_injection()
		_check(start.get("ok") == true, "inject for happy path")
	else:
		_check(true, "inject for happy path")
	var guard := 0
	while GameState.active_order and GameState.active_order.good_units_produced < GameState.active_order.quantity and guard < 40:
		GameState.advance_cycle()
		if GameState.line.status != LineState.Status.RUNNING:
			if GameState.materials < 20:
				GameState.buy_materials(80, 80)
			GameState.advance_cycle()
			GameState.try_start_injection()
		guard += 1
	_check(GameState.active_order != null, "order still active before deliver")
	if GameState.active_order:
		_check(GameState.active_order.good_units_produced >= GameState.active_order.quantity, "quota met")
	if GameState.line.is_running():
		GameState.try_stop_injection()
	var d: Dictionary = GameState.try_deliver()
	_check(d.get("ok") == true, "delivery+settlement success credits reward")
	_check(GameState.active_order == null, "slot free after settle")

func _test_delivery_fail_settlement() -> void:
	print("-- delivery fail + penalty settlement")
	var bal := GameState.balance
	var late := GameState.debug_push_order({
		"item": "Bottle Cap", "quantity": 80, "deadline": GameState.cycle + 2,
		"reward": 400, "margin_tag": "bulk", "penalty": 90,
	})
	var acc: Dictionary = GameState.try_accept_order(late.id)
	_check(acc.get("ok") == true, "accept short-lead order for fail settle")
	# skip production; blow past deadline
	GameState.advance_cycle()
	GameState.advance_cycle()
	GameState.advance_cycle()
	var d: Dictionary = GameState.try_deliver()
	_check(d.get("ok") == false, "delivery/settlement fail when short and late")
	_check(GameState.balance == bal - 90, "penalty applied on fail settlement")
	_check(GameState.active_order == null, "slot freed after fail settle")

func _test_save_exists() -> void:
	print("-- save")
	_check(FileAccess.file_exists(GameState.SAVE_PATH), "user://save_v1.json exists after settle")
	var f := FileAccess.open(GameState.SAVE_PATH, FileAccess.READ)
	if f == null:
		_check(false, "could not read save")
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	_check(typeof(parsed) == TYPE_DICTIONARY, "save is JSON object")
	if typeof(parsed) == TYPE_DICTIONARY:
		_check(int(parsed.get("save_version", 0)) == 1, "save_version == 1")
		_check(int(parsed.get("balance", 0)) >= 1000, "balance credited")
