extends Node

## The mystery box: the three-state machine (idle, spinning, offering), the roll,
## the teddy bear and the relocation.
##
## Split out of main.gd. The box's own art is a prop, so the sprite comes from
## Atmosphere; the box's *interactable* — the row in the interact table that
## carries its position — is handed over once by InteractionSystem rather than
## searched for in that table every time a relocation lands. Both files used to be
## the same file, which is the only reason the search existed.

## preload rather than the global class name: a freshly added script is not in
## the class registry until the editor rescans, and a headless run has no editor.
const ATMOSPHERE := preload("res://scripts/systems/atmosphere.gd")

const BOX_COST := 950
const BOX_SPIN := 2.9
const BOX_OFFER := 7.0

var player: Player
## atmosphere.gd. Untyped for the same reason main.gd's `hud` and `lighting` are:
## the script is attached at runtime, so a typed variable cannot see
## `prop_sprite()`.
var atmos

var _state := "idle"      # idle | spinning | offering
var _timer := 0.0
var _gun := ""
var _node: Sprite3D
var _teddy := false
## The box's row in the interact table. The same Dictionary the interact scan
## reads, not a copy — relocating the box moves it by writing `pos` here.
var _entry: Dictionary = {}


func bind(p: Player, a: Node3D) -> void:
	player = p
	atmos = a


## Called by InteractionSystem as it builds the table, which is also the moment
## the box first needs art.
func adopt(entry: Dictionary) -> void:
	_entry = entry
	Game.box_spot = 0
	_place(0)


func state() -> String:
	return _state


func gun() -> String:
	return _gun


## True while the box is holding a weapon out. The interact prompt reads this.
func offering() -> bool:
	return _state == "offering"


## Returns false when the player could not pay, so the caller can raise the deny
## cue — that cue is the HUD's and the interact layer owns the HUD handle.
func use() -> bool:
	if _state == "offering":
		player.give_gun(_gun, false)
		_state = "idle"
		_set_art("closed")
		if _teddy:
			_relocate()
		return true
	if _state != "idle":
		return true
	if not Game.spend(BOX_COST):
		return false
	Game.box_uses += 1
	_state = "spinning"
	_timer = BOX_SPIN
	_set_art("open")
	_gun = Weapons.roll_box(Rng.stream(Rng.BOX))
	# The teddy bear starts becoming likely after four pulls.
	_teddy = Game.box_uses > 3 and Rng.randf(Rng.BOX) < 0.16 * (Game.box_uses - 3)
	Sfx.play("box")
	return true


## Driven from main.gd rather than from this node's own `_process` — see the note
## on the drive order there. Runs immediately after the round loop and before the
## power-ups, exactly where main.gd's `_update_box` used to sit, because an
## expiring offer can relocate the box and that draws from the BOX stream.
func tick(dt: float) -> void:
	if _state == "idle":
		return
	_timer -= dt
	if _timer > 0.0:
		return
	if _state == "spinning":
		_state = "offering"
		_timer = BOX_OFFER
		_set_art("teddy" if _teddy else "open")
	else:
		_state = "idle"
		_set_art("closed")
		if _teddy:
			_relocate()


func _relocate() -> void:
	_teddy = false
	Game.box_uses = 0
	var next := Game.box_spot
	while next == Game.box_spot:
		next = Rng.stream(Rng.BOX).randi() % MapData.BOXSPOTS.size()
	Game.box_spot = next
	_entry.pos = MapData.BOXSPOTS[next]
	_place(next)
	Game.toast.emit("THE BOX HAS MOVED")


func _place(spot: int) -> void:
	if _node and is_instance_valid(_node):
		_node.queue_free()
	_node = atmos.prop_sprite("box_closed", MapData.BOXSPOTS[spot], "MysteryBox")


func _set_art(which: String) -> void:
	if _node and is_instance_valid(_node):
		_node.texture = load(ATMOSPHERE.PROP_DIR + "box_" + which + ".png")
