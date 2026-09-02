extends Control

## Static developer showcase for the Cartel corporate theme.


func _ready() -> void:
	var metrics := $Layout/VBox/Tabs/System/SystemContent/MetricsRow
	metrics.get_node("MetricCredits/Value").text = "d12,450"
	metrics.get_node("MetricHull/Value").text = "18 / 18"
	metrics.get_node("MetricSpeed/Value").text = "142 u/s"
