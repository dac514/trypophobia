extends TextureRect

@onready var fireworks: ColorRect = $Fireworks


func _ready() -> void:
	var shader_material: ShaderMaterial = fireworks.material

	if (
		OS.get_name() == "Android"
		or OS.get_name() == "iOS"
		or (OS.get_name() == "Web" and (OS.has_feature("web_android") or OS.has_feature("web_ios")))
	):
		# Lower quality for mobile
		var mobile_quality := 0.3
		if OS.get_processor_count() <= 4 or OS.get_processor_name().to_lower().contains("snapdragon"):
			mobile_quality = 0.2

		shader_material.set_shader_parameter("quality", mobile_quality)
		shader_material.set_shader_parameter("resolution", Vector2(250, 150))
	else:
		# Full quality for desktop
		shader_material.set_shader_parameter("quality", 1.0)
