extends Node2D

const SCRIPT_VERSION = 1.2


# =========================================================
# MODEL
# =========================================================

@onready var model: GDCubismUserModel = $Sprite2D/GDCubismUserModel
@onready var player: AudioStreamPlayer = $Node/VoicePlayer

var model_ready := false


# =========================================================
# PARAMETERS
# =========================================================

var breath_param
var eyeX_param
var eyeY_param
var headX_param
var headY_param
var headZ_param
var part8
var mouth_open
var mouth_form
var mouth_target_open := 0.0
var mouth_target_form  := 0.0
var mouth_queue: Array = []
var mouth_interval     := 0.1
var audio_duration     := 0.0


# =========================================================
# AUDIO / WEBSOCKET / PHONEMES
# =========================================================

var socket         := WebSocketPeer.new()
var audio_buffer   := PackedByteArray()
var receiving_audio := false
var talking         := false
var first_chunk     := true       # tracks whether WAV header has been received
var phoneme_timeline: Array = []


# =========================================================
# BREATH SETTINGS
# =========================================================

var breath_time  := 0.0
var breath_speed := 1.1


# =========================================================
# LOOK PRESETS
# =========================================================

var LOOK_PRESETS = [
	{ "eye": Vector2(0,0),  "head": Vector3(0,0,0)  },
	{ "eye": Vector2(1,0),  "head": Vector3(6,0,0)  },
	{ "eye": Vector2(-1,0), "head": Vector3(-6,0,0) },
	{ "eye": Vector2(0,1),  "head": Vector3(0,6,0)  },
	{ "eye": Vector2(0,-1), "head": Vector3(0,-6,0) },
	{ "eye": Vector2(1,1),  "head": Vector3(5,4,0)  },
	{ "eye": Vector2(-1,1), "head": Vector3(-5,4,0) },
	{ "eye": Vector2(0,0),  "head": Vector3(0,0,8)  },
	{ "eye": Vector2(0,0),  "head": Vector3(0,0,-8) }
]


# =========================================================
# LOOK SYSTEM
# =========================================================

var look_timer     := 0.0
var next_look_time := 0.0
var looking        := false
var look_elapsed   := 0.0
var look_duration  := 2.5
var eye_start      := Vector2.ZERO
var eye_target     := Vector2.ZERO
var head_start     := Vector3.ZERO
var head_target    := Vector3.ZERO


# =========================================================
# EYE COLOR SWITCH
# =========================================================

var eye_color_current    := 0.0
var eye_color_target     := 0.0
var eye_color_timer      := 0.0
var next_eye_color_time  := 0.0
var eye_color_transition := 0.0
var eye_color_duration   := 4.0
var eye_color_active     := false
var toRed_min  := 5.0
var toRed_max  := 10.0
var toBlue_min := 5.0
var toBlue_max := 10.0


# =========================================================
# READY
# =========================================================

func _ready():
	print("Ravyn avatar script version:", SCRIPT_VERSION)
	randomize()
	print("Connecting WebSocket")
	socket.connect_to_url("ws://192.168.1.154:9000/ws/audio")
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
			"ParamEyeBallX":   eyeX_param   = p
			"ParamEyeBallY":   eyeY_param   = p
			"ParamAngleX":     headX_param  = p
			"ParamAngleY":     headY_param  = p
			"ParamAngleZ":     headZ_param  = p

	for part in model.get_part_opacities():
		if part.id == "Part8":
			part8 = part

	if part8:
		part8.value = 0.0

	_schedule_next_look()
	_schedule_eye_color()
	model_ready = true


# =========================================================
# MAIN LOOP
# =========================================================

func _process(delta):
	if not model_ready:
		return

	_handle_websocket()
	breathe(delta)
	idleLook(delta)
	eyeColorChange(delta)
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
				talking          = true
				mouth_queue.clear()
				phoneme_timeline.clear()
				audio_buffer     = PackedByteArray()
				receiving_audio  = true
				first_chunk      = true

			elif msg == "END":
				talking         = false
				receiving_audio = false
				_prepare_audio()

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
				var raw  = float(msg.split(":")[1])
				var amp  = clamp(raw * 8.0, 0.0, 1.0)
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

	var pcm = audio_buffer.slice(44, audio_buffer.size())

	var stream         := AudioStreamWAV.new()
	stream.data        = pcm
	stream.format      = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate    = 24000
	stream.stereo      = false

	audio_duration = float(pcm.size()) / float(24000 * 2)

	if mouth_queue.size() > 1:
		mouth_interval = audio_duration / float(mouth_queue.size() - 1)
	else:
		mouth_interval = 0.1

	print("Audio duration: ", audio_duration, "s  |  Mouth msgs: ", mouth_queue.size(), "  |  Interval: ", mouth_interval, "s")

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
		if mouth_form:
			mouth_form.value = lerp(mouth_form.value, 0.0, 0.1)
		return

	var amp := 0.0
	var playback_pos = player.get_playback_position()
	var stream = player.stream as AudioStreamWAV

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
		var viseme = _current_viseme(playback_pos)
		mouth_form.value = lerp(mouth_form.value, viseme["form"], 0.25)


# =========================================================
# VISEME LOOKUP
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

	# WIDE VOWELS (A)
	if s in ["a","ɑ","æ","ɐ","ɑː"]:
		return { "open": 1.0, "form": 0.0 }

	# ROUND VOWELS (O / U)
	if s in ["o","ɔ","oʊ","ʊ","u","uː","ɔː"]:
		return { "open": 0.5, "form": -0.25 }

	# FRONT VOWELS (I / E) - toned down smile
	if s in ["i","ɪ","e","ɛ","eɪ","aɪ","iː"]:
		return { "open": 0.6, "form": 0.6 }

	# CLOSED CONSONANTS
	if s in ["m","b","p"]:
		return { "open": 0.0, "form": 0.0 }

	# FRICATIVES
	if s in ["f","v","θ","ð"]:
		return { "open": 0.25, "form": 0.3 }

	# SIBILANTS
	if s in ["s","z","ʃ","ʒ"]:
		return { "open": 0.3, "form": 0.4 }

	# DEFAULT - neutral rest
	return { "open": 0.35, "form": 0.0 }


# =========================================================
# BREATH
# =========================================================

func breathe(delta):
	if not breath_param:
		return
	breath_time        += delta * breath_speed
	breath_param.value  = (cos(breath_time) * -0.5) + 0.5


# =========================================================
# IDLE LOOK SYSTEM
# =========================================================

func idleLook(delta):
	if not looking:
		look_timer += delta
		if look_timer >= next_look_time:
			look_timer = 0.0
			startLook()
	else:
		look_elapsed += delta
		var t = clamp(look_elapsed / look_duration, 0, 1)
		t = t * t * (3.0 - 2.0 * t)

		if eyeX_param:  eyeX_param.value  = lerp(eye_start.x,   eye_target.x,   t)
		if eyeY_param:  eyeY_param.value  = lerp(eye_start.y,   eye_target.y,   t)
		if headX_param: headX_param.value = lerp(head_start.x,  head_target.x,  t)
		if headY_param: headY_param.value = lerp(head_start.y,  head_target.y,  t)
		if headZ_param: headZ_param.value = lerp(head_start.z,  head_target.z,  t)

		if t >= 1.0:
			looking = false
			_schedule_next_look()


func startLook():
	looking      = true
	look_elapsed = 0.0
	look_duration = randf_range(1.5, 3.5)

	var preset = LOOK_PRESETS.pick_random()

	eye_start  = Vector2(eyeX_param.value,  eyeY_param.value)
	head_start = Vector3(headX_param.value, headY_param.value, headZ_param.value)

	eye_target  = preset["eye"]
	head_target = preset["head"]


func _schedule_next_look():
	next_look_time = randf_range(5.0, 30.0)


# =========================================================
# EYE COLOR SWITCH
# =========================================================

func eyeColorChange(delta):
	if not part8:
		return

	if not eye_color_active:
		eye_color_timer += delta
		if eye_color_timer >= next_eye_color_time:
			eye_color_timer      = 0.0
			eye_color_target     = 1.0 - eye_color_target
			eye_color_transition = 0.0
			eye_color_active     = true
	else:
		eye_color_transition += delta
		var t = clamp(eye_color_transition / eye_color_duration, 0.0, 1.0)
		t = t * t * (3.0 - 2.0 * t)
		eye_color_current = lerp(eye_color_current, eye_color_target, t)
		part8.value       = eye_color_current
		if t >= 1.0:
			eye_color_active = false
			_schedule_eye_color()


func _schedule_eye_color():
	if eye_color_target < 0.5:
		next_eye_color_time = randf_range(toRed_min, toRed_max)
	else:
		next_eye_color_time = randf_range(toBlue_min, toBlue_max)
