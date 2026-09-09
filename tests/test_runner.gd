class_name TestRunner
extends RefCounted

var failures: int = 0


func check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures += 1
		push_error("FAIL: %s" % label)
		print("FAIL: %s" % label)


func check_eq(actual: Variant, expected: Variant, label: String) -> void:
	check(actual == expected, "%s (expected %s, got %s)" % [label, str(expected), str(actual)])
