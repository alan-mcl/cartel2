class_name InteractableDef
extends Resource

enum Kind { INSPECT, SALVAGE }

@export var id: String = ""
@export var title: String = ""
@export var inspect_text: String = ""
@export var kind: Kind = Kind.INSPECT
@export var salvage_reward: int = 0
