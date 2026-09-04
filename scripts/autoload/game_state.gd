extends Node
## Autoload: orders, molds, line, materials, balance, defect_rate, save.
## Numbers match PROJECT MVP Game Design balance sheet.

signal state_changed()
signal toast_requested(message: String, kind: String)  ## kind: fail | info | warn
signal settlement_requested(result: Dictionary)
signal cycle_advanced(cycle: int)

const SAVE_PATH := "user://save_v1.json"
const SAVE_VERSION := 1
const MAX_ORDER_SLOTS := 1
const NEAR_DEADLINE_CYCLES := 1
## 1 injection cycle = 1 shot producing 1 unit; material 1 per shot.
const UNITS_PER_CYCLE := 1
const HEAT_COOL_PER_CYCLE := 5.0
const STARTING_BALANCE := 500
const STARTING_MATERIALS := 250
## Default 12%; usable range conceptually 5%–35% (no pressure/temp system yet).
const STARTING_DEFECT_RATE := 0.12
const DEFECT_RATE_MIN := 0.05
const DEFECT_RATE_MAX := 0.35
const LATE_PENALTY_RATIO := 0.4  ## late settlement = −40% of reward
const EXCESS_DEFECT_RATIO := 0.15  ## fail settlement if defects / total > this
const MOLD_SWAP_CYCLES := 8

var save_version: int = SAVE_VERSION
var cycle: int = 0
var balance: int = STARTING_BALANCE
var materials: int = STARTING_MATERIALS
var defect_rate: float = STARTING_DEFECT_RATE
var line: LineState = LineState.new()
var molds: Array[MoldData] = []
var board_orders: Array[OrderData] = []  ## available on order board
var active_order: OrderData = null
var last_settlement: Dictionary = {}
var _order_seq: int = 1
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()
	if not load_game():
		_new_game()
	# Pause / close autosave
	get_tree().root.close_requested.connect(_on_close_requested)
	state_changed.emit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()
		get_tree().quit()
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		save_game()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		save_game()

func _on_close_requested() -> void:
	save_game()
	get_tree().quit()

# ---------------------------------------------------------------------------
# New game / catalogs
# ---------------------------------------------------------------------------

func _new_game() -> void:
	save_version = SAVE_VERSION
	cycle = 0
	balance = STARTING_BALANCE
	materials = STARTING_MATERIALS
	defect_rate = STARTING_DEFECT_RATE
	line = LineState.new()
	line.status = LineState.Status.IDLE
	line.current_mold_id = ""
	molds = _default_molds()
	board_orders.clear()
	active_order = null
	_order_seq = 1
	_refill_board()

func _default_molds() -> Array[MoldData]:
	var list: Array[MoldData] = []
	list.append(MoldData.from_dict({
		"id": "mold_cap", "name": "Bottle Cap Mold", "item": "Bottle Cap",
		"swap_time": MOLD_SWAP_CYCLES, "owned": true, "material_per_unit": 1, "heat_per_cycle": 8.0,
	}))
	list.append(MoldData.from_dict({
		"id": "mold_case", "name": "Phone Case Mold", "item": "Phone Case",
		"swap_time": MOLD_SWAP_CYCLES, "owned": true, "material_per_unit": 1, "heat_per_cycle": 10.0,
	}))
	list.append(MoldData.from_dict({
		"id": "mold_toy", "name": "Toy Brick Mold", "item": "Toy Brick",
		"swap_time": MOLD_SWAP_CYCLES, "owned": false, "material_per_unit": 1, "heat_per_cycle": 9.0,
	}))
	return list

## Fixed board catalog (not random ranges). Matches MVP sheet.
func _fixed_catalog() -> Array[Dictionary]:
	return [
		{
			"key": "tutorial",
			"item": "Bottle Cap",
			"quantity": 20,
			"lead": 120,
			"reward": 150,
			"margin_tag": "bulk",
			"penalty": 0,
		},
		{
			"key": "bulk",
			"item": "Bottle Cap",
			"quantity": 100,
			"lead": 180,
			"reward": 300,
			"margin_tag": "bulk",
			"penalty": late_penalty_amount(300),
		},
		{
			"key": "special",
			"item": "Phone Case",
			"quantity": 30,
			"lead": 90,
			"reward": 500,
			"margin_tag": "special",
			"penalty": late_penalty_amount(500),
		},
	]

static func late_penalty_amount(reward: int) -> int:
	return int(round(float(reward) * LATE_PENALTY_RATIO))

func _order_matches_catalog(o: OrderData, template: Dictionary) -> bool:
	return o.item == str(template["item"]) \
		and o.quantity == int(template["quantity"]) \
		and o.reward == int(template["reward"])

func _refill_board() -> void:
	var catalog := _fixed_catalog()
	for template in catalog:
		var present := false
		for o in board_orders:
			if _order_matches_catalog(o, template):
				present = true
				break
		if present:
			continue
		var o := OrderData.from_dict({
			"id": "ord_%d" % _order_seq,
			"item": template["item"],
			"quantity": template["quantity"],
			"deadline": cycle + int(template["lead"]),
			"reward": template["reward"],
			"margin_tag": template["margin_tag"],
			"penalty": template["penalty"],
		})
		_order_seq += 1
		board_orders.append(o)

# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------

func get_mold(mold_id: String) -> MoldData:
	for m in molds:
		if m.id == mold_id:
			return m
	return null

func get_mold_for_item(item: String) -> MoldData:
	for m in molds:
		if m.item == item:
			return m
	return null

func slot_free() -> bool:
	return active_order == null

func current_mold() -> MoldData:
	if line.current_mold_id.is_empty():
		return null
	return get_mold(line.current_mold_id)

func order_summary() -> String:
	if active_order == null:
		return "No active order"
	return "%s  %s  due C%d  $%d  [%s]" % [
		active_order.item,
		active_order.progress_text(),
		active_order.deadline,
		active_order.reward,
		active_order.margin_tag_str(),
	]

func hud_defect_text() -> String:
	return "%.0f%%" % (defect_rate * 100.0)

# ---------------------------------------------------------------------------
# 1. ORDER  — accept if free slot; fail if slots full or near-deadline
# ---------------------------------------------------------------------------

func try_accept_order(order_id: String) -> Dictionary:
	var order := _find_board_order(order_id)
	if order == null:
		return _fail("Order not found on board.")
	if not slot_free():
		return _fail("Order slot full. Finish or settle the current job first.")
	if order.is_near_deadline(cycle):
		return _fail("Too close to deadline (≤ %d cycle). Reject or skip." % NEAR_DEADLINE_CYCLES)
	active_order = order
	active_order.accepted = true
	_remove_board(order_id)
	_refill_board()
	_changed()
	return _ok_sheet("Order accepted", {
		"title": "Order Accepted",
		"body": "Item: %s\nQty: %d good units\nDeadline: cycle %d (%d left)\nReward: $%d  Penalty: $%d\nTag: %s\n\nSwap to the matching mold, then inject." % [
			order.item, order.quantity, order.deadline, order.remaining_cycles(cycle),
			order.reward, order.penalty, order.margin_tag_str(),
		],
		"kind": "order_accept",
	})

func try_reject_order(order_id: String) -> Dictionary:
	var order := _find_board_order(order_id)
	if order == null:
		return _fail("Order not found on board.")
	var near := order.is_near_deadline(cycle)
	_remove_board(order_id)
	_refill_board()
	_changed()
	if near:
		return _fail("Rejected a near-deadline job (≤ %d cycle). Slot stays free." % NEAR_DEADLINE_CYCLES)
	toast("Order declined.", "info")
	return {"ok": true, "sheet": false, "message": "Order declined."}

func _remove_board(order_id: String) -> void:
	var next: Array[OrderData] = []
	for o in board_orders:
		if o.id != order_id:
			next.append(o)
	board_orders = next

func _find_board_order(order_id: String) -> OrderData:
	for o in board_orders:
		if o.id == order_id:
			return o
	return null

# ---------------------------------------------------------------------------
# 2. MOLD SWAP — success after swap_time if idle & owned; fail if running / not owned
# ---------------------------------------------------------------------------

func try_start_swap(mold_id: String) -> Dictionary:
	var mold := get_mold(mold_id)
	if mold == null:
		return _fail("Unknown mold.")
	if not mold.owned:
		return _fail("Mold not owned: %s. (Locked in MVP — no R&D.)" % mold.name)
	if line.is_running():
		return _fail("Line is running. Stop injection before swapping molds.")
	if line.status == LineState.Status.SWAPPING:
		return _fail("Already swapping a mold.")
	if line.current_mold_id == mold_id:
		toast("That mold is already installed.", "info")
		return {"ok": true, "sheet": false, "message": "Already installed."}
	line.status = LineState.Status.SWAPPING
	line.target_mold_id = mold_id
	line.swap_remaining = mold.swap_time
	_changed()
	toast("Swapping to %s (%d cycle)." % [mold.name, mold.swap_time], "info")
	return {"ok": true, "sheet": false, "message": "Swap started."}

func _complete_swap() -> void:
	var mold := get_mold(line.target_mold_id)
	line.current_mold_id = line.target_mold_id
	line.target_mold_id = ""
	line.swap_remaining = 0
	line.status = LineState.Status.IDLE
	line.heat = maxf(line.heat - HEAT_COOL_PER_CYCLE, 0.0)
	var name := mold.name if mold else line.current_mold_id
	_ok_sheet("Mold swapped", {
		"title": "Mold Swap Complete",
		"body": "%s is installed.\nLine is idle — ready to inject." % name,
		"kind": "mold_swap",
	})

# ---------------------------------------------------------------------------
# 3. INJECTION — produce with defect_rate; fail stop on overheat or material shortage
# ---------------------------------------------------------------------------

func try_start_injection() -> Dictionary:
	if active_order == null:
		return _fail("No active order. Accept a job first.")
	if line.status == LineState.Status.SWAPPING:
		return _fail("Line is swapping a mold.")
	if line.is_running():
		return _fail("Line is already injecting.")
	var mold := current_mold()
	if mold == null:
		return _fail("No mold installed. Swap a mold first.")
	if mold.item != active_order.item:
		return _fail("Wrong mold. Need %s, have %s." % [active_order.item, mold.item])
	if materials < mold.material_per_unit * UNITS_PER_CYCLE:
		return _fail("Material shortage. Buy resin or wait — cannot start.")
	if line.heat >= line.max_heat:
		return _fail("Line overheated. Cool down before injecting.")
	line.status = LineState.Status.RUNNING
	line.units_this_run = 0
	_changed()
	toast("Injection started.", "info")
	return {"ok": true, "sheet": false, "message": "Injection started."}

func try_stop_injection() -> Dictionary:
	if not line.is_running():
		return _fail("Line is not injecting.")
	line.status = LineState.Status.IDLE
	_changed()
	toast("Injection stopped.", "info")
	return {"ok": true, "sheet": false, "message": "Stopped."}

func buy_materials(amount: int = 80, cost: int = 80) -> Dictionary:
	if balance < cost:
		return _fail("Not enough cash to buy resin ($%d)." % cost)
	balance -= cost
	materials += amount
	_changed()
	toast("Bought %d resin for $%d." % [amount, cost], "info")
	return {"ok": true, "sheet": false}

# ---------------------------------------------------------------------------
# Cycle tick
# ---------------------------------------------------------------------------

func advance_cycle() -> void:
	cycle += 1
	match line.status:
		LineState.Status.SWAPPING:
			line.swap_remaining -= 1
			if line.swap_remaining <= 0:
				_complete_swap()
		LineState.Status.RUNNING:
			_inject_tick()
		LineState.Status.IDLE, LineState.Status.COOLING:
			line.heat = maxf(line.heat - HEAT_COOL_PER_CYCLE, 0.0)
			if line.heat <= 0.0:
				line.status = LineState.Status.IDLE
	# Board orders past deadline drop off
	var dropped: Array[OrderData] = []
	var kept: Array[OrderData] = []
	for o in board_orders:
		if o.deadline < cycle:
			dropped.append(o)
		else:
			kept.append(o)
	board_orders = kept
	if dropped.size() > 0:
		toast("%d board order(s) expired." % dropped.size(), "warn")
	_refill_board()
	cycle_advanced.emit(cycle)
	_changed()

func _inject_tick() -> void:
	var mold := current_mold()
	if mold == null:
		_fail_stop("Injection stopped: no mold.")
		return
	var shots := UNITS_PER_CYCLE
	var need := mold.material_per_unit * shots
	if materials < need:
		_fail_stop("Material shortage — injection stopped.")
		return
	materials -= need
	var good := 0
	var bad := 0
	for _i in shots:
		if rng.randf() < defect_rate:
			bad += 1
		else:
			good += 1
	if active_order:
		active_order.good_units_produced += good
		active_order.defect_units_produced += bad
	line.units_this_run += shots
	line.heat += mold.heat_per_cycle
	if line.heat >= line.max_heat:
		line.heat = line.max_heat
		_fail_stop("Overheat — injection stopped. Cool the line.")
		return
	# Auto-stop if order already filled (player still must deliver)
	if active_order and active_order.good_units_produced >= active_order.quantity:
		line.status = LineState.Status.IDLE
		toast("Quota met. Deliver before the deadline.", "info")

func _fail_stop(msg: String) -> void:
	line.status = LineState.Status.COOLING
	toast(msg, "fail")

# ---------------------------------------------------------------------------
# 4. DELIVERY — success if good_units >= qty before deadline; else fail
# 5. SETTLEMENT — success credit reward; late/fail apply −40% reward penalty
#    Shortage = no delivery / fail. Late = −40% of reward (order.penalty).
# ---------------------------------------------------------------------------

func try_deliver() -> Dictionary:
	if active_order == null:
		return _fail("No active order to deliver.")
	if line.is_running() or line.status == LineState.Status.SWAPPING:
		return _fail("Stop the line before delivering.")
	var order := active_order
	var on_time := cycle <= order.deadline
	var qty_ok := order.good_units_produced >= order.quantity
	var total := order.good_units_produced + order.defect_units_produced
	var defect_ratio := (float(order.defect_units_produced) / float(total)) if total > 0 else 0.0
	var excess_defects := defect_ratio > EXCESS_DEFECT_RATIO

	var delivery_ok := on_time and qty_ok
	if delivery_ok:
		toast("Delivery accepted.", "info")
	else:
		var why: PackedStringArray = []
		if not on_time:
			why.append("late (C%d > C%d)" % [cycle, order.deadline])
		if not qty_ok:
			why.append("short %d/%d good" % [order.good_units_produced, order.quantity])
		toast("Delivery failed: %s." % ", ".join(why), "fail")

	# Settlement
	var settle_ok := delivery_ok and not excess_defects
	var delta := 0
	var reason := ""
	if settle_ok:
		delta = order.reward
		balance += delta
		reason = "Paid in full."
	else:
		# Late / shortage / excess defects: apply order.penalty (−40% reward by default).
		delta = -order.penalty
		balance += delta  # may go negative in MVP — visible fail
		var parts: PackedStringArray = []
		if not on_time:
			parts.append("late (−%d%% reward)" % int(LATE_PENALTY_RATIO * 100.0))
		if not qty_ok:
			parts.append("short quantity (no delivery)")
		if excess_defects:
			parts.append("excess defects (%.0f%% > %.0f%%)" % [defect_ratio * 100.0, EXCESS_DEFECT_RATIO * 100.0])
		reason = "Penalty for %s." % ", ".join(parts)

	var result := {
		"title": "Settlement — Success" if settle_ok else "Settlement — Failed",
		"ok": settle_ok,
		"delivery_ok": delivery_ok,
		"kind": "settlement",
		"delta": delta,
		"balance": balance,
		"body": _settlement_body(order, delivery_ok, settle_ok, on_time, qty_ok, excess_defects, defect_ratio, delta, reason),
	}
	last_settlement = result
	order.delivered = true
	active_order = null
	save_game()
	settlement_requested.emit(result)
	_changed()
	return {"ok": settle_ok, "sheet": true, "result": result}

func _settlement_body(
		order: OrderData, delivery_ok: bool, settle_ok: bool,
		on_time: bool, qty_ok: bool, excess_defects: bool,
		defect_ratio: float, delta: int, reason: String) -> String:
	return "Item: %s\nGood: %d / %d\nDefects: %d (%.0f%%)\nDeadline: C%d  Now: C%d  %s\n\n%s\nCash %s$%d\nBalance: $%d" % [
		order.item,
		order.good_units_produced, order.quantity,
		order.defect_units_produced, defect_ratio * 100.0,
		order.deadline, cycle, "ON TIME" if on_time else "LATE",
		reason,
		"+" if delta >= 0 else "", delta,
		balance,
	]

# ---------------------------------------------------------------------------
# Save / Load
# ---------------------------------------------------------------------------

func save_game() -> bool:
	var data := {
		"save_version": SAVE_VERSION,
		"cycle": cycle,
		"balance": balance,
		"materials": materials,
		"defect_rate": defect_rate,
		"order_seq": _order_seq,
		"line": line.to_dict(),
		"molds": molds.map(func(m: MoldData) -> Dictionary: return m.to_dict()),
		"board_orders": board_orders.map(func(o: OrderData) -> Dictionary: return o.to_dict()),
		"active_order": active_order.to_dict() if active_order else {},
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("Save failed: %s" % FileAccess.get_open_error())
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = parsed
	if int(d.get("save_version", 0)) != SAVE_VERSION:
		return false
	cycle = int(d.get("cycle", 0))
	balance = int(d.get("balance", STARTING_BALANCE))
	materials = int(d.get("materials", STARTING_MATERIALS))
	defect_rate = float(d.get("defect_rate", STARTING_DEFECT_RATE))
	_order_seq = int(d.get("order_seq", 1))
	line = LineState.from_dict(d.get("line", {}))
	molds.clear()
	for m in d.get("molds", []):
		molds.append(MoldData.from_dict(m))
	if molds.is_empty():
		molds = _default_molds()
	board_orders.clear()
	for o in d.get("board_orders", []):
		board_orders.append(OrderData.from_dict(o))
	var ao: Dictionary = d.get("active_order", {})
	if ao is Dictionary and not ao.is_empty() and str(ao.get("id", "")) != "":
		active_order = OrderData.from_dict(ao)
	else:
		active_order = null
	if board_orders.is_empty():
		_refill_board()
	return true

func debug_push_order(d: Dictionary) -> OrderData:
	var o := OrderData.from_dict(d)
	if o.id.is_empty():
		o.id = "ord_%d" % _order_seq
		_order_seq += 1
	board_orders.insert(0, o)
	_changed()
	return o

func reset_game() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	_new_game()
	save_game()
	_changed()
	toast("New factory started.", "info")

# ---------------------------------------------------------------------------
# UI helpers
# ---------------------------------------------------------------------------

func toast(message: String, kind: String = "fail") -> void:
	toast_requested.emit(message, kind)

func _fail(message: String) -> Dictionary:
	toast(message, "fail")
	return {"ok": false, "sheet": false, "message": message}

func _ok_sheet(message: String, result: Dictionary) -> Dictionary:
	settlement_requested.emit(result)  # reused as generic sheet
	return {"ok": true, "sheet": true, "message": message, "result": result}

func _changed() -> void:
	state_changed.emit()
