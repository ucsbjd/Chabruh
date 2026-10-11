class_name UrlParams
extends RefCounted
## Reads query-string flags from the page URL (for example ?fps or ?mood=neon).
## Always empty outside the web build.


static func has(flag: String) -> bool:
	# JavaScript booleans do not compare reliably with GDScript's, so ask for a string.
	return _eval("new URLSearchParams(location.search).has(%s) ? 'yes' : 'no'" % JSON.stringify(flag)) == "yes"


static func get_value(key: String) -> String:
	var value: Variant = _eval("new URLSearchParams(location.search).get(%s)" % JSON.stringify(key))
	return value if value is String else ""


static func _eval(code: String) -> Variant:
	if not OS.has_feature("web"):
		return null
	return JavaScriptBridge.eval(code, true)
