extends Node2D

var server := TCPServer.new()
var peer : StreamPeerTCP

@onready var voice_player : AudioStreamPlayer = $VoicePlayer


func _ready():
	server.listen(8080)
	print("Speech server listening")
	print("User dir:", ProjectSettings.globalize_path("user://"))


func _process(_delta):

	if server.is_connection_available():
		peer = server.take_connection()

	if peer and peer.get_available_bytes() > 0:

		var data = peer.get_utf8_string(peer.get_available_bytes())
		print("Received:", data)

		var json = JSON.parse_string(data)

		if json and json.has("audio"):
			play_audio(json["audio"])

		peer.disconnect_from_host()



# --------------------------------------------------
# AUDIO PLAYBACK
# --------------------------------------------------
func play_audio(path:String):

	var absolute = ProjectSettings.globalize_path(path)

	print("Loading:", absolute)

	if not FileAccess.file_exists(absolute):
		print("File not found:", absolute)
		return

	var stream = AudioStreamWAV.load_from_file(absolute)

	if stream == null:
		print("Failed to load wav")
		return

	voice_player.stream = stream
	voice_player.play()

	print("Playback started")
