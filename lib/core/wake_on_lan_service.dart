import 'dart:io';

/// Sends a Wake-on-LAN "magic packet" to power the TV on from full standby.
/// The WebSocket API only works once the TV is already reachable on the
/// network, so this covers the "TV is fully off" case.
///
/// Note: the TV must have an option like "Power on with Mobile" enabled in
/// its network settings for this to work.
class WakeOnLanService {
  static Future<void> wake(
    String macAddress, {
    String broadcastIp = '255.255.255.255',
  }) async {
    final macBytes = _parseMac(macAddress);
    final packet = <int>[
      ...List.filled(6, 0xFF),
      for (var i = 0; i < 16; i++) ...macBytes,
    ];

    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    socket.send(packet, InternetAddress(broadcastIp), 9);
    socket.close();
  }

  static List<int> _parseMac(String mac) {
    final parts = mac.split(RegExp(r'[:\-]'));
    if (parts.length != 6) {
      throw ArgumentError('Invalid MAC address: $mac');
    }
    return parts.map((p) => int.parse(p, radix: 16)).toList();
  }
}
