extends Control

@onready var art: TextureRect = $Art

var card_data: Dictionary = {}

var base_scale := Vector2.ONE
var hover_scale := Vector2(1.06, 1.06)
var selected_scale := Vector2(1.10, 1.10)

var tween: Tween
var is_selected: bool = false

signal clicked(card: Control)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_update_pivot()

	mouse_entered.connect(_on_enter)
	mouse_exited.connect(_on_exit)
	resized.connect(_update_pivot)


func set_card_data(d: Dictionary) -> void:
	card_data = d

	var sprite_path: String = card_data.get("sprite", "")
	if sprite_path != "":
		var tex = load(sprite_path)
		if tex is Texture2D:
			art.texture = tex
		else:
			art.texture = null
	else:
		art.texture = null


func set_selected(v: bool) -> void:
	is_selected = v

	if is_selected:
		z_index = 60
		_animate_scale(selected_scale)
	else:
		z_index = 0
		_animate_scale(base_scale)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		emit_signal("clicked", self)


func _on_enter() -> void:
	if is_selected:
		return
	z_index = 50
	_animate_scale(hover_scale)


func _on_exit() -> void:
	if is_selected:
		return
	z_index = 0
	_animate_scale(base_scale)
	
	
func _update_pivot() -> void:
	pivot_offset = size * 0.5


func _animate_scale(target: Vector2) -> void:
	if tween and tween.is_running():
		tween.kill()
	tween = create_tween()
	tween.tween_property(self, "scale", target, 0.08)
