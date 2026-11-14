extends Node
## FTC match clock: AUTO -> TRANSITION -> TELEOP -> ENDED. IDLE = free practice, no clock.

enum State { IDLE, AUTO, TRANSITION, TELEOP, ENDED }

signal state_changed(state: State)

var state: State = State.IDLE
var time_left := 0.0

var auto_s := 30.0
var transition_s := 8.0
var teleop_s := 120.0
var _auto_only := false

func _ready() -> void:
	apply_config()

func apply_config() -> void:
	auto_s = Config.num("match.auto_s", 30.0)
	transition_s = Config.num("match.transition_s", 8.0)
	teleop_s = Config.num("match.teleop_s", 120.0)

func start_full_match() -> void:
	_auto_only = false
	_enter(State.AUTO, auto_s)

## Autonomous period only (used when a Java autonomous OpMode runs).
func start_auto_only() -> void:
	_auto_only = true
	_enter(State.AUTO, auto_s)

func start_teleop_only() -> void:
	_enter(State.TELEOP, teleop_s)

func reset() -> void:
	_enter(State.IDLE, 0.0)

## True when the driver is allowed to drive.
func driver_enabled() -> bool:
	return state == State.IDLE or state == State.TELEOP

func state_name() -> String:
	return ["FREE PRACTICE", "AUTONOMOUS", "TRANSITION", "DRIVER-CONTROLLED", "MATCH OVER"][state]

func _enter(s: State, t: float) -> void:
	state = s
	time_left = t
	state_changed.emit(s)

func _physics_process(dt: float) -> void:
	if state == State.IDLE or state == State.ENDED:
		return
	time_left -= dt
	if time_left > 0.0:
		return
	match state:
		State.AUTO:
			if _auto_only:
				_enter(State.ENDED, 0.0)
			elif transition_s > 0.0:
				_enter(State.TRANSITION, transition_s)
			else:
				_enter(State.TELEOP, teleop_s)
		State.TRANSITION:
			_enter(State.TELEOP, teleop_s)
		State.TELEOP:
			_enter(State.ENDED, 0.0)
