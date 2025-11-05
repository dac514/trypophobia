class_name NextMoves extends HBoxContainer

const TEX_ROTATE_0 := preload("res://assets/rotate-0.png")
const TEX_ROTATE_90 := preload("res://assets/rotate-90.png")
const TEX_ROTATE_180 := preload("res://assets/rotate-180.png")
const TEX_ROTATE_HINT := preload("res://scenes/degrees_hint.tscn")

const SLIDE_DISTANCE := 212.0

var rotation_preview_tween: Tween
var is_first_rotation: bool = true


func draw_next_moves(board: Board, is_bot: bool) -> void:
	var next_rotation_states := board.board_rotator.next_rotation_states.duplicate()
	next_rotation_states.reverse()

	var last_child_original: TextureRect = get_children().back() as TextureRect
	var preserved_rotation: float = last_child_original.rotation
	var preserved_pivot_offset := last_child_original.pivot_offset
	var last_child: TextureRect = last_child_original.duplicate()

	if is_first_rotation:
		# Fade out existing children before removing them
		var fade_tween := create_tween()
		fade_tween.set_parallel(true)
		for child in get_children():
			fade_tween.tween_property(child, "modulate:a", 0.0, 0.5).set_ease(Tween.EASE_IN_OUT)
		await fade_tween.finished
		is_first_rotation = false

	# Remove children from next_moves
	for child in get_children():
		child.queue_free()

	# Re-add children based on latest states, and duplicate the last child to
	## animate it out for a smooth sliding effect
	for i in range(next_rotation_states.size()):
		var state: Dictionary = next_rotation_states[i]
		var tex_rect := _set_texture(state)
		add_child(tex_rect)
	add_child(last_child)

	# Wait one frame for HBoxContainer to position all children
	await get_tree().process_frame

	last_child.pivot_offset = preserved_pivot_offset
	last_child.rotation = preserved_rotation

	# Position children back by SLIDE_DISTANCE
	for child in get_children():
		var tex_rect := child as TextureRect
		tex_rect.position.x -= SLIDE_DISTANCE

	# Animate: slide all children to the right by SLIDE_DISTANCE
	var assembly_line_tween := create_tween()
	assembly_line_tween.set_parallel(true)
	for child in get_children():
		var tex_rect := child as TextureRect
		(
			assembly_line_tween
			. tween_property(tex_rect, "position:x", tex_rect.position.x + SLIDE_DISTANCE, 0.5)
			. set_ease(Tween.EASE_IN_OUT)
			. set_trans(Tween.TRANS_CUBIC)
		)

	# Clean up after animation
	assembly_line_tween.set_parallel(false)
	assembly_line_tween.tween_callback(
		func() -> void:
			# Remove the rightmost child
			last_child.queue_free()
			# Wait a frame for layout to stabilize
			await get_tree().process_frame
			if not is_bot:
				# Start hint animation on the new rightmost item
				var rightmost := get_child(get_child_count() - 1) as TextureRect
				_animate_next_move(rightmost, next_rotation_states[next_rotation_states.size() - 1])
	)


func _set_texture(state: Dictionary) -> TextureRect:
	var tex_rect := TextureRect.new()
	# Choose texture based on degrees
	if state.degrees == BoardRotator.RotationAmount.DEG_90:
		tex_rect.texture = TEX_ROTATE_90
	elif state.degrees == BoardRotator.RotationAmount.DEG_180:
		tex_rect.texture = TEX_ROTATE_180
	else:
		tex_rect.texture = TEX_ROTATE_0

	# Flip texture based on direction
	tex_rect.flip_h = (state.direction == BoardRotator.RotationDirection.RIGHT)

	# Set pivot to center for proper rotation
	tex_rect.pivot_offset = tex_rect.texture.get_size() / 2

	return tex_rect


func _animate_next_move(tex_rect: TextureRect, state: Dictionary) -> void:
	var is_not_a_rotation: bool = !(
		state.degrees == BoardRotator.RotationAmount.DEG_90
		or state.degrees == BoardRotator.RotationAmount.DEG_180
	)

	# Ensure any previous looping tween is stopped
	stop_animation()

	# Add hint label
	var hint := TEX_ROTATE_HINT.instantiate() as RichTextLabel
	if state.degrees == BoardRotator.RotationAmount.DEG_90:
		hint.text = "90°"
	elif state.degrees == BoardRotator.RotationAmount.DEG_180:
		hint.text = "180°"
	else:
		hint.text = "0°"
	hint.modulate.a = 0.0
	hint.pivot_offset = tex_rect.texture.get_size() / 2
	tex_rect.add_child(hint)

	# Fade in the hint label
	var fade_in_tween := create_tween()
	fade_in_tween.tween_property(hint, "modulate:a", 1.0, 0.3).set_ease(Tween.EASE_OUT)

	rotation_preview_tween = create_tween()
	rotation_preview_tween.set_loops()
	rotation_preview_tween.tween_interval(1.0)

	if is_not_a_rotation:
		# For no rotation, do a shake
		rotation_preview_tween.tween_property(tex_rect, "position:x", tex_rect.position.x + 16, 0.1)
		rotation_preview_tween.tween_property(tex_rect, "position:x", tex_rect.position.x - 16, 0.1)
		rotation_preview_tween.tween_property(tex_rect, "position:x", tex_rect.position.x, 0.1)
	else:
		# For rotations, animate the rotation
		var is_90: bool = state.degrees == BoardRotator.RotationAmount.DEG_90
		var rotation_step: float = deg_to_rad(90 if is_90 else 180)
		if state.direction == BoardRotator.RotationDirection.LEFT:
			rotation_step = -rotation_step
		rotation_preview_tween.tween_callback(
			func() -> void:
				if is_instance_valid(tex_rect) and is_instance_valid(hint):
					var current := tex_rect.rotation
					var target := current + rotation_step
					var sub_tween := create_tween()
					sub_tween.set_parallel(true)
					sub_tween.tween_property(tex_rect, "rotation", target, 0.6 if is_90 else 0.9)
					# Counter-rotate the hint to keep it upright
					sub_tween.tween_property(
						hint, "rotation", hint.rotation - rotation_step, 0.6 if is_90 else 0.9
					)
		)
		rotation_preview_tween.tween_interval(0.6 if is_90 else 0.9)

	rotation_preview_tween.tween_interval(3.0)


func stop_animation() -> void:
	if is_instance_valid(rotation_preview_tween):
		rotation_preview_tween.kill()
