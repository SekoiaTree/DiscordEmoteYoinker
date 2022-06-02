extends HBoxContainer

# Woop terrible code, but I can clone it! Using required naming schemes baby!
onready var textbox = $LineEdit

func _ready():
	if has_node("Button"):
		get_node("Button").connect("pressed", self, "toggle_secret")
	$Label.hint_tooltip = "Test"

func get_text():
	return textbox.text

func toggle_secret():
	if get_node("Button").text == "Show":
		get_node("Button").text = "Hide"
	else:
		get_node("Button").text = "Show"
	
	textbox.secret = !textbox.secret
