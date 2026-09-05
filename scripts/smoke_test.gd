extends Node
## Headless happy-path + fail-branch smoke.
##   godot --headless --path /workspace/injection-tycoon-mvp res://scenes/smoke.tscn

var _fails: PackedStringArray = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	GameState.reset_game()
	GameState.rng.seed = 42  ## deterministic defects for smoke
	_test_onboarding_flags()
	_test_order_fails()
	_test_mold_fails()
	_test_injection_fail_stops()
	_test_happy_path()
	_test_delivery_fail_settlement()
	_test_save_exists()
	_test_mash_guards()
	_test_save_load_roundtrip()
	_test_force_quit_recovery()
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

func _test_onboarding_flags() -> void:
	print("-- onboarding auto-accept + flags")
	# reset_game alone must NOT auto-accept (smoke / headless safety)
	_check(GameState.active_order == null, "reset_game leaves slot empty (no auto-accept in GameState)")
	_check(GameState.onboarding_done == false, "onboarding_done false on new game")
	_check(GameState.guide_dismissed == false, "guide_dismissed false on new game")
	var ok := GameState.ensure_tutorial_onboarding()
	_check(ok == true, "ensure_tutorial_onboarding accepts tutorial")
	_check(GameState.active_order != null, "tutorial order active after ensure")
	_check(GameState.active_order.item == "병 마개", "tutorial item 병 마개")
	_check(GameState.active_order.quantity == 20, "tutorial qty 20")
	_check(GameState.active_order.reward == 150, "tutorial reward 150")
	_check(GameState.active_order.penalty == 0, "tutorial penalty 0")
	_check(GameState.active_order.lead_cycles == 120, "tutorial lead_cycles 120")
	_check(GameState.should_show_guide() == true, "guide visible before dismiss / delivery")
	GameState.dismiss_guide()
	_check(GameState.guide_dismissed == true, "guide_dismissed after X")
	_check(GameState.should_show_guide() == false, "guide hidden after dismiss")
	_check(GameState.active_order != null, "tutorial stays accepted after skip X")
	# Clear slot so subsequent order-fail tests can accept freely
	GameState.active_order = null
	GameState.guide_dismissed = false  # leave flags mostly fresh; onboarding still false
	GameState._changed()

func _test_order_fails() -> void:
	print("-- order fail branches")
	var near := GameState.debug_push_order({
		"item": "병 마개", "quantity": 10, "deadline": GameState.cycle + 1,
		"reward": 100, "margin_tag": "bulk", "penalty": 40,
	})
	var r: Dictionary = GameState.try_accept_order(near.id)
	_check(r.get("ok") == false, "accept fail when deadline <= 1 cycle")
	var good := GameState.debug_push_order({
		"item": "병 마개", "quantity": 20, "deadline": GameState.cycle + 120,
		"reward": 150, "margin_tag": "bulk", "penalty": 0,
	})
	r = GameState.try_accept_order(good.id)
	_check(r.get("ok") == true, "accept when slot free and not near-deadline")
	_check(GameState.active_order.lead_cycles >= 100, "accepted order stores lead_cycles")
	_check(GameState.is_active_deadline_urgent() == false, "not urgent at full lead window")
	var extra := GameState.debug_push_order({
		"item": "폰케이스", "quantity": 30, "deadline": GameState.cycle + 90,
		"reward": 500, "margin_tag": "special", "penalty": 200,
	})
	r = GameState.try_accept_order(extra.id)
	_check(r.get("ok") == false, "accept fail when slots full")
	var near2 := GameState.debug_push_order({
		"item": "폰케이스", "quantity": 10, "deadline": GameState.cycle + 0,
		"reward": 100, "margin_tag": "special", "penalty": 40,
	})
	r = GameState.try_reject_order(near2.id)
	_check(r.get("ok") == false, "reject near-deadline is a fail toast")

func _test_mold_fails() -> void:
	print("-- mold fail branches")
	var r: Dictionary = GameState.try_start_swap("mold_toy")
	_check(r.get("ok") == false, "swap fail if mold not owned")
	r = GameState.try_start_swap("mold_cap")
	_check(r.get("ok") == true, "swap start when idle and owned")
	var swap_guard := 0
	while GameState.line.status == LineState.Status.SWAPPING and swap_guard < 20:
		GameState.advance_cycle()
		swap_guard += 1
	_check(GameState.line.current_mold_id == "mold_cap", "swap completes after swap_time (8)")
	_check(swap_guard == 8, "mold swap takes 8 cycles")
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
	_check(is_equal_approx(GameState.line.max_heat, 80.0), "max_heat is 80")
	GameState.line.heat = 0.0
	# overheat mid-run
	r = GameState.try_start_injection()
	_check(r.get("ok") == true, "injection running for overheat tick")
	GameState.line.heat = GameState.line.max_heat - 1.0
	GameState.advance_cycle()
	_check(GameState.line.status == LineState.Status.COOLING, "overheat fail-stop cools the line")
	# Warn threshold is 80% of max_heat (64)
	_check(is_equal_approx(GameState.heat_warn_threshold(), 64.0), "heat warn threshold 64")
	GameState.line.heat = 0.0
	GameState.line.status = LineState.Status.IDLE

func _cool_until_ready(max_cycles: int = 40) -> void:
	var n := 0
	while GameState.line.heat > 0.0 and n < max_cycles:
		if GameState.line.is_running():
			GameState.try_stop_injection()
		GameState.advance_cycle()
		n += 1
	GameState.line.status = LineState.Status.IDLE

func _test_happy_path() -> void:
	print("-- happy path to settlement save")
	if GameState.active_order == null:
		var o := GameState.debug_push_order({
			"item": "병 마개", "quantity": 20, "deadline": GameState.cycle + 200,
			"reward": 150, "margin_tag": "bulk", "penalty": 0,
		})
		GameState.try_accept_order(o.id)
	if GameState.line.current_mold_id != "mold_cap":
		GameState.try_start_swap("mold_cap")
		while GameState.line.status == LineState.Status.SWAPPING:
			GameState.advance_cycle()
	_cool_until_ready()
	if not GameState.line.is_running():
		var start: Dictionary = GameState.try_start_injection()
		_check(start.get("ok") == true, "inject for happy path")
	else:
		_check(true, "inject for happy path")
	var guard := 0
	while GameState.active_order and GameState.active_order.good_units_produced < GameState.active_order.quantity and guard < 400:
		GameState.advance_cycle()
		if GameState.line.status != LineState.Status.RUNNING:
			if GameState.materials < 5:
				GameState.buy_materials(80, 80)
			# Cool a few cycles so heat drops enough to run a stretch again
			var cool_n := 0
			while GameState.line.heat >= GameState.line.max_heat - 16.0 and cool_n < 20:
				GameState.advance_cycle()
				cool_n += 1
			GameState.line.status = LineState.Status.IDLE
			GameState.try_start_injection()
		guard += 1
	_check(GameState.active_order != null, "order still active before deliver")
	if GameState.active_order:
		_check(GameState.active_order.good_units_produced >= GameState.active_order.quantity, "quota met")
	if GameState.line.is_running():
		GameState.try_stop_injection()
	# Avoid flaky excess-defect fail in smoke: clamp produced defects for settle check
	if GameState.active_order:
		var tot := GameState.active_order.good_units_produced + GameState.active_order.defect_units_produced
		if tot > 0 and float(GameState.active_order.defect_units_produced) / float(tot) > GameState.EXCESS_DEFECT_RATIO:
			GameState.active_order.defect_units_produced = int(GameState.active_order.good_units_produced * 0.1)
	var bal_before := GameState.balance
	var reward := GameState.active_order.reward if GameState.active_order else 0
	var d: Dictionary = GameState.try_deliver()
	_check(d.get("ok") == true, "delivery+settlement success credits reward")
	_check(GameState.balance == bal_before + reward, "reward credited (+%d)" % reward)
	_check(GameState.active_order == null, "slot free after settle")
	_check(GameState.onboarding_done == true, "first successful delivery sets onboarding_done")
	_check(GameState.upgrade_hint_shown == true, "upgrade hint marked after first success")

func _test_delivery_fail_settlement() -> void:
	print("-- delivery fail + late penalty settlement (40%% of reward)")
	var bal := GameState.balance
	var reward := 400
	var expected_pen := GameState.late_penalty_amount(reward)  ## 160
	var late := GameState.debug_push_order({
		"item": "병 마개", "quantity": 80, "deadline": GameState.cycle + 2,
		"reward": reward, "margin_tag": "bulk", "penalty": expected_pen,
	})
	var acc: Dictionary = GameState.try_accept_order(late.id)
	_check(acc.get("ok") == true, "accept short-lead order for fail settle")
	# skip production; blow past deadline
	GameState.advance_cycle()
	GameState.advance_cycle()
	GameState.advance_cycle()
	var d: Dictionary = GameState.try_deliver()
	_check(d.get("ok") == false, "delivery/settlement fail when short and late")
	_check(expected_pen == 160, "late penalty is 40%% of 400 (=160)")
	_check(GameState.balance == bal - expected_pen, "penalty applied on fail settlement (−40%% reward)")
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
		# Starting balance 500; after +150 tutorial and −160 late penalty (and possible resin buys)
		_check(int(parsed.get("balance", -1)) >= 0, "balance present after settles")
		_check(is_equal_approx(float(parsed.get("defect_rate", 0.0)), 0.12), "defect_rate starts at 0.12")


func _test_mash_guards() -> void:
	print("-- mash / re-entrancy guards")
	GameState.reset_game()
	GameState.rng.seed = 42
	# Rapid accept same order: only first succeeds
	var o := GameState.debug_push_order({
		"item": "병 마개", "quantity": 10, "deadline": GameState.cycle + 100,
		"reward": 100, "margin_tag": "bulk", "penalty": 40,
	})
	var r1: Dictionary = GameState.try_accept_order(o.id)
	var r2: Dictionary = GameState.try_accept_order(o.id)
	var r3: Dictionary = GameState.try_accept_order(o.id)
	_check(r1.get("ok") == true, "first accept ok")
	_check(r2.get("ok") == false, "second accept ignored/fails (no double-accept)")
	_check(r3.get("ok") == false, "third accept ignored/fails")
	_check(GameState.active_order != null and GameState.active_order.id == o.id, "single active order after mash accept")

	# Sheet-open blocks further accepts/swaps/delivers
	GameState.sheet_open = true
	var extra := GameState.debug_push_order({
		"item": "폰케이스", "quantity": 5, "deadline": GameState.cycle + 90,
		"reward": 50, "margin_tag": "special", "penalty": 20,
	})
	# Clear slot for a fair "blocked by sheet" check: temporarily null then restore
	var held := GameState.active_order
	GameState.active_order = null
	var blocked_acc: Dictionary = GameState.try_accept_order(extra.id)
	_check(blocked_acc.get("ok") == false, "accept blocked while sheet_open")
	GameState.active_order = held
	var blocked_swap: Dictionary = GameState.try_start_swap("mold_cap")
	_check(blocked_swap.get("ok") == false, "swap blocked while sheet_open")
	var blocked_del: Dictionary = GameState.try_deliver()
	_check(blocked_del.get("ok") == false, "deliver blocked while sheet_open")
	GameState.sheet_open = false

	# Rapid swap: second while already swapping fails
	var s1: Dictionary = GameState.try_start_swap("mold_cap")
	_check(s1.get("ok") == true, "first swap starts")
	var s2: Dictionary = GameState.try_start_swap("mold_case")
	_check(s2.get("ok") == false, "second swap ignored while swapping")
	_check(GameState.line.target_mold_id == "mold_cap", "swap target unchanged by mash")
	while GameState.line.status == LineState.Status.SWAPPING:
		GameState.advance_cycle()

	# Rapid settle: only one settlement / balance delta
	GameState.active_order.good_units_produced = GameState.active_order.quantity
	GameState.active_order.defect_units_produced = 0
	var bal := GameState.balance
	var reward := GameState.active_order.reward
	var d1: Dictionary = GameState.try_deliver()
	var d2: Dictionary = GameState.try_deliver()
	var d3: Dictionary = GameState.try_deliver()
	_check(d1.get("ok") == true, "first settle ok")
	_check(d2.get("ok") == false, "second settle ignored (no double-settle)")
	_check(d3.get("ok") == false, "third settle ignored")
	_check(GameState.balance == bal + reward, "balance credited exactly once")
	_check(GameState.active_order == null, "slot free after single settle")
	_check(GameState.can_interact() == true, "can_interact after settle")

func _test_save_load_roundtrip() -> void:
	print("-- save→mutate→load roundtrip")
	GameState.reset_game()
	GameState.rng.seed = 7
	var o := GameState.debug_push_order({
		"item": "폰케이스", "quantity": 30, "deadline": GameState.cycle + 90,
		"reward": 500, "margin_tag": "special", "penalty": 200,
	})
	GameState.try_accept_order(o.id)
	GameState.try_start_swap("mold_case")
	GameState.advance_cycle()
	GameState.advance_cycle()
	GameState.balance = 777
	GameState.materials = 123
	GameState.defect_rate = 0.12
	GameState.active_order.good_units_produced = 4
	GameState.active_order.defect_units_produced = 1
	GameState.onboarding_done = true
	GameState.upgrade_hint_shown = true
	GameState.guide_dismissed = true
	var snap := {
		"cycle": GameState.cycle,
		"balance": GameState.balance,
		"materials": GameState.materials,
		"defect_rate": GameState.defect_rate,
		"order_seq": GameState._order_seq,
		"onboarding_done": GameState.onboarding_done,
		"upgrade_hint_shown": GameState.upgrade_hint_shown,
		"guide_dismissed": GameState.guide_dismissed,
		"mold": GameState.line.current_mold_id,
		"target": GameState.line.target_mold_id,
		"swap_rem": GameState.line.swap_remaining,
		"status": GameState.line.status,
		"heat": GameState.line.heat,
		"ao_id": GameState.active_order.id if GameState.active_order else "",
		"ao_good": GameState.active_order.good_units_produced if GameState.active_order else -1,
		"ao_def": GameState.active_order.defect_units_produced if GameState.active_order else -1,
		"board_n": GameState.board_orders.size(),
		"molds_n": GameState.molds.size(),
		"owned_toy": GameState.get_mold("mold_toy").owned,
	}
	_check(GameState.save_game() == true, "save_game succeeds")
	_check(FileAccess.file_exists(GameState.SAVE_PATH), "save file present after atomic write")
	_check(not FileAccess.file_exists(GameState.SAVE_TEMP), "temp save cleaned up after rename")

	# Mutate everything
	GameState.cycle = 9999
	GameState.balance = 1
	GameState.materials = 2
	GameState.defect_rate = 0.99
	GameState.line = LineState.new()
	GameState.line.current_mold_id = "mutated"
	GameState.active_order = null
	GameState.board_orders.clear()
	GameState.molds.clear()
	GameState._order_seq = 0

	_check(GameState.load_game() == true, "load_game restores from disk")
	_check(GameState.cycle == snap["cycle"], "roundtrip cycle")
	_check(GameState.balance == snap["balance"], "roundtrip balance")
	_check(GameState.materials == snap["materials"], "roundtrip materials")
	_check(is_equal_approx(GameState.defect_rate, float(snap["defect_rate"])), "roundtrip defect_rate")
	_check(GameState._order_seq == snap["order_seq"], "roundtrip order_seq")
	_check(GameState.line.current_mold_id == snap["mold"], "roundtrip line.current_mold_id")
	_check(GameState.line.target_mold_id == snap["target"], "roundtrip line.target_mold_id")
	_check(GameState.line.swap_remaining == snap["swap_rem"], "roundtrip line.swap_remaining")
	_check(GameState.line.status == snap["status"], "roundtrip line.status")
	_check(is_equal_approx(GameState.line.heat, float(snap["heat"])), "roundtrip line.heat")
	_check(GameState.active_order != null and GameState.active_order.id == snap["ao_id"], "roundtrip active_order id")
	_check(GameState.active_order.good_units_produced == snap["ao_good"], "roundtrip active_order good")
	_check(GameState.active_order.defect_units_produced == snap["ao_def"], "roundtrip active_order defects")
	_check(GameState.board_orders.size() == snap["board_n"], "roundtrip board size")
	_check(GameState.molds.size() == snap["molds_n"], "roundtrip molds size")
	_check(GameState.get_mold("mold_toy").owned == snap["owned_toy"], "roundtrip mold owned flag")
	_check(GameState.onboarding_done == snap["onboarding_done"], "roundtrip onboarding_done")
	_check(GameState.upgrade_hint_shown == snap["upgrade_hint_shown"], "roundtrip upgrade_hint_shown")
	_check(GameState.guide_dismissed == snap["guide_dismissed"], "roundtrip guide_dismissed")

func _test_force_quit_recovery() -> void:
	print("-- force-quit recovery (save mid-loop → wipe RAM → reload)")
	GameState.reset_game()
	GameState.rng.seed = 99
	var o := GameState.debug_push_order({
		"item": "병 마개", "quantity": 20, "deadline": GameState.cycle + 120,
		"reward": 150, "margin_tag": "bulk", "penalty": 0,
	})
	GameState.try_accept_order(o.id)
	GameState.try_start_swap("mold_cap")
	# Mid-swap + mid-order: simulate kill after autosave
	GameState.advance_cycle()
	GameState.advance_cycle()
	GameState.advance_cycle()
	GameState.balance = 4242
	GameState.materials = 200
	GameState.active_order.good_units_produced = 2
	var mid_cycle := GameState.cycle
	var mid_swap := GameState.line.swap_remaining
	var mid_status := GameState.line.status
	var mid_ao := GameState.active_order.id
	_check(GameState.save_game() == true, "mid-loop save (force-quit snapshot)")

	# App killed: RAM wiped, then cold start via reload_from_save (load path, not _new_game)
	var loaded := GameState.reload_from_save()
	_check(loaded == true, "reload_from_save used disk (not _new_game)")
	_check(GameState.cycle == mid_cycle, "force-quit restores cycle")
	_check(GameState.balance == 4242, "force-quit restores balance")
	_check(GameState.materials == 200, "force-quit restores materials")
	_check(GameState.active_order != null and GameState.active_order.id == mid_ao, "force-quit restores active order")
	_check(GameState.active_order.good_units_produced == 2, "force-quit restores production progress")
	_check(GameState.line.status == mid_status, "force-quit restores line status (mid-swap)")
	_check(GameState.line.swap_remaining == mid_swap, "force-quit restores swap_remaining")
	_check(GameState.line.target_mold_id == "mold_cap", "force-quit restores swap target")
	_check(GameState.board_orders.size() > 0, "force-quit restores board orders")
	_check(GameState.can_interact() == true, "busy flags cleared after reload")

	# Continue loop after recovery — swap should finish cleanly
	var guard := 0
	while GameState.line.status == LineState.Status.SWAPPING and guard < 20:
		GameState.advance_cycle()
		guard += 1
	_check(GameState.line.current_mold_id == "mold_cap", "post-recovery swap completes")
