extends Resource

class_name LLMConfig

const SETTINGS_PATH: String = "user://llm_settings.cfg"
const SECRETS_PATH: String = "res://llm_secrets.cfg"

var endpoint: String = "https://ollama.com/v1/chat/completions"
var api_key: String = ""
var model: String = "gemma3:4b"
var max_tokens: int = 512
var temperature: float = 0.8
var enabled: bool = true


func _init() -> void:
	_load_secrets()


func _load_secrets() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(SECRETS_PATH)
	if err == OK:
		api_key = cfg.get_value("llm", "api_key", "")


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("llm", "endpoint", endpoint)
	cfg.set_value("llm", "api_key", api_key)
	cfg.set_value("llm", "model", model)
	cfg.set_value("llm", "max_tokens", max_tokens)
	cfg.set_value("llm", "temperature", temperature)
	cfg.set_value("llm", "enabled", enabled)
	cfg.save(SETTINGS_PATH)


func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(SETTINGS_PATH)
	if err == OK:
		enabled = cfg.get_value("llm", "enabled", enabled)


func is_ready() -> bool:
	return enabled and not api_key.is_empty()
