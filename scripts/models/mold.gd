class_name MoldData
extends RefCounted
## Injection mold definition.

var id: String = ""
var name: String = ""
var item: String = ""  ## product item this mold makes
var swap_time: int = 8  ## cycles to install (MVP sheet)
var owned: bool = false
var material_per_unit: int = 1
var heat_per_cycle: float = 8.0

static func from_dict(d: Dictionary) -> MoldData:
	var m := MoldData.new()
	m.id = str(d.get("id", ""))
	m.name = str(d.get("name", ""))
	m.item = str(d.get("item", ""))
	m.swap_time = int(d.get("swap_time", 8))
	m.owned = bool(d.get("owned", false))
	m.material_per_unit = int(d.get("material_per_unit", 1))
	m.heat_per_cycle = float(d.get("heat_per_cycle", 8.0))
	return m

func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"item": item,
		"swap_time": swap_time,
		"owned": owned,
		"material_per_unit": material_per_unit,
		"heat_per_cycle": heat_per_cycle,
	}
