extends Node


@onready var light_detection_viewport: SubViewport = %SubViewport
@onready var light_detection: Node3D = %LightDetection
@onready var debug: Label = %Debug
@onready var distortion: Sprite2D = %Distortion
@onready var distortion_material: ShaderMaterial = distortion.material
@onready var player_camera: Camera3D = %Camera3D

@onready var flash_sprite: Sprite2D = %PuzzleComplete
@onready var flash_material: ShaderMaterial = flash_sprite.material



var light_level: float = 0.0

# Sanity Variables
var sanity: float = 100.0
var time_since_sanity_change: float = 0.0
const SANITY_DRAIN_INTERVAL: float = .25
const SANITY_DRAIN_RATE: float = 1.0
const DARKNESS_THRESHOLD: float = 0.3
const SANITY_REGEN_TARGET: float = 51.0
const SANITY_REGEN_RATE: float = 1.0 / SANITY_DRAIN_INTERVAL
const ENEMY_VIEW_RANGE: float = 10.0

func ready() -> void:
	light_detection_viewport.debug_draw = Viewport.DEBUG_DRAW_LIGHTING
	
	
func _process(delta: float) -> void:
	light_level = get_light_level()
	
	update_sanity(delta)
	update_distortion(sanity)
	
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if is_enemy_on_screen(enemy):
			if is_enemy_in_view(enemy, ENEMY_VIEW_RANGE):
				drain_sanity(delta * 8.0)
				
	
	#debug.text = str("FPS : ", Engine.get_frames_per_second(), "\n light_level : ", light_level)
	
	debug.text = "FPS: %d \nLight Level: %.2f\nSanity: %.2f\nState: %s" % [
		Engine.get_frames_per_second(),
		light_level,
		sanity,
		get_sanity_state()
	]
	
	
func get_light_level() -> float:
	light_detection.global_position = get_parent().global_position
	var texture = light_detection_viewport.get_texture()
	var color = get_average_color(texture)
	return color.get_luminance()
	

func get_average_color(texture: ViewportTexture) -> Color:
	var image = texture.get_image()
	image.resize(1,1, Image.INTERPOLATE_BILINEAR)
	return image.get_pixel(0,0)

func update_sanity(delta) -> void:
	time_since_sanity_change += delta
	
	if light_level <= DARKNESS_THRESHOLD: #in the dark
		#drain sanity
		if time_since_sanity_change >= SANITY_DRAIN_INTERVAL and sanity > 0.0:
			sanity -= 1.0
			sanity = clamp(sanity, 0.0, 100.0)
			time_since_sanity_change = 0.0
	else:
		if sanity < SANITY_REGEN_TARGET:
			if time_since_sanity_change >= SANITY_DRAIN_INTERVAL:
				sanity += SANITY_REGEN_RATE * SANITY_DRAIN_INTERVAL
				sanity = clamp(sanity, 0.0, SANITY_REGEN_TARGET)
				time_since_sanity_change = 0.0
			
	
func get_sanity_state() -> String:
	if sanity >= 75.0:
		return "Crystal Clear"
	elif  sanity >=50.0:
		return "A slight headache"
	elif sanity >= 25.0:
		return "Head is pounding and hands are shaking"
	elif sanity >=1.0:
		return "..."
	else:
		return "Unconcious"
	
	
	
	
func update_distortion(sanity: float) -> void:
	var distortion: float = 0.0
	if sanity < 50.0:
		var t: float = (50.0 - sanity) / 50 # btw 0 to 1
		t = pow(t, 2.5)
		distortion = t * 0.05
		
	distortion_material.set_shader_parameter("distortion_strength", distortion)
	
	
func is_enemy_on_screen(enemy: Node3D) -> bool:
	var viewport: Viewport = player_camera.get_viewport()
	var screen_size: Vector2 = viewport.size
	
	var enemy_position: Vector3 = enemy.global_transform.origin
	var camera_position: Vector3 = player_camera.global_transform.origin
	var to_enemy: Vector3 = enemy_position - camera_position
	
	var forward: Vector3 = -player_camera.global_transform.basis.z
	
	if forward.dot(to_enemy) < 0.0 :
		return false
		
	var screen_pos: Vector2 = player_camera.unproject_position(enemy_position)
	
	if screen_pos.x < 0.0 or screen_pos.x > screen_size.x:
		return false
	if screen_pos.y < 0.0 or screen_pos.y > screen_size.y:
		return false
	
	return true
	
func is_enemy_in_view(enemy: Node3D, tolerance_degrees: float) -> bool:
	var enemy_position: Vector3 = enemy.global_transform.origin
	var camera_position: Vector3 = player_camera.global_transform.origin
	
	# VEctor pointing from the player camera to the enemy
	var to_enemy: Vector3 = (enemy_position - camera_position).normalized()
	
	# Camera's forward direction
	var forward: Vector3 = -player_camera.global_transform.basis.z
	
	var angle_deg: float = rad_to_deg(acos(forward.dot(to_enemy)))
	
	return angle_deg <= tolerance_degrees
	
	
func drain_sanity(amount: float) -> void :
	sanity -= amount
	sanity = clamp(sanity, 0.0, 100.0)
	
func add_sanity(amount: float) -> void :
	sanity += amount
	sanity = clamp(sanity, 0.0, 100.0)
	
	


func on_puzzle_complete(flash_duration: float = 0.1, fade_duration: float = 0.5) -> void:
	flash_sprite.visible = true
	
	flash_material.set_shader_parameter("alpha", 0.5)
	
	var tween = get_tree().create_tween()
	
	tween.tween_interval(flash_duration)
	
	tween.tween_property(flash_material, "shader_parameter/alpha", 0.0, fade_duration)
	
	tween.tween_callback(Callable(self, "_on_flash_complete"))

func _on_flash_complete() -> void:
	
	flash_material.set_shader_parameter("alpha", 0.0)
	flash_sprite.visible = false
