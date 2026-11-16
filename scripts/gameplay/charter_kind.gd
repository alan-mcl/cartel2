class_name CharterKind
extends RefCounted

## Per-kind charter hooks and save metadata. Lifecycle bodies call MissionSubsystem helpers.

enum Type {
	PASSENGER,
	FREIGHT,
	SCAN,
	BOUNTY,
	RETRIEVAL,
}

const ORDER: Array = [
	Type.PASSENGER,
	Type.FREIGHT,
	Type.SCAN,
	Type.BOUNTY,
	Type.RETRIEVAL,
]

var kind_type: Type
var slice_key: String = ""
var offers_save_key: String = ""
var accepted_save_key: String = ""
var next_id_save_key: String = ""
## Mission save version that introduced this kind's keys (for migrate).
var migrate_introduced_at: int = 1
## When true, migrate wipes this kind's offer map for saves at or below 6.
var migrate_clear_offers_at_v6: bool = true


static func create(type: Type) -> CharterKind:
	var k := CharterKind.new()
	k.kind_type = type
	match type:
		Type.PASSENGER:
			k.slice_key = "passenger"
			k.offers_save_key = "offers_by_habitat"
			k.accepted_save_key = "accepted"
			k.next_id_save_key = "next_charter_id"
			k.migrate_introduced_at = 1
			k.migrate_clear_offers_at_v6 = true
		Type.FREIGHT:
			k.slice_key = "freight"
			k.offers_save_key = "freight_offers_by_habitat"
			k.accepted_save_key = "freight_accepted"
			k.next_id_save_key = "next_freight_charter_id"
			k.migrate_introduced_at = 2
			k.migrate_clear_offers_at_v6 = true
		Type.SCAN:
			k.slice_key = "scan"
			k.offers_save_key = "scan_offers_by_habitat"
			k.accepted_save_key = "scan_accepted"
			k.next_id_save_key = "next_scan_charter_id"
			k.migrate_introduced_at = 3
			k.migrate_clear_offers_at_v6 = true
		Type.BOUNTY:
			k.slice_key = "bounty"
			k.offers_save_key = "bounty_offers_by_habitat"
			k.accepted_save_key = "bounty_accepted"
			k.next_id_save_key = "next_bounty_charter_id"
			k.migrate_introduced_at = 4
			k.migrate_clear_offers_at_v6 = true
		Type.RETRIEVAL:
			k.slice_key = "retrieval"
			k.offers_save_key = "retrieval_offers_by_habitat"
			k.accepted_save_key = "retrieval_accepted"
			k.next_id_save_key = "next_retrieval_charter_id"
			k.migrate_introduced_at = 6
			k.migrate_clear_offers_at_v6 = true
	return k


static func all_configs() -> Array:
	var out: Array = []
	for type_variant in ORDER:
		out.append(create(int(type_variant)))
	return out


func book_for(missions: MissionSubsystem) -> CharterBook:
	match kind_type:
		Type.PASSENGER:
			return missions.passengers
		Type.FREIGHT:
			return missions.freight
		Type.SCAN:
			return missions.scans
		Type.BOUNTY:
			return missions.bounties
		Type.RETRIEVAL:
			return missions.retrievals
	return null


func evaluate_with_missions(
	missions: MissionSubsystem,
	session: GameSession,
	catalog: Catalog,
	offer: Dictionary,
	ship_id: String
) -> Dictionary:
	match kind_type:
		Type.PASSENGER:
			var committed_passengers := (
				missions.committed_passengers_for_ship(ship_id)
				+ missions.committed_freight_life_support_for_ship(ship_id)
			)
			return PassengerCharters.evaluate_offer_for_ship(
				session, catalog, offer, ship_id, committed_passengers
			)
		Type.FREIGHT:
			return FreightCharters.evaluate_offer_for_ship(
				session,
				catalog,
				offer,
				ship_id,
				missions._freight_commitment_for_evaluate(ship_id)
			)
		Type.SCAN:
			return ScanCharters.evaluate_offer_for_ship(session, catalog, offer, ship_id)
		Type.BOUNTY:
			return BountyCharters.evaluate_offer_for_ship(session, catalog, offer, ship_id)
		Type.RETRIEVAL:
			return RetrievalCharters.evaluate_offer_for_ship(session, catalog, offer, ship_id)
	return {"ok": false, "reason": "unknown kind"}


func reject_reason_default() -> String:
	match kind_type:
		Type.PASSENGER:
			return "Cannot accept charter."
		Type.FREIGHT:
			return "Cannot accept freight charter."
		Type.SCAN:
			return "Cannot accept scan charter."
		Type.BOUNTY:
			return "Cannot accept bounty."
		Type.RETRIEVAL:
			return "Cannot accept retrieval charter."
	return "Cannot accept."


func cancel_blocked_log() -> String:
	match kind_type:
		Type.PASSENGER:
			return "Cannot cancel charter after departure."
		Type.FREIGHT:
			return "Cannot cancel freight after departure."
		Type.SCAN:
			return "Cannot cancel scan charter after departure."
		Type.BOUNTY:
			return "Cannot cancel bounty after departure."
		Type.RETRIEVAL:
			return "Cannot cancel retrieval charter after departure."
	return "Cannot cancel."


func cancel_penalty(catalog: Catalog, reward: int) -> int:
	match kind_type:
		Type.PASSENGER:
			return PassengerCharters.cancel_penalty(PassengerCharters.config(catalog), reward)
		Type.FREIGHT:
			return FreightCharters.cancel_penalty(FreightCharters.config(catalog), reward)
		Type.SCAN:
			return ScanCharters.cancel_penalty(ScanCharters.config(catalog), reward)
		Type.BOUNTY:
			return BountyCharters.cancel_penalty(BountyCharters.config(catalog), reward)
		Type.RETRIEVAL:
			return RetrievalCharters.cancel_penalty(RetrievalCharters.config(catalog), reward)
	return 0


func cancel_log(penalty: int) -> String:
	match kind_type:
		Type.PASSENGER:
			return "Charter cancelled. Fee d%d." % penalty if penalty > 0 else "Charter cancelled."
		Type.FREIGHT:
			return "Freight cancelled. Fee d%d." % penalty if penalty > 0 else "Freight cancelled."
		Type.SCAN:
			return "Scan charter cancelled. Fee d%d." % penalty if penalty > 0 else "Scan charter cancelled."
		Type.BOUNTY:
			return "Bounty cancelled. Fee d%d." % penalty if penalty > 0 else "Bounty cancelled."
		Type.RETRIEVAL:
			return "Retrieval cancelled. Fee d%d." % penalty if penalty > 0 else "Retrieval cancelled."
	return "Cancelled."


func accept_log(offer: Dictionary) -> String:
	match kind_type:
		Type.PASSENGER:
			return (
				"Charter accepted: %s to %s for d%d."
				% [
					str(offer.get("role_title", "Passengers")),
					str(offer.get("destination_name", "")),
					int(offer.get("reward", 0)),
				]
			)
		Type.FREIGHT:
			return (
				"Freight accepted to %s for d%d."
				% [str(offer.get("destination_name", "")), int(offer.get("reward", 0))]
			)
		Type.SCAN:
			return (
				"Scan charter accepted: %s at %s for d%d."
				% [
					str(offer.get("designation", "Survey")),
					str(offer.get("site_label", "")),
					int(offer.get("reward", 0)),
				]
			)
		Type.BOUNTY:
			return (
				"Bounty accepted: %s at %s for d%d."
				% [
					str(offer.get("target_callsign", "")),
					str(offer.get("site_label", "")),
					int(offer.get("reward", 0)),
				]
			)
		Type.RETRIEVAL:
			return (
				"Retrieval accepted: %s at %s for d%d."
				% [
					str(offer.get("specimen_label", "Specimen")),
					str(offer.get("site_label", "")),
					int(offer.get("reward", 0)),
				]
			)
	return "Accepted."


func grant_failure_log() -> String:
	match kind_type:
		Type.SCAN:
			return "Could not open survey site."
		Type.BOUNTY:
			return "Could not open bounty site."
		Type.RETRIEVAL:
			return "Could not open retrieval site."
	return ""


func uses_volatile_cancel_rules() -> bool:
	return kind_type in [Type.SCAN, Type.BOUNTY, Type.RETRIEVAL]


func prepare_accept(
	session: GameSession,
	catalog: Catalog,
	offer: Dictionary,
	charter: Dictionary,
	missions: MissionSubsystem
) -> bool:
	charter["accepted_gst"] = session.gst_seconds
	match kind_type:
		Type.PASSENGER, Type.FREIGHT:
			missions._apply_charter_deadline(session, charter)
			return true
		Type.SCAN:
			var target_kind := str(offer.get("target_kind", ""))
			if target_kind == "planet":
				charter["scan_contact_id"] = "planet"
				charter["volatile_record_id"] = ""
				missions._apply_charter_deadline(session, charter)
				return true
			var record_id := VolatileTranslation.grant(
				session,
				catalog,
				ScanCharters.build_volatile_grant_params(catalog, offer)
			)
			if record_id.is_empty():
				return false
			charter["volatile_record_id"] = record_id
			charter["scan_contact_id"] = ScanCharters.scan_contact_id_for_offer(offer, record_id)
			var record := VolatileTranslation.find_by_id(session, record_id)
			if not record.is_empty():
				charter["deadline_gst"] = float(record.get("return_expires_gst", 0.0))
			return true
		Type.BOUNTY:
			var bounty_record_id := VolatileTranslation.grant(
				session,
				catalog,
				BountyCharters.build_volatile_grant_params(catalog, offer)
			)
			if bounty_record_id.is_empty():
				return false
			charter["volatile_record_id"] = bounty_record_id
			charter["bounty_target_id"] = BountyCharters.bounty_target_id_for_record(bounty_record_id)
			var bounty_record := VolatileTranslation.find_by_id(session, bounty_record_id)
			if not bounty_record.is_empty():
				charter["deadline_gst"] = float(bounty_record.get("return_expires_gst", 0.0))
			session.player.set_bounty_contract(
				str(charter.get("bounty_target_id", "")),
				BountyCharters.bounty_sector_for_contract(charter)
			)
			return true
		Type.RETRIEVAL:
			charter["retrieved"] = false
			var retrieval_record_id := VolatileTranslation.grant(
				session,
				catalog,
				RetrievalCharters.build_volatile_grant_params(catalog, offer)
			)
			if retrieval_record_id.is_empty():
				return false
			charter["volatile_record_id"] = retrieval_record_id
			charter["retrieval_contact_id"] = RetrievalCharters.retrieval_contact_id(retrieval_record_id)
			var retrieval_record := VolatileTranslation.find_by_id(session, retrieval_record_id)
			if not retrieval_record.is_empty():
				charter["deadline_gst"] = float(retrieval_record.get("return_expires_gst", 0.0))
			return true
	return true


func cancel_eligible(session: GameSession, charter: Dictionary, at_origin: Callable) -> bool:
	if not bool(at_origin.call(session, charter)):
		return false
	if not uses_volatile_cancel_rules():
		return true
	var volatile_id := str(charter.get("volatile_record_id", ""))
	if volatile_id.is_empty():
		return true
	var record := VolatileTranslation.find_by_id(session, volatile_id)
	if record.is_empty():
		return true
	return not bool(record.get("consumed", false))


func discard_volatile_on_cancel(session: GameSession, charter: Dictionary) -> void:
	if not uses_volatile_cancel_rules():
		return
	var volatile_id := str(charter.get("volatile_record_id", ""))
	if not volatile_id.is_empty():
		VolatileTranslation.discard_record(session, volatile_id)


func clear_bounty_contract_on_cancel(session: GameSession, charter: Dictionary) -> void:
	if kind_type == Type.BOUNTY:
		session.player.clear_bounty_contract(str(charter.get("bounty_target_id", "")))


func clear_bounty_contract_on_resolve(session: GameSession, charter: Dictionary) -> void:
	if kind_type == Type.BOUNTY:
		session.player.clear_bounty_contract(str(charter.get("bounty_target_id", "")))


func completion_habitat_field() -> String:
	if kind_type in [Type.PASSENGER, Type.FREIGHT]:
		return "destination_habitat_id"
	return "origin_habitat_id"


func requires_satisfied_for_complete() -> bool:
	return kind_type in [Type.SCAN, Type.BOUNTY, Type.RETRIEVAL]


func charter_satisfied(session: GameSession, entry: Dictionary) -> bool:
	match kind_type:
		Type.SCAN:
			return ScanCharters.charter_satisfied(session, entry)
		Type.BOUNTY:
			return BountyCharters.charter_satisfied(session, entry)
		Type.RETRIEVAL:
			return RetrievalCharters.charter_satisfied(session, entry)
	return true


func enforce_late_passenger_style() -> bool:
	return kind_type == Type.PASSENGER


func enforce_late_origin_unsatisfied() -> bool:
	return kind_type in [Type.SCAN, Type.BOUNTY, Type.RETRIEVAL]


func missed_deadline_log(penalty: int) -> String:
	match kind_type:
		Type.PASSENGER:
			return "Passengers left charter after deadline. Fee d%d." % penalty
		Type.SCAN:
			return "Scan charter missed deadline. Fee d%d." % penalty
		Type.BOUNTY:
			return "Bounty missed deadline. Fee d%d." % penalty
		Type.RETRIEVAL:
			return "Retrieval charter missed deadline. Fee d%d." % penalty
	return "Missed deadline. Fee d%d." % penalty


func settle_logs(charter: Dictionary, penalty: int) -> Dictionary:
	match kind_type:
		Type.PASSENGER:
			var dest_name := str(charter.get("destination_name", ""))
			return {
				"late": "Charter late to %s. Fee d%d." % [dest_name, penalty],
				"paid": "Charter complete to %s. +d%d." % [dest_name, int(charter.get("reward", 0))],
				"unpaid": "Charter complete to %s." % dest_name,
			}
		Type.FREIGHT:
			var freight_dest := str(charter.get("destination_name", ""))
			return {
				"late": "Freight late to %s. Fee d%d." % [freight_dest, penalty],
				"paid": "Freight delivered to %s. +d%d." % [freight_dest, int(charter.get("reward", 0))],
				"unpaid": "Freight delivered to %s." % freight_dest,
			}
		Type.SCAN:
			var site := str(charter.get("site_label", ""))
			return {
				"late": "Scan charter late to %s. Fee d%d." % [site, penalty],
				"paid": "Scan charter complete. +d%d." % int(charter.get("reward", 0)),
				"unpaid": "Scan charter complete.",
			}
		Type.BOUNTY:
			var callsign := str(charter.get("target_callsign", ""))
			return {
				"late": "Bounty late (%s). Fee d%d." % [callsign, penalty],
				"paid": "Bounty complete (%s). +d%d." % [callsign, int(charter.get("reward", 0))],
				"unpaid": "Bounty complete (%s)." % callsign,
			}
		Type.RETRIEVAL:
			var specimen := str(charter.get("specimen_label", "Specimen"))
			return {
				"late": "Retrieval late (%s). Fee d%d." % [specimen, penalty],
				"paid": "Retrieval complete (%s). +d%d." % [specimen, int(charter.get("reward", 0))],
				"unpaid": "Retrieval complete (%s)." % specimen,
			}
	return {"late": "", "paid": "", "unpaid": ""}