class_name TestPlotlines
extends RefCounted


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_catalog_loads_empty_plotlines(runner, catalog)
	_test_charter_completed_event(runner, catalog)
	_test_bar_gig_chits_accept(runner, catalog)
	_test_event_transition(runner, catalog)
	_test_days_in_state(runner, catalog)
	_test_gig_accept_and_flags(runner, catalog)
	_test_transition_chain(runner, catalog)
	_test_require_flags(runner, catalog)
	_test_terminal_state(runner, catalog)
	_test_contribute_messages_and_gigs(runner, catalog)
	_test_save_round_trip(runner, catalog)
	_test_missing_save_section(runner, catalog)
	_test_message_subsystem_hook(runner, catalog)


static func _subsystem() -> PlotlineSubsystem:
	return PlotlineSubsystem.new()


static func _session(catalog: Catalog) -> GameSession:
	var session := GameSession.new()
	session.start_new_game(catalog, "Plot Test", "tester", "")
	return session


static func _install_def(catalog: Catalog, def: Dictionary) -> String:
	var plotline_id := str(def.get("id", ""))
	catalog.plotlines_by_id[plotline_id] = def
	return plotline_id


static func _simulation() -> Simulation:
	return Simulation.new()


static func _missions(simulation: Simulation) -> MissionSubsystem:
	return simulation.get_subsystem("missions") as MissionSubsystem


static func _best_docked_ship(session: GameSession, catalog: Catalog, habitat_id: String) -> OwnedShip:
	var best: OwnedShip = null
	var best_cap := -1.0
	for ship in session.ships_at(habitat_id):
		var assembled := ShipAssembler.assemble_owned(catalog, ship)
		var cap := float(assembled.capacities.get("life_support_capacity", 0.0))
		if cap > best_cap:
			best_cap = cap
			best = ship
	return best


static func _inject_passenger_offer(
	missions: MissionSubsystem,
	session: GameSession,
	catalog: Catalog,
	origin_habitat_id: String,
	destination_habitat_id: String,
	offer_id: String
) -> Dictionary:
	var dest := catalog.get_habitat(destination_habitat_id)
	var cfg := PassengerCharters.config(catalog)
	var friction := PassengerCharters.friction_between(
		catalog,
		str(catalog.get_habitat(origin_habitat_id).get("sector_id", "")),
		str(dest.get("sector_id", ""))
	)
	var reward := PassengerCharters.compute_reward(cfg, 2, 1.0, friction)
	var offer := {
		"id": offer_id,
		"board": PassengerCharters.BOARD_TERMINAL,
		"origin_habitat_id": origin_habitat_id,
		"destination_habitat_id": destination_habitat_id,
		"destination_name": str(dest.get("name", destination_habitat_id)),
		"destination_sector_id": str(dest.get("sector_id", "")),
		"friction": friction,
		"role_id": "steerage",
		"role_title": "Steerage passengers",
		"affiliation": "civilian",
		"life_support": "spartan",
		"quantity": 2,
		"pay_multiplier": 1.0,
		"requires_player_affiliation": false,
		"corporation_id": "",
		"corporation_name": "",
		"description": "Test charter.",
		"reward": reward,
	}
	missions.passengers.offers[origin_habitat_id] = {
		PassengerCharters.BOARD_TERMINAL: [offer],
	}
	missions.mark_habitat_boards_materialised(origin_habitat_id)
	missions.generated_day = CommodityEconomy.gst_day(session.gst_seconds)
	return offer


static func _test_catalog_loads_empty_plotlines(runner: TestRunner, catalog: Catalog) -> void:
	var loaded := Catalog.load_default()
	runner.check(loaded != null, "plotlines: default catalog loads")
	runner.check(
		typeof(loaded.list_plotlines()) == TYPE_ARRAY,
		"plotlines: list_plotlines returns array when json empty"
	)


static func _test_charter_completed_event(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := _simulation()
	var missions := _missions(simulation)
	var session := _session(catalog)
	simulation.attach_events(session, catalog)
	var ship := _best_docked_ship(session, catalog, "proxima_habitat")
	if ship == null:
		return
	var picked := _inject_passenger_offer(
		missions,
		session,
		catalog,
		"proxima_habitat",
		"bela_orbital_habitat",
		"plotline_charter_complete"
	)
	runner.check(
		missions.accept_offer(session, catalog, str(picked.get("id", "")), ship.id),
		"plotlines: accept charter for completion event"
	)
	var charter_id := str(missions.list_accepted()[0].get("charter_id", ""))
	var reward := int(picked.get("reward", 0))
	var completed_events: Array = []
	session.events.subscribe(SimEvent.CHARTER_COMPLETED, func(evt: Dictionary) -> void:
		completed_events.append(evt)
	)
	runner.check(session.undock(catalog, ship.id, missions), "plotlines: undock for charter event")
	runner.check(session.enter_sector(catalog, "bela", false), "plotlines: travel for charter event")
	runner.check(session.dock(catalog, "bela_orbital_habitat"), "plotlines: dock for charter event")
	runner.check(missions.list_accepted().is_empty(), "plotlines: charter completes on dock")
	runner.check_eq(completed_events.size(), 1, "plotlines: charter_completed published once")
	if completed_events.is_empty():
		return
	var seen: Dictionary = completed_events[0]
	runner.check_eq(str(seen.get("type", "")), SimEvent.CHARTER_COMPLETED, "plotlines: charter_completed type")
	runner.check_eq(str(seen.get("charter_kind", "")), "passenger", "plotlines: charter_kind passenger")
	runner.check_eq(str(seen.get("charter_id", "")), charter_id, "plotlines: charter_id on event")
	runner.check_eq(int(seen.get("reward", -1)), reward, "plotlines: reward on event")


static func _test_bar_gig_chits_accept(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := _simulation()
	var session := _session(catalog)
	simulation.attach_events(session, catalog)
	var missions := _missions(simulation)
	_install_def(
		catalog,
		{
			"id": "bar_desk_arc",
			"initial": "offer",
			"states": {
				"offer": {
					"gigs": [
						{"id": "tip", "desk": "bar", "title": "Tip", "text": "Quiet word."},
					],
					"transitions": [
						{
							"to": "done",
							"when": {"kind": "gig_accepted", "gig_id": "tip"},
						},
					],
				},
				"done": {"terminal": true},
			},
		}
	)
	var gigs := missions.list_plot_gigs("proxima_habitat", "bar", session, catalog)
	runner.check_eq(gigs.size(), 1, "plotlines: bar desk lists gig")
	var chits: Array = PlotlineGigChits.chits(gigs, session, catalog)
	runner.check(chits.size() >= 1, "plotlines: bar chits built")
	var accept_chit: CharterChit = null
	for chit_variant in chits:
		if chit_variant is CharterChit and chit_variant.describe.is_valid():
			var spec: Dictionary = chit_variant.describe.call(chit_variant.entry, "")
			if str(spec.get("button_text", "")) == "Accept":
				accept_chit = chit_variant
				break
	runner.check(accept_chit != null, "plotlines: accept chit present")
	runner.check(
		bool(accept_chit.act.call(accept_chit.entry, "")),
		"plotlines: accept chit act succeeds"
	)
	runner.check_eq(
		str(session.bound_plotlines.get_instance("bar_desk_arc").get("state", "")),
		"done",
		"plotlines: bar accept advances arc"
	)
	catalog.plotlines_by_id.erase("bar_desk_arc")


static func _test_event_transition(runner: TestRunner, catalog: Catalog) -> void:
	var plotlines := _subsystem()
	var def := {
		"id": "event_arc",
		"initial": "idle",
		"states": {
			"idle": {
				"transitions": [
					{
						"to": "seen",
						"when": {"kind": "event", "type": SimEvent.DOCKED, "habitat_id": "proxima_habitat"},
					}
				],
			},
			"seen": {"terminal": true},
		},
	}
	_install_def(catalog, def)
	var session := _session(catalog)
	plotlines.on_event(session, catalog, SimEvent.docked("tycho_habitat"))
	runner.check_eq(
		str(plotlines.get_instance("event_arc").get("state", "")),
		"idle",
		"plotlines: wrong habitat does not advance"
	)
	plotlines.on_event(session, catalog, SimEvent.docked("proxima_habitat"))
	runner.check_eq(
		str(plotlines.get_instance("event_arc").get("state", "")),
		"seen",
		"plotlines: dock event advances state"
	)


static func _test_days_in_state(runner: TestRunner, catalog: Catalog) -> void:
	var plotlines := _subsystem()
	var def := {
		"id": "day_arc",
		"initial": "wait",
		"states": {
			"wait": {
				"transitions": [{"to": "ready", "when": {"kind": "days_in_state", "days": 3}}],
			},
			"ready": {"terminal": true},
		},
	}
	_install_def(catalog, def)
	var session := _session(catalog)
	plotlines.on_day(session, catalog, CommodityEconomy.gst_day(session.gst_seconds))
	runner.check_eq(
		str(plotlines.get_instance("day_arc").get("state", "")),
		"wait",
		"plotlines: not enough days yet"
	)
	session.gst_seconds += float(GalacticCalendar.SECONDS_PER_DAY * 3)
	plotlines.on_day(session, catalog, CommodityEconomy.gst_day(session.gst_seconds))
	runner.check_eq(
		str(plotlines.get_instance("day_arc").get("state", "")),
		"ready",
		"plotlines: days_in_state advances"
	)


static func _test_gig_accept_and_flags(runner: TestRunner, catalog: Catalog) -> void:
	var plotlines := _subsystem()
	var def := {
		"id": "gig_arc",
		"initial": "offer",
		"states": {
			"offer": {
				"gigs": [
					{"id": "ask", "desk": "bar", "title": "Ask", "text": "Quiet word."},
				],
				"transitions": [
					{
						"to": "engaged",
						"when": {"kind": "gig_accepted", "gig_id": "ask"},
						"set_flags": {"pilot": "Ada Voss"},
					},
				],
			},
			"engaged": {"terminal": true},
		},
	}
	_install_def(catalog, def)
	var session := _session(catalog)
	var gigs := plotlines.contribute_gigs("bar", "proxima_habitat", session, catalog)
	runner.check_eq(gigs.size(), 1, "plotlines: gig listed on matching desk")
	runner.check(
		not plotlines.accept_gig(session, catalog, "gig_arc", "wrong"),
		"plotlines: wrong gig id does not advance"
	)
	runner.check(plotlines.accept_gig(session, catalog, "gig_arc", "ask"), "plotlines: accept_gig succeeds")
	runner.check_eq(
		str(plotlines.get_instance("gig_arc").get("state", "")),
		"engaged",
		"plotlines: accept moves to engaged"
	)
	runner.check_eq(
		str(plotlines.get_instance("gig_arc").get("flags", {}).get("pilot", "")),
		"Ada Voss",
		"plotlines: set_flags applied"
	)
	runner.check_eq(
		plotlines.contribute_gigs("bar", "proxima_habitat", session, catalog).size(),
		0,
		"plotlines: terminal state offers no gigs"
	)


static func _test_transition_chain(runner: TestRunner, catalog: Catalog) -> void:
	var plotlines := _subsystem()
	var def := {
		"id": "chain_arc",
		"initial": "a",
		"states": {
			"a": {
				"transitions": [{"to": "b", "when": {"kind": "gig_accepted", "gig_id": "step"}}],
			},
			"b": {
				"transitions": [{"to": "c", "when": {"kind": "gig_accepted", "gig_id": "step"}}],
			},
			"c": {"terminal": true},
		},
	}
	_install_def(catalog, def)
	var session := _session(catalog)
	runner.check(plotlines.accept_gig(session, catalog, "chain_arc", "step"), "plotlines: chain accept")
	runner.check_eq(
		str(plotlines.get_instance("chain_arc").get("state", "")),
		"c",
		"plotlines: chained transitions on one stimulus"
	)


static func _test_require_flags(runner: TestRunner, catalog: Catalog) -> void:
	var plotlines := _subsystem()
	var def := {
		"id": "flag_arc",
		"initial": "gate",
		"states": {
			"gate": {
				"transitions": [
					{
						"to": "open",
						"when": {"kind": "event", "type": SimEvent.SECTOR_ENTERED},
						"require_flags": {"key": "secret"},
					},
					{"to": "closed", "when": {"kind": "event", "type": SimEvent.SECTOR_ENTERED}},
				],
			},
			"open": {"terminal": true},
			"closed": {"terminal": true},
		},
	}
	_install_def(catalog, def)
	var session := _session(catalog)
	plotlines.on_event(session, catalog, SimEvent.sector_entered("proxima"))
	runner.check_eq(
		str(plotlines.get_instance("flag_arc").get("state", "")),
		"closed",
		"plotlines: first matching transition without flags"
	)


static func _test_terminal_state(runner: TestRunner, catalog: Catalog) -> void:
	var plotlines := _subsystem()
	var def := {
		"id": "terminal_arc",
		"initial": "done",
		"states": {"done": {"terminal": true}},
	}
	_install_def(catalog, def)
	var session := _session(catalog)
	plotlines.on_event(session, catalog, SimEvent.docked("proxima_habitat"))
	runner.check_eq(
		str(plotlines.get_instance("terminal_arc").get("state", "")),
		"done",
		"plotlines: terminal state ignores events"
	)


static func _test_contribute_messages_and_gigs(runner: TestRunner, catalog: Catalog) -> void:
	var plotlines := _subsystem()
	var def := {
		"id": "content_arc",
		"initial": "live",
		"states": {
			"live": {
				"messages": [
					{"channel": "gossip", "text": "Whisper.", "weight": 1.0},
					{"channel": "headlines", "text": "Wire.", "weight": 1.0},
				],
				"gigs": [
					{"id": "x", "desk": "any", "title": "T", "text": "Body", "habitats": ["proxima_habitat"]},
				],
			},
		},
	}
	catalog.plotlines_by_id = {str(def.get("id", "")): def}
	var session := _session(catalog)
	runner.check_eq(
		plotlines.contribute_messages(MessageChannels.GOSSIP, session, catalog).size(),
		1,
		"plotlines: gossip message filter"
	)
	runner.check_eq(
		plotlines.contribute_messages(MessageChannels.HEADLINES, session, catalog).size(),
		1,
		"plotlines: headlines message filter"
	)
	runner.check_eq(
		plotlines.contribute_gigs("terminal", "proxima_habitat", session, catalog).size(),
		1,
		"plotlines: desk any matches terminal"
	)
	runner.check_eq(
		plotlines.contribute_gigs("bar", "tycho_habitat", session, catalog).size(),
		0,
		"plotlines: habitat filter"
	)


static func _test_save_round_trip(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := Simulation.new()
	var def := {
		"id": "save_arc",
		"initial": "s1",
		"states": {"s1": {}, "s2": {}},
	}
	_install_def(catalog, def)
	var manual := PlotlineSubsystem.new()
	manual.from_dict({"instances": {"save_arc": {"state": "s2", "entered_gst": 42.0, "flags": {"k": "v"}}}})
	var blob := {"plotlines": {"version": 1, "data": manual.to_dict()}}
	simulation.apply_save(blob)
	var restored := simulation.get_subsystem("plotlines") as PlotlineSubsystem
	var instance := restored.get_instance("save_arc")
	runner.check_eq(str(instance.get("state", "")), "s2", "plotlines: save restores state")
	runner.check_eq(float(instance.get("entered_gst", 0.0)), 42.0, "plotlines: save restores entered_gst")
	runner.check_eq(str(instance.get("flags", {}).get("k", "")), "v", "plotlines: save restores flags")
	var collected := simulation.collect_save()
	var round: Dictionary = collected.get("plotlines", {})
	runner.check_eq(int(round.get("version", 0)), 1, "plotlines: collect save version")


static func _test_missing_save_section(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := Simulation.new()
	var plotlines := simulation.get_subsystem("plotlines") as PlotlineSubsystem
	_install_def(
		catalog,
		{"id": "fresh_arc", "initial": "start", "states": {"start": {}, "other": {}}}
	)
	simulation.apply_save({})
	var session := _session(catalog)
	plotlines.on_day(session, catalog, 0)
	runner.check(
		not plotlines.get_instance("fresh_arc").is_empty(),
		"plotlines: missing save section creates instance on ensure"
	)


static func _test_message_subsystem_hook(runner: TestRunner, catalog: Catalog) -> void:
	var saved_emitters: Dictionary = catalog.message_emitters_by_id.duplicate(true)
	catalog.message_emitters_by_id = {}
	var def := {
		"id": "tape_arc",
		"initial": "rumour",
		"states": {
			"rumour": {
				"messages": [
					{
						"channel": "gossip",
						"text": "Plotline tape marker xyzzy.",
						"weight": 1.0,
					},
				],
			},
		},
	}
	_install_def(catalog, def)
	var simulation := Simulation.new()
	var session := _session(catalog)
	session.bound_plotlines = simulation.get_subsystem("plotlines") as PlotlineSubsystem
	var messages := simulation.get_subsystem("messages") as MessageSubsystem
	var rng := RandomNumberGenerator.new()
	rng.seed = 991
	var line := messages.next_line(MessageChannels.GOSSIP, session, catalog, rng, simulation)
	catalog.message_emitters_by_id = saved_emitters
	runner.check(
		str(line.get("text", "")).find("xyzzy") >= 0,
		"plotlines: message subsystem samples plotline line"
	)
	runner.check(
		str(line.get("emitter_id", "")).begins_with("plotline:"),
		"plotlines: message emitter_id tagged"
	)
