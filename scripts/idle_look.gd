extends GDCubismEffectCustom

# =========================================================
# IDLE LOOK + ATTENTION
# Handles: wandering eye/head movement with hold phases
#          random transition speeds
#          mood/tired slowdown
#          attention tween when talking starts
# =========================================================

var eyeX_param
var eyeY_param
var headX_param
var headY_param
var headZ_param

# =========================================================
# LOOK PRESETS
# Rule: Z rotation is exclusive - never mixed with X or Y
# Constraints:
#   EyeX:  -0.8 to  0.8
#   EyeY:  -1.0 to  1.0
#   HeadX: -9   to  9
#   HeadY: -30  to  15
#   HeadZ: -16  to  16
# =========================================================

const LOOK_PRESETS = [
	# CENTER
	{ "eye": Vector2( 0.0,  0.0), "head": Vector3(  0,   0,  0) },

	# HORIZONTAL
	{ "eye": Vector2( 0.8,  0.0), "head": Vector3(  9,   0,  0) },
	{ "eye": Vector2(-0.8,  0.0), "head": Vector3( -9,   0,  0) },
	{ "eye": Vector2( 0.5,  0.0), "head": Vector3(  5,   0,  0) },
	{ "eye": Vector2(-0.5,  0.0), "head": Vector3( -5,   0,  0) },
	{ "eye": Vector2( 0.3,  0.0), "head": Vector3(  3,   0,  0) },
	{ "eye": Vector2(-0.3,  0.0), "head": Vector3( -3,   0,  0) },

	# VERTICAL
	{ "eye": Vector2( 0.0,  1.0), "head": Vector3(  0,  15,  0) },
	{ "eye": Vector2( 0.0, -1.0), "head": Vector3(  0, -30,  0) },
	{ "eye": Vector2( 0.0,  0.6), "head": Vector3(  0,   8,  0) },
	{ "eye": Vector2( 0.0, -0.6), "head": Vector3(  0, -15,  0) },
	{ "eye": Vector2( 0.0,  0.3), "head": Vector3(  0,   4,  0) },
	{ "eye": Vector2( 0.0, -0.3), "head": Vector3(  0,  -8,  0) },

	# DIAGONAL - upper
	{ "eye": Vector2( 0.8,  1.0), "head": Vector3(  9,  15,  0) },
	{ "eye": Vector2(-0.8,  1.0), "head": Vector3( -9,  15,  0) },
	{ "eye": Vector2( 0.5,  0.8), "head": Vector3(  5,  10,  0) },
	{ "eye": Vector2(-0.5,  0.8), "head": Vector3( -5,  10,  0) },
	{ "eye": Vector2( 0.3,  0.5), "head": Vector3(  3,   6,  0) },
	{ "eye": Vector2(-0.3,  0.5), "head": Vector3( -3,   6,  0) },

	# DIAGONAL - lower
	{ "eye": Vector2( 0.8, -0.6), "head": Vector3(  9, -15,  0) },
	{ "eye": Vector2(-0.8, -0.6), "head": Vector3( -9, -15,  0) },
	{ "eye": Vector2( 0.5, -0.5), "head": Vector3(  5, -10,  0) },
	{ "eye": Vector2(-0.5, -0.5), "head": Vector3( -5, -10,  0) },
	{ "eye": Vector2( 0.3, -0.3), "head": Vector3(  3,  -6,  0) },
	{ "eye": Vector2(-0.3, -0.3), "head": Vector3( -3,  -6,  0) },

	# Z ROTATION ONLY - no X or Y allowed
	{ "eye": Vector2( 0.0,  0.0), "head": Vector3(  0,   0, 16) },
	{ "eye": Vector2( 0.0,  0.0), "head": Vector3(  0,   0,-16) },
	{ "eye": Vector2( 0.0,  0.0), "head": Vector3(  0,   0,  8) },
	{ "eye": Vector2( 0.0,  0.0), "head": Vector3(  0,   0, -8) },
	{ "eye": Vector2( 0.0,  0.0), "head": Vector3(  0,   0,  4) },
	{ "eye": Vector2( 0.0,  0.0), "head": Vector3(  0,   0, -4) },
]

# user look target
const USER_LOOK_EYE  := Vector2(0.0,  1.0)
const USER_LOOK_HEAD := Vector3(0.0, 10.0, 0.0)

# =========================================================
# IDLE STATE
# =========================================================

var look_timer    := 0.0
var next_look_time := 0.0
var looking       := false
var look_elapsed  := 0.0
var look_duration := 1.5
var eye_start     := Vector2.ZERO
var eye_target    := Vector2.ZERO
var head_start    := Vector3.ZERO
var head_target   := Vector3.ZERO

# hold phase - stay at position before next move
var holding       := false
var hold_elapsed  := 0.0
var hold_duration := 0.0

# =========================================================
# ATTENTION STATE
# =========================================================

var looking_at_user     := false
var attention_triggered := false

# =========================================================
# MOOD / TIRED - received from main script
# these slow down movement speed
# =========================================================

var mood  := 0.0   # -1.0 to 1.0
var tired := 0.0   # 0.0 to 1.0


func _ready():
	cubism_init.connect(_on_init)
	cubism_process.connect(_on_process)
	next_look_time = randf_range(1.0, 3.0)


func _on_init(model: GDCubismUserModel):
	for p in model.get_parameters():
		match p.id:
			"ParamEyeBallX": eyeX_param  = p
			"ParamEyeBallY": eyeY_param  = p
			"ParamAngleX":   headX_param = p
			"ParamAngleY":   headY_param = p
			"ParamAngleZ":   headZ_param = p

	print("IdleLook ready  eyeX:", eyeX_param != null, " headX:", headX_param != null)


func _on_process(model: GDCubismUserModel, delta: float):
	if looking_at_user:
		_update_attention()
	else:
		_update_idle(delta)


# =========================================================
# ATTENTION
# =========================================================

func _update_attention():
	if attention_triggered:
		return
	attention_triggered = true

	var tween = get_tree().get_root().create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)

	if eyeX_param:  tween.tween_property(eyeX_param,  "value", USER_LOOK_EYE.x,  1.0)
	if eyeY_param:  tween.tween_property(eyeY_param,  "value", USER_LOOK_EYE.y,  1.0)
	if headX_param: tween.tween_property(headX_param, "value", USER_LOOK_HEAD.x, 1.0)
	if headY_param: tween.tween_property(headY_param, "value", USER_LOOK_HEAD.y, 1.0)
	if headZ_param: tween.tween_property(headZ_param, "value", USER_LOOK_HEAD.z, 1.0)


# =========================================================
# IDLE WANDERING
# =========================================================

func _update_idle(delta: float):

	# mood/tired slows everything down
	# tired 1.0 = half speed, mood -1.0 = 80% speed
	var speed_mult = lerp(1.0, 0.5, tired) * lerp(1.0, 0.8, abs(mood))

	if not looking and not holding:
		look_timer += delta
		if look_timer >= next_look_time:
			look_timer = 0.0
			_start_look()

	elif looking:
		look_elapsed += delta * speed_mult
		var t = clamp(look_elapsed / look_duration, 0.0, 1.0)
		t = t * t * (3.0 - 2.0 * t)

		if eyeX_param:  eyeX_param.value  = lerp(eye_start.x,  eye_target.x,  t)
		if eyeY_param:  eyeY_param.value  = lerp(eye_start.y,  eye_target.y,  t)
		if headX_param: headX_param.value = lerp(head_start.x, head_target.x, t)
		if headY_param: headY_param.value = lerp(head_start.y, head_target.y, t)
		if headZ_param: headZ_param.value = lerp(head_start.z, head_target.z, t)

		if t >= 1.0:
			looking      = false
			holding      = true
			hold_elapsed = 0.0
			# longer hold for more extreme positions
			var dist = eye_target.length() + head_target.length() * 0.04
			# tired holds longer - she lingers
			var tired_hold = lerp(1.0, 2.0, tired)
			hold_duration = (randf_range(1.4, 4.9) + dist * 0.3) * tired_hold

	elif holding:
		hold_elapsed += delta
		if hold_elapsed >= hold_duration:
			holding        = false
			look_timer     = 0.0
			# tired waits longer between moves too
			var tired_wait = lerp(1.0, 2.5, tired)
			next_look_time = randf_range(1.4, 5.7) * tired_wait


func _start_look():
	looking      = true
	look_elapsed = 0.0

	# tired = slower moves only, no quick glances
	var roll = randf()
	if tired > 0.5:
		# tired - only slow dreamy moves
		look_duration = randf_range(2.0, 4.0)
	elif roll < 0.2:
		# quick glance
		look_duration = randf_range(0.3, 0.6)
	elif roll < 0.7:
		# normal move
		look_duration = randf_range(0.8, 1.8)
	else:
		# slow dreamy
		look_duration = randf_range(2.0, 3.5)

	var preset  = LOOK_PRESETS[randi() % LOOK_PRESETS.size()]
	eye_start   = Vector2(eyeX_param.value  if eyeX_param  else 0.0,
						  eyeY_param.value  if eyeY_param  else 0.0)
	head_start  = Vector3(headX_param.value if headX_param else 0.0,
						  headY_param.value if headY_param else 0.0,
						  headZ_param.value if headZ_param else 0.0)
	eye_target  = preset["eye"]
	head_target = preset["head"]


# =========================================================
# PUBLIC API
# =========================================================

func start_talking():
	looking_at_user     = true
	attention_triggered = false
	looking             = false
	holding             = false


func stop_talking():
	looking_at_user = false
	look_timer      = 0.0
	next_look_time  = randf_range(2.0, 5.0)


func set_mood(value: float):
	mood = clamp(value, -1.0, 1.0)


func set_tired(value: float):
	tired = clamp(value, 0.0, 1.0)
