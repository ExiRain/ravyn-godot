extends Node2D

const SCRIPT_VERSION = 1.5

# =========================================================
# MODEL
# =========================================================

@onready var model          : GDCubismUserModel = $Sprite2D/GDCubismUserModel
@onready var player         : AudioStreamPlayer = $Node/VoicePlayer
@onready var ears_node                          = $Sprite2D/GDCubismUserModel/Ears
@onready var eyes_node                          = $Sprite2D/GDCubismUserModel/Eyes
@onready var idle_node                     = $Sprite2D/GDCubismUserModel/Idle

var model_ready := false

# =========================================================
# PARAMETERS - only what main script owns
# =========================================================

var breath_param
var mouth_open
var mouth_form

# =========================================================
# AUDIO / WEBSOCKET / PHONEMES
# =========================================================

var socket          := WebSocketPeer.new()
var audio_buffer    := PackedByteArray()
var receiving_audio := false
var talking         := false
var first_chunk     := true
var phoneme_timeline: Array = []
var mouth_queue     : Array = []
var mouth_interval  := 0.1
var audio_duration  := 0.0

# =========================================================
# BREATH
# =========================================================

var breath_time  := 0.0
var breath_speed := 1.1


# =========================================================
# READY
# =========================================================

func _ready():
	print("Ravyn avatar script version:", SCRIPT_VERSION)
	randomize()
	print("Connecting WebSocket")
	socket.connect_to_url("ws://localhost:9000/ws/audio")
	call_deferred("_wait_for_model")


# =========================================================
# INITIALIZATION
# =========================================================

func _wait_for_model():
	while model.get_parameters().is_empty():
		await get_tree().process_frame

	for p in model.get_parameters():
		match p.id:
			"ParamBreath":     breath_param = p
			"ParamMouthOpenY": mouth_open   = p
			"ParamMouthForm":  mouth_form   = p

	model_ready = true
	idle_node.eyes_node        = eyes_node
	idle_node.mouth_form_param = mouth_form
	eyes_node.idle_node 	   = idle_node
	print("mouth_form:", mouth_form != null)


# =========================================================
# MAIN LOOP
# =========================================================

func _process(delta):
	if not model_ready:
		return

	_handle_websocket()
	breathe(delta)
	_update_lipsync()
	model.advance(delta)


# =========================================================
# WEBSOCKET
# =========================================================

func _handle_websocket():
	socket.poll()

	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return

	socket.send_text("ping")

	while socket.get_available_packet_count():
		var pkt = socket.get_packet()

		if socket.was_string_packet():
			var msg = pkt.get_string_from_utf8()

			if msg == "START":
				talking         = true
				first_chunk     = true
				receiving_audio = true
				audio_buffer    = PackedByteArray()
				mouth_queue.clear()
				phoneme_timeline.clear()
				ears_node.perk_up()
				idle_node.start_talking()

			elif msg == "END":
				talking         = false
				receiving_audio = false
				idle_node.stop_talking()
				_prepare_audio()

			elif msg.begins_with("MOOD:"):
				var value = float(msg.split(":")[1])
				eyes_node.set_mood(float(msg.split(":")[1]))
				idle_node.set_mood(value)

			elif msg.begins_with("TIRED:"):
				var value = float(msg.split(":")[1])
				eyes_node.set_tired(float(msg.split(":")[1]))
				idle_node.set_tired(value)

			elif msg.begins_with("PHONEME:"):
				var parts = msg.split(":")
				if parts.size() >= 3:
					var word_phoneme = parts[1]
					var t            = float(parts[2])
					var chars        = []
					var i            = 0
					while i < word_phoneme.length():
						if i + 1 < word_phoneme.length():
							var two = word_phoneme.substr(i, 2)
							if two in ["oʊ","eɪ","aɪ","ɔː","uː","iː","ɑː"]:
								chars.append(two)
								i += 2
								continue
						chars.append(word_phoneme[i])
						i += 1
					var char_duration = 0.18
					for idx in range(chars.size()):
						phoneme_timeline.append({
							"p": chars[idx],
							"t": t + idx * char_duration
						})

			elif msg.begins_with("MOUTH:"):
				var raw         = float(msg.split(":")[1])
				var amp         = clamp(raw * 8.0, 0.0, 1.0)
				var open: float = amp
				var form: float = 0.0
				if amp < 0.1:
					form = 0.0
				elif amp < 0.3:
					form = -0.35
				elif amp < 0.6:
					form = -0.1
				else:
					form = 0.8
				mouth_queue.append({ "open": open, "form": form })

		else:
			if receiving_audio:
				if first_chunk:
					audio_buffer.append_array(pkt)
					first_chunk = false
				else:
					audio_buffer.append_array(pkt)


# =========================================================
# AUDIO PREP
# =========================================================

func _prepare_audio():
	if audio_buffer.size() < 44:
		return

	var pcm        = audio_buffer.slice(44, audio_buffer.size())
	var stream     := AudioStreamWAV.new()
	stream.data    = pcm
	stream.format  = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 24000
	stream.stereo  = false

	audio_duration = float(pcm.size()) / float(24000 * 2)

	if mouth_queue.size() > 1:
		mouth_interval = audio_duration / float(mouth_queue.size() - 1)
	else:
		mouth_interval = 0.1

	player.stream = stream
	player.play()


# =========================================================
# LIP SYNC
# =========================================================

func _update_lipsync():
	if not mouth_open:
		return

	if not player.playing:
		mouth_open.value = lerp(mouth_open.value, 0.0, 0.15)
		if mouth_form and not idle_node.mouth_flicker_active:
			mouth_form.value = lerp(mouth_form.value, 0.0, 0.1)
		return

	var amp          := 0.0
	var playback_pos  = player.get_playback_position()
	var stream        = player.stream as AudioStreamWAV

	if stream and stream.data.size() > 0:
		var sample_idx = int(playback_pos * 24000)
		var window     := 128
		var byte_start = clamp((sample_idx - window / 2) * 2, 0, stream.data.size() - 2)
		var byte_end   = clamp(byte_start + window * 2, 0, stream.data.size())

		var sum   := 0.0
		var count := 0
		var i      = byte_start
		while i < byte_end - 1:
			var lo     = stream.data[i]
			var hi     = stream.data[i + 1]
			var sample = (hi << 8) | lo
			if sample > 32767:
				sample -= 65536
			sum   += abs(sample)
			count += 1
			i     += 2

		if count > 0:
			var raw_amp = (sum / count) / 32767.0
			amp = clamp(raw_amp * 25.0, 0.0, 1.0)

	mouth_open.value = lerp(mouth_open.value, amp, 0.5)

	if mouth_form:
		if not idle_node.mouth_flicker_active:
			var viseme = _current_viseme(playback_pos)
			mouth_form.value = lerp(mouth_form.value, viseme["form"], 0.25)


# =========================================================
# VISEME
# =========================================================

func _current_viseme(playback_time: float) -> Dictionary:
	if phoneme_timeline.is_empty():
		return { "open": 0.4, "form": 0.0 }

	var current = phoneme_timeline[0]
	for item in phoneme_timeline:
		if playback_time >= float(item["t"]):
			current = item
		else:
			break

	return _map_phoneme_to_viseme(str(current["p"]))


func _map_phoneme_to_viseme(p: String) -> Dictionary:
	var s = p.to_lower()

	if s in ["a","ɑ","æ","ɐ","ɑː"]:
		return { "open": 1.0, "form": 0.0 }
	if s in ["o","ɔ","oʊ","ʊ","u","uː","ɔː"]:
		return { "open": 0.5, "form": -0.25 }
	if s in ["i","ɪ","e","ɛ","eɪ","aɪ","iː"]:
		return { "open": 0.6, "form": 0.6 }
	if s in ["m","b","p"]:
		return { "open": 0.0, "form": 0.0 }
	if s in ["f","v","θ","ð"]:
		return { "open": 0.25, "form": 0.3 }
	if s in ["s","z","ʃ","ʒ"]:
		return { "open": 0.3, "form": 0.4 }

	return { "open": 0.35, "form": 0.0 }


# =========================================================
# BREATH
# =========================================================

func breathe(delta):
	if not breath_param:
		return
	breath_time       += delta * breath_speed
	breath_param.value = (cos(breath_time) * -0.5) + 0.5
