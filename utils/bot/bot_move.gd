class_name BotMove
extends RefCounted

var column: int
var chip_type: Globals.ChipType
var direction: String


func _init(p_chip_type: Globals.ChipType, p_column: int, p_direction: String = "right") -> void:
	self.chip_type = p_chip_type
	self.column = p_column
	self.direction = p_direction
