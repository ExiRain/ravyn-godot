extends GDCubismEffectCustom

# =========================================================
# IDLE
# USER_FOCUS_GROUP:  Z tilt only, snappy eye X, free Y
# WANDERING_GROUP:   full presets, smooth movement
# 4 turns minimum per group before evaluating switch
# =========================================================

# node/param references set from main script
var eyes_node        = null
var mouth_form_param = null

# eye/head params
var eyeX_param
var eyeY_param
var headX_param
var headY_param
var headZ_param

# brow params
var brow_l_y_param
var brow_r_y_param
var brow_l_form_param
var brow_r_form_param

# brow asym target floats
var brow_asym_l  := 0.0
var brow_asym_r  := 0.0
var brow_asym_lf := 0.0
var brow_asym_rf := 0.0

# =========================================================
# USER_FOCUS_GROUP
# Head: Z tilt only -6 to 6, no X or Y head movement
# Eye X: ±0.7 snappy - looking through viewer
# Eye Y: free variation, no limits
# =========================================================

const USER_FOCUS_GROUP_PRESETS = [
	# pure center stare with Y variation - more extremes
	{ "eye": Vector2( 0.00,  0.0),  "head": Vector3(0, 0,  0) },
	{ "eye": Vector2( 0.00,  0.3),  "head": Vector3(0, 0,  0) },
	{ "eye": Vector2( 0.00, -0.3),  "head": Vector3(0, 0,  0) },
	{ "eye": Vector2( 0.00,  0.6),  "head": Vector3(0, 0,  0) },
	{ "eye": Vector2( 0.00, -0.6),  "head": Vector3(0, 0,  0) },
	{ "eye": Vector2( 0.00,  1.0),  "head": Vector3(0, 0,  0) },
	{ "eye": Vector2( 0.00, -1.0),  "head": Vector3(0, 0,  0) },
	{ "eye": Vector2( 0.00,  0.8),  "head": Vector3(0, 0,  0) },
	{ "eye": Vector2( 0.00, -0.8),  "head": Vector3(0, 0,  0) },
	# tiny X drift with Y extremes
	{ "eye": Vector2( 0.09,  0.0),  "head": Vector3(0, 0,  0) },
	{ "eye": Vector2(-0.09,  0.0),  "head": Vector3(0, 0,  0) },
	{ "eye": Vector2( 0.09,  0.3),  "head": Vector3(0, 0,  0) },
	{ "eye": Vector2(-0.09,  0.3),  "head": Vector3(0, 0,  0) },
	{ "eye": Vector2( 0.09,  0.6),  "head": Vector3(0, 0,  0) },
	{ "eye": Vector2(-0.09,  0.6),  "head": Vector3(0, 0,  0) },
	{ "eye": Vector2( 0.09,  1.0),  "head": Vector3(0, 0,  0) },
	{ "eye": Vector2(-0.09,  1.0),  "head": Vector3(0, 0,  0) },
	{ "eye": Vector2( 0.09, -0.6),  "head": Vector3(0, 0,  0) },
	{ "eye": Vector2(-0.09, -0.6),  "head": Vector3(0, 0,  0) },
	{ "eye": Vector2( 0.09, -1.0),  "head": Vector3(0, 0,  0) },
	{ "eye": Vector2(-0.09, -1.0),  "head": Vector3(0, 0,  0) },
	# Z tilts with full Y range
	{ "eye": Vector2( 0.00,  0.0),  "head": Vector3(0, 0,  4) },
	{ "eye": Vector2( 0.00,  0.0),  "head": Vector3(0, 0, -4) },
	{ "eye": Vector2( 0.00,  0.0),  "head": Vector3(0, 0,  6) },
	{ "eye": Vector2( 0.00,  0.0),  "head": Vector3(0, 0, -6) },
	{ "eye": Vector2( 0.09,  0.6),  "head": Vector3(0, 0,  4) },
	{ "eye": Vector2(-0.09,  0.6),  "head": Vector3(0, 0, -4) },
	{ "eye": Vector2( 0.09,  1.0),  "head": Vector3(0, 0,  6) },
	{ "eye": Vector2(-0.09,  1.0),  "head": Vector3(0, 0, -6) },
	{ "eye": Vector2( 0.00,  1.0),  "head": Vector3(0, 0,  4) },
	{ "eye": Vector2( 0.00, -1.0),  "head": Vector3(0, 0, -4) },
	{ "eye": Vector2( 0.00,  0.8),  "head": Vector3(0, 0,  6) },
	{ "eye": Vector2( 0.00, -0.8),  "head": Vector3(0, 0, -6) },
]

# =========================================================
# WANDERING_GROUP - full range, smooth movement
# =========================================================

const WANDERING_GROUP_PRESETS = [
	# NO center X values - always offset ±0.35 minimum
	{ "eye": Vector2( 0.8,  0.0), "head": Vector3(  9,   0,  0) },
	{ "eye": Vector2(-0.8,  0.0), "head": Vector3( -9,   0,  0) },
	{ "eye": Vector2( 0.5,  0.0), "head": Vector3(  5,   0,  0) },
	{ "eye": Vector2(-0.5,  0.0), "head": Vector3( -5,   0,  0) },
	{ "eye": Vector2( 0.35, 0.0), "head": Vector3(  4,   0,  0) },
	{ "eye": Vector2(-0.35, 0.0), "head": Vector3( -4,   0,  0) },
	{ "eye": Vector2( 0.0,  1.0), "head": Vector3(  0,  15,  0) },
	{ "eye": Vector2( 0.0, -1.0), "head": Vector3(  0, -30,  0) },
	{ "eye": Vector2( 0.0, -0.6), "head": Vector3(  0, -15,  0) },
	{ "eye": Vector2( 0.8,  1.0), "head": Vector3(  9,  15,  0) },
	{ "eye": Vector2(-0.8,  1.0), "head": Vector3( -9,  15,  0) },
	{ "eye": Vector2( 0.8, -0.6), "head": Vector3(  9, -15,  0) },
	{ "eye": Vector2(-0.8, -0.6), "head": Vector3( -9, -15,  0) },
	{ "eye": Vector2( 0.5,  0.8), "head": Vector3(  5,  10,  0) },
	{ "eye": Vector2(-0.5,  0.8), "head": Vector3( -5,  10,  0) },
	{ "eye": Vector2( 0.35,-0.5), "head": Vector3(  4, -10,  0) },
	{ "eye": Vector2(-0.35,-0.5), "head": Vector3( -4, -10,  0) },
	{ "eye": Vector2( 0.0,  0.0), "head": Vector3(  0,   0, 16) },
	{ "eye": Vector2( 0.0,  0.0), "head": Vector3(  0,   0,-16) },
	{ "eye": Vector2( 0.0,  0.0), "head": Vector3(  0,   0,  8) },
	{ "eye": Vector2( 0.0,  0.0), "head": Vector3(  0,   0, -8) },
]

const USER_LOOK_EYE  := Vector2(0.0, 0.0)
const USER_LOOK_HEAD := Vector3(0.0, 0.0, 0.0)
const MICRO_NEUTRAL  := -1
const MIN_TURNS_PER_GROUP := 4

# =========================================================
# GROUP STATE
# =========================================================

var current_group  := "USER_FOCUS"
var turns_in_group := 0

# =========================================================
# IDLE LOOK STATE
# =========================================================

var look_timer     := 0.0
var next_look_time := 0.0
var looking        := false
var look_elapsed   := 0.0
var look_duration  := 1.5
var eye_start      := Vector2.ZERO
var eye_target     := Vector2.ZERO
var head_start     := Vector3.ZERO
var head_target    := Vector3.ZERO
var holding        := false
var hold_elapsed   := 0.0
var hold_duration  := 0.0

# =========================================================
# ATTENTION
# =========================================================

var looking_at_user     := false
var attention_triggered := false
var talking             := false

# =========================================================
# MOOD / TIRED
# =========================================================

var mood  := 0.0
var tired := 0.0

# =========================================================
# MICRO EXPRESSIONS
# =========================================================

var micro_timer   := 0.0
var micro_next    := 0.0
var micro_active  := false
var micro_elapsed := 0.0
var micro_timeout := 0.0

# =========================================================
# ASYMMETRIC BROWS
# brow_asym_active read by eyes.gd to skip overwriting
# =========================================================

var brow_asym_active  := false
var brow_asym_elapsed := 0.0
var brow_asym_timeout := 0.0
var brow_asym_timer   := 0.0
var brow_asym_next    := 0.0

# =========================================================
# MOUTH FLICKER
# mouth_flicker_active read by main script lipsync
# =========================================================

var mouth_flicker_active  := false
var mouth_flicker_elapsed := 0.0
var mouth_flicker_timeout := 0.0
var mouth_flicker_target  := 0.0
var mouth_flicker_timer   := 0.0
var mouth_flicker_next    := 0.0


func _ready():
	cubism_init.connect(_on_init)
	cubism_process.connect(_on_process)
	next_look_time = randf_range(2.0, 5.0)
	_schedule_micro()
	_schedule_brow_asym()
	_schedule_mouth_flicker()


func _on_init(model: GDCubismUserModel):
	for p in model.get_parameters():
		match p.id:
			"ParamEyeBallX":  eyeX_param        = p
			"ParamEyeBallY":  eyeY_param        = p
			"ParamAngleX":    headX_param       = p
			"ParamAngleY":    headY_param       = p
			"ParamAngleZ":    headZ_param       = p
			"ParamBrowLY":    brow_l_y_param    = p
			"ParamBrowRY":    brow_r_y_param    = p
			"ParamBrowLForm": brow_l_form_param = p
			"ParamBrowRForm": brow_r_form_param = p

	print("Idle ready")
	print("  brow_l_y:", brow_l_y_param != null, " brow_l_form:", brow_l_form_param != null)


func _on_process(model: GDCubismUserModel, delta: float):
	if looking_at_user:
		_update_attention()
	else:
		_update_idle(delta)
		if not talking:
			_update_micro(delta)
			_update_brow_asym(delta)
			_update_mouth_flicker(delta)


# =========================================================
# GROUP SWITCHING - evaluated after MIN_TURNS_PER_GROUP
# =========================================================

func _evaluate_group_switch():
	turns_in_group += 1
	# chance to switch grows each turn but never certain
	# at turn 1: ~10% chance, turn 4: ~40% chance, turn 8+: ~70% chance
	var switch_chance = clamp(turns_in_group * 0.1, 0.05, 0.7)
	if randf() > switch_chance:
		return  # stay in current group

	var chance_user = clamp(0.6 + mood * 0.1 - tired * 0.2, 0.2, 0.8)
	var new_group   = "USER_FOCUS" if randf() < chance_user else "WANDERING"
	if new_group != current_group:
		current_group  = new_group
		turns_in_group = 0
		print("Group switched to: ", current_group)
		ActionLog.add("look_group", {"group": current_group})


# =========================================================
# ATTENTION
# =========================================================
# The old version tweened once and stopped. This version
# actively holds eyes/head in user focus position every frame
# while talking, with gentle micro-drift for life.
# =========================================================
 
func _update_attention():
	if not attention_triggered:
		# first frame — fire the tween for smooth transition IN
		attention_triggered = true
		ActionLog.add("attention")
		var tween = get_tree().get_root().create_tween()
		tween.set_parallel(true)
		tween.set_ease(Tween.EASE_IN_OUT)
		tween.set_trans(Tween.TRANS_CUBIC)
		if eyeX_param:  tween.tween_property(eyeX_param,  "value", USER_LOOK_EYE.x,  0.6)
		if eyeY_param:  tween.tween_property(eyeY_param,  "value", USER_LOOK_EYE.y,  0.6)
		if headX_param: tween.tween_property(headX_param, "value", USER_LOOK_HEAD.x, 0.6)
		if headY_param: tween.tween_property(headY_param, "value", USER_LOOK_HEAD.y, 0.6)
		if headZ_param: tween.tween_property(headZ_param, "value", USER_LOOK_HEAD.z, 0.6)
	else:
		# every subsequent frame — gently hold position
		# this prevents any other system from pulling eyes away
		if eyeX_param:
			eyeX_param.value = lerp(eyeX_param.value, USER_LOOK_EYE.x, 0.1)
		if eyeY_param:
			eyeY_param.value = lerp(eyeY_param.value, USER_LOOK_EYE.y, 0.1)
		if headX_param:
			headX_param.value = lerp(headX_param.value, USER_LOOK_HEAD.x, 0.05)
		if headY_param:
			headY_param.value = lerp(headY_param.value, USER_LOOK_HEAD.y, 0.05)
		if headZ_param:
			headZ_param.value = lerp(headZ_param.value, USER_LOOK_HEAD.z, 0.05)


# =========================================================
# IDLE WANDERING
# =========================================================

func _update_idle(delta: float):
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
			var dist       = eye_target.length() + head_target.length() * 0.04
			var tired_hold = lerp(1.0, 2.0, tired)
			# user focus holds shorter - snappier attention feel
			var group_mult = 0.6 if current_group == "USER_FOCUS" else 1.3
			hold_duration  = (randf_range(1.5, 5.0) + dist * 0.3) * tired_hold * group_mult

	elif holding:
		hold_elapsed += delta
		if hold_elapsed >= hold_duration:
			holding        = false
			look_timer     = 0.0
			# evaluate group switch after each hold
			_evaluate_group_switch()
			var tired_wait = lerp(1.0, 2.5, tired)
			# user focus moves more frequently
			var group_wait = 0.5 if current_group == "USER_FOCUS" else 1.2
			next_look_time = randf_range(1.0, 4.0) * tired_wait * group_wait


func _start_look():
	looking      = true
	look_elapsed = 0.0

	var presets = USER_FOCUS_GROUP_PRESETS if current_group == "USER_FOCUS" else WANDERING_GROUP_PRESETS
	var preset_index = randi() % presets.size()
	var preset  = presets[preset_index]
	var roll    = randf()

	if tired > 0.5:
		look_duration = randf_range(2.0, 4.0)
	elif current_group == "USER_FOCUS":
		# user focus: snappy eye movement
		look_duration = randf_range(0.15, 0.4) if roll < 0.6 else randf_range(0.4, 0.8)
	else:
		# wandering: smooth mix
		if roll < 0.2:
			look_duration = randf_range(0.4, 0.8)
		elif roll < 0.7:
			look_duration = randf_range(0.9, 2.0)
		else:
			look_duration = randf_range(2.0, 3.5)

	eye_start  = Vector2(eyeX_param.value  if eyeX_param  else 0.0,
						 eyeY_param.value  if eyeY_param  else 0.0)
	head_start = Vector3(headX_param.value if headX_param else 0.0,
						 headY_param.value if headY_param else 0.0,
						 headZ_param.value if headZ_param else 0.0)
	eye_target  = preset["eye"]
	head_target = preset["head"]
	ActionLog.add("look", {
		"group": current_group, "preset": preset_index,
		"duration_s": snappedf(look_duration, 0.01)})


# =========================================================
# MICRO EXPRESSIONS
# =========================================================

func _update_micro(delta: float):
	if not eyes_node:
		return

	if micro_active:
		micro_elapsed += delta
		if micro_elapsed >= micro_timeout:
			micro_active = false
			eyes_node.set_expression(eyes_node.Expressions.NEUTRAL)
			_schedule_micro()
	else:
		micro_timer += delta
		if micro_timer >= micro_next:
			micro_timer = 0.0
			_trigger_micro()


func _trigger_micro():
	if not eyes_node:
		return

	var pool = _build_expression_pool()
	if pool.is_empty():
		_schedule_micro()
		return

	var total_weight := 0
	for item in pool:
		total_weight += item["weight"]

	var roll   = randi() % total_weight
	var picked = pool[0]
	var acc    := 0
	for item in pool:
		acc += item["weight"]
		if roll < acc:
			picked = item
			break

	if picked["expr"] == MICRO_NEUTRAL:
		_schedule_micro()
		return

	eyes_node.set_expression(picked["expr"])
	ActionLog.add("micro_expression", {
		"name": eyes_node.Expressions.keys()[picked["expr"]],
		"duration_s": snappedf(picked["dur"], 0.01)})
	micro_active  = true
	micro_elapsed = 0.0
	micro_timeout = picked["dur"]


func _build_expression_pool() -> Array:
	var pool = []

	# always available - wow eyes
	if tired < 0.6:
		pool.append({ "expr": eyes_node.Expressions.SURPRISED, "dur": randf_range(1.5, 2.5), "weight": 3 })

	# happy extras
	if mood > 0.5 and tired < 0.4:
		pool.append({ "expr": eyes_node.Expressions.SURPRISED, "dur": randf_range(2.5, 4.0), "weight": 2 })

	# always available at low weight for variety
	pool.append({ "expr": eyes_node.Expressions.SAD,   "dur": randf_range(1.5, 3.0), "weight": 1 })
	pool.append({ "expr": eyes_node.Expressions.ANGRY, "dur": randf_range(1.0, 2.0), "weight": 1 })

	# mood amplifies negative
	if mood < -0.3:
		pool.append({ "expr": eyes_node.Expressions.SAD,   "dur": randf_range(2.0, 5.0), "weight": 3 })
	if mood < -0.6:
		pool.append({ "expr": eyes_node.Expressions.ANGRY, "dur": randf_range(1.0, 2.5), "weight": 2 })

	# tired
	if tired > 0.4:
		pool.append({ "expr": eyes_node.Expressions.SLEEPY, "dur": randf_range(3.0, 7.0), "weight": int(tired * 4) })

	# neutral filler
	pool.append({ "expr": MICRO_NEUTRAL, "dur": 0.0, "weight": 2 })
	return pool


func _schedule_micro():
	micro_next = randf_range(8.0, 18.0) * lerp(1.0, 0.5, tired)


# =========================================================
# ASYMMETRIC BROWS
# =========================================================

func _update_brow_asym(delta: float):
	if not brow_l_y_param or not brow_r_y_param:
		return

	if brow_asym_active:
		brow_asym_elapsed += delta
		var fading = (brow_asym_elapsed / brow_asym_timeout) > 0.8

		if fading:
			brow_l_y_param.value = lerp(brow_l_y_param.value, 0.0, 0.04)
			brow_r_y_param.value = lerp(brow_r_y_param.value, 0.0, 0.04)
			if brow_l_form_param: brow_l_form_param.value = lerp(brow_l_form_param.value, 0.0, 0.04)
			if brow_r_form_param: brow_r_form_param.value = lerp(brow_r_form_param.value, 0.0, 0.04)
		else:
			brow_l_y_param.value = lerp(brow_l_y_param.value, brow_asym_l,  0.02)
			brow_r_y_param.value = lerp(brow_r_y_param.value, brow_asym_r,  0.02)
			if brow_l_form_param: brow_l_form_param.value = lerp(brow_l_form_param.value, brow_asym_lf, 0.02)
			if brow_r_form_param: brow_r_form_param.value = lerp(brow_r_form_param.value, brow_asym_rf, 0.02)

		if brow_asym_elapsed >= brow_asym_timeout:
			brow_asym_active = false
			_schedule_brow_asym()
	else:
		brow_asym_timer += delta
		if brow_asym_timer >= brow_asym_next:
			brow_asym_timer = 0.0
			_trigger_brow_asym()


func _trigger_brow_asym():
	if tired > 0.6:
		_schedule_brow_asym()
		return

	ActionLog.add("brow_asym")
	brow_asym_active  = true
	brow_asym_elapsed = 0.0
	brow_asym_timeout = randf_range(3.0, 7.0)

	var roll = randf()

	if mood >= 0.0:
		if roll < 0.5:
			brow_asym_l = 0.9;  brow_asym_r = 0.0
			brow_asym_lf = 0.8; brow_asym_rf = 0.0
		else:
			brow_asym_l = 0.0;  brow_asym_r = 0.9
			brow_asym_lf = 0.0; brow_asym_rf = 0.8
	else:
		if roll < 0.33:
			brow_asym_l = -0.9;  brow_asym_r = 0.0
			brow_asym_lf = -0.9; brow_asym_rf = 0.0
		elif roll < 0.66:
			brow_asym_l = 0.0;   brow_asym_r = -0.9
			brow_asym_lf = 0.0;  brow_asym_rf = -0.9
		else:
			brow_asym_l = 0.9;   brow_asym_r = -0.9
			brow_asym_lf = 0.8;  brow_asym_rf = -0.8


func _schedule_brow_asym():
	brow_asym_next  = randf_range(15.0, 35.0)
	brow_asym_timer = 0.0


# =========================================================
# MOUTH FORM FLICKER
# =========================================================

func _update_mouth_flicker(delta: float):
	if not mouth_form_param:
		return

	if mouth_flicker_active:
		mouth_flicker_elapsed += delta
		var t = mouth_flicker_elapsed / mouth_flicker_timeout
		if t > 0.8:
			mouth_form_param.value = lerp(mouth_form_param.value, 0.0, 0.04)
		else:
			mouth_form_param.value = lerp(mouth_form_param.value, mouth_flicker_target, 0.06)
		if mouth_flicker_elapsed >= mouth_flicker_timeout:
			mouth_flicker_active = false
			_schedule_mouth_flicker()
	else:
		mouth_flicker_timer += delta
		if mouth_flicker_timer >= mouth_flicker_next:
			mouth_flicker_timer = 0.0
			_trigger_mouth_flicker()


func _trigger_mouth_flicker():
	if tired > 0.7:
		_schedule_mouth_flicker()
		return

	ActionLog.add("mouth_flicker")
	mouth_flicker_active  = true
	mouth_flicker_elapsed = 0.0
	mouth_flicker_timeout = randf_range(3.0, 7.0)

	if mood > 0.2:
		mouth_flicker_target = randf_range(0.6, 1.0)
	elif mood < -0.3:
		mouth_flicker_target = randf_range(-1.0, -0.8)
	else:
		if randf() < 0.2:
			mouth_flicker_target = randf_range(-1.0, -0.7)  # rare frown
		else:
			mouth_flicker_target = randf_range(0.5, 1.0)    # smile


func _schedule_mouth_flicker():
	mouth_flicker_next = randf_range(8.0, 18.0)


# =========================================================
# PUBLIC API
# =========================================================

func start_talking():
	talking              = true
	looking_at_user      = true
	attention_triggered  = false
	looking              = false
	holding              = false
	mouth_flicker_active = false
	brow_asym_active     = false
	if micro_active and eyes_node:
		micro_active = false
		# Back to the face her mood calls for, not NEUTRAL: MOOD arrives
		# before START, so NEUTRAL here wiped the expression it had just set
		# (2026-11-12: a +0.90 cheer spoken with a neutral face).
		eyes_node.set_mood(eyes_node.mood)


func stop_talking():
	talking         = false
	looking_at_user = false
	look_timer      = 0.0
	next_look_time  = randf_range(2.0, 5.0)
	_schedule_micro()
	_schedule_mouth_flicker()
	_schedule_brow_asym()


func set_mood(value: float):
	mood = clamp(value, -1.0, 1.0)


func set_tired(value: float):
	tired = clamp(value, 0.0, 1.0)
