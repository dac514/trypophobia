class_name NextMoves
extends HBoxContainer

func draw_next_moves(board: Board) -> void:
	# Remove all children from next_moves
	for child in get_children():
		child.queue_free()
	# Draw moves
	var tween := create_tween()
	var reversed_states := board.board_rotator.next_rotation_states.duplicate()
	reversed_states.reverse()
	for state: Dictionary in reversed_states:
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
		# Animate the change
		tween.tween_property(tex_rect, "modulate:a", 0.0, 0.0)
		tween.tween_callback(func() -> void: add_child(tex_rect))
		tween.tween_property(tex_rect, "modulate:a", 1.0, 0.15)
