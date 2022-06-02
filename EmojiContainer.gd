extends Button

func set_name(name : String):
	hint_tooltip = name

func set_texture(texture : Texture):
	$TextureRect.texture = texture

func set_gif(gif : bool):
	$HBoxContainer/VBoxContainer/Label.visible = gif
