extends CharacterBody3D

# ─────────────────────────────
# Node references (cached once)
# ─────────────────────────────
@onready var head: Node3D = $Head                    # Rotates vertically (mouse look)
@onready var eyes: Node3D = $Head/Eyes               # Camera + head bobbing pivot
@onready var camera_3d: Camera3D = $Head/Eyes/Camera3D
@onready var standing_collision_shape_3d: CollisionShape3D = $StandingCollisionShape3D
@onready var crouching_collision_shape_3d: CollisionShape3D = $CrouchingCollisionShape3D
@onready var standup_check: RayCast3D = $StandupCheck # Checks if player can stand up safely
@onready var interaction_controller: Node = %InteractionController
@onready var note_hand: Marker3D = %NoteHand
@onready var note_camera: Camera3D = %NoteCamera
@onready var footsteps_sfx: AudioStreamPlayer3D = %Footsteps
@onready var jump_sfx: AudioStreamPlayer3D = %Jump



# ─────────────────────────────
# Movement variables
# ─────────────────────────────
const walking_speed: float = 3.0
const sprinting_speed: float = 5.0
const crouching_speed: float = 1.0
var current_speed : float = 3.0                      # Active speed based on state
var moving: bool = false                             # True when input vector ≠ zero
var input_dir: Vector2 = Vector2.ZERO                # WASD input (2D)
var direction: Vector3 = Vector3.ZERO                # World-space movement direction
const crouching_depth: float = -0.9                  # Camera offset while crouching
const jump_velocity: float = 4.0

var lerp_speed: float = 10.0                          # Smoothness for camera & movement
var is_in_air: bool = false

# ─────────────────────────────
# Player Settings
# ─────────────────────────────
var base_fov: float = 90.0
var normal_sensitivity: float = 0.2
var current_sensitivity: float = normal_sensitivity
var sensitivity_restore_speed: float = 5.0
var sensitivity_fading_in: bool = false

# ─────────────────────────────
# Player State Machine
# ─────────────────────────────
enum PlayerState {
	IDLE_STAND,
	IDLE_CROUCH,
	CROUCHING,
	WALKING,
	SPRINTING,
	AIR
}
var player_state: PlayerState = PlayerState.IDLE_STAND


# ─────────────────────────────
# Head bobbing variables
# ─────────────────────────────
const head_bobbing_sprinting_speed: float = 22.0
const head_bobbing_walking_speed: float = 14.0
const head_bobbing_crouching_speed: float = 10.0
const head_bobbing_sprinting_intensity: float = 0.2
const head_bobbing_walking_intensity: float = 0.1
const head_bobbing_crouching_intensity: float = 0.05

var head_bobbing_current_intensity: float = 0.0
var head_bobbing_vector: Vector2 = Vector2.ZERO
var head_bobbing_index: float = 0.0                  # Time accumulator for sine wave

var last_bob_position_x: float = 0.0 # track previous horizontal head-bob position
var last_bob_direction: int = 0 # track the previous movement direction -1 = left , +1 = right


# ─────────────────────────────
# Note Sway variables
# ─────────────────────────────

@export var note_sway_amount: float = 0.1



func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)     # Lock mouse for FPS control


func _input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("quit"):
		get_tree().quit()
	
	# Mouse look (yaw on body, pitch on head)
	if event is InputEventMouseMotion:
		if current_sensitivity > 0.01 and not interaction_controller.isCameraLocked():
			rotate_y(deg_to_rad(-event.relative.x * current_sensitivity))
			head.rotate_x(deg_to_rad(-event.relative.y * current_sensitivity))
			head.rotation.x = clamp(head.rotation.x, deg_to_rad(-85), deg_to_rad(85))

func _process(delta: float) -> void:
	if sensitivity_fading_in:
		current_sensitivity = lerp(current_sensitivity, normal_sensitivity, delta * sensitivity_restore_speed)
		
		if abs(current_sensitivity - normal_sensitivity) < 0.01:
			current_sensitivity = normal_sensitivity
			sensitivity_fading_in = false
			
	set_camera_locked(interaction_controller.isCameraLocked())  
func _physics_process(delta: float) -> void:
	updatePlayerState()                                 # Decide current player state
	updateCamera(delta)                                 # Visual feedback based on state
	
	# ───── Gravity & Jumping ─────
	if not is_on_floor():
		is_in_air = true
		if velocity.y >= 0:                             # Going up
			velocity += get_gravity() * delta
		else:                                           # Falling faster
			velocity += get_gravity() * delta * 2.0
	else:
		if is_in_air == true: #if true , this is first frame since the player has landed
			is_in_air = false
			footsteps_sfx.play() # landing sfx 
		if Input.is_action_just_pressed("jump"):
			velocity.y = jump_velocity
			jump_sfx.play()
	# ───── Movement Input ─────
	input_dir = Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_back"
	)
	
	# Smooth directional change
	direction = lerp(
		direction,
		(transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized(),
		delta * 10.0
	)

	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)
		
	move_and_slide()
	note_tilt_and_sway(input_dir, delta)


func updatePlayerState() -> void:
	moving = (input_dir != Vector2.ZERO)                # Used by camera & bobbing
	
	if not is_on_floor():
		player_state = PlayerState.AIR
	else:
		# HOLD-based crouch 
		if Input.is_action_pressed("crouch"):
			player_state = PlayerState.CROUCHING if moving else PlayerState.IDLE_CROUCH
		
		# Only allow standing if headroom is clear
		elif !standup_check.is_colliding():
			if not moving:
				player_state = PlayerState.IDLE_STAND
			elif Input.is_action_pressed("sprint"):
				player_state = PlayerState.SPRINTING
			else:
				player_state = PlayerState.WALKING
			
	updatePlayerColShape(player_state)                  # Collision state accordingly
	updatePlayerSpeed(player_state)                     # Apply speed for state


func updatePlayerColShape(_player_state: PlayerState) -> void:
	# Swap collision shapes based on crouch state
	if _player_state == PlayerState.CROUCHING or _player_state == PlayerState.IDLE_CROUCH:
		standing_collision_shape_3d.disabled = true
		crouching_collision_shape_3d.disabled = false
	else:
		standing_collision_shape_3d.disabled = false
		crouching_collision_shape_3d.disabled = true


func updatePlayerSpeed(_player_state: PlayerState) -> void:
	# Centralized speed control by state
	if _player_state == PlayerState.CROUCHING or _player_state == PlayerState.IDLE_CROUCH:
		current_speed = crouching_speed
	elif _player_state == PlayerState.WALKING:
		current_speed = walking_speed
	elif _player_state == PlayerState.SPRINTING:
		current_speed = sprinting_speed
		

func updateCamera(delta: float) -> void:
	# AIR state intentionally left neutral (no bobbing changes)
	if player_state == PlayerState.AIR:
		pass
		
	# ───── Crouching ─────
	if player_state == PlayerState.CROUCHING or player_state == PlayerState.IDLE_CROUCH:
		head.position.y = lerp(head.position.y, 1.8 + crouching_depth, delta * lerp_speed)
		camera_3d.fov = lerp(camera_3d.fov, base_fov * 0.95, delta * lerp_speed)
		head_bobbing_current_intensity = head_bobbing_crouching_intensity
		head_bobbing_index += head_bobbing_crouching_speed * delta
		
	# ───── Standing / Walking ─────
	elif player_state == PlayerState.IDLE_STAND or player_state == PlayerState.WALKING:
		head.position.y = lerp(head.position.y, 1.8, delta * lerp_speed)
		camera_3d.fov = lerp(camera_3d.fov, base_fov, delta * lerp_speed)
		head_bobbing_current_intensity = head_bobbing_walking_intensity
		head_bobbing_index += head_bobbing_walking_speed * delta
		
	# ───── Sprinting ─────
	elif player_state == PlayerState.SPRINTING:
		head.position.y = lerp(head.position.y, 1.8, delta * lerp_speed)
		camera_3d.fov = lerp(camera_3d.fov, base_fov * 1.05, delta * lerp_speed)
		head_bobbing_current_intensity = head_bobbing_sprinting_intensity
		head_bobbing_index += head_bobbing_sprinting_speed * delta
		
	# ───── Head bobbing math ─────
	head_bobbing_vector.y = sin(head_bobbing_index)
	head_bobbing_vector.x = sin(head_bobbing_index / 2.0)

	if moving:
		eyes.position.y = lerp(
			eyes.position.y,
			head_bobbing_vector.y * (head_bobbing_current_intensity / 2.0),
			delta * lerp_speed
		)
		eyes.position.x = lerp(
			eyes.position.x,
			head_bobbing_vector.x * head_bobbing_current_intensity,
			delta * lerp_speed
		)
	else:
		# Reset camera offset when idle
		eyes.position.y = lerp(eyes.position.y, 0.0, delta * lerp_speed)
		eyes.position.x = lerp(eyes.position.x, 0.0, delta * lerp_speed)
		
	note_camera.fov = camera_3d.fov
	
	play_footsteps()
	
func set_camera_locked(locked: bool) -> void:
	if locked:
		current_sensitivity = 0.0
		sensitivity_fading_in = false
	else:
		sensitivity_fading_in = true
		

func note_tilt_and_sway(input_dir: Vector2, delta:float) -> void:
	if note_hand:
		note_hand.rotation.x = lerp(note_hand.rotation.x, -input_dir.y * note_sway_amount, 10 * delta)
		note_hand.rotation.z = lerp(note_hand.rotation.z, -input_dir.x * note_sway_amount, 10 * delta)


func play_footsteps() -> void:
	if moving and is_on_floor():
		var bob_position_x = head_bobbing_vector.x
		var bob_direction = sign(bob_position_x - last_bob_position_x)
		
		if bob_direction != 0 and bob_direction != last_bob_direction and last_bob_direction !=0:
			#play sound effect
			footsteps_sfx.play() # footsteps sfx
			
		last_bob_direction = bob_direction
		last_bob_position_x = bob_position_x
	else:
		last_bob_direction = 0
		last_bob_position_x = head_bobbing_vector.x
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
