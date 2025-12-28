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
@onready var shop_deck_count_label: Label = $ShopOverlay/Panel/VBoxContainer/DeckPanel/DeckCountLabel
@onready var shop_deck_list: VBoxContainer = $ShopOverlay/Panel/VBoxContainer/DeckPanel/DeckScroll/DeckList
@onready var shop_sell_button: Button = $ShopOverlay/Panel/VBoxContainer/ShopButtons/SellButton
@onready var deck_button: Button = $Stats/VBoxContainer/Buttons/DeckButton
@onready var deck_overlay: PanelContainer = $DeckOverlay
@onready var deck_count_label: Label = $DeckOverlay/DeckVBox/DeckCountLabel
@onready var deck_list: VBoxContainer = $DeckOverlay/DeckVBox/DeckScroll/DeckList

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
var discard_gold_claimed: bool = false
var shop_open: bool = false
var shop_minimized: bool = false
var shop_locked: bool = false
var shop_pending: bool = false
var player_hp: int = 100
var enemy_hp: int = 100
var current_fight_index: int = 1
var max_fights: int = 5
var player_deck: Array[Dictionary] = []
var player_draw_pile: Array[Dictionary] = []
var player_discard: Array[Dictionary] = []
var next_card_id: int = 1
var starting_deck_size: int = 15
var enemy_deck_size: int = 18
var enemy_card_pool: Array[Dictionary] = []
var enemy_deck: Array[Dictionary] = []
var enemy_hand: Array[Dictionary] = []
var enemy_max_energy: int = 1
var enemy_current_energy: int = 1
enum Phase { SHOP, PLAYER, ENEMY, COMBAT, GAME_OVER }
var phase: Phase = Phase.PLAYER
var deck_overlay_selected_id: int = -1


func _ready() -> void:
	randomize()
	_connect_slot_clicks()
	_connect_buttons()
	_hide_game_over()
	_start_run()


func _on_card_clicked(card) -> void:
	if _is_in_shop_offer(card):
		_try_buy_card(card)
		return

	if phase != Phase.PLAYER and phase != Phase.SHOP:
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
	if is_instance_valid(shop_sell_button):
		shop_sell_button.pressed.connect(_on_sell_from_shop_pressed)
	if is_instance_valid(deck_button):
		deck_button.pressed.connect(_on_deck_toggle_pressed)

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


func _is_enemy_card_node(card: Node) -> bool:
	var current := card.get_parent()
	while current:
		if current.get_parent() == enemy_slots:
			return true
		current = current.get_parent()
	return false

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
	turn_label.text = "Fight %d/%d  Turn %d" % [current_fight_index, max_fights, turn_number]
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
	_set_controls_enabled(phase == Phase.PLAYER)


func _on_discard_pressed() -> void:
	if selected_card == null:
		return
	if phase == Phase.SHOP and shop_pending:
		_sell_selected_card()
		return
	if phase != Phase.PLAYER:
		return

	if _is_in_shop_offer(selected_card):
		return

	if _is_in_active_slots(selected_card):
		var parent := selected_card.get_parent()
		if parent:
			parent.remove_child(selected_card)
		if "card_data" in selected_card:
			_send_card_data_to_discard(selected_card.card_data)
		selected_card.queue_free()
		selected_card = null
		_update_active_stats()
		return

	if selected_card.get_parent() == hand_panel:
		if "card_data" in selected_card:
			_send_card_data_to_discard(selected_card.card_data)
		selected_card.queue_free()
		selected_card = null
		if not discard_gold_claimed:
			discard_gold_claimed = true
			gold = gold + 1
		_update_gold_ui()
		_update_active_stats()


func _sell_selected_card() -> void:
	# Allow selling directly from deck overlay during shop
	if phase == Phase.SHOP and deck_overlay_selected_id != -1 and shop_pending:
		var card_id := deck_overlay_selected_id
		var value_overlay: int = max(0, _price_for_stars(_get_card_stars(card_id)) - 1)
		gold += value_overlay
		_sell_deck_card_by_id(card_id)
		deck_overlay_selected_id = -1
		_refresh_deck_overlay()
		_update_gold_ui()
		return

	if selected_card == null:
		return
	if selected_card.get_parent() != hand_panel:
		return
	if _is_in_shop_offer(selected_card):
		return
	var data: Dictionary = selected_card.card_data if "card_data" in selected_card else {}
	var stars: int = int(data.get("stars", 1))
	var value: int = max(0, _price_for_stars(stars) - 1)
	gold += value
	var card_id := int(data.get("id", -1))
	_remove_card_from_collections(card_id)
	selected_card.queue_free()
	selected_card = null
	_update_gold_ui()
	_update_shop_buttons()
	_refresh_deck_overlay()
	_update_active_stats()


func _send_card_data_to_discard(data: Dictionary) -> void:
	if data.is_empty():
		return
	var copy: Dictionary = data.duplicate(true)
	copy["hp"] = int(copy.get("hp_max", copy.get("def", 1)))
	player_discard.append(copy)


func _discard_board_and_hand() -> void:
	for slot in active_slots.get_children():
		if not (slot is Control):
			continue
		var content: Node = slot.get_node_or_null("Content")
		if content and content.get_child_count() > 0:
			var card := content.get_child(0)
			if card is Node and ("card_data" in card):
				_send_card_data_to_discard(card.card_data)
			card.queue_free()
	for child in hand_panel.get_children():
		if child is Node and ("card_data" in child):
			_send_card_data_to_discard(child.card_data)
		child.queue_free()
	selected_card = null
	_update_active_stats()


func _start_player_turn(is_new_fight: bool) -> void:
	_close_shop_overlay(false)
	shop_pending = false
	shop_open = false
	discard_gold_claimed = false
	if turn_number == 1 and current_fight_index == 1 and is_new_fight:
		gold = 3
	else:
		var income_bonus: int = int(gold / 5.0)
		gold = gold + 2 + income_bonus
	if not is_new_fight and hand_panel.get_child_count() < 5 and not player_draw_pile.is_empty():
		_draw_cards_to_hand(1)
	_reset_energy_for_turn()
	_update_active_stats()
	_update_enemy_stats()
	_update_hp_ui()
	_update_gold_ui()
	_update_shop_buttons()
	_update_shop_toggle_label()
	_refresh_deck_overlay()
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
	_start_run()


func _start_run() -> void:
	current_fight_index = 1
	turn_number = 1
	player_hp = 100
	enemy_hp = 100
	gold = 3
	shop_pending = false
	shop_open = false
	shop_locked = false
	shop_minimized = false
	_close_shop_overlay(true)
	_build_player_deck()
	_prepare_fight()
	_refresh_deck_overlay()


func _build_player_deck() -> void:
	player_deck.clear()
	player_draw_pile.clear()
	player_discard.clear()
	next_card_id = 1
	if card_db and card_db.has_method("get_random_card_weighted"):
		for i in range(starting_deck_size):
			var data := _normalize_card_for_deck(card_db.get_random_card_weighted())
			player_deck.append(data)
	elif card_db:
		for i in range(starting_deck_size):
			var data2 := _normalize_card_for_deck(card_db.get_random_card())
			player_deck.append(data2)
	_refresh_deck_overlay()


func _normalize_card_for_deck(data: Dictionary) -> Dictionary:
	var d := _with_combat_stats(data)
	if not d.has("id"):
		d["id"] = next_card_id
		next_card_id += 1
	else:
		next_card_id = max(next_card_id, int(d["id"]) + 1)
	d["hp"] = int(d.get("hp_max", d.get("def", 1)))
	return d


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


func _clear_enemy_board() -> void:
	for slot in enemy_slots.get_children():
		if not (slot is Control):
			continue
		var content: Node = slot.get_node_or_null("Content")
		if content:
			for child in content.get_children():
				child.queue_free()
	enemy_hand.clear()
	enemy_deck.clear()


func _prepare_fight() -> void:
	_clear_all_cards()
	_build_enemy_deck()
	enemy_hp = 100
	turn_number = 1
	selected_card = null
	shop_pending = false
	shop_open = false
	shop_minimized = false
	shop_locked = false
	_close_shop_overlay(true)
	_refresh_draw_pile_for_fight()
	_draw_starting_hand()
	_update_active_stats()
	_update_enemy_stats()
	_update_hp_ui()
	_refresh_deck_overlay()
	phase = Phase.PLAYER
	_start_player_turn(true)


func _refresh_draw_pile_for_fight() -> void:
	player_draw_pile.clear()
	player_discard.clear()
	for card_data in player_deck:
		if not (card_data is Dictionary):
			continue
		var copy: Dictionary = card_data.duplicate(true)
		copy["hp"] = int(copy.get("hp_max", copy.get("def", 1)))
		player_draw_pile.append(copy)
	player_draw_pile.shuffle()


func _draw_starting_hand() -> void:
	for child in hand_panel.get_children():
		child.queue_free()
	_draw_cards_to_hand(5)


func _draw_cards_to_hand(count: int) -> void:
	for i in range(count):
		if player_draw_pile.is_empty():
			return
		var card_data: Dictionary = player_draw_pile.pop_back()
		_spawn_card_to_hand(card_data)


func _spawn_card_to_hand(card_data: Dictionary) -> void:
	if card_data.is_empty():
		return
	var card_instance = card_scene.instantiate()
	hand_panel.add_child(card_instance) # add first so @onready vars exist
	if card_instance.has_method("set_card_data"):
		card_instance.set_card_data(card_data)
	if card_instance.has_signal("clicked"):
		card_instance.clicked.connect(_on_card_clicked)




func _remove_card_from_collections(card_id: int) -> void:
	if card_id < 0:
		return
	for arr in [player_deck, player_draw_pile, player_discard]:
		for i in range(arr.size()):
			if int(arr[i].get("id", -1)) == card_id:
				arr.remove_at(i)
				break


func _refresh_deck_overlay() -> void:
	if deck_count_label:
		deck_count_label.text = "Cards: %d" % player_deck.size()
	if shop_deck_count_label:
		shop_deck_count_label.text = "Cards: %d" % player_deck.size()
	if deck_list:
		for child in deck_list.get_children():
			child.queue_free()
	var shuffled: Array = player_deck.duplicate(true)
	shuffled.shuffle()
	for card_data in shuffled:
		if not (card_data is Dictionary):
			continue
		var card_instance = card_scene.instantiate()
		if card_instance.has_method("set_card_data"):
			card_instance.set_card_data(card_data)
		card_instance.mouse_filter = Control.MOUSE_FILTER_STOP
		card_instance.gui_input.connect(func(event):
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				_on_deck_card_sprite_selected(int(card_data.get("id", -1)))
		)
		if deck_list:
			deck_list.add_child(card_instance)
	if shop_deck_list:
		for child in shop_deck_list.get_children():
			child.queue_free()
		for card_data in shuffled:
			if not (card_data is Dictionary):
				continue
			var card_instance2 = card_scene.instantiate()
			if card_instance2.has_method("set_card_data"):
				card_instance2.set_card_data(card_data)
			card_instance2.mouse_filter = Control.MOUSE_FILTER_STOP
			card_instance2.gui_input.connect(func(event):
				if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
					_on_deck_card_sprite_selected(int(card_data.get("id", -1)))
			)
			shop_deck_list.add_child(card_instance2)


func _on_deck_toggle_pressed() -> void:
	if not deck_overlay:
		return
	deck_overlay.visible = not deck_overlay.visible
	_refresh_deck_overlay()


func _on_deck_entry_selected(card_id: int) -> void:
	deck_overlay_selected_id = card_id
	_refresh_deck_overlay()


func _on_deck_card_sprite_selected(card_id: int) -> void:
	if phase != Phase.SHOP or not shop_pending:
		return
	deck_overlay_selected_id = card_id
	_refresh_deck_overlay()


func _sell_deck_card_by_id(card_id: int) -> void:
	if card_id < 0:
		return
	_remove_card_from_collections(card_id)
	_update_gold_ui()
	_update_shop_buttons()
	_update_active_stats()


func _get_card_stars(card_id: int) -> int:
	for arr in [player_deck, player_draw_pile, player_discard]:
		for c in arr:
			if int(c.get("id", -1)) == card_id:
				return int(c.get("stars", 1))
	return 1


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


func _get_weighted_card_data() -> Dictionary:
	var card_data: Dictionary
	if card_db and card_db.has_method("get_random_card_weighted"):
		card_data = card_db.get_random_card_weighted()
	elif card_db:
		card_data = card_db.get_random_card()
	else:
		card_data = {}
	if card_data is Dictionary:
		return _with_combat_stats(card_data)
	return {}


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
	phase = Phase.SHOP
	shop_open = true
	shop_minimized = false
	_set_controls_enabled(false)
	if discard_button:
		discard_button.disabled = false
	# Respect lock: only clear when unlocked and empty
	if not shop_locked and shop_offer_container.get_child_count() == 0:
		_clear_shop_offer()
	shop_overlay.visible = true
	shop_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if shop_instruction_label:
		var next_fight: int = min(current_fight_index + 1, max_fights)
		shop_instruction_label.text = "Between fights (next: %d/%d) — buy adds to deck, sell from hand for value-1" % [next_fight, max_fights]
	if shop_offer_container.get_child_count() == 0:
		_generate_shop_offer()
	_update_gold_ui()
	_refresh_deck_overlay()
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
		var card_data: Dictionary = _get_weighted_card_data()
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
	_advance_to_next_fight()


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
	if card == null or not _is_in_shop_offer(card):
		return
	var price: int = _price_for_stars(int(card.card_data.get("stars", 1)) if "card_data" in card else 1)
	if price > gold:
		_show_insufficient_energy_feedback(card) # reuse shake/red feedback
		return

	gold -= price
	var parent := card.get_parent()
	if parent:
		parent.remove_child(card)
	var data: Dictionary = card.card_data if "card_data" in card else {}
	if not data.is_empty():
		player_deck.append(_normalize_card_for_deck(data))
	_update_gold_ui()
	_update_shop_buttons()
	_refresh_deck_overlay()
	card.queue_free()


func _on_shop_lock_pressed() -> void:
	if not shop_pending:
		return
	shop_locked = not shop_locked
	_update_shop_buttons()


func _on_shop_reroll_pressed() -> void:
	if not shop_pending:
		return
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
		var can_reroll: bool = gold >= 1
		shop_reroll_button.disabled = not can_reroll
		shop_reroll_button.text = "Reroll (-1 gold)"


func _on_sell_from_shop_pressed() -> void:
	if not shop_pending:
		return
	_sell_selected_card()


func _advance_to_next_fight() -> void:
	_close_shop_overlay(true)
	shop_pending = false
	shop_open = false
	shop_locked = false
	shop_minimized = false
	if current_fight_index >= max_fights:
		phase = Phase.GAME_OVER
		shop_pending = false
		_show_game_over(true)
		return
	current_fight_index += 1
	_prepare_fight()


func _end_fight_victory() -> void:
	_discard_board_and_hand()
	_clear_enemy_board()
	_update_active_stats()
	_update_enemy_stats()
	if current_fight_index >= max_fights:
		phase = Phase.GAME_OVER
		shop_pending = false
		_show_game_over(true)
		return
	shop_pending = true
	phase = Phase.SHOP
	_open_shop_overlay()


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
		end_turn_button.disabled = not enabled or phase != Phase.PLAYER
	if discard_button:
		if phase == Phase.SHOP:
			discard_button.disabled = false
			discard_button.text = "Sell Selected"
		else:
			discard_button.disabled = not enabled
			discard_button.text = "Discard Selected"
	if shop_toggle_button:
		shop_toggle_button.disabled = not shop_pending


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
		if not _is_enemy_card_node(card):
			_send_card_data_to_discard(card.card_data)
		card.queue_free()


func _resolve_combat() -> void:
	pass # handled in animated phase


func _run_enemy_phase() -> void:
	enemy_max_energy = min(turn_number, 5)
	enemy_current_energy = enemy_max_energy
	var draw_count: int = 1
	if turn_number == 1 and enemy_hand.is_empty():
		draw_count = 5
	_enemy_draw_to_hand(draw_count)
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
			var tw: Tween = create_tween()
			tw.tween_property(placed, "scale", Vector2(1.05, 1.05), 0.15)
			tw.tween_property(placed, "scale", Vector2.ONE, 0.12)
		_update_enemy_stats()
		await get_tree().create_timer(0.2).timeout


func _run_combat_phase() -> void:
	var lane_count: int = min(active_slots.get_child_count(), enemy_slots.get_child_count())
	for i in range(lane_count):
		await _resolve_combat_lane(i)
		await get_tree().create_timer(0.12).timeout
	_update_active_stats()
	_update_enemy_stats()
	_update_hp_ui()

	if player_hp <= 0:
		_discard_board_and_hand()
		_clear_enemy_board()
		phase = Phase.GAME_OVER
		_show_game_over(false)
		return
	if enemy_hp <= 0:
		_end_fight_victory()
		return

	turn_number += 1
	phase = Phase.PLAYER
	_start_player_turn(false)


func _resolve_combat_lane(index: int) -> void:
	var p_card := _get_lane_card(active_slots, index)
	var e_card := _get_lane_card(enemy_slots, index)

	var p_atk: int = p_card.card_data.get("atk", 0) if p_card and ("card_data" in p_card) else 0
	var e_atk: int = e_card.card_data.get("atk", 0) if e_card and ("card_data" in e_card) else 0

	var p_orig: Vector2 = p_card.position if p_card else Vector2.ZERO
	var e_orig: Vector2 = e_card.position if e_card else Vector2.ZERO

	var tween: Tween = null
	if p_card or e_card:
		tween = create_tween()
		if p_card:
			tween.tween_property(p_card, "position", p_orig + Vector2(0, -24), 0.2).set_ease(Tween.EASE_OUT)
		if e_card:
			tween.parallel().tween_property(e_card, "position", e_orig + Vector2(0, 24), 0.2).set_ease(Tween.EASE_OUT)
		await tween.finished

	# Apply damage
	if p_card and e_card:
		_apply_damage_to_card(p_card, e_atk)
		_apply_damage_to_card(e_card, p_atk)
	elif p_card and not e_card:
		enemy_hp = max(0, enemy_hp - int(p_atk))
	elif e_card and not p_card:
		player_hp = max(0, player_hp - int(e_atk))

	var tween_back: Tween = null
	if (p_card and is_instance_valid(p_card)) or (e_card and is_instance_valid(e_card)):
		tween_back = create_tween()
		if p_card and is_instance_valid(p_card):
			tween_back.tween_property(p_card, "position", p_orig, 0.18).set_ease(Tween.EASE_OUT)
		if e_card and is_instance_valid(e_card):
			tween_back.parallel().tween_property(e_card, "position", e_orig, 0.18).set_ease(Tween.EASE_OUT)
		await tween_back.finished

	await get_tree().create_timer(0.08).timeout


func _build_enemy_deck() -> void:
	enemy_card_pool.clear()
	enemy_deck.clear()
	enemy_hand.clear()
	if card_db == null:
		return
	while enemy_deck.size() < enemy_deck_size:
		var card_data := _get_weighted_card_data()
		if card_data.is_empty():
			break
		enemy_deck.append(card_data.duplicate(true))
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
