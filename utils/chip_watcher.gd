## Watches a group of Chip objects and emits a signal when
## all have settled (i.e., entered sleep state), or when a timeout occurs.
class_name ChipWatcher
extends Node

## Emitted when all watched Chip objects have settled or the timeout has elapsed.
## @param objects Array of Chip instances that were being watched.
signal all_objects_settled(objects: Array)

var _watched_objects: Array[Chip] = []
var _settling_count: int = 0
var _timeout: float = 3.0
var _timer: Timer


## Begins watching the given Chip objects for sleep state.
## Emits `all_objects_settled` when all objects sleep or timeout is reached.
##
## @param objects Array of Chip instances to monitor.
## @param timeout Maximum time (in seconds) to wait before emitting the signal.
func watch(objects: Array[Chip], timeout: float = 3.0) -> void:
	_cleanup()
	_watched_objects = []
	_timeout = timeout

	for obj in objects:
		if is_instance_valid(obj) and obj.can_sleep:
			obj.sleeping_state_changed.connect(_on_object_sleep.bind(obj), CONNECT_ONE_SHOT)
			_watched_objects.append(obj)
			_settling_count += 1

	# Start timeout timer
	_timer = Timer.new()
	_timer.wait_time = _timeout
	_timer.one_shot = true
	_timer.timeout.connect(_on_timeout)
	add_child(_timer)
	_timer.start()


func _on_object_sleep(obj: RigidBody2D) -> void:
	if obj.is_sleeping:
		_settling_count -= 1
		if _settling_count <= 0:
			_emit_and_cleanup()


func _on_timeout() -> void:
	_emit_and_cleanup()


func _emit_and_cleanup() -> void:
	if _timer and _timer.is_inside_tree():
		_timer.stop()
		_timer.queue_free()
	_timer = null
	all_objects_settled.emit(_watched_objects)
	_cleanup()


func _cleanup() -> void:
	for obj in _watched_objects:
		if (
			is_instance_valid(obj)
			and obj.sleeping_state_changed.is_connected(_on_object_sleep.bind(obj))
		):
			obj.sleeping_state_changed.disconnect(_on_object_sleep.bind(obj))
	_watched_objects.clear()
	_settling_count = 0
