extends GridContainer

var current_initial = null

# Called when the node enters the scene tree for the first time.
func _ready():
	pass


# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass

func child_pressed(child_index : int):
	if Input.is_action_pressed("shift"):
		if current_initial != null:
			var offset = 1
			if current_initial < child_index:
				offset = -1
			
			while child_index != current_initial:
				get_child(child_index).pressed = get_child(current_initial).pressed
				child_index += offset
			
		else:
			current_initial = child_index
	else:
		current_initial = null

func select_all():
	for i in get_children():
		i.pressed = true

func select_none():
	for i in get_children():
		i.pressed = false
