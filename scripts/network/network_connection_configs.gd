extends Resource
class_name NetworkConnectionConfigs

@export var host_ip: String = ""
@export var host_port: int = -1

func _init(host_ip_: String) -> void:
	host_ip = host_ip_
