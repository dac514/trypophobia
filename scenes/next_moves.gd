class_name NextMoves extends HBoxContainer

var animation_tween: Tween
var is_animation_stopped: bool = false

func draw_next_moves(board: Board) -> void:
	# Stop any existing animation first
	stop_animation()
	is_animation_stopped = false

	# Remove all children from next_moves
	for child in get_children():
		child.queue_free()
	# Draw moves
	var tween := create_tween()
	var reversed_states := board.board_rotator.next_rotation_states.duplicate()
	reversed_states.reverse()
	for i in range(reversed_states.size()):
		var state: Dictionary = reversed_states[i]
		var tex_rect := TextureRect.new()
		# Choose texture based on degrees
		if state.degrees == board.board_rotator.RotationAmount.DEG_90:
			tex_rect.texture = preload("res://assets/rotate-90.png")
		elif state.degrees == board.board_rotator.RotationAmount.DEG_180:
			tex_rect.texture = preload("res://assets/rotate-180.png")
		else:
			tex_rect.texture = preload("res://assets/rotate-0.png")
		# Flip texture based on direction
		tex_rect.flip_h = (state.direction == board.board_rotator.RotationDirection.RIGHT)

		# Set pivot to center for proper rotation
		tex_rect.pivot_offset = tex_rect.texture.get_size() / 2

		# Animate the change
		tween.tween_property(tex_rect, "modulate:a", 0.0, 0.0)
		tween.tween_callback(func() -> void: add_child(tex_rect))
		tween.tween_property(tex_rect, "modulate:a", 1.0, 0.15)

		# Animate the next move
		if i == reversed_states.size() - 1 and not is_animation_stopped:
			tween.tween_callback(func() -> void: _animate_next_move(tex_rect, state, board))


func _animate_next_move(tex_rect: TextureRect, state: Dictionary, board: Board) -> void:
	var is_no_rotation: bool = !(state.degrees == board.board_rotator.RotationAmount.DEG_90 or state.degrees == board.board_rotator.RotationAmount.DEG_180)

	animation_tween = create_tween()

	animation_tween.set_loops()
	animation_tween.tween_interval(1.0)

	if is_no_rotation:
		# For no rotation, do a shake
		animation_tween.tween_property(tex_rect, "position:x", tex_rect.position.x + 16, 0.1)
		animation_tween.tween_property(tex_rect, "position:x", tex_rect.position.x - 16, 0.1)
		animation_tween.tween_property(tex_rect, "position:x", tex_rect.position.x, 0.1)
	else:
		# For rotations, animate the rotation
		var is_90: bool = state.degrees == board.board_rotator.RotationAmount.DEG_90
		var rotation_step: float = deg_to_rad(90 if is_90 else 180)
		if state.direction == board.board_rotator.RotationDirection.LEFT:
			rotation_step = -rotation_step
		animation_tween.tween_callback(
			func() -> void:
				if is_instance_valid(tex_rect):
					var current := tex_rect.rotation
					var target := current + rotation_step
					var sub_tween := create_tween()
					sub_tween.tween_property(tex_rect, "rotation", target, 0.6 if is_90 else 0.9)
		)
		animation_tween.tween_interval(0.6 if is_90 else 0.9)

	animation_tween.tween_interval(3.0)


func stop_animation() -> void:
	if animation_tween and animation_tween.is_valid():
		animation_tween.kill()
	is_animation_stopped = true
