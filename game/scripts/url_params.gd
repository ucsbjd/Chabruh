class_name UrlParams
extends RefCounted
## Reads query-string flags from the page URL (for example ?fps or ?mood=neon).
## On desktop they are read from the command line instead (see _native_value).


static func has(flag: String) -> bool:
	if not OS.has_feature("web"):
		return _native_value(flag) != null
	# JavaScript booleans do not compare reliably with GDScript's, so ask for a string.
	return _eval("new URLSearchParams(location.search).has(%s) ? 'yes' : 'no'" % JSON.stringify(flag)) == "yes"


static func get_value(key: String) -> String:
	if not OS.has_feature("web"):
		var native: Variant = _native_value(key)
		return native if native is String else ""
	var value: Variant = _eval("new URLSearchParams(location.search).get(%s)" % JSON.stringify(key))
	return value if value is String else ""


## On desktop the same flags come after a lone -- on the command line, as --flag or --key=value.
static func _native_value(key: String) -> Variant:
	for argument in OS.get_cmdline_user_args():
		if argument == "--" + key:
			return ""
		if argument.begins_with("--" + key + "="):
			return argument.substr(key.length() + 3)
	return null


static func _eval(code: String) -> Variant:
	if not OS.has_feature("web"):
		return null
	return JavaScriptBridge.eval(code, true)
