extends Node

@onready var model: GDCubismUserModel = $"../Sprite2D/GDCubismUserModel"
@onready var player: AudioStreamPlayer = $VoicePlayer

var socket := WebSocketPeer.new()

var mouth_open_param
var mouth_form_param


func _ready():

	print("Waiting for model parameters")

	await _wait_for_model()

	print("Model ready")

	if mouth_open_param:
		print("Opening mouth")
		mouth_open_param.value = 1.0
		print("param", mouth_open_param.value)

	if mouth_form_param:
		mouth_form_param.value = 0.0


func _wait_for_model():

	while model.get_parameters().is_empty():
		await get_tree().process_frame

	for p in model.get_parameters():

		print("Found parameter:", p.id)

		if p.id == "ParamMouthOpenY":
			mouth_open_param = p

		if p.id == "ParamMouthForm":
			mouth_form_param = p
