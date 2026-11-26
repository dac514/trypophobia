extends GutTest

## Column geometry used to aim and refuse drops (Board is centered on its grid, 96px cells).

const COLUMNS: int = Board.GRID_SIZE.x


func test_column_centers_are_one_cell_apart_and_symmetric() -> void:
	for column in range(COLUMNS):
		assert_almost_eq(Board.column_center_local_x(column), -Board.HALF_EXTENT + Board.CELL_SIZE * (column + 0.5), 0.001)
	assert_almost_eq(Board.column_center_local_x(0), -Board.column_center_local_x(COLUMNS - 1), 0.001)


func test_every_column_center_maps_to_its_column() -> void:
	for column in range(COLUMNS):
		assert_eq(Board.column_at_local_x(Board.column_center_local_x(column)), column)


func test_column_edges() -> void:
	assert_eq(Board.column_at_local_x(-Board.HALF_EXTENT), 0, "left edge belongs to the first column")
	assert_eq(Board.column_at_local_x(Board.HALF_EXTENT), COLUMNS - 1, "right edge belongs to the last column")
	assert_eq(Board.column_at_local_x(-Board.HALF_EXTENT + Board.CELL_SIZE - 0.01), 0)
	assert_eq(Board.column_at_local_x(-Board.HALF_EXTENT + Board.CELL_SIZE + 0.01), 1)


func test_outside_the_grid_is_no_column() -> void:
	assert_eq(Board.column_at_local_x(-Board.HALF_EXTENT - 1.0), -1)
	assert_eq(Board.column_at_local_x(Board.HALF_EXTENT + 1.0), -1)
