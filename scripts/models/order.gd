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
var penalty: int = 0
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
		o.margin_tag = MarginTag.SPECIAL if str(tag) == "special" else MarginTag.BULK
	o.penalty = int(d.get("penalty", maxi(o.reward / 2, 50)))
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
		"accepted": accepted,
		"delivered": delivered,
		"good_units_produced": good_units_produced,
		"defect_units_produced": defect_units_produced,
	}

func margin_tag_str() -> String:
	return "special" if margin_tag == MarginTag.SPECIAL else "bulk"

func is_near_deadline(current_cycle: int) -> bool:
	## Near-deadline = remaining cycles <= 1
	return (deadline - current_cycle) <= 1

func remaining_cycles(current_cycle: int) -> int:
	return deadline - current_cycle

func progress_text() -> String:
	return "%d / %d good" % [good_units_produced, quantity]
