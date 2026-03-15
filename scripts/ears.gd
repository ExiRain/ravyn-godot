extends GDCubismEffectCustom

# =========================================================
# EAR JIGGLE + PERK
# =========================================================

var ear_jig_l
var ear_jig_r

# random jiggle state
var l_timer    := 0.0
var l_next     := 0.0
var l_elapsed  := 0.0
var l_jiggling := false

var r_timer    := 0.0
var r_next     := 0.0
var r_elapsed  := 0.0
var r_jiggling := false

# perk state - both ears spike when talking starts
var perking      := false
var perk_elapsed := 0.0

const JIGGLE_DURATION := 0.4
const JIGGLE_AMOUNT   := 25.0
const MIN_PAUSE       := 15.0
const MAX_PAUSE       := 35.0
const PERK_DURATION   := 1.0
const PERK_VALUE      := -30.0


func _ready():
	cubism_init.connect(_on_init)
	cubism_process.connect(_on_process)
	l_next  = randf_range(MIN_PAUSE, MAX_PAUSE)
	r_next  = randf_range(MIN_PAUSE, MAX_PAUSE)
	l_timer = randf_range(0.0, MAX_PAUSE)
	r_timer = randf_range(0.0, MAX_PAUSE)


func _on_init(model: GDCubismUserModel):
	for p in model.get_parameters():
		match p.id:
			"EarJigL": ear_jig_l = p
			"EarJigR": ear_jig_r = p
	print("Ears L:", ear_jig_l != null, " R:", ear_jig_r != null)


# call this from main script on START
func perk_up():
	perking      = true
	perk_elapsed = 0.0
	l_jiggling   = false
	r_jiggling   = false


func _on_process(model: GDCubismUserModel, delta: float):

	# perk overrides random jiggle while active
	if perking:
		perk_elapsed += delta
		var t        = clamp(perk_elapsed / PERK_DURATION, 0.0, 1.0)
		var perk_val = sin(t * PI) * PERK_VALUE
		if ear_jig_l: ear_jig_l.value = perk_val
		if ear_jig_r: ear_jig_r.value = perk_val
		if perk_elapsed >= PERK_DURATION:
			perking        = false
			l_timer        = 0.0
			r_timer        = 0.0
			l_next         = randf_range(MIN_PAUSE, MAX_PAUSE)
			r_next         = randf_range(MIN_PAUSE, MAX_PAUSE)
		return

	# left ear random jiggle
	if ear_jig_l:
		if not l_jiggling:
			l_timer += delta
			if l_timer >= l_next:
				l_jiggling = true
				l_elapsed  = 0.0
				l_timer    = 0.0
		else:
			l_elapsed       += delta
			ear_jig_l.value  = sin((l_elapsed / JIGGLE_DURATION) * PI) * JIGGLE_AMOUNT
			if l_elapsed >= JIGGLE_DURATION:
				ear_jig_l.value = 0.0
				l_jiggling      = false
				l_next          = randf_range(MIN_PAUSE, MAX_PAUSE)

	# right ear random jiggle
	if ear_jig_r:
		if not r_jiggling:
			r_timer += delta
			if r_timer >= r_next:
				r_jiggling = true
				r_elapsed  = 0.0
				r_timer    = 0.0
		else:
			r_elapsed       += delta
			ear_jig_r.value  = sin((r_elapsed / JIGGLE_DURATION) * PI) * JIGGLE_AMOUNT
			if r_elapsed >= JIGGLE_DURATION:
				ear_jig_r.value = 0.0
				r_jiggling      = false
				r_next          = randf_range(MIN_PAUSE, MAX_PAUSE)
