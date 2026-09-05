extends Node
## Autoload: orders, molds, line, materials, balance, defect_rate, save.
## Numbers match PROJECT MVP Game Design balance sheet.

signal state_changed()
signal toast_requested(message: String, kind: String)  ## kind: fail | info | warn
signal settlement_requested(result: Dictionary)
signal cycle_advanced(cycle: int)

const SAVE_PATH := "user://save_v1.json"
const SAVE_TEMP := "user://save_v1.json.tmp"
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
## Mash / re-entrancy guards (UI + GameState).
var sheet_open: bool = false
var _accepting: bool = false
var _settling: bool = false
var _swap_starting: bool = false

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
		"id": "mold_cap", "name": "병 마개 금형", "item": "병 마개",
		"swap_time": MOLD_SWAP_CYCLES, "owned": true, "material_per_unit": 1, "heat_per_cycle": 8.0,
	}))
	list.append(MoldData.from_dict({
		"id": "mold_case", "name": "폰케이스 금형", "item": "폰케이스",
		"swap_time": MOLD_SWAP_CYCLES, "owned": true, "material_per_unit": 1, "heat_per_cycle": 10.0,
	}))
	list.append(MoldData.from_dict({
		"id": "mold_toy", "name": "브릭 금형", "item": "브릭",
		"swap_time": MOLD_SWAP_CYCLES, "owned": false, "material_per_unit": 1, "heat_per_cycle": 9.0,
	}))
	return list

## Fixed board catalog (not random ranges). Matches MVP sheet.
func _fixed_catalog() -> Array[Dictionary]:
	return [
		{
			"key": "tutorial",
			"item": "병 마개",
			"quantity": 20,
			"lead": 120,
			"reward": 150,
			"margin_tag": "bulk",
			"penalty": 0,
		},
		{
			"key": "bulk",
			"item": "병 마개",
			"quantity": 100,
			"lead": 180,
			"reward": 300,
			"margin_tag": "bulk",
			"penalty": late_penalty_amount(300),
		},
		{
			"key": "special",
			"item": "폰케이스",
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


## Map legacy English catalog strings → Korean (old saves).
func _localize_item(item: String) -> String:
	match item:
		"Bottle Cap":
			return "병 마개"
		"Phone Case":
			return "폰케이스"
		"Toy Brick":
			return "브릭"
		_:
			return item

func _localize_mold_name(n: String) -> String:
	match n:
		"Bottle Cap Mold":
			return "병 마개 금형"
		"Phone Case Mold":
			return "폰케이스 금형"
		"Toy Brick Mold":
			return "브릭 금형"
		_:
			return n

func _migrate_locale_strings() -> void:
	for m in molds:
		m.name = _localize_mold_name(m.name)
		m.item = _localize_item(m.item)
	for o in board_orders:
		o.item = _localize_item(o.item)
	if active_order:
		active_order.item = _localize_item(active_order.item)

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

func can_interact() -> bool:
	## False while confirm sheet is up or a settle/accept/swap start is in flight.
	return not sheet_open and not _settling and not _accepting and not _swap_starting

func is_settling() -> bool:
	return _settling

func is_swapping() -> bool:
	return line.status == LineState.Status.SWAPPING or _swap_starting

func _clear_busy() -> void:
	_accepting = false
	_settling = false
	_swap_starting = false
	sheet_open = false

func current_mold() -> MoldData:
	if line.current_mold_id.is_empty():
		return null
	return get_mold(line.current_mold_id)

func order_summary() -> String:
	if active_order == null:
		return "활성 주문 없음"
	return "%s  %s  기한 C%d  $%d  [%s]" % [
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
	if _accepting or _settling:
		return {"ok": false, "sheet": false, "message": "처리 중."}
	if sheet_open:
		return {"ok": false, "sheet": false, "message": "시트를 먼저 닫아주세요."}
	var order := _find_board_order(order_id)
	if order == null:
		return _fail("주문 보드에 없는 주문입니다.")
	if not slot_free():
		return _fail("주문 슬롯이 가득 찬습니다. 현재 작업을 먼저 끝내세요.")
	if order.is_near_deadline(cycle):
		return _fail("기한이 너무 임박합니다 (≤ %d 사이클). 거절하거나 건너뛰세요." % NEAR_DEADLINE_CYCLES)
	_accepting = true
	active_order = order
	active_order.accepted = true
	_remove_board(order_id)
	_refill_board()
	_changed()
	var out := _ok_sheet("주문 수주", {
		"title": "주문 수주",
		"body": "품목: %s\n수량(양품): %d\n기한: C%d (%d 남음)\n보상: $%d  페널티: $%d\n마진: %s\n\n맞는 금형으로 교체한 뒤 사출하세요." % [
			order.item, order.quantity, order.deadline, order.remaining_cycles(cycle),
			order.reward, order.penalty, order.margin_tag_str(),
		],
		"kind": "order_accept",
	})
	_accepting = false
	return out

func try_reject_order(order_id: String) -> Dictionary:
	if not can_interact():
		return {"ok": false, "sheet": false, "message": "처리 중."}
	var order := _find_board_order(order_id)
	if order == null:
		return _fail("주문 보드에 없는 주문입니다.")
	var near := order.is_near_deadline(cycle)
	_remove_board(order_id)
	_refill_board()
	_changed()
	if near:
		return _fail("기한 임박 주문을 거절했습니다 (≤ %d 사이클). 슬롯은 비어 있습니다." % NEAR_DEADLINE_CYCLES)
	toast("주문을 거절했습니다.", "info")
	return {"ok": true, "sheet": false, "message": "주문을 거절했습니다."}

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
	if _swap_starting or _settling:
		return {"ok": false, "sheet": false, "message": "처리 중."}
	if sheet_open:
		return {"ok": false, "sheet": false, "message": "시트를 먼저 닫아주세요."}
	var mold := get_mold(mold_id)
	if mold == null:
		return _fail("알 수 없는 금형입니다.")
	if not mold.owned:
		return _fail("보유하지 않은 금형입니다: %s. (MVP — R&D 없음.)" % mold.name)
	if line.is_running():
		return _fail("라인 가동 중에는 교체할 수 없습니다. 사출을 먼저 정지하세요.")
	if line.status == LineState.Status.SWAPPING:
		return _fail("이미 금형을 교체 중입니다.")
	if line.current_mold_id == mold_id:
		toast("이미 장착된 금형입니다.", "info")
		return {"ok": true, "sheet": false, "message": "이미 장착된 금형입니다."}
	_swap_starting = true
	line.status = LineState.Status.SWAPPING
	line.target_mold_id = mold_id
	line.swap_remaining = mold.swap_time
	_changed()
	toast("%s(으)로 교체 중 (%d 사이클)." % [mold.name, mold.swap_time], "info")
	_swap_starting = false
	return {"ok": true, "sheet": false, "message": "교체 시작."}

func _complete_swap() -> void:
	var mold := get_mold(line.target_mold_id)
	line.current_mold_id = line.target_mold_id
	line.target_mold_id = ""
	line.swap_remaining = 0
	line.status = LineState.Status.IDLE
	line.heat = maxf(line.heat - HEAT_COOL_PER_CYCLE, 0.0)
	var name := mold.name if mold else line.current_mold_id
	_ok_sheet("금형 교체 완료", {
		"title": "금형 교체 완료",
		"body": "%s이(가) 장착되었습니다.\n라인 대기 — 사출 가능." % name,
		"kind": "mold_swap",
	})

# ---------------------------------------------------------------------------
# 3. INJECTION — produce with defect_rate; fail stop on overheat or material shortage
# ---------------------------------------------------------------------------

func try_start_injection() -> Dictionary:
	if active_order == null:
		return _fail("활성 주문이 없습니다. 먼저 수주하세요.")
	if line.status == LineState.Status.SWAPPING:
		return _fail("금형 교체 중입니다.")
	if line.is_running():
		return _fail("이미 사출 중입니다.")
	var mold := current_mold()
	if mold == null:
		return _fail("금형이 없습니다. 먼저 금형을 교체하세요.")
	if mold.item != active_order.item:
		return _fail("금형이 맞지 않습니다. 필요 %s, 현재 %s." % [active_order.item, mold.item])
	if materials < mold.material_per_unit * UNITS_PER_CYCLE:
		return _fail("원료가 부족합니다. 원료를 구매하세요.")
	if line.heat >= line.max_heat:
		return _fail("과열입니다. 냉각 후 사출하세요.")
	line.status = LineState.Status.RUNNING
	line.units_this_run = 0
	_changed()
	toast("사출을 시작했습니다.", "info")
	return {"ok": true, "sheet": false, "message": "사출을 시작했습니다."}

func try_stop_injection() -> Dictionary:
	if not line.is_running():
		return _fail("사출 중이 아닙니다.")
	line.status = LineState.Status.IDLE
	_changed()
	toast("사출을 정지했습니다.", "info")
	return {"ok": true, "sheet": false, "message": "정지됨."}

func buy_materials(amount: int = 80, cost: int = 80) -> Dictionary:
	if balance < cost:
		return _fail("원료를 살 잔고가 부족합니다 ($%d)." % cost)
	balance -= cost
	materials += amount
	_changed()
	toast("원료 %d개를 $%d에 구매했습니다." % [amount, cost], "info")
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
		toast("보드 주문 %d건이 만료되었습니다." % dropped.size(), "warn")
	_refill_board()
	cycle_advanced.emit(cycle)
	_changed()

func _inject_tick() -> void:
	var mold := current_mold()
	if mold == null:
		_fail_stop("금형 없음 — 사출 정지.")
		return
	var shots := UNITS_PER_CYCLE
	var need := mold.material_per_unit * shots
	if materials < need:
		_fail_stop("원료 부족 — 사출 정지.")
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
		_fail_stop("과열 — 사출 정지. 라인을 냉각하세요.")
		return
	# Auto-stop if order already filled (player still must deliver)
	if active_order and active_order.good_units_produced >= active_order.quantity:
		line.status = LineState.Status.IDLE
		toast("목표 수량 도달. 기한 전에 납품하세요.", "info")

func _fail_stop(msg: String) -> void:
	line.status = LineState.Status.COOLING
	toast(msg, "fail")

# ---------------------------------------------------------------------------
# 4. DELIVERY — success if good_units >= qty before deadline; else fail
# 5. SETTLEMENT — success credit reward; late/fail apply −40% reward penalty
#    Shortage = no delivery / fail. Late = −40% of reward (order.penalty).
# ---------------------------------------------------------------------------

func try_deliver() -> Dictionary:
	if _settling:
		return {"ok": false, "sheet": false, "message": "이미 정산 중."}
	if sheet_open:
		return {"ok": false, "sheet": false, "message": "시트를 먼저 닫아주세요."}
	if active_order == null:
		return _fail("납품할 활성 주문이 없습니다.")
	if line.is_running() or line.status == LineState.Status.SWAPPING:
		return _fail("납품 전에 라인을 정지하세요.")
	_settling = true
	var order := active_order
	var on_time := cycle <= order.deadline
	var qty_ok := order.good_units_produced >= order.quantity
	var total := order.good_units_produced + order.defect_units_produced
	var defect_ratio := (float(order.defect_units_produced) / float(total)) if total > 0 else 0.0
	var excess_defects := defect_ratio > EXCESS_DEFECT_RATIO

	var delivery_ok := on_time and qty_ok
	if delivery_ok:
		toast("납품 완료.", "info")
	else:
		var why: PackedStringArray = []
		if not on_time:
			why.append("기한 초과 (C%d > C%d)" % [cycle, order.deadline])
		if not qty_ok:
			why.append("양품 부족 %d/%d" % [order.good_units_produced, order.quantity])
		toast("납품 실패: %s" % ", ".join(why), "fail")

	# Settlement
	var settle_ok := delivery_ok and not excess_defects
	var delta := 0
	var reason := ""
	if settle_ok:
		delta = order.reward
		balance += delta
		reason = "전액 입금"
	else:
		# Late / shortage / excess defects: apply order.penalty (−40% reward by default).
		delta = -order.penalty
		balance += delta  # may go negative in MVP — visible fail
		var parts: PackedStringArray = []
		if not on_time:
			parts.append("기한 초과 (−보상 %d%%)" % int(LATE_PENALTY_RATIO * 100.0))
		if not qty_ok:
			parts.append("수량 부족 (납품 불가)")
		if excess_defects:
			parts.append("불량 과다 (%.0f%% > %.0f%%)" % [defect_ratio * 100.0, EXCESS_DEFECT_RATIO * 100.0])
		reason = ", ".join(parts)

	var result := {
		"title": "정산 — 성공" if settle_ok else "정산 — 실패",
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
	_settling = false
	_changed()
	return {"ok": settle_ok, "sheet": true, "result": result}

func _settlement_body(
		order: OrderData, delivery_ok: bool, settle_ok: bool,
		on_time: bool, qty_ok: bool, excess_defects: bool,
		defect_ratio: float, delta: int, reason: String) -> String:
	return "품목: %s\n양품: %d / %d\n불량: %d (%.0f%%)\n기한: C%d  현재: C%d  %s\n\n%s\n현금 %s$%d\n잔고: $%d" % [
		order.item,
		order.good_units_produced, order.quantity,
		order.defect_units_produced, defect_ratio * 100.0,
		order.deadline, cycle, "기한 내" if on_time else "지연",
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
	# Atomic-ish: write temp then rename over the live save so a kill mid-write
	# cannot leave a truncated user://save_v1.json.
	var f := FileAccess.open(SAVE_TEMP, FileAccess.WRITE)
	if f == null:
		push_error("Save failed: %s" % FileAccess.get_open_error())
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	var err := DirAccess.rename_absolute(SAVE_TEMP, SAVE_PATH)
	if err != OK:
		# Fallback: copy-over if rename unavailable on this platform.
		var src := FileAccess.open(SAVE_TEMP, FileAccess.READ)
		if src == null:
			push_error("Save rename failed (%s) and temp unreadable." % error_string(err))
			return false
		var dst := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		if dst == null:
			src.close()
			push_error("Save fallback write failed: %s" % FileAccess.get_open_error())
			return false
		dst.store_string(src.get_as_text())
		src.close()
		dst.close()
		DirAccess.remove_absolute(SAVE_TEMP)
	return true

func load_game() -> bool:
	_clear_busy()
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
	_migrate_locale_strings()
	return true

## Simulate app restart after force-quit: wipe RAM, then load disk (or new game).
func reload_from_save() -> bool:
	_clear_busy()
	# Wipe in-memory without touching the save file.
	cycle = 0
	balance = STARTING_BALANCE
	materials = STARTING_MATERIALS
	defect_rate = STARTING_DEFECT_RATE
	line = LineState.new()
	molds.clear()
	board_orders.clear()
	active_order = null
	last_settlement = {}
	_order_seq = 1
	if load_game():
		_changed()
		return true
	_new_game()
	_changed()
	return false

func debug_push_order(d: Dictionary) -> OrderData:
	var o := OrderData.from_dict(d)
	if o.id.is_empty():
		o.id = "ord_%d" % _order_seq
		_order_seq += 1
	board_orders.insert(0, o)
	_changed()
	return o

func reset_game() -> void:
	_clear_busy()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	if FileAccess.file_exists(SAVE_TEMP):
		DirAccess.remove_absolute(SAVE_TEMP)
	_new_game()
	save_game()
	_changed()
	toast("초기화되었습니다.", "info")

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
