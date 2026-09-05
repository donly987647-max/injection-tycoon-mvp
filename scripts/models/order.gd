class_name OrderData
extends RefCounted
## Order board entry / active order contract.

enum MarginTag { BULK, SPECIAL }

var id: String = ""
var item: String = ""
var quantity: int = 0
var deadline: int = 0  ## absolute cycle number
var reward: int = 0
var margin_tag: int = MarginTag.BULK
var penalty: int = 0  ## late = 40% of reward by default; tutorial may be 0
var lead_cycles: int = 0  ## original lead window (for tension ≤30%)
var accepted: bool = false
var delivered: bool = false
var good_units_produced: int = 0
var defect_units_produced: int = 0

static func from_dict(d: Dictionary) -> OrderData:
	var o := OrderData.new()
	o.id = str(d.get("id", ""))
	o.item = str(d.get("item", ""))
	o.quantity = int(d.get("quantity", 0))
	o.deadline = int(d.get("deadline", 0))
	o.reward = int(d.get("reward", 0))
	var tag = d.get("margin_tag", "bulk")
	if tag is int:
		o.margin_tag = tag
	else:
		o.margin_tag = MarginTag.SPECIAL if str(tag) in ["special", "특수"] else MarginTag.BULK
	# Default late penalty = 40% of reward (MVP sheet), not half.
	var default_pen := int(round(float(o.reward) * 0.4))
	o.penalty = int(d.get("penalty", default_pen))
	o.lead_cycles = int(d.get("lead_cycles", 0))
	o.accepted = bool(d.get("accepted", false))
	o.delivered = bool(d.get("delivered", false))
	o.good_units_produced = int(d.get("good_units_produced", 0))
	o.defect_units_produced = int(d.get("defect_units_produced", 0))
	return o

func to_dict() -> Dictionary:
	return {
		"id": id,
		"item": item,
		"quantity": quantity,
		"deadline": deadline,
		"reward": reward,
		"margin_tag": "special" if margin_tag == MarginTag.SPECIAL else "bulk",
		"penalty": penalty,
		"lead_cycles": lead_cycles,
		"accepted": accepted,
		"delivered": delivered,
		"good_units_produced": good_units_produced,
		"defect_units_produced": defect_units_produced,
	}

func margin_tag_str() -> String:
	return "특수" if margin_tag == MarginTag.SPECIAL else "대량"

func is_near_deadline(current_cycle: int) -> bool:
	## Near-deadline = remaining cycles <= 1 (accept reject rule)
	return (deadline - current_cycle) <= 1

func remaining_cycles(current_cycle: int) -> int:
	return deadline - current_cycle

## Tension: remaining ≤ 30% of original lead window.
func is_deadline_urgent(current_cycle: int) -> bool:
	var lead := lead_cycles if lead_cycles > 0 else maxi(remaining_cycles(current_cycle), 1)
	var rem := remaining_cycles(current_cycle)
	return rem >= 0 and float(rem) <= float(lead) * 0.3

func progress_text() -> String:
	return "%d / %d 양품" % [good_units_produced, quantity]
