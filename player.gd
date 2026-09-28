extends CharacterBody3D

@export var walk_speed: float = 4.0

@export var mouse_sensitivity: float = 0.002

@export var fly_speed: float = 5.0

var fly_mode: bool = false

@onready var head: Node3D = $Head #make a variable called head that gets the node head

@onready var interaction_ray: RayCast3D = \
	$Head/Camera3D/InteractionRay




func _ready() -> void: #once the game starts we get the input of mouse 
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED #this mouse mode captured hides mouse and locks into the window

func _unhandled_input(event: InputEvent) -> void: #call this function whenever a key is presses 
	# event is info about what is contained
	#do a check for if a button is pressed
	if event.is_action_pressed("interact"):
		check_interaction()
	elif event.is_action_pressed("toggle_fly"):
		fly_mode = not fly_mode
		velocity = Vector3.ZERO
		print("Fly mode: ", fly_mode)

	#unhandeled input because interface can use it first and take priority like activting the hmi
	if event is InputEventMouseMotion: # if the event detected is mouse motion
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED: # rotate the camera only in the game
			# Horizontal movement rotates the complete player.
			rotate_y(-event.relative.x * mouse_sensitivity) # rotate around the y axis, relative to x tells relative to the last frame / lst mouse move event

			# Vertical movement rotates only the head.
			#rotates the head around the x axis, look up ans look down
			head.rotate_x(-event.relative.y * mouse_sensitivity)

			# Prevent looking completely backwards/upside-down.
			#prevents its from rotating beyond
			head.rotation.x = clampf(
				head.rotation.x,
				deg_to_rad(-85.0),
				deg_to_rad(85.0)
			)

	if event.is_action_pressed("ui_cancel"): # if the default cancel key escape is pressed
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE #makes the cursor visible 

	if event is InputEventMouseButton and event.pressed: #checek if mouse button is pressed we make it so it can capture it again
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# check for interaction occurs
func check_interaction() -> void:
	if not interaction_ray.is_colliding():
		return

	var collider := interaction_ray.get_collider() as Node

	if collider and collider.is_in_group("hmi_console"):
		print("HMI recognised — ready to open")

# use delta as it keeps the time constant since it starts/ from last physics update 
func _physics_process(delta: float) -> void:
	
	if fly_mode:
		velocity.y = Input.get_axis("fly_down", "fly_up") * fly_speed
	
	else:
		if not is_on_floor(): # this pulls the character to the floor 
			velocity += get_gravity() * delta # get the value of gravity times time and move them

	var input_direction := Input.get_vector( #we get all the inputs and put them into a vector 2
		"move_left",
		"move_right",
		"move_forward",
		"move_backward"
	)

	var direction := (
		transform.basis * #for movement direction the movment direciton matches the current players rotation 
		Vector3(input_direction.x, 0.0, input_direction.y) # so the rotation changes and our input matches in that direciton 
	).normalized() # so same speed in w+d etc, magnitude vector

	if direction != Vector3.ZERO:
		velocity.x = direction.x * walk_speed # for movement that directoin times our speed we travel at
		velocity.z = direction.z * walk_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, walk_speed) # if no movement detected move it back to zero
		velocity.z = move_toward(velocity.z, 0.0, walk_speed)

	move_and_slide() #moves the character body 
