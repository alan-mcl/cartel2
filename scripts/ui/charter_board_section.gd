class_name CharterBoardSection
extends RefCounted

## One posted or accepted block on a charter board.
## `describe` returns the tile copy. `act` runs the button and reports whether the board should refresh.

var heading: String = ""
var empty_text: String = ""
var rows: Array = []
## (entry: Dictionary, ship_id: String) -> Dictionary
var describe: Callable = Callable()
## (entry: Dictionary, ship_id: String) -> bool
var act: Callable = Callable()
