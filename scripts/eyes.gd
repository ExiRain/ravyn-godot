extends GDCubismEffectCustom

# =========================================================
# EYES + BROWS + EYE COLOR
# Handles: blink, expressions, mood/tired ceiling,
#          eye color switching, eye transition param
# =========================================================

# eye params
var eye_l_open
var eye_r_open

var idle_node = null

# brow params
var brow_l_y
var brow_r_y
var brow_l_form
var brow_r_form

# eye color params
var part8
var eye_transition

# =========================================================
# MOOD / TIRED STATE
# =========================================================

var mood  := 0.0
var tired := 0.0

var eye_open_limit := 1.0

# =========================================================
# BLINK
# =========================================================

var blink_timer   := 0.0
var blink_next    := 0.0
var blink_elapsed := 0.0
var blinking      := false

const BLINK_CLOSE_TIME := 0.12
const BLINK_HOLD_TIME  := 0.04
const BLINK_OPEN_TIME  := 0.16

# =========================================================
# EXPRESSIONS
# =========================================================

enum Expressions { NEUTRAL, SURPRISED, ANGRY, SAD, SLEEPY, WINK_L, WINK_R }
var current_expression := Expressions.NEUTRAL

var target_brow_l_y := 0.0
var target_brow_r_y := 0.0
var target_brow_l_f := 0.0
var target_brow_r_f := 0.0

var cur_brow_l_y := 0.0
var cur_brow_r_y := 0.0
var cur_brow_l_f := 0.0
var cur_brow_r_f := 0.0

# =========================================================
# EYE COLOR
# =========================================================

var eye_color_current    := 0.0
var eye_color_target     := 0.0
var eye_color_timer      := 0.0
var next_eye_color_time  := 0.0
var eye_color_transition := 0.0
var eye_color_active     := false

const EYE_COLOR_DURATION := 10.0  # slow dreamy transition
const TO_RED_MIN  := 5.0
const TO_RED_MAX  := 10.0
const TO_BLUE_MIN := 5.0
const TO_BLUE_MAX := 10.0


func _ready():
	cubism_init.connect(_on_init)
	cubism_process.connect(_on_process)
	_schedule_blink()
	_schedule_eye_color()


func _on_init(model: GDCubismUserModel):
	for p in model.get_parameters():
		match p.id:
			"ParamEyeLOpen":  eye_l_open  = p
			"ParamEyeROpen":  eye_r_open  = p
			"ParamBrowLY":    brow_l_y    = p
			"ParamBrowRY":    brow_r_y    = p
			"ParamBrowLForm": brow_l_form = p
			"ParamBrowRForm": brow_r_form = p
			"EyeTransition":  eye_transition = p

	for part in model.get_part_opacities():
		if part.id == "Part8":
			part8 = part

	if part8:
		part8.value = 0.0

	print("Eyes ready  L:", eye_l_open != null, " R:", eye_r_open != null)
	print("Brows ready LY:", brow_l_y != null, " LF:", brow_l_form != null)
	print("Eye color ready part8:", part8 != null, " transition:", eye_transition != null)


func _on_process(model: GDCubismUserModel, delta: float):
	_update_ceiling()
	_update_targets()
	_update_blink(delta)
	_smooth_apply(delta)
	_update_eye_color(delta)


# =========================================================
# CEILING
# =========================================================

func _update_ceiling():
	if current_expression == Expressions.SURPRISED:
		eye_open_limit = 1.4
	else:
		eye_open_limit = lerp(1.0, 0.75, tired)


# =========================================================
# TARGETS
# =========================================================

func _update_targets():
	match current_expression:

		Expressions.NEUTRAL:
			target_brow_l_y = clamp(mood * 0.5, -1.0, 1.0)
			target_brow_r_y = clamp(mood * 0.5, -1.0, 1.0)
			target_brow_l_f = clamp(mood * 0.7, -1.0, 1.0)
			target_brow_r_f = clamp(mood * 0.7, -1.0, 1.0)

		Expressions.SURPRISED:
			target_brow_l_y = 1.0
			target_brow_r_y = 1.0
			target_brow_l_f = 1.0
			target_brow_r_f = 1.0

		Expressions.ANGRY:
			target_brow_l_y = -0.6
			target_brow_r_y = -0.6
			target_brow_l_f = -1.0
			target_brow_r_f = -1.0

		Expressions.SAD:
			target_brow_l_y = -0.3
			target_brow_r_y = -0.3
			target_brow_l_f = -0.5
			target_brow_r_f = -0.5

		Expressions.SLEEPY:
			target_brow_l_y = -0.2
			target_brow_r_y = -0.2
			target_brow_l_f = -0.2
			target_brow_r_f = -0.2

		Expressions.WINK_L:
			target_brow_l_y = -0.3
			target_brow_r_y = 0.0
			target_brow_l_f = 0.0
			target_brow_r_f = 0.0

		Expressions.WINK_R:
			target_brow_l_y = 0.0
			target_brow_r_y = -0.3
			target_brow_l_f = 0.0
			target_brow_r_f = 0.0


# =========================================================
# BLINK
# =========================================================

func _update_blink(delta: float):
	if blinking:
		blink_elapsed += delta
		var total = BLINK_CLOSE_TIME + BLINK_HOLD_TIME + BLINK_OPEN_TIME

		if blink_elapsed < BLINK_CLOSE_TIME:
			var t = blink_elapsed / BLINK_CLOSE_TIME
			if eye_l_open: eye_l_open.value = lerp(eye_open_limit, 0.0, t)
			if eye_r_open: eye_r_open.value = lerp(eye_open_limit, 0.0, t)

		elif blink_elapsed < BLINK_CLOSE_TIME + BLINK_HOLD_TIME:
			if eye_l_open: eye_l_open.value = 0.0
			if eye_r_open: eye_r_open.value = 0.0

		else:
			var t = (blink_elapsed - BLINK_CLOSE_TIME - BLINK_HOLD_TIME) / BLINK_OPEN_TIME
			if eye_l_open: eye_l_open.value = lerp(0.0, eye_open_limit, t)
			if eye_r_open: eye_r_open.value = lerp(0.0, eye_open_limit, t)

		if blink_elapsed >= total:
			blinking = false
			if randf() < 0.2:
				# double blink - very short pause then blink again
				blink_next  = randf_range(0.1, 0.3)
				blink_timer = 0.0
			else:
				_schedule_blink()

	else:
		blink_timer += delta
		if blink_timer >= blink_next:
			blink_timer   = 0.0
			blink_elapsed = 0.0
			blinking      = true


func _schedule_blink():
	blink_next = randf_range(2.5, 6.0)


# =========================================================
# SMOOTH APPLY - brows only, eyes driven directly by blink
# =========================================================

func _smooth_apply(delta: float):
	var speed    := 8.0 * delta
	
	# skip brows if idle is doing asymmetric animation
	if not (idle_node and idle_node.brow_asym_active):
		cur_brow_l_y  = lerp(cur_brow_l_y, target_brow_l_y, speed)
		cur_brow_r_y  = lerp(cur_brow_r_y, target_brow_r_y, speed)
		cur_brow_l_f  = lerp(cur_brow_l_f, target_brow_l_f, speed)
		cur_brow_r_f  = lerp(cur_brow_r_f, target_brow_r_f, speed)
		if brow_l_y:    brow_l_y.value    = cur_brow_l_y
		if brow_r_y:    brow_r_y.value    = cur_brow_r_y
		if brow_l_form: brow_l_form.value = cur_brow_l_f
		if brow_r_form: brow_r_form.value = cur_brow_r_f


# =========================================================
# EYE COLOR SWITCH
# =========================================================

func _update_eye_color(delta: float):
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
		var t = clamp(eye_color_transition / EYE_COLOR_DURATION, 0.0, 1.0)
		t = t * t * (3.0 - 2.0 * t)
		eye_color_current = lerp(eye_color_current, eye_color_target, t)
		part8.value       = eye_color_current
		if eye_transition:
			eye_transition.value = eye_color_current * 30.0
		if t >= 1.0:
			eye_color_active = false
			_schedule_eye_color()


func _schedule_eye_color():
	if eye_color_target < 0.5:
		next_eye_color_time = randf_range(TO_RED_MIN, TO_RED_MAX)
	else:
		next_eye_color_time = randf_range(TO_BLUE_MIN, TO_BLUE_MAX)


# =========================================================
# PUBLIC API
# =========================================================

func set_mood(value: float):
	mood = clamp(value, -1.0, 1.0)
	if mood > 0.7:
		set_expression(Expressions.SURPRISED)
	elif mood < -0.7:
		set_expression(Expressions.ANGRY)
	elif mood < -0.4:
		set_expression(Expressions.SAD)
	else:
		set_expression(Expressions.NEUTRAL)


func set_tired(value: float):
	tired = clamp(value, 0.0, 1.0)
	if tired > 0.7:
		set_expression(Expressions.SLEEPY)


func set_expression(expr: Expressions):
	current_expression = expr
	_update_ceiling()


func do_wink(left: bool = true):
	set_expression(Expressions.WINK_L if left else Expressions.WINK_R)
	await get_tree().create_timer(0.4).timeout
	set_expression(Expressions.NEUTRAL)
