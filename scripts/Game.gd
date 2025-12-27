extends Control

@onready var card_db: Node = $CardDatabase
@onready var hand_panel: Container = $BottomUI/UIStack/HandPanel
@onready var active_slots: HBoxContainer = $BottomUI/UIStack/ActiveSlots

var card_scene: PackedScene = preload("res://scenes/Card.tscn")
var selected_card: Node = null


func _ready() -> void:
	randomize()
	_connect_slot_clicks()
	_populate_hand()


func _populate_hand() -> void:
	# Clear existing hand cards
	for child in hand_panel.get_children():
		child.queue_free()

	# Draw 5 cards
	for i in range(5):
		var card_data: Dictionary
		if card_db.has_method("get_random_card_weighted"):
			card_data = card_db.get_random_card_weighted()
		else:
			card_data = card_db.get_random_card()

		if card_data.is_empty():
			return

		var card_instance = card_scene.instantiate()
		hand_panel.add_child(card_instance) # IMPORTANT: add first so @onready vars exist

		# Set visuals/data
		if card_instance.has_method("set_card_data"):
			card_instance.set_card_data(card_data)

		# Listen for click-to-select
		if card_instance.has_signal("clicked"):
			card_instance.clicked.connect(_on_card_clicked)


func _on_card_clicked(card) -> void:
	# Toggle off if clicking the same card
	if selected_card == card:
		_unselect_current()
		print("Unselected")
		return

	# Unselect previous
	_unselect_current()

	# Select new
	selected_card = card
	if selected_card != null and selected_card.has_method("set_selected"):
		selected_card.set_selected(true)

	# Print selected card name if available
	if selected_card != null and ("card_data" in selected_card):
		print("Selected:", selected_card.card_data.get("name", "Unknown"))
	else:
		print("Selected card")


func _unselect_current() -> void:
	if selected_card != null and selected_card.has_method("set_selected"):
		selected_card.set_selected(false)
	selected_card = null


func _connect_slot_clicks() -> void:
	# Connect click handlers for each slot PanelContainer inside ActiveSlots
	for slot in active_slots.get_children():
		if slot is Control:
			# Use gui_input so clicking the slot works even if it has children
			slot.gui_input.connect(func(event): _on_slot_gui_input(slot, event))


func _on_slot_gui_input(slot: Control, event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_try_place_selected_into_slot(slot)


func _try_place_selected_into_slot(slot: Control) -> void:
	if selected_card == null:
		return

	# Each slot should have a CenterContainer child named "Content"
	if not slot.has_node("Content"):
		push_warning("Slot '%s' missing child node named 'Content'." % slot.name)
		return

	var content: Node = slot.get_node("Content")

	# If slot already occupied, do nothing (simple version)
	if content.get_child_count() > 0:
		return

	# Move selected card into slot
	var old_parent := selected_card.get_parent()
	if old_parent:
		old_parent.remove_child(selected_card)

	content.add_child(selected_card)

	# Reset transforms so it sits nicely
	if selected_card is Control:
		(selected_card as Control).scale = Vector2.ONE
		(selected_card as Control).position = Vector2.ZERO

	# Clear selection state
	if selected_card.has_method("set_selected"):
		selected_card.set_selected(false)
	selected_card = null
