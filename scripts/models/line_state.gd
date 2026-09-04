class_name LineState
extends RefCounted
## Single production line state.

enum Status { IDLE, SWAPPING, RUNNING, COOLING }

var status: int = Status.IDLE
var current_mold_id: String = ""
var target_mold_id: String = ""  ## during swap
var swap_remaining: int = 0
var heat: float = 0.0
var max_heat: float = 80.0  ## MVP sheet overheat threshold
var units_this_run: int = 0

static func from_dict(d: Dictionary) -> LineState:
	var l := LineState.new()
	l.status = int(d.get("status", Status.IDLE))
	l.current_mold_id = str(d.get("current_mold_id", ""))
	l.target_mold_id = str(d.get("target_mold_id", ""))
	l.swap_remaining = int(d.get("swap_remaining", 0))
	l.heat = float(d.get("heat", 0.0))
	l.max_heat = float(d.get("max_heat", 80.0))
	l.units_this_run = int(d.get("units_this_run", 0))
	return l

func to_dict() -> Dictionary:
	return {
		"status": status,
		"current_mold_id": current_mold_id,
		"target_mold_id": target_mold_id,
		"swap_remaining": swap_remaining,
		"heat": heat,
		"max_heat": max_heat,
		"units_this_run": units_this_run,
	}

func status_str() -> String:
	match status:
		Status.IDLE: return "Idle"
		Status.SWAPPING: return "Swapping mold…"
		Status.RUNNING: return "Injecting"
		Status.COOLING: return "Cooling"
		_: return "Unknown"

func is_idle() -> bool:
	return status == Status.IDLE or status == Status.COOLING

func is_running() -> bool:
	return status == Status.RUNNING
