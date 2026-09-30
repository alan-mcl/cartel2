extends Control

## Static developer showcase for the Cartel corporate theme.


func _ready() -> void:
	var metrics := $Layout/VBox/Tabs/System/SystemContent/MetricsRow
	metrics.get_node("MetricCredits/Value").text = "d12,450"
	metrics.get_node("MetricHull/Value").text = "18 / 18"
	metrics.get_node("MetricSpeed/Value").text = "142 u/s"

	var ticker: MessageBar = $Layout/VBox/Tabs/Media/WireTicker
	if ticker != null:
		ticker.set_tag("WIRE")
		ticker.set_feed(
			[
				{"text": "Proxima Exchange: PX-FUEL +2.4%", "tone": "positive"},
				{"text": "Skyedge backlog clears after parts shipment"},
				{"text": "Transit advisory: Bela gate steady", "tone": "info"},
				{"text": "MR: Habitat council denies dock fee rumours", "tone": "warning"},
			],
			true
		)
