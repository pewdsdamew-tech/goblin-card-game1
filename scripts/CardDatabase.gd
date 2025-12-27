extends Node

var cards: Array[Dictionary] = []

func _ready() -> void:
	print("Loading cards.json...")

	var json_text := FileAccess.get_file_as_string("res://data/cards.json")
	var parsed = JSON.parse_string(json_text)

	if typeof(parsed) == TYPE_DICTIONARY and parsed.has("cards"):
		cards.clear()
		for c in parsed["cards"]:
			if typeof(c) == TYPE_DICTIONARY:
				cards.append(c)

	print("Loaded %d cards" % cards.size())
	if cards.size() > 0:
		print("First card:", cards[0].get("name", ""))

func get_all_cards() -> Array[Dictionary]:
	return cards

func get_random_card() -> Dictionary:
	if cards.is_empty():
		return {}
	return cards.pick_random()
	
func get_random_card_weighted() -> Dictionary:
	if cards.is_empty():
		return {}

	# Adjust anytime you like:
	# 1★ very common, 5★ very rare
	var weights_by_stars := {
		1: 60,
		2: 25,
		3: 10,
		4: 4,
		5: 1
	}

	var total_weight := 0
	for c in cards:
		var s := int(c.get("stars", 1))
		total_weight += int(weights_by_stars.get(s, 1))

	var roll := randi() % total_weight
	for c in cards:
		var s := int(c.get("stars", 1))
		roll -= int(weights_by_stars.get(s, 1))
		if roll < 0:
			return c

	return cards[0]
