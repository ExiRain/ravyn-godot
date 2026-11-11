extends Node2D

# =========================================================
# RAVYN — ISOLATED ANIMATION RECORDER (Catmull-Rom timeline)
# Plays ONE animation on scene run, for Movie Maker capture.
# Motion flows continuously through keyframes (no stops),
# every channel clamped to model limits, holds on the final
# pose at the end.
# Tuning surface = the KEYS_* tables.
# =========================================================

@export_enum("sub", "follow", "raid", "donation") var animation : String = "raid"
@export var lead_in : float = 0.0
@export var loop    : bool  = false

@onready var model : GDCubismUserModel = $Sprite2D/GDCubismUserModel

var model_ready := false

var eye_l_open
var eye_r_open
var eyeball_x
var eyeball_y
var angle_x
var angle_y
var angle_z
var brow_l_y
var brow_r_y
var brow_l_form
var brow_r_form
var mouth_open
var mouth_form
var breath_param
var eye_transition
var part8

var playing   := false
var finished  := false
var lead_t    := 0.0
var anim_time := 0.0
var keys : Array = []

var breath_time  := 0.0
var breath_speed := 1.1

# channels: eo eye-open | br brow | rd red | lx/ly eye look | hy head-up | hz head-tilt | mo mouth-open | mf mouth-form
const CH := ["eo", "br", "rd", "lx", "ly", "hy", "hz", "mo", "mf"]
const LO := { "eo":0.0, "br":-1.0, "rd":0.0, "lx":-1.0, "ly":-1.0, "hy":-30.0, "hz":-16.0, "mo":0.0, "mf":-1.0 }
const HI := { "eo":1.4, "br":1.0,  "rd":1.0, "lx":1.0,  "ly":1.0,  "hy":15.0,  "hz":16.0,  "mo":1.0, "mf":1.0 }

# =========================================================
# SUB — down/50% closed -> open + look up + head up -> POP
#       (red, max eyes, open max-smile). Holds on final.
# =========================================================
const KEYS_SUB := [
	{ "t":0.00, "eo":0.50, "br":0.0, "rd":0.0, "lx":0.0, "ly":-0.60, "hy":-12.0, "hz":0.0, "mo":0.00, "mf":0.0 }, # down, 50% closed
	{ "t":0.85, "eo":1.00, "br":0.2, "rd":0.0, "lx":0.0, "ly": 0.50, "hy": 12.0, "hz":0.0, "mo":0.00, "mf":0.0 }, # open, look up, head up
	{ "t":1.45, "eo":1.40, "br":1.0, "rd":1.0, "lx":0.0, "ly": 0.45, "hy": 12.0, "hz":0.0, "mo":0.95, "mf":1.0 }, # POP — final, holds here
]

# =========================================================
# FOLLOW — down/50% closed -> look up, closed-mouth smile,
#          red eyes, slightly bigger (not maxed), side tilt.
#          Head stays neutral on AngleY so tilt never mixes.
#          Holds on final.
# =========================================================
const KEYS_FOLLOW := [
	{ "t":0.00, "eo":0.50, "br":0.00, "rd":0.0, "lx":0.0, "ly":-0.60, "hy":0.0, "hz":0.0, "mo":0.0, "mf":0.00 }, # down, 50% closed
	{ "t":0.90, "eo":1.10, "br":0.25, "rd":0.6, "lx":0.0, "ly": 0.45, "hy":0.0, "hz":4.0, "mo":0.0, "mf":0.50 }, # rising, smiling, reddening, slight tilt
	{ "t":1.60, "eo":1.10, "br":0.40, "rd":1.0, "lx":0.0, "ly": 0.40, "hy":0.0, "hz":9.0, "mo":0.0, "mf":0.90 }, # final — closed smile, red, slightly bigger, tilted, holds
]

# =========================================================
# RAID — energetic nodding. Head bobs up/down ~4-5x.
#        Eyes counter the head (head down -> eyes up, head up
#        -> eyes down) to keep the stare locked on the viewer.
#        Smile, mouth somewhat closed, NO red (blue throughout).
#        Ends in the LOW position and holds (= start pose).
#        AngleZ stays 0 so AngleY never mixes with a tilt.
# =========================================================
const KEYS_RAID := [
	{ "t":0.00, "eo":1.00, "br":0.0, "rd":0.0, "lx":0.0, "ly": 0.00, "hy":  0.0, "hz":0.0, "mo":0.00, "mf":0.15 }, # casual (start)
	{ "t":0.40, "eo":1.40, "br":0.9, "rd":0.0, "lx":0.0, "ly": 0.85, "hy": 14.0, "hz":0.0, "mo":0.80, "mf":0.30 }, # FLASH — snap up, maxed wide, mouth open, look high
	{ "t":1.55, "eo":1.35, "br":0.7, "rd":0.0, "lx":0.0, "ly": 0.45, "hy":  8.0, "hz":0.0, "mo":0.65, "mf":0.30 }, # descending, still wide
	{ "t":2.75, "eo":1.20, "br":0.4, "rd":0.0, "lx":0.0, "ly":-0.20, "hy": -2.0, "hz":0.0, "mo":0.45, "mf":0.25 }, # lower, softening
	{ "t":3.95, "eo":1.05, "br":0.2, "rd":0.0, "lx":0.0, "ly":-0.70, "hy": -9.0, "hz":0.0, "mo":0.20, "mf":0.20 }, # settling toward bottom
	{ "t":4.70, "eo":1.05, "br":0.1, "rd":0.0, "lx":0.0, "ly":-0.80, "hy":-11.0, "hz":0.0, "mo":0.10, "mf":0.20 }, # lowest — final, holds here
]

# =========================================================
# DONATION — heartbeat. Eyes locked on viewer, no head move,
#            mouth held mid-open. "tum-tum .. tum-tum" double
#            beat: eyes pump bigger and redden to full red at
#            the peak, back to small + blue at rest. ~3 reps.
#            Ends on the calm blue resting stare (= start pose).
# =========================================================
const KEYS_DONATION := [
	{ "t":0.00, "eo":1.00, "br":0.1, "rd":0.0, "lx":0.0, "ly":0.0, "hy":0.0, "hz":0.0, "mo":0.45, "mf":0.2 }, # calm blue (start)
	# --- iteration 1: tum-tum ---
	{ "t":0.25, "eo":1.40, "br":0.1, "rd":1.0, "lx":0.0, "ly":0.0, "hy":0.0, "hz":0.0, "mo":0.45, "mf":0.2 }, # TUM
	{ "t":0.45, "eo":1.05, "br":0.1, "rd":0.1, "lx":0.0, "ly":0.0, "hy":0.0, "hz":0.0, "mo":0.45, "mf":0.2 }, # tum-dip
	{ "t":0.65, "eo":1.40, "br":0.1, "rd":1.0, "lx":0.0, "ly":0.0, "hy":0.0, "hz":0.0, "mo":0.45, "mf":0.2 }, # TUM
	{ "t":1.05, "eo":1.00, "br":0.1, "rd":0.0, "lx":0.0, "ly":0.0, "hy":0.0, "hz":0.0, "mo":0.45, "mf":0.2 }, # rest (pause)
	# --- iteration 2: tum-tum ---
	{ "t":1.30, "eo":1.40, "br":0.1, "rd":1.0, "lx":0.0, "ly":0.0, "hy":0.0, "hz":0.0, "mo":0.45, "mf":0.2 }, # TUM
	{ "t":1.50, "eo":1.05, "br":0.1, "rd":0.1, "lx":0.0, "ly":0.0, "hy":0.0, "hz":0.0, "mo":0.45, "mf":0.2 }, # tum-dip
	{ "t":1.70, "eo":1.40, "br":0.1, "rd":1.0, "lx":0.0, "ly":0.0, "hy":0.0, "hz":0.0, "mo":0.45, "mf":0.2 }, # TUM
	{ "t":2.10, "eo":1.00, "br":0.1, "rd":0.0, "lx":0.0, "ly":0.0, "hy":0.0, "hz":0.0, "mo":0.45, "mf":0.2 }, # rest (pause)
	# --- iteration 3: tum-tum ---
	{ "t":2.35, "eo":1.40, "br":0.1, "rd":1.0, "lx":0.0, "ly":0.0, "hy":0.0, "hz":0.0, "mo":0.45, "mf":0.2 }, # TUM
	{ "t":2.55, "eo":1.05, "br":0.1, "rd":0.1, "lx":0.0, "ly":0.0, "hy":0.0, "hz":0.0, "mo":0.45, "mf":0.2 }, # tum-dip
	{ "t":2.75, "eo":1.40, "br":0.1, "rd":1.0, "lx":0.0, "ly":0.0, "hy":0.0, "hz":0.0, "mo":0.45, "mf":0.2 }, # TUM
	{ "t":3.25, "eo":1.00, "br":0.1, "rd":0.0, "lx":0.0, "ly":0.0, "hy":0.0, "hz":0.0, "mo":0.45, "mf":0.2 }, # calm blue — final, holds here
]


func _ready():
	randomize()
	call_deferred("_wait_for_model")


func _wait_for_model():
	while model.get_parameters().is_empty():
		await get_tree().process_frame

	for p in model.get_parameters():
		match p.id:
			"ParamEyeLOpen":   eye_l_open     = p
			"ParamEyeROpen":   eye_r_open     = p
			"ParamEyeBallX":   eyeball_x      = p
			"ParamEyeBallY":   eyeball_y      = p
			"ParamAngleX":     angle_x        = p
			"ParamAngleY":     angle_y        = p
			"ParamAngleZ":     angle_z        = p
			"ParamBrowLY":     brow_l_y       = p
			"ParamBrowRY":     brow_r_y       = p
			"ParamBrowLForm":  brow_l_form    = p
			"ParamBrowRForm":  brow_r_form    = p
			"ParamMouthOpenY": mouth_open     = p
			"ParamMouthForm":  mouth_form     = p
			"ParamBreath":     breath_param   = p
			"EyeTransition":   eye_transition = p

	for part in model.get_part_opacities():
		if part.id == "Part8":
			part8 = part

	match animation:
		"follow":   keys = KEYS_FOLLOW
		"raid":     keys = KEYS_RAID
		"donation": keys = KEYS_DONATION
		_:          keys = KEYS_SUB

	model_ready = true
	_apply_pose(keys[0])        # first frame = the start pose, not neutral
	print("Recorder ready — animation:", animation)


func _process(delta):
	if not model_ready:
		return

	breathe(delta)

	if not playing and not finished:
		lead_t += delta
		_apply_pose(keys[0])
		if lead_t >= lead_in:
			playing   = true
			anim_time = 0.0
	elif playing:
		anim_time += delta
		_apply_pose(_sample(anim_time))
		if anim_time >= keys[keys.size() - 1]["t"]:
			if loop:
				anim_time = 0.0
			else:
				playing  = false
				finished = true
	else:
		_apply_pose(keys[keys.size() - 1])   # hold final pose

	model.advance(delta)


# =========================================================
# TIMELINE — Catmull-Rom (continuous velocity through keys)
# =========================================================

func _spline(p0: float, p1: float, p2: float, p3: float, t: float) -> float:
	var t2 = t * t
	var t3 = t2 * t
	return 0.5 * ((2.0 * p1) \
		+ (-p0 + p2) * t \
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 \
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


func _sample(time: float) -> Dictionary:
	var n = keys.size()
	if time <= keys[0]["t"]:
		return keys[0]
	if time >= keys[n - 1]["t"]:
		return keys[n - 1]

	var i = 0
	for j in range(n - 1):
		if time >= keys[j]["t"] and time <= keys[j + 1]["t"]:
			i = j
			break

	var p1 = keys[i]
	var p2 = keys[i + 1]
	var p0 = keys[i - 1] if i > 0 else p1
	var p3 = keys[i + 2] if i + 2 < n else p2

	var span = p2["t"] - p1["t"]
	var lt   = 0.0 if span <= 0.0 else (time - p1["t"]) / span

	var out = {}
	for c in CH:
		out[c] = clamp(_spline(p0[c], p1[c], p2[c], p3[c], lt), LO[c], HI[c])
	return out


func _apply_pose(p: Dictionary):
	_face(p["eo"], p["br"], p["rd"])
	_pset(eyeball_x, p["lx"])
	_pset(eyeball_y, p["ly"])
	_pset(angle_y, p["hy"])
	_pset(angle_z, p["hz"])
	_pset(angle_x, 0.0)
	_mouth(p["mo"], p["mf"])


# =========================================================
# POSE / UTIL
# =========================================================

func _face(eye_open: float, brow: float, red: float):
	_pset(eye_l_open, eye_open)
	_pset(eye_r_open, eye_open)
	_pset(part8, red)
	_pset(eye_transition, red * 30.0)
	_pset(brow_l_y, brow)
	_pset(brow_r_y, brow)
	_pset(brow_l_form, brow)
	_pset(brow_r_form, brow)


func _mouth(open_v: float, form_v: float):
	_pset(mouth_open, open_v)
	_pset(mouth_form, form_v)


func breathe(delta):
	if not breath_param:
		return
	breath_time += delta * breath_speed
	breath_param.value = (cos(breath_time) * -0.5) + 0.5


func _pset(p, v: float):
	if p:
		p.value = v
