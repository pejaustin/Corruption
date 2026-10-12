extends Resource
class_name NetworkConnectionConfigs

@export var host_ip: String = ""
@export var host_port: int = -1
## Hosts only: ask the router to open the port (UPnP). Off for headless network tests (tools/net/).
@export var use_upnp: bool = true

func _init(host_ip_: String) -> void:
	host_ip = host_ip_
