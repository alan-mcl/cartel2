class_name CharterResolution
extends RefCounted

## Shared dock pay, late fee, and missed-deadline settlement.
## Offer lists, id counters, and accept paths stay on MissionSubsystem.


static func is_late(session: GameSession, charter: Dictionary) -> bool:
	if session == null or not charter.has("deadline_gst"):
		return false
	return session.gst_seconds > float(charter.get("deadline_gst", 0.0))


static func settle_on_dock(
	session: GameSession,
	charter: Dictionary,
	penalty: int,
	late_log: String,
	paid_log: String,
	unpaid_log: String
) -> void:
	if session == null:
		return
	var reward := int(charter.get("reward", 0))
	if is_late(session, charter):
		session.assess_penalty_credits(penalty)
		log_with_reputation_delta(session, -1, late_log)
		if not session.player.sandbox:
			session.career.missions_late += 1
			session.career.record_mission_penalty(penalty)
	elif reward > 0:
		session.add_credits(reward)
		log_with_reputation_delta(session, 1, paid_log)
		if not session.player.sandbox:
			session.career.missions_completed_on_time += 1
			session.career.record_charter_reward(reward)
	else:
		log_with_reputation_delta(session, 1, unpaid_log)
		if not session.player.sandbox:
			session.career.missions_completed_on_time += 1
	session.changed.emit()


static func fail_missed_deadline(session: GameSession, penalty: int, log_line: String) -> void:
	if session == null:
		return
	session.assess_penalty_credits(penalty)
	log_with_reputation_delta(session, -1, log_line)
	if not session.player.sandbox:
		session.career.missions_missed_deadline += 1
		session.career.record_mission_penalty(penalty)
	session.changed.emit()


static func log_with_reputation_delta(session: GameSession, delta: int, message: String) -> void:
	var applied := session.player.adjust_reputation(delta)
	if applied > 0:
		session.last_log = "%s Reputation +%d." % [message, applied]
	elif applied < 0:
		session.last_log = "%s Reputation %d." % [message, applied]
	else:
		session.last_log = message
