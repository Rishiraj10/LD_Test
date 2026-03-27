extends Node3D

func execute(_percentage: float) -> void:
	if _percentage > .8:
		hide()
	elif  _percentage < .8:
		show()
