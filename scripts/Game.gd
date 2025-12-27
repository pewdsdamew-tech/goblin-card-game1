extends Control

@onready var card_db: Node = $CardDatabase
@onready var hand_panel: Container = $BottomUI/UIStack/HandPanel
@onready var active_slots: HBoxContainer = $BottomUI/UIStack/ActiveSlots
@onready var stats_label: Label = $Stats/VBoxContainer/StatsLabel
@onready var turn_label: Label = $Stats/VBoxContainer/TurnLabel
@onready var energy_label: Label = $Stats/VBoxContainer/EnergyLabel
@onready var end_turn_button: Button = $Stats/VBoxContainer/Buttons/EndTurnButton
@onready var discard_button: Button = $Stats/VBoxContainer/Buttons/DiscardButton

var card_scene: PackedScene = preload("res://scenes/Card.tscn")
var selected_card: Node = null

var turn_number: int = 1
var max_energy: int = 1
var current_energy: int = 1


func _ready() -> void:
	randomize()
	_connect_slot_clicks()
	_connect_buttons()
	_reset_energy_for_turn()
	_populate_hand()
	_update_active_stats()
	_update_energy_ui()


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
		
	# If another card is already selected, treat this click as a swap target (if in a slot)
	if selected_card != null:
		var slot := _find_slot_for_card(card)
		if slot:
			_try_place_selected_into_slot(slot)
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


func _connect_buttons() -> void:
	if is_instance_valid(end_turn_button):
		end_turn_button.pressed.connect(_on_end_turn_pressed)
	if is_instance_valid(discard_button):
		discard_button.pressed.connect(_on_discard_pressed)

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

	var selected_parent := selected_card.get_parent()
	if selected_parent == null:
		return

	if content.get_child_count() > 0 and content.get_child(0) == selected_card:
		_reset_card_transform(selected_card)
		if selected_card.has_method("set_selected"):
			selected_card.set_selected(false)
		selected_card = null
		return
	
	var selected_index := selected_parent.get_children().find(selected_card)
	var occupying_card: Node = null
	var card_data: Dictionary = {}
	if "card_data" in selected_card:
		card_data = selected_card.card_data
	var cost := int(card_data.get("stars", 0))

	var selected_in_board := _is_in_active_slots(selected_card)
	if content.get_child_count() > 0:
		occupying_card = content.get_child(0)

# If placing from hand, check energy
	if not selected_in_board:
		if cost > current_energy:
			print("Not enough energy to play this card.")
			return

	# Move selected card into slot
	selected_parent.remove_child(selected_card)

	if occupying_card:
		if selected_in_board:
			# Swap between slots (free)
			content.remove_child(occupying_card)
			selected_parent.add_child(occupying_card)

		if selected_parent is Container:
				(selected_parent as Container).move_child(occupying_card, selected_index)

		_reset_card_transform(occupying_card)
	else:
			# Replace with new card from hand; discard old card
			if is_instance_valid(occupying_card):
				content.remove_child(occupying_card)
				occupying_card.queue_free()

	content.add_child(selected_card)
	
	# Deduct energy only when playing from hand
	if not selected_in_board:
		current_energy -= cost
	_update_energy_ui()

	# Reset transforms so it sits nicely
	_reset_card_transform(selected_card)

	# Clear selection state
	if selected_card.has_method("set_selected"):
		selected_card.set_selected(false)
	selected_card = null
	_update_active_stats()


func _reset_card_transform(card: Node) -> void:
	if card is Control:
		var ctrl := card as Control
		ctrl.scale = Vector2.ONE
		ctrl.position = Vector2.ZERO
		ctrl.z_index = 0

func _find_slot_for_card(card: Node) -> Control:
	var current := card.get_parent()
	while current:
		if current.get_parent() == active_slots:
			return current as Control
		current = current.get_parent()
	return null

func _is_in_active_slots(card: Node) -> bool:
	return _find_slot_for_card(card) != null

func _update_active_stats() -> void:
	var total_off := 0
	var total_def := 0
	var total_stars := 0

	for slot in active_slots.get_children():
		if not (slot is Control):
			continue
		var content: Node = slot.get_node_or_null("Content")
		if content and content.get_child_count() > 0:
			var card := content.get_child(0)
			if card is Node and ("card_data" in card):
				var data: Dictionary = card.card_data
				total_off += int(data.get("off", 0))
				total_def += int(data.get("def", 0))
				total_stars += int(data.get("stars", 0))

	stats_label.text = "OFF: %d   DEF: %d   STARS: %d" % [total_off, total_def, total_stars]

func _update_energy_ui() -> void:
	turn_label.text = "Turn %d" % turn_number
	energy_label.text = "Energy: %d / %d" % [current_energy, max_energy]


func _reset_energy_for_turn() -> void:
	max_energy = min(5, turn_number)
	current_energy = max_energy
	_update_energy_ui()


func _refill_hand_to_max() -> void:
	while hand_panel.get_child_count() < 5:
		var card_data: Dictionary
		if card_db.has_method("get_random_card_weighted"):
			card_data = card_db.get_random_card_weighted()
		else:
			card_data = card_db.get_random_card()

		if card_data.is_empty():
			return

		var card_instance = card_scene.instantiate()
		hand_panel.add_child(card_instance)

		if card_instance.has_method("set_card_data"):
			card_instance.set_card_data(card_data)

		if card_instance.has_signal("clicked"):
			card_instance.clicked.connect(_on_card_clicked)


func _on_end_turn_pressed() -> void:
	_unselect_current()
	turn_number += 1
	_reset_energy_for_turn()
	_refill_hand_to_max()
	_update_active_stats()


func _on_discard_pressed() -> void:
	if selected_card == null:
		return

	if not _is_in_active_slots(selected_card):
		return

	var parent := selected_card.get_parent()
	if parent:
		parent.remove_child(selected_card)

	selected_card.queue_free()
	selected_card = null
	_update_active_stats()
