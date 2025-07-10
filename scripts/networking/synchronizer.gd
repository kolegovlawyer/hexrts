extends MultiplayerSynchronizer

# GDE ETO NA MINIRTS?

@export var position: Vector3:
	set(val):
		if is_multiplayer_authority():
			position = val
		else:
			get_parent().position = val

@export var y_rotation:float:
	set(val):
		if is_multiplayer_authority():
			y_rotation = val
		else:
			get_parent().rotation.y = val

@export var owner_id:int=1:
	set(val):
		if is_multiplayer_authority():
			owner_id = val
		else:
			get_parent().owner_id = val
			print("New owner",val)
