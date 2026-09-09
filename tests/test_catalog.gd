class_name TestCatalog
extends RefCounted


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()

	runner.check(not catalog.get_sector("proxima").is_empty(), "proxima sector exists")
	runner.check(not catalog.get_sector("bela").is_empty(), "bela sector exists")

	var unspace := catalog.get_unspace_for_n(4)
	runner.check_eq(str(unspace.get("id", "")), "n4_default", "get_unspace_for_n(4)")

	var exit_def := InteractableDef.from_dict(catalog.get_interactable("unspace_exit"))
	runner.check(exit_def.kind == InteractableDef.Kind.ARRIVE, "unspace_exit parses as ARRIVE")

	var mapping := catalog.get_mapping("proxima", "bela", 4)
	runner.check(not mapping.is_empty(), "proxima→bela n=4 mapping exists")
	runner.check(int(mapping.get("solution", 0)) == 42, "proxima→bela solution is 42")
