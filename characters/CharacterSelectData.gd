extends Node

var p1_character: CharacterData = null
var p2_character: CharacterData = null

@onready var default_dav = load("res://characters/DAV.character.tres")
@onready var default_woo = load("res://characters/WOO.character.tres")
@onready var default_den = load("res://characters/DEN.character.tres")

func _ready() -> void:
	p1_character = default_dav
	p2_character = default_den
