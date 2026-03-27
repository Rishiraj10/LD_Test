extends SpotLight3D

@export var actutaion_percentage: float = 0.8


func execute(_percentage: float) -> void:
	#if _percentage < actutaion_percentage:
		#visible = false
	#else:
		#visible = true
		light_energy = (_percentage*100.0)
