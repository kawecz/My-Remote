class TvDevice {
  final String ip;
  final String name;
  final String? mac;
  String? token;

  TvDevice({required this.ip, required this.name, this.mac, this.token});

  Map<String, dynamic> toJson() => {
    'ip': ip,
    'name': name,
    'mac': mac,
    'token': token,
  };

  factory TvDevice.fromJson(Map<String, dynamic> json) => TvDevice(
    ip: json['ip'] as String,
    name: json['name'] as String,
    mac: json['mac'] as String?,
    token: json['token'] as String?,
  );

  TvDevice copyWith({String? token}) =>
      TvDevice(ip: ip, name: name, mac: mac, token: token ?? this.token);
}
