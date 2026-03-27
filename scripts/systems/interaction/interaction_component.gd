extends Node


# This is defined on individual objects in the game

enum InteractionType {
	DEFAULT,
	DOOR,
	SWITCH,
	WHEEL,
	ITEM,
	NOTE
}

@export var object_ref: Node3D
@export var interaction_type: InteractionType = InteractionType.DEFAULT
@export var maximum_rotation: float = 90
@export var pivot_point: Node3D
@export var nodes_to_effect: Array[Node]
@export var content: String

var can_interact: bool = true
var is_interacting: bool = false
var lock_camera: bool = false
var starting_rotation: float
var is_front: bool
var player_hand: Marker3D
var camera: Camera3D
var previous_mouse_position: Vector2


# door variables
var door_angle: float = 0.0
var door_velocity: float = 0.0
@export var door_smoothing: float = 80.0 # control how heavy the door feels while opening/letting go
var door_input_active: bool = false
var door_opened: bool = false
var creak_velocity_threshold: float = 0.005
var shut_angle_threshold: float = 0.2
var shut_snap_range: float = 0.05
var creak_volume_scale: float = 1000.0
var door_fade_speed: float = 1.0
var prev_door_angle: float = 0.0

# switch variables
var switch_target_rotation: float = 0.0
var switch_lerp_speed: float = 8.0
var is_switch_snapping: bool  = false
var switch_moved: bool = false
var last_switch_angle: float = 0.0
var switch_creak_velocity_threshold: float = 0.01
var switch_fade_speed: float = 50.0
var switch_kickback_triggered: bool = false

# wheel variables
var wheel_kickback: float = 0.0
var wheel_kick_intensity: float = 0.1
var wheel_rotation: float = 0.0
var wheel_creak_velocity_threshold: float = 0.005
var wheel_fade_speed: float = 5.0
var last_wheel_angle: float = 0.0
var wheel_kickback_triggered: bool = false

# Sound Effects Variables
var primary_audio_player: AudioStreamPlayer3D
var secondary_audio_player: AudioStreamPlayer3D
var last_velocity: Vector3 = Vector3.ZERO
var contact_velocity_threshold: float = 1.0
@export var primary_sfx: AudioStreamOggVorbis
@export var secondary_sfx: AudioStreamOggVorbis

# Signals
signal item_collected(item: Node)
signal note_collected(note: Node3D)

func _ready() -> void:
	primary_audio_player = AudioStreamPlayer3D.new()
	primary_audio_player.stream = primary_sfx
	add_child(primary_audio_player)
	secondary_audio_player = AudioStreamPlayer3D.new()
	secondary_audio_player.stream = secondary_sfx
	add_child(secondary_audio_player)
	
	match interaction_type:
		InteractionType.DEFAULT:
			if object_ref.has_signal("body_entered"):
				object_ref.connect("body_entered", Callable(self, "_fire_default_collision"))
				object_ref.contact_monitor = true
				object_ref.max_contacts_reported = 1
		InteractionType.DOOR:
			starting_rotation = pivot_point.rotation.y
			maximum_rotation = deg_to_rad(rad_to_deg(starting_rotation)+maximum_rotation)
		InteractionType.SWITCH:
			starting_rotation = object_ref.rotation.z
			maximum_rotation = deg_to_rad(rad_to_deg(starting_rotation)+maximum_rotation)
		InteractionType.WHEEL:
			starting_rotation = object_ref.rotation.z
			maximum_rotation = deg_to_rad(rad_to_deg(starting_rotation)+maximum_rotation)
			camera = get_tree().get_current_scene().find_child("Camera3D", true, false)
		InteractionType.NOTE:
			content = content.replace("\\n", "\\n")
	

# Run once, when the player FIRST clicks on an object to interact with
func preInteract(hand: Marker3D) -> void:
	is_interacting = true
	match  interaction_type:
		InteractionType.DEFAULT:
			player_hand = hand
		InteractionType.DOOR:
			lock_camera = true
		InteractionType.SWITCH:
			lock_camera = true
			switch_moved = false
		InteractionType.WHEEL:
			lock_camera = true
			previous_mouse_position = get_viewport().get_mouse_position()
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		
	

func _physics_process(delta: float) -> void:
	match interaction_type:
		InteractionType.DEFAULT:
			if object_ref:
				last_velocity = object_ref.linear_velocity

func _process(delta: float) -> void:
	match interaction_type:
		InteractionType.DOOR:
			if not door_input_active:
				door_velocity = lerp(door_velocity, 0.0, delta * 4.0)
				
			
			door_angle += door_velocity
			door_angle = clamp(door_angle, starting_rotation, maximum_rotation)
			pivot_point.rotation.y = door_angle
			door_input_active = false
			
			if prev_door_angle == door_angle:
				stop_door_sounds(delta)
			else:
				update_door_sounds(delta)
		InteractionType.SWITCH:
			if is_interacting:
				update_switch_sounds(delta)
			else :
				stop_switch_sounds(delta)
			
			if is_switch_snapping:
				if not switch_kickback_triggered:
					switch_kickback_triggered = true
					if secondary_sfx and not secondary_audio_player.playing:
						secondary_audio_player.stop()
						secondary_audio_player.volume_db = 0.0
						secondary_audio_player.play()
				object_ref.rotation.z = lerp(object_ref.rotation.z, switch_target_rotation, delta * switch_lerp_speed)

				# Stope snapping when close enough
				if abs(object_ref.rotation.z - switch_target_rotation) < 0.01:
					object_ref.rotation.z = switch_target_rotation
					is_switch_snapping = false
					
				var percentage: float = (object_ref.rotation.z - starting_rotation) / (maximum_rotation - starting_rotation)
				notify_nodes(percentage)
			else:
				switch_kickback_triggered = false
		InteractionType.WHEEL:
			if is_interacting:
				update_wheel_sounds(delta)
			else:
				stop_wheel_sounds(delta)

			if abs(wheel_kickback) > 0.001:
				wheel_rotation += wheel_kickback
				wheel_kickback = lerp(wheel_kickback, 0.0, delta * 6.0)
				
				var min_wheel_rotation: float = starting_rotation / 0.1
				var max_wheel_rotation: float = maximum_rotation / 0.1
				wheel_rotation = clamp(wheel_rotation, min_wheel_rotation, max_wheel_rotation)
				
				object_ref.rotation.z = wheel_rotation * 0.1
				var percentage: float = (object_ref.rotation.z - starting_rotation) / (maximum_rotation - starting_rotation)
				notify_nodes(percentage)
				
				if not is_interacting and not wheel_kickback_triggered:
					wheel_kickback_triggered = true
					
					if secondary_sfx:
						secondary_audio_player.stop()
						secondary_audio_player.volume_db = 0.0
						secondary_audio_player.play()
			else:
				wheel_kickback_triggered = false

# Run every frame, perform some logic on this object
func interact() -> void:
	if not can_interact:
		return
		
	match interaction_type:
		InteractionType.DEFAULT:
			_default_interact()
		InteractionType.ITEM:
			_collect_item()
		InteractionType.NOTE:
			_collect_note()
	
	
func auxInteract() -> void:
	if not can_interact:
		return
		
	match interaction_type:
		InteractionType.DEFAULT:
			_default_throw()
	
# Runs once, when the player LAST inetracts with an object
func postInteract() -> void:
	is_interacting = false
	lock_camera = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	match interaction_type:
		InteractionType.DOOR:
			return
		InteractionType.SWITCH:
			var percentage: float = (object_ref.rotation.z - starting_rotation) / (maximum_rotation - starting_rotation)
			if percentage < 0.3:
				switch_target_rotation = starting_rotation
				is_switch_snapping = true
			elif  percentage > 0.7:
				switch_target_rotation = maximum_rotation
				is_switch_snapping = true
		InteractionType.WHEEL:
			wheel_kickback = -sign(wheel_rotation) * wheel_kick_intensity

func _input(event: InputEvent) -> void:
	if is_interacting:
		match  interaction_type:
			InteractionType.DOOR:
				if event is InputEventMouseMotion:
					
					door_input_active = true
					var delta: float = -event.relative.y * .001
					
					if not is_front:
						delta = -delta
					
					if abs(delta) < 0.01:
						delta *= 0.25
					
					door_velocity = lerp(door_velocity, delta, 1.0 / door_smoothing)
					
					
			InteractionType.SWITCH:
				if event is InputEventMouseMotion:
					var prev_angle = object_ref.rotation.z
					object_ref.rotate_z(event.relative.y * .001)
					object_ref.rotation.z = clamp(object_ref.rotation.z, starting_rotation, maximum_rotation)
					var percentage: float = (object_ref.rotation.z - starting_rotation) / (maximum_rotation - starting_rotation)
					
					if abs(object_ref.rotation.z - prev_angle) > 0.01:
						switch_moved = true
						
					notify_nodes(percentage)
			InteractionType.WHEEL:
				if event is InputEventMouseMotion:
					var mouse_position: Vector2 = event.position
					var percentage: float
					if calculate_cross_product(mouse_position) > 0:
						wheel_rotation += 0.2
					else:
						wheel_rotation -= 0.2
						
					object_ref.rotation.z = wheel_rotation * .1
					object_ref.rotation.z = clamp(object_ref.rotation.z, starting_rotation, maximum_rotation)
					percentage = (object_ref.rotation.z - starting_rotation) / (maximum_rotation - starting_rotation)
						
					previous_mouse_position = mouse_position
					
					var min_wheel_rotation: float = starting_rotation / 0.1
					var max_wheel_rotation: float = maximum_rotation / 0.1
					wheel_rotation = clamp(wheel_rotation, min_wheel_rotation, max_wheel_rotation)
					
					print("Visible Wheel Rotation ", rad_to_deg(object_ref.rotation.z))
					print("Inernal Wheel Rotation", wheel_rotation)
					
					notify_nodes(percentage)

func _default_interact() -> void:
	var objects_current_position: Vector3 = object_ref.global_transform.origin
	var player_hand_position: Vector3 = player_hand.global_transform.origin
	var object_distance: Vector3 = player_hand_position - objects_current_position # player hand position - object current position
	
	var rigid_body_3d: RigidBody3D = object_ref as RigidBody3D
	if rigid_body_3d:
		rigid_body_3d.set_linear_velocity((object_distance)*(5/rigid_body_3d.mass))
	
func _default_throw() -> void:
	var objects_current_position: Vector3 = object_ref.global_transform.origin
	var player_hand_position: Vector3 = player_hand.global_transform.origin
	var object_distance: Vector3 = player_hand_position - objects_current_position # player hand position - object current position
	
	var rigid_body_3d: RigidBody3D = object_ref as RigidBody3D
	if rigid_body_3d:
		var throw_direction: Vector3 = -player_hand.global_transform.basis.z.normalized()
		var throw_strenght: float = (20.0/rigid_body_3d.mass)
		rigid_body_3d.set_linear_velocity(throw_direction*throw_strenght)
		
		can_interact = false
		await  get_tree().create_timer(2.0).timeout
		can_interact = true
	
	
func set_direction(_normal: Vector3) -> void:
	if _normal.z > 0:
		is_front = true
	else:
		is_front = false
	
func notify_nodes(percentage: float) -> void:
	for node in nodes_to_effect:
		if node and node.has_method("execute"):
			node.call("execute", percentage)
	

func calculate_cross_product(_mouse_position: Vector2) -> float:
	var center_position = camera.unproject_position(object_ref.global_transform.origin)
	var vector_to_previous = previous_mouse_position - center_position
	var vector_to_current = _mouse_position - center_position
	var cross_product = vector_to_current.x * vector_to_previous.y - vector_to_current.y * vector_to_previous.x
	return cross_product
	
	
func _collect_item() -> void:
	emit_signal("item_collected", get_parent())
	await _play_sound_effect(false, false)
	get_parent().queue_free()
	

func _collect_note() -> void:
	var col = get_parent().find_child("CollisionShape3D", true, false)
	var mesh = get_parent().find_child("MeshInstance3D", true, false)
	if mesh:
		mesh.layers = 2
	if col:
		col.get_parent().remove_child(col)
		col.queue_free()
	_play_sound_effect(true, false)
	emit_signal("note_collected", get_parent())
	
func _play_sound_effect(visible: bool, interact: bool) -> void:
	if primary_sfx:
		primary_audio_player.play()
		get_parent().visible = visible
		self.can_interact = interact
		await primary_audio_player.finished

func _fire_default_collision(node: Node) -> void:
	var impact_strength = (last_velocity - object_ref.linear_velocity).length()
	if impact_strength > contact_velocity_threshold:
		_play_sound_effect(true, true)
	
## Fires when the player is interacting with door
func update_door_sounds(delta: float) -> void:
	# ----CREAK LOGIC-----#
	var velocity_amount: float = abs(door_velocity)
	var target_volume: float = 0.0
	
	if velocity_amount > creak_velocity_threshold:
		target_volume = clamp((velocity_amount - creak_velocity_threshold) * creak_volume_scale, 0.0, 1.0)
		
	
	if not primary_audio_player.playing and primary_sfx:
		primary_audio_player.volume_db = -80.0
		primary_audio_player.play()
		
	if primary_audio_player.playing:
		var current_vol: float = db_to_linear(primary_audio_player.volume_db)
		var new_vol: float = lerp(current_vol, target_volume, delta * door_fade_speed)
		primary_audio_player.volume_db = linear_to_db(clamp(new_vol, 0.0, 3.0))
	
	#-----SHUT LOGIC------#
	if abs(door_angle  - starting_rotation) > shut_angle_threshold:
		door_opened = true
		
	if door_opened and abs(door_angle - starting_rotation) < shut_snap_range:
		if secondary_sfx:
			secondary_audio_player.volume_db = -8.0
			secondary_audio_player.play()
			primary_audio_player.stop()
		door_opened = false
	
	
func stop_door_sounds(delta: float) -> void:
	if primary_audio_player.playing:
		var current_vol: float = db_to_linear(primary_audio_player.volume_db)
		var new_vol: float = lerp(current_vol, 0.0, delta * door_fade_speed)
		primary_audio_player.volume_db = linear_to_db(clamp(new_vol, 0.0, 1.0))
	
		if new_vol < 0.001:
			primary_audio_player.stop()
	
func update_switch_sounds(delta: float) -> void:
	var angular_speed = abs(object_ref.rotation.z - last_switch_angle) / max(delta, 0.0001)
	last_switch_angle = object_ref.rotation.z
	
	var target_volume: float = 0.0
	if angular_speed > switch_creak_velocity_threshold:
		target_volume = clamp((angular_speed - switch_creak_velocity_threshold) * creak_volume_scale, 0.0, 1.5)
		
	if not primary_audio_player.playing and primary_sfx:
		primary_audio_player.volume_db = -15.0
		primary_audio_player.play()
		
	if primary_audio_player.playing:
		var current_vol: float = db_to_linear(primary_audio_player.volume_db)
		var new_vol: float = lerp(current_vol, target_volume, delta * switch_fade_speed)
		primary_audio_player.volume_db = linear_to_db(clamp(new_vol, 0.0, 1.5))
		
	
	#-----THUNK LOGIC----#
	if switch_moved:
		if abs(object_ref.rotation.z - maximum_rotation) < 0.01 or abs(object_ref.rotation.z - starting_rotation) < 0.01:
			if secondary_sfx:
				secondary_audio_player.volume_db = -0.0
				secondary_audio_player.play()
			switch_moved = false
	
func stop_switch_sounds(delta: float) -> void:
	if primary_audio_player.playing:
		var current_vol: float = db_to_linear(primary_audio_player.volume_db)
		var new_vol: float = lerp(current_vol, 0.0, delta * switch_fade_speed)
		primary_audio_player.volume_db = linear_to_db(clamp(new_vol, 0.0, 1.0))
	
		if new_vol < 0.001:
			primary_audio_player.stop()
	
func update_wheel_sounds(delta: float) -> void:
	var angular_speed = abs(object_ref.rotation.z - last_wheel_angle) / max(delta, 0.0001)
	last_wheel_angle = object_ref.rotation.z
	
	var target_volume: float = 0.0
	if angular_speed > wheel_creak_velocity_threshold:
		target_volume = clamp((angular_speed - wheel_creak_velocity_threshold) * creak_volume_scale, 0.0, 1.0)
		
	if not primary_audio_player.playing and primary_sfx:
		primary_audio_player.volume_db = -15.0
		primary_audio_player.play()
		
	if primary_audio_player.playing:
		var current_vol: float = db_to_linear(primary_audio_player.volume_db)
		var new_vol: float = lerp(current_vol, target_volume, delta * wheel_fade_speed)
		primary_audio_player.volume_db = linear_to_db(clamp(new_vol, 0.0, 1.0))
	
func stop_wheel_sounds(delta: float) -> void:
	if primary_audio_player.playing:
		var current_vol: float = db_to_linear(primary_audio_player.volume_db)
		var new_vol: float = lerp(current_vol, 0.0, delta * wheel_fade_speed)
		primary_audio_player.volume_db = linear_to_db(clamp(new_vol, 0.0, 1.0))
	
		# Stop completely once inaudible
		if new_vol < 0.001:
			primary_audio_player.stop()
	
	
	
	
	
	
	
	
	
