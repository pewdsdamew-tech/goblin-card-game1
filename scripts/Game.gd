extends Control

@onready var card_db: Node = $CardDatabase
@onready var hand_panel: Container = $BottomUI/UIStack/HandPanel
@onready var active_slots: HBoxContainer = $BottomUI/UIStack/ActiveSlots
@onready var stats_label: Label = $Stats/VBoxContainer/StatsLabel
@onready var turn_label: Label = $Stats/VBoxContainer/TurnLabel
@onready var energy_label: Label = $Stats/VBoxContainer/EnergyLabel
@onready var opponent_label: RichTextLabel = $Stats/VBoxContainer/OpponentLabel
@onready var gold_label: Label = $Stats/VBoxContainer/GoldLabel
@onready var end_turn_button: Button = $Stats/VBoxContainer/Buttons/EndTurnButton
@onready var discard_button: Button = $Stats/VBoxContainer/Buttons/DiscardButton
@onready var shop_toggle_button: Button = $Stats/VBoxContainer/Buttons/ShopToggleButton
@onready var game_over_layer: Control = $GameOverOverlay
@onready var game_over_label: Label = $GameOverOverlay/Panel/VBoxContainer/MessageLabel
@onready var restart_button: Button = $GameOverOverlay/Panel/VBoxContainer/RestartButton
@onready var shop_overlay: Control = $ShopOverlay
@onready var shop_offer_container: HBoxContainer = $ShopOverlay/Panel/VBoxContainer/Offers
@onready var shop_instruction_label: Label = $ShopOverlay/Panel/VBoxContainer/InstructionLabel
@onready var shop_skip_button: Button = $ShopOverlay/Panel/VBoxContainer/ShopButtons/SkipButton
@onready var shop_lock_button: Button = $ShopOverlay/Panel/VBoxContainer/ShopButtons/ShopLockButton
@onready var shop_reroll_button: Button = $ShopOverlay/Panel/VBoxContainer/ShopButtons/ShopRerollButton

var card_scene: PackedScene = preload("res://scenes/Card.tscn")
var selected_card: Node = null

var turn_number: int = 1
var max_energy: int = 1
var current_energy: int = 1
var current_total_off: int = 0
var current_total_def: int = 0
var current_archetype: Dictionary = {}
var gold: int = 3
var purchases_this_turn: int = 0
var discard_gold_claimed: bool = false
var shop_open: bool = false
var shop_minimized: bool = false
var shop_locked: bool = false
var shop_pending: bool = false


func _ready() -> void:
	randomize()
	_connect_slot_clicks()
	_connect_buttons()
	_hide_game_over()
	_start_turn()
	_populate_hand()
	_update_active_stats()
	_update_requirement_ui()
	_update_gold_ui()
	_close_shop_overlay(true)


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
	if _is_in_shop_offer(card):
		_try_buy_card(card)
		return

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
	if is_instance_valid(shop_toggle_button):
		shop_toggle_button.pressed.connect(_on_shop_toggle_pressed)
	if is_instance_valid(restart_button):
		restart_button.pressed.connect(_reset_game)
	if is_instance_valid(shop_skip_button):
		shop_skip_button.pressed.connect(_on_shop_skip_pressed)
	if is_instance_valid(shop_lock_button):
		shop_lock_button.pressed.connect(_on_shop_lock_pressed)
	if is_instance_valid(shop_reroll_button):
		shop_reroll_button.pressed.connect(_on_shop_reroll_pressed)

func _on_slot_gui_input(slot: Control, event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_try_place_selected_into_slot(slot)


func _try_place_selected_into_slot(slot: Control) -> void:
	if selected_card == null:
		return
	if _is_in_shop_offer(selected_card):
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

	# Prevent overwriting a filled slot when playing from hand
	if occupying_card and not selected_in_board:
		print("Cannot place: slot is already occupied. Move or discard the existing card first.")
		return

	# Star cap check when playing from hand
	if not selected_in_board:
		var projected_stars := _get_board_star_total()
		if occupying_card and "card_data" in occupying_card:
			projected_stars -= int(occupying_card.card_data.get("stars", 0))
		projected_stars += cost
		var star_cap := _get_star_cap()
		if projected_stars > star_cap:
			print("Cannot place: star cap exceeded (%d > %d). Discard or move a card first." % [projected_stars, star_cap])
			return

# If placing from hand, check energy
	if not selected_in_board:
		if cost > current_energy:
			_show_insufficient_energy_feedback(selected_card)
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
	current_total_off = 0
	current_total_def = 0
	var total_stars := 0

	for slot in active_slots.get_children():
		if not (slot is Control):
			continue
		var content: Node = slot.get_node_or_null("Content")
		if content and content.get_child_count() > 0:
			var card := content.get_child(0)
			if card is Node and ("card_data" in card):
				var data: Dictionary = card.card_data
				current_total_off += int(data.get("off", 0))
				current_total_def += int(data.get("def", 0))
				total_stars += int(data.get("stars", 0))

	stats_label.text = "OFF: %d   DEF: %d   STARS: %d" % [current_total_off, current_total_def, total_stars]
	_update_requirement_ui()

func _update_energy_ui() -> void:
	turn_label.text = "Turn %d" % turn_number
	energy_label.text = "Energy: %d / %d" % [current_energy, max_energy]
	_update_gold_ui()


func _update_gold_ui() -> void:
	if gold_label:
		gold_label.text = "Gold: %d" % gold


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
	_update_active_stats()
	var requirements := get_turn_requirements(turn_number)
	if _meets_requirements(requirements):
		turn_number += 1
		shop_pending = true
		_open_shop_overlay()
	else:
		_show_game_over(requirements)


func _on_discard_pressed() -> void:
	if selected_card == null:
		return

	if _is_in_shop_offer(selected_card):
		return

	if _is_in_active_slots(selected_card):
		var parent := selected_card.get_parent()
		if parent:
			parent.remove_child(selected_card)
		selected_card.queue_free()
		selected_card = null
		_update_active_stats()
		return

	if selected_card.get_parent() == hand_panel:
		selected_card.queue_free()
		selected_card = null
		if not discard_gold_claimed:
			discard_gold_claimed = true
			gold = gold + 1
		_update_gold_ui()
		_update_active_stats()


func _start_turn() -> void:
	_close_shop_overlay(false)
	shop_pending = false
	purchases_this_turn = 0
	discard_gold_claimed = false
	if turn_number == 1:
		gold = 3
	else:
		var income_bonus: int = int(gold / 5.0)
		gold = gold + 2 + income_bonus
	_reset_energy_for_turn()
	_roll_archetype()
	if not shop_locked:
		_generate_shop_offer(true)
	_update_active_stats()
	_update_requirement_ui()
	_update_gold_ui()
	_update_shop_buttons()


func get_turn_requirements(turn: int) -> Dictionary:
	var base_energy: int = min(5, turn)
	var base_min_off: int = base_energy * 4
	var base_min_def: int = base_energy * 3
	var base_score: int = base_energy * 8

	var archetype: Dictionary = current_archetype if not current_archetype.is_empty() else _balanced_archetype()
	var req_off_mult: float = float(archetype.get("req_off_mult", 1.0))
	var req_def_mult: float = float(archetype.get("req_def_mult", 1.0))
	var score_mult: float = float(archetype.get("score_mult", 1.0))
	var off_count_mult: float = float(archetype.get("off_count_mult", 1.0))
	var def_count_mult: float = float(archetype.get("def_count_mult", 1.0))

	var min_off: int = int(round(base_min_off * req_off_mult))
	var min_def: int = int(round(base_min_def * req_def_mult))
	var score_target: int = int(round(base_score * score_mult))

	return {
		"min_off": min_off,
		"min_def": min_def,
		"score_target": score_target,
		"archetype": archetype,
		"off_count_mult": off_count_mult,
		"def_count_mult": def_count_mult,
	}


func _meets_requirements(req: Dictionary) -> bool:
	var off_mult := float(req.get("off_count_mult", 1.0))
	var def_mult := float(req.get("def_count_mult", 1.0))
	var adjusted_off := current_total_off * off_mult
	var adjusted_def := current_total_def * def_mult

	var min_gate := adjusted_off >= float(req.get("min_off", 0)) or adjusted_def >= float(req.get("min_def", 0))
	var score_gate := (adjusted_off + adjusted_def) >= float(req.get("score_target", 0))
	return min_gate and score_gate


func _update_requirement_ui() -> void:
	var req := get_turn_requirements(turn_number)
	var off_mult := float(req.get("off_count_mult", 1.0))
	var def_mult := float(req.get("def_count_mult", 1.0))
	var adjusted_off := current_total_off * off_mult
	var adjusted_def := current_total_def * def_mult
	var min_gate := adjusted_off >= float(req.get("min_off", 0)) or adjusted_def >= float(req.get("min_def", 0))
	var score_gate := (adjusted_off + adjusted_def) >= float(req.get("score_target", 0))
	var meets := min_gate and score_gate

	var status_text := "[color=green]✓[/color]" if meets else "[color=red]✗[/color]"
	var min_status := "[color=green]✓[/color]" if min_gate else "[color=red]✗[/color]"
	var score_status := "[color=green]✓[/color]" if score_gate else "[color=red]✗[/color]"
	var archetype: Dictionary = req.get("archetype", _balanced_archetype())
	var archetype_name := String(archetype.get("name", "Balanced"))

	if opponent_label:
		opponent_label.bbcode_enabled = true
		opponent_label.bbcode_text = "Archetype: [b]%s[/b] %s\nMin: OFF %d or DEF %d %s\nScore: %.1f / %d %s\nTotals: OFF %.1f, DEF %.1f" % [
			archetype_name,
			status_text,
			req.get("min_off", 0),
			req.get("min_def", 0),
			min_status,
			adjusted_off + adjusted_def,
			req.get("score_target", 0),
			score_status,
			adjusted_off,
			adjusted_def,
		]


func _show_insufficient_energy_feedback(card: Node) -> void:
	if card is Control:
		var ctrl := card as Control
		var start_pos := ctrl.position
		var tween := create_tween()
		tween.tween_property(ctrl, "position", start_pos + Vector2(-6, 0), 0.05)
		tween.tween_property(ctrl, "position", start_pos + Vector2(6, 0), 0.1)
		tween.tween_property(ctrl, "position", start_pos + Vector2(-6, 0), 0.05)
		tween.tween_property(ctrl, "position", start_pos, 0.05)

	if energy_label:
		var original_color := energy_label.modulate
		var tween_color := create_tween()
		energy_label.modulate = Color(1, 0, 0)
		tween_color.tween_property(energy_label, "modulate", Color(1, 0, 0), 0.2)
		tween_color.tween_property(energy_label, "modulate", original_color, 0.1)


func _show_game_over(requirements: Dictionary) -> void:
	if game_over_label:
		game_over_label.text = "Game Over\nNeeded OFF %d / DEF %d\nYou had OFF %d / DEF %d" % [
			requirements.get("min_off", 0),
			requirements.get("min_def", 0),
			current_total_off,
			current_total_def,
		]
	if game_over_layer:
		game_over_layer.visible = true
		if game_over_layer.has_method("grab_focus"):
			game_over_layer.grab_focus()


func _hide_game_over() -> void:
	if game_over_layer:
		game_over_layer.visible = false


func _reset_game() -> void:
	_hide_game_over()
	selected_card = null
	_clear_all_cards()
	turn_number = 1
	_start_turn()
	_populate_hand()
	_update_active_stats()
	_close_shop_overlay()


func _clear_all_cards() -> void:
	for slot in active_slots.get_children():
		if not (slot is Control):
			continue
		var content: Node = slot.get_node_or_null("Content")
		if content:
			for child in content.get_children():
				child.queue_free()
	for child in hand_panel.get_children():
		child.queue_free()
	_clear_shop_offer()


func _roll_archetype() -> void:
	var pool := _get_archetypes()
	if pool.is_empty():
		current_archetype = _balanced_archetype()
		return
	current_archetype = pool[randi() % pool.size()]


func _balanced_archetype() -> Dictionary:
	return {
		"name": "Balanced",
		"req_off_mult": 1.0,
		"req_def_mult": 1.0,
		"score_mult": 1.0,
		"off_count_mult": 1.0,
		"def_count_mult": 1.0,
	}


func _get_archetypes() -> Array:
	return [
		_balanced_archetype(),
		{
			"name": "Fortress",
			"req_off_mult": 0.9,
			"req_def_mult": 1.25,
			"score_mult": 1.075,
			"off_count_mult": 1.0,
			"def_count_mult": 1.0,
		},
		{
			"name": "Blitz",
			"req_off_mult": 1.25,
			"req_def_mult": 0.9,
			"score_mult": 1.075,
			"off_count_mult": 1.0,
			"def_count_mult": 1.0,
		},
		{
			"name": "Anti-Off",
			"req_off_mult": 1.0,
			"req_def_mult": 1.0,
			"score_mult": 1.0,
			"off_count_mult": 0.9,
			"def_count_mult": 1.1,
		},
		{
			"name": "Anti-Def",
			"req_off_mult": 1.0,
			"req_def_mult": 1.0,
			"score_mult": 1.0,
			"off_count_mult": 1.1,
			"def_count_mult": 0.9,
		},
	]


func _clear_shop_offer() -> void:
	if not shop_offer_container:
		return
	for child in shop_offer_container.get_children():
		child.queue_free()
	shop_offer_container.queue_redraw()


func _is_in_shop_offer(card: Node) -> bool:
	if card == null:
		return false
	var parent := card.get_parent()
	while parent:
		if parent == shop_offer_container:
			return true
		parent = parent.get_parent()
	return false


func _price_for_stars(stars: int) -> int:
	match stars:
		1:
			return 1
		2:
			return 2
		3:
			return 4
		4:
			return 6
		5:
			return 9
		_:
			return max(1, stars)


func _open_shop_overlay() -> void:
	if not shop_pending:
		return
	shop_open = true
	shop_minimized = false
	# Respect lock: only clear when unlocked and empty
	if not shop_locked and shop_offer_container.get_child_count() == 0:
		_clear_shop_offer()
	shop_overlay.visible = true
	shop_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if shop_instruction_label:
		shop_instruction_label.text = "Select one card (cost shown below)"
	if shop_offer_container.get_child_count() == 0:
		_generate_shop_offer()
	_update_gold_ui()
	_update_shop_toggle_label()


func _close_shop_overlay(clear: bool = true) -> void:
	shop_open = false
	shop_minimized = false
	if clear and not shop_locked:
		_clear_shop_offer()
	if shop_overlay:
		shop_overlay.visible = false
	_update_shop_toggle_label()


func _generate_shop_offer(clear_first: bool = false) -> void:
	if not shop_offer_container:
		return
	if clear_first:
		_clear_shop_offer()
	if shop_offer_container.get_child_count() > 0 and shop_locked:
		return
	for i in range(3):
		var card_data: Dictionary
		if card_db.has_method("get_random_card_weighted"):
			card_data = card_db.get_random_card_weighted()
		else:
			card_data = card_db.get_random_card()
		if card_data.is_empty():
			continue

		var offer_box := VBoxContainer.new()
		offer_box.alignment = BoxContainer.ALIGNMENT_CENTER
		offer_box.add_theme_constant_override("separation", 6)

		var center := CenterContainer.new()
		var card_instance = card_scene.instantiate()
		center.add_child(card_instance)
		if card_instance.has_signal("clicked"):
			card_instance.clicked.connect(_on_card_clicked)

		var stars := int(card_data.get("stars", 1))
		var price_label := Label.new()
		price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		price_label.text = "Cost: %d (⭐%d)" % [_price_for_stars(stars), stars]

		offer_box.add_child(center)
		offer_box.add_child(price_label)
		shop_offer_container.add_child(offer_box)

		card_instance.call_deferred("set_card_data", card_data)


func _on_shop_skip_pressed() -> void:
	if not shop_pending:
		return
	_close_shop_overlay(true)
	_start_turn()


func _on_shop_toggle_pressed() -> void:
	if not shop_pending:
		return
	if not shop_open:
		_open_shop_overlay()
		return
	_toggle_shop_visibility()


func _toggle_shop_visibility() -> void:
	if not shop_overlay:
		return
	shop_minimized = not shop_minimized
	shop_overlay.visible = not shop_minimized
	shop_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_update_shop_toggle_label()


func _try_buy_card(card: Node) -> void:
	if not shop_pending:
		return
	if purchases_this_turn >= 1:
		return
	if card == null or not _is_in_shop_offer(card):
		return
	if hand_panel.get_child_count() >= 5:
		return
	var price: int = _price_for_stars(int(card.card_data.get("stars", 1)) if "card_data" in card else 1)
	if price > gold:
		_show_insufficient_energy_feedback(card) # reuse shake/red feedback
		return

	gold -= price
	purchases_this_turn += 1
	var parent := card.get_parent()
	if parent:
		parent.remove_child(card)
	hand_panel.add_child(card)
	_reset_card_transform(card)
	_update_gold_ui()
	_update_active_stats()
	_close_shop_overlay(true)
	shop_locked = false
	_start_turn()


func _on_shop_lock_pressed() -> void:
	shop_locked = not shop_locked
	_update_shop_buttons()


func _on_shop_reroll_pressed() -> void:
	if gold < 1:
		return
	shop_locked = false
	gold -= 1
	_generate_shop_offer(true)
	_update_gold_ui()
	_update_shop_buttons()


func _update_shop_toggle_label() -> void:
	if not shop_toggle_button:
		return
	shop_toggle_button.disabled = not shop_pending
	if shop_open:
		shop_toggle_button.text = "Hide Shop" if shop_overlay.visible else "Show Shop"
	else:
		shop_toggle_button.text = "Open Shop"


func _update_shop_buttons() -> void:
	if shop_lock_button:
		shop_lock_button.text = "Unlock Shop" if shop_locked else "Lock Shop"
	if shop_reroll_button:
		var can_reroll := gold >= 1
		shop_reroll_button.disabled = not can_reroll
		shop_reroll_button.text = "Reroll (-1 gold)"


func _get_board_star_total() -> int:
	var total := 0
	for slot in active_slots.get_children():
		if not (slot is Control):
			continue
		var content: Node = slot.get_node_or_null("Content")
		if content and content.get_child_count() > 0:
			var card := content.get_child(0)
			if card is Node and ("card_data" in card):
				total += int(card.card_data.get("stars", 0))
	return total


func _get_star_cap() -> int:
	if turn_number <= 2:
		return 4
	if turn_number <= 4:
		return 6
	return 8
