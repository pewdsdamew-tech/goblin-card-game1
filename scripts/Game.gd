extends Control

@onready var card_db: Node = $CardDatabase
@onready var hand_panel: Container = $BottomUI/UIStack/HandPanel
@onready var active_slots: HBoxContainer = $BottomUI/UIStack/ActiveSlots
@onready var enemy_slots: HBoxContainer = $BottomUI/UIStack/EnemySlots
@onready var stats_label: Label = $Stats/VBoxContainer/StatsLabel
@onready var enemy_stats_label: Label = $Stats/VBoxContainer/EnemyStatsLabel
@onready var turn_label: Label = $Stats/VBoxContainer/TurnLabel
@onready var energy_label: Label = $Stats/VBoxContainer/EnergyLabel
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
var enemy_total_off: int = 0
var enemy_total_def: int = 0
var enemy_total_stars: int = 0
var gold: int = 3
var purchases_this_turn: int = 0
var discard_gold_claimed: bool = false
var shop_open: bool = false
var shop_minimized: bool = false
var shop_locked: bool = false
var shop_pending: bool = false
var player_hp: int = 100
var enemy_hp: int = 100
var enemy_card_pool: Array[Dictionary] = []
var enemy_deck: Array[Dictionary] = []
var enemy_hand: Array[Dictionary] = []
var enemy_max_energy: int = 1
var enemy_current_energy: int = 1
enum Phase { SHOP, PLAYER, ENEMY, COMBAT, GAME_OVER }
var phase: Phase = Phase.PLAYER


func _ready() -> void:
	randomize()
	_connect_slot_clicks()
	_connect_buttons()
	_hide_game_over()
	_build_enemy_deck()
	phase = Phase.PLAYER
	_start_turn()
	_populate_hand()
	_update_active_stats()
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
			card_data = _with_combat_stats(card_db.get_random_card_weighted())
		else:
			card_data = _with_combat_stats(card_db.get_random_card())

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

	if phase != Phase.PLAYER or shop_open or shop_pending:
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
	if phase != Phase.PLAYER or shop_pending or shop_open:
		return
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

func _update_energy_ui() -> void:
	turn_label.text = "Turn %d" % turn_number
	energy_label.text = "Energy: %d / %d" % [current_energy, max_energy]
	_update_gold_ui()
	_update_hp_ui()


func _update_gold_ui() -> void:
	if gold_label:
		gold_label.text = "Gold: %d" % gold
	_update_hp_ui()


func _reset_energy_for_turn() -> void:
	max_energy = min(5, turn_number)
	current_energy = max_energy
	_update_energy_ui()
	_update_hp_ui()


func _update_enemy_stats() -> void:
	enemy_total_off = 0
	enemy_total_def = 0
	enemy_total_stars = 0

	for slot in enemy_slots.get_children():
		if not (slot is Control):
			continue
		var content: Node = slot.get_node_or_null("Content")
		if content and content.get_child_count() > 0:
			var card := content.get_child(0)
			if card is Node and ("card_data" in card):
				var data: Dictionary = card.card_data
				enemy_total_off += int(data.get("off", 0))
				enemy_total_def += int(data.get("def", 0))
				enemy_total_stars += int(data.get("stars", 0))

	if enemy_stats_label:
		enemy_stats_label.text = "Enemy OFF: %d   DEF: %d   STARS: %d" % [enemy_total_off, enemy_total_def, enemy_total_stars]


func _update_hp_ui() -> void:
	if has_node("Stats/VBoxContainer/PlayerHpLabel"):
		var lbl: Label = get_node("Stats/VBoxContainer/PlayerHpLabel")
		lbl.text = "HP: %d" % player_hp
	if has_node("Stats/VBoxContainer/EnemyHpLabel"):
		var lbl2: Label = get_node("Stats/VBoxContainer/EnemyHpLabel")
		lbl2.text = "Enemy HP: %d" % enemy_hp


func _refill_hand_to_max() -> void:
	while hand_panel.get_child_count() < 5:
		var card_data: Dictionary
		if card_db.has_method("get_random_card_weighted"):
			card_data = _with_combat_stats(card_db.get_random_card_weighted())
		else:
			card_data = _with_combat_stats(card_db.get_random_card())

		if card_data.is_empty():
			return

		var card_instance = card_scene.instantiate()
		hand_panel.add_child(card_instance)

		if card_instance.has_method("set_card_data"):
			card_instance.set_card_data(card_data)

		if card_instance.has_signal("clicked"):
			card_instance.clicked.connect(_on_card_clicked)


func _on_end_turn_pressed() -> void:
	if phase != Phase.PLAYER:
		return
	phase = Phase.ENEMY
	_set_controls_enabled(false)
	_unselect_current()
	_update_active_stats()
	await _run_enemy_phase()
	phase = Phase.COMBAT
	await _run_combat_phase()
	_set_controls_enabled(true)


func _on_discard_pressed() -> void:
	if phase != Phase.PLAYER:
		return
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
		player_hp = 100
		enemy_hp = 100
	if turn_number == 1:
		gold = 3
	else:
		var income_bonus: int = int(gold / 5.0)
		gold = gold + 2 + income_bonus
	_reset_energy_for_turn()
	_enemy_prepare_turn()
	if not shop_locked:
		_generate_shop_offer(true)
	_update_active_stats()
	_update_enemy_stats()
	_update_hp_ui()
	_update_gold_ui()
	_update_shop_buttons()
	phase = Phase.PLAYER
	_set_controls_enabled(true)


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


func _show_game_over(victory: bool) -> void:
	_set_controls_enabled(false)
	if game_over_label:
		if victory:
			game_over_label.text = "Victory!\nEnemy HP %d\nYour HP %d" % [
				enemy_hp,
				player_hp,
			]
		else:
			game_over_label.text = "Game Over\nEnemy HP %d\nYour HP %d" % [
				enemy_hp,
				player_hp,
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
	_build_enemy_deck()
	_start_turn()
	_populate_hand()
	_update_active_stats()
	_close_shop_overlay(true)


func _clear_all_cards() -> void:
	for slot in active_slots.get_children():
		if not (slot is Control):
			continue
		var content: Node = slot.get_node_or_null("Content")
		if content:
			for child in content.get_children():
				child.queue_free()
	for slot in enemy_slots.get_children():
		if not (slot is Control):
			continue
		var content2: Node = slot.get_node_or_null("Content")
		if content2:
			for child in content2.get_children():
				child.queue_free()
	enemy_hand.clear()
	enemy_deck.clear()
	for child in hand_panel.get_children():
		child.queue_free()
	_clear_shop_offer()


func _with_combat_stats(data: Dictionary) -> Dictionary:
	var d := data.duplicate(true)
	var atk := int(d.get("off", 0))
	var hp_max := int(d.get("def", 0))
	if hp_max <= 0:
		hp_max = 1
	d["atk"] = atk
	d["hp_max"] = hp_max
	if not d.has("hp"):
		d["hp"] = hp_max
	else:
		d["hp"] = int(d.get("hp", hp_max))
	return d


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
	_set_controls_enabled(false)
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
			card_data = _with_combat_stats(card_db.get_random_card_weighted())
		else:
			card_data = _with_combat_stats(card_db.get_random_card())
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
	phase = Phase.PLAYER
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
	phase = Phase.PLAYER
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


func _set_controls_enabled(enabled: bool) -> void:
	if end_turn_button:
		end_turn_button.disabled = not enabled
	if discard_button:
		discard_button.disabled = not enabled
	if shop_toggle_button:
		shop_toggle_button.disabled = not enabled or not shop_pending


func _get_lane_card(container: HBoxContainer, index: int) -> Node:
	if index >= container.get_child_count():
		return null
	var slot := container.get_child(index)
	if not (slot is Control):
		return null
	var content: Node = slot.get_node_or_null("Content")
	if content and content.get_child_count() > 0:
		return content.get_child(0)
	return null


func _apply_damage_to_card(card: Node, damage: int) -> void:
	if card == null or damage <= 0:
		return
	if not ("card_data" in card):
		return
	var current_hp := int(card.card_data.get("hp", card.card_data.get("hp_max", 0)))
	current_hp -= damage
	card.card_data["hp"] = current_hp
	if card.has_method("update_hp"):
		card.update_hp(current_hp)
	if current_hp <= 0:
		card.queue_free()


func _resolve_combat() -> void:
	pass # handled in animated phase


func _run_enemy_phase() -> void:
	enemy_max_energy = min(turn_number, 5)
	enemy_current_energy = enemy_max_energy
	_enemy_draw_to_hand(5)
	_update_enemy_stats()

	while enemy_current_energy > 0:
		var target_slot := _get_leftmost_empty_enemy_slot()
		if target_slot == null:
			break

		var playable_indices: Array = []
		for i in range(enemy_hand.size()):
			var card_data: Dictionary = enemy_hand[i]
			if int(card_data.get("stars", 1)) <= enemy_current_energy:
				playable_indices.append(i)
		if playable_indices.is_empty():
			break

		var totals_off: int = enemy_total_off
		var totals_def: int = enemy_total_def
		var need_off: int = max(0, (current_total_def + 1) - totals_off)
		var need_def: int = max(0, (current_total_off + 1) - totals_def)

		var best_score := -INF
		var best_index := -1
		for idx in playable_indices:
			var cdata: Dictionary = enemy_hand[idx]
			var off_val := float(cdata.get("off", 0))
			var def_val := float(cdata.get("def", 0))
			var stars := float(cdata.get("stars", 1))
			var off_weight := 1.25 if need_off > need_def else 1.0
			var def_weight := 1.25 if need_def >= need_off else 1.0
			var score := (off_val * off_weight) + (def_val * def_weight) - (stars * 0.2)
			if score > best_score:
				best_score = score
				best_index = idx

		if best_index == -1:
			break

		var chosen := enemy_hand[best_index]
		enemy_hand.remove_at(best_index)
		enemy_current_energy -= int(chosen.get("stars", 1))
		var placed := _place_enemy_card(target_slot, chosen)
		if placed and placed is Control:
			var tw := create_tween()
			tw.tween_property(placed, "scale", Vector2(1.05, 1.05), 0.1)
			tw.tween_property(placed, "scale", Vector2.ONE, 0.08)
		_update_enemy_stats()
		await get_tree().create_timer(0.12).timeout


func _run_combat_phase() -> void:
	var lane_count: int = min(active_slots.get_child_count(), enemy_slots.get_child_count())
	for i in range(lane_count):
		await _resolve_combat_lane(i)
	_update_active_stats()
	_update_enemy_stats()
	_update_hp_ui()

	if player_hp <= 0:
		phase = Phase.GAME_OVER
		_show_game_over(false)
		return
	if enemy_hp <= 0:
		phase = Phase.GAME_OVER
		_show_game_over(true)
		return

	turn_number += 1
	shop_pending = true
	phase = Phase.SHOP
	_open_shop_overlay()


func _resolve_combat_lane(index: int) -> void:
	var p_card := _get_lane_card(active_slots, index)
	var e_card := _get_lane_card(enemy_slots, index)

	var p_atk: int = p_card.card_data.get("atk", 0) if p_card and ("card_data" in p_card) else 0
	var e_atk: int = e_card.card_data.get("atk", 0) if e_card and ("card_data" in e_card) else 0

	var p_orig: Vector2 = p_card.position if p_card else Vector2.ZERO
	var e_orig: Vector2 = e_card.position if e_card else Vector2.ZERO

	var tween := create_tween()
	if p_card:
		tween.tween_property(p_card, "position", p_orig + Vector2(0, -20), 0.15).set_ease(Tween.EASE_OUT)
	if e_card:
		tween.parallel().tween_property(e_card, "position", e_orig + Vector2(0, 20), 0.15).set_ease(Tween.EASE_OUT)
	await tween.finished

	# Apply damage
	if p_card and e_card:
		_apply_damage_to_card(p_card, e_atk)
		_apply_damage_to_card(e_card, p_atk)
	elif p_card and not e_card:
		enemy_hp = max(0, enemy_hp - int(p_atk))
	elif e_card and not p_card:
		player_hp = max(0, player_hp - int(e_atk))

	var tween_back := create_tween()
	if p_card and is_instance_valid(p_card):
		tween_back.tween_property(p_card, "position", p_orig, 0.12).set_ease(Tween.EASE_OUT)
	if e_card and is_instance_valid(e_card):
		tween_back.parallel().tween_property(e_card, "position", e_orig, 0.12).set_ease(Tween.EASE_OUT)
	await tween_back.finished


func _build_enemy_deck() -> void:
	enemy_card_pool.clear()
	if card_db and card_db.has_method("get_all_cards"):
		var all_cards: Array = card_db.get_all_cards()
		for c in all_cards:
			if c is Dictionary:
				enemy_card_pool.append(_with_combat_stats(c))

	if enemy_card_pool.is_empty() and card_db:
		for i in range(15):
			var fallback: Dictionary = card_db.get_random_card_weighted() if card_db.has_method("get_random_card_weighted") else card_db.get_random_card()
			if fallback is Dictionary and not fallback.is_empty():
				enemy_card_pool.append(_with_combat_stats(fallback))

	enemy_deck.clear()
	enemy_hand.clear()
	if enemy_card_pool.is_empty():
		return
	for i in range(2):
		for c in enemy_card_pool:
			enemy_deck.append(_with_combat_stats(c))
	enemy_deck.shuffle()


func _ensure_enemy_deck() -> void:
	if enemy_deck.is_empty() and not enemy_card_pool.is_empty():
		for c in enemy_card_pool:
			enemy_deck.append(c.duplicate(true))
		enemy_deck.shuffle()


func _enemy_draw_to_hand(target_size: int) -> void:
	while enemy_hand.size() < target_size:
		_ensure_enemy_deck()
		if enemy_deck.is_empty():
			break
		enemy_hand.append(enemy_deck.pop_back())


func _enemy_prepare_turn() -> void:
	enemy_max_energy = min(turn_number, 5)
	enemy_current_energy = enemy_max_energy
	_enemy_draw_to_hand(5)
	_update_enemy_stats()


func _get_leftmost_empty_enemy_slot() -> Control:
	for slot in enemy_slots.get_children():
		if not (slot is Control):
			continue
		var content: Node = slot.get_node_or_null("Content")
		if content and content.get_child_count() == 0:
			return slot as Control
	return null


func _enemy_take_turn() -> void:
	enemy_max_energy = min(turn_number, 5)
	enemy_current_energy = enemy_max_energy
	_enemy_draw_to_hand(5)
	_update_enemy_stats()

	while enemy_current_energy > 0:
		var target_slot := _get_leftmost_empty_enemy_slot()
		if target_slot == null:
			break

		var playable_indices: Array = []
		for i in range(enemy_hand.size()):
			var card_data: Dictionary = enemy_hand[i]
			if int(card_data.get("stars", 1)) <= enemy_current_energy:
				playable_indices.append(i)
		if playable_indices.is_empty():
			break

		var totals_off: int = enemy_total_off
		var totals_def: int = enemy_total_def
		var need_off: int = max(0, (current_total_def + 1) - totals_off)
		var need_def: int = max(0, (current_total_off + 1) - totals_def)

		var best_score := -INF
		var best_index := -1
		for idx in playable_indices:
			var cdata: Dictionary = enemy_hand[idx]
			var off_val := float(cdata.get("off", 0))
			var def_val := float(cdata.get("def", 0))
			var stars := float(cdata.get("stars", 1))
			var off_weight := 1.25 if need_off > need_def else 1.0
			var def_weight := 1.25 if need_def >= need_off else 1.0
			var score := (off_val * off_weight) + (def_val * def_weight) - (stars * 0.2)
			if score > best_score:
				best_score = score
				best_index = idx

		if best_index == -1:
			break

		var chosen := enemy_hand[best_index]
		enemy_hand.remove_at(best_index)
		enemy_current_energy -= int(chosen.get("stars", 1))
		_place_enemy_card(target_slot, chosen)
		_update_enemy_stats()


func _place_enemy_card(slot: Control, card_data: Dictionary) -> Node:
	if not slot or not slot.has_node("Content"):
		return null
	var content: Node = slot.get_node("Content")
	if content.get_child_count() > 0:
		return null
	var card_instance = card_scene.instantiate()
	content.add_child(card_instance)
	if card_instance.has_method("set_card_data"):
		card_instance.set_card_data(card_data)
	_reset_card_transform(card_instance)
	return card_instance
