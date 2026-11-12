extends Node2D

const SCRIPT_VERSION = 1.8

# =========================================================
# MODEL
# =========================================================

@onready var model          : GDCubismUserModel = $Sprite2D/GDCubismUserModel
@onready var player         : AudioStreamPlayer = $Node/VoicePlayer
@onready var ears_node                          = $Sprite2D/GDCubismUserModel/Ears
@onready var eyes_node                          = $Sprite2D/GDCubismUserModel/Eyes
@onready var idle_node                     = $Sprite2D/GDCubismUserModel/Idle

# The node that actually draws her, for ghost mode's fade. If modulate on the
# Sprite2D turns out not to affect the Cubism render in your setup, point this
# at `self` instead — the fade only ever touches `modulate.a`.
@onready var avatar         : CanvasItem        = $Sprite2D

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
var reconnect_timer := 0.0
var reconnect_interval := 3.0
var ws_connected    := false    # for the action log: say it once, not per frame

# What she actually looks like, written to the action log on a clock: twice a
# second while her voice plays, every few seconds otherwise. Sampled, not
# per frame — enough to see where her eyes and head were during each line.
const STATE_TALKING_S := 0.5
const STATE_IDLE_S    := 3.0
var state_timer       := 0.0
var was_playing       := false

# The audio server runs on the PC (AUDIO_SERVER_HOST = "0.0.0.0", port 9000)
# and so does Godot, so localhost is right. 192.168.1.154 is the NOTEBOOK —
# that was correct only while the notebook did TTS, which it has not for a
# while. If Godot ever runs on another machine, this becomes the PC's IP.
var ws_url := "ws://localhost:9000/ws/audio"

# The rate the PCM actually arrives at. The PC sends RATE:<int> with the first
# sentence of every utterance; this default is what an older PC build, which
# sends none, is assumed to be using.
var sample_rate := 24000

# =========================================================
# GHOST MODE
# =========================================================
#
# The PC sends SHOW:percent:fade_ms before START and after END when it is
# started with --ghost, and sends nothing at all otherwise — so `ghost_mode`
# stays false and none of this runs.
#
# Visibility follows the UTTERANCE, not the amplitude: alpha driven from MOUTH
# would strobe, because speech hits zero between syllables several times a
# word. MOUTH keeps doing the mouth.

var ghost_mode    := false
var fade_from     := 1.0
var fade_to       := 1.0
var fade_elapsed  := 0.0
var fade_duration := 0.0

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
	socket.connect_to_url(ws_url)
	ActionLog.add("avatar_start", {"version": SCRIPT_VERSION})
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
	_update_visibility(delta)
	_update_lipsync()
	_log_state(delta)
	model.advance(delta)


# =========================================================
# WEBSOCKET
# =========================================================

func _handle_websocket():
	socket.poll()
	var state = socket.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		reconnect_timer = 0.0
		socket.send_text("ping")
		if not ws_connected:
			ws_connected = true
			ActionLog.add("connected")

		while socket.get_available_packet_count():
			var pkt = socket.get_packet()

			if socket.was_string_packet():
				var msg = pkt.get_string_from_utf8()

				# Which line this is: the PC's req_id, sent before START.
				if msg.begins_with("LINE:"):
					ActionLog.line_id = msg.substr(5)

				elif msg == "START":
					talking         = true
					first_chunk     = true
					receiving_audio = true
					audio_buffer    = PackedByteArray()
					mouth_queue.clear()
					phoneme_timeline.clear()
					ears_node.perk_up()
					idle_node.start_talking()
					ActionLog.add("talk_start")

				elif msg == "END":
					talking         = false
					receiving_audio = false
					idle_node.stop_talking()
					_prepare_audio()
					ActionLog.add("talk_end", {
						"audio_s": snappedf(audio_duration, 0.01),
						"phonemes": phoneme_timeline.size(),
						"mouth_frames": mouth_queue.size()})

				elif msg.begins_with("MOOD:"):
					var value = float(msg.split(":")[1])
					eyes_node.set_mood(float(msg.split(":")[1]))
					idle_node.set_mood(value)
					ActionLog.add("mood", {"value": value})

				elif msg.begins_with("TIRED:"):
					var value = float(msg.split(":")[1])
					eyes_node.set_tired(float(msg.split(":")[1]))
					idle_node.set_tired(value)
					ActionLog.add("tired", {"value": value})

				# Ghost mode: SHOW:percent:fade_ms. Sent only with --ghost.
				elif msg.begins_with("SHOW:"):
					var show_parts = msg.split(":")
					if show_parts.size() >= 3:
						_set_visibility(
							float(show_parts[1]) / 100.0,
							float(show_parts[2]) / 1000.0)
						ActionLog.add("visibility", {
							"percent": int(show_parts[1]),
							"fade_ms": int(show_parts[2])})

				# The rate the PCM is at, sent once per utterance with the
				# first sentence. Hardcoding 24000 was only right while the
				# TTS happened to run there.
				elif msg.begins_with("RATE:"):
					var rate_parts = msg.split(":")
					if rate_parts.size() >= 2:
						var rate = int(rate_parts[1])
						if rate > 0:
							sample_rate = rate

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

		ActionLog.flush(socket)

	elif state == WebSocketPeer.STATE_CLOSED or state ==  WebSocketPeer.STATE_CLOSING:
		if ws_connected:
			ws_connected = false
			ActionLog.add("disconnected")
		reconnect_timer += get_process_delta_time()
		if reconnect_timer >= reconnect_interval:
			reconnect_timer = 0.0
			print("Reconnect WebSocket...")
			socket = WebSocketPeer.new()
			socket.connect_to_url(ws_url)


# =========================================================
# GHOST MODE — FADE
# =========================================================

func _set_visibility(target: float, seconds: float) -> void:
	if avatar == null:
		return

	# The first SHOW is what turns ghost mode on. Before one arrives she is
	# simply visible, which is what a stream without --ghost wants and what an
	# older PC build gives.
	if not ghost_mode:
		ghost_mode = true
		print("Ghost mode on (the PC is sending SHOW)")

	fade_from     = avatar.modulate.a
	fade_to       = clamp(target, 0.0, 1.0)
	fade_duration = max(seconds, 0.0)
	fade_elapsed  = 0.0

	# A zero-length fade is a snap, not a division by zero.
	if fade_duration <= 0.0:
		_apply_alpha(fade_to)


func _update_visibility(delta: float) -> void:
	if not ghost_mode or avatar == null:
		return
	if fade_duration <= 0.0 or fade_elapsed >= fade_duration:
		return

	fade_elapsed += delta
	var t = clamp(fade_elapsed / fade_duration, 0.0, 1.0)

	# Smoothstep rather than linear: over 200ms a linear fade starts and stops
	# abruptly enough to read as a cut.
	t = t * t * (3.0 - 2.0 * t)
	_apply_alpha(lerp(fade_from, fade_to, t))


# =========================================================
# ACTION LOG — HER STATE, ON A CLOCK
# =========================================================

func _log_state(delta: float) -> void:
	var playing: bool = player.playing
	if playing and not was_playing:
		ActionLog.add("voice_start")
		state_timer = STATE_TALKING_S      # sample at once
	elif was_playing and not playing:
		_log_state_now("state")
		ActionLog.add("voice_end")
		ActionLog.line_id = ""
	was_playing = playing

	state_timer += delta
	if state_timer >= (STATE_TALKING_S if playing else STATE_IDLE_S):
		state_timer = 0.0
		_log_state_now("state")


func _log_state_now(kind: String) -> void:
	ActionLog.add(kind, {
		"voice": player.playing,
		"talking": idle_node.talking,
		"focus": idle_node.looking_at_user,
		"group": idle_node.current_group,
		"wandering": idle_node.looking or idle_node.holding,
		"expression": eyes_node.Expressions.keys()[eyes_node.current_expression],
		"face_override": eyes_node.face_override,
		"micro": idle_node.micro_active,
		"mood": snappedf(eyes_node.mood, 0.01),
		"tired": snappedf(eyes_node.tired, 0.01),
		"eye": [_value(idle_node.eyeX_param), _value(idle_node.eyeY_param)],
		"head": [_value(idle_node.headX_param), _value(idle_node.headY_param),
				 _value(idle_node.headZ_param)],
		"alpha": snappedf(avatar.modulate.a, 0.01) if avatar else 1.0,
	})


func _value(param) -> float:
	return snappedf(param.value, 0.01) if param else 0.0


func _apply_alpha(value: float) -> void:
	var tint = avatar.modulate
	tint.a = clamp(value, 0.0, 1.0)
	avatar.modulate = tint


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
	stream.mix_rate = sample_rate
	stream.stereo  = false

	audio_duration = float(pcm.size()) / float(sample_rate * 2)

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
		var sample_idx = int(playback_pos * sample_rate)
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
