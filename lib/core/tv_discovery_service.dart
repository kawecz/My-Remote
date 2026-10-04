import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;

/// Discovers Samsung TVs on the local network via SSDP (UPnP M-SEARCH).
///
/// This is used as a fallback when the saved TV IP no longer works — for
/// example, when the router gives the TV a new DHCP lease after a power
/// outage. The service sends a multicast M-SEARCH request and waits for
/// replies, then extracts the IP from the `LOCATION` header.
///
/// Discovery runs with a short timeout (default 3s) so the UI stays
/// responsive. If no TV is found within the timeout, `null` is returned.
class TvDiscoveryService {
  static const _ssdpAddress = '239.255.255.250';
  static const _ssdpPort = 1900;

  /// Samsung-specific UPnP service exposed by TVs that have IP Control
  /// enabled. This is the most reliable signal that the device is a
  /// controllable Samsung TV.
  static const _samsungIpControlSt = 'urn:samsung.com:device:IPControlServer:1';

  /// Sends an M-SEARCH for Samsung TVs and returns the IP of the first
  /// one that responds, or `null` if none found within [timeout].
  ///
  /// Strategy (Option C):
  ///   1. Try the Samsung-specific IPControlServer ST first.
  ///   2. If no response, fall back to `ssdp:all` and filter by the
  ///      `SERVER` header containing "Samsung".
  static Future<String?> discoverTv({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    // Step 1: try the specific Samsung service first — cleanest signal.
    final ipControl = await _mSearch(
      searchTarget: _samsungIpControlSt,
      timeout: timeout,
      validator: (_) => true, // any response to this ST is a valid TV
    );
    if (ipControl != null) {
      debugPrint('[Discovery] Found TV via IPControlServer: $ipControl');
      return ipControl;
    }

    // Step 2: fall back to broad search, filter by Samsung SERVER header.
    debugPrint('[Discovery] IPControlServer not found, trying ssdp:all');
    final anySamsung = await _mSearch(
      searchTarget: 'ssdp:all',
      timeout: timeout,
      validator: (headers) {
        final server = headers['server'] ?? '';
        return server.toLowerCase().contains('samsung');
      },
    );
    if (anySamsung != null) {
      debugPrint('[Discovery] Found TV via ssdp:all: $anySamsung');
      return anySamsung;
    }

    debugPrint('[Discovery] No Samsung TV found within ${timeout.inSeconds}s');
    return null;
  }

  /// Sends a single M-SEARCH request with [searchTarget] and waits for
  /// replies until [timeout] elapses. Returns the IP from the first reply
  /// whose headers pass [validator].
  static Future<String?> _mSearch({
    required String searchTarget,
    required Duration timeout,
    required bool Function(Map<String, String> headers) validator,
  }) async {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      final request = StringBuffer()
        ..write('M-SEARCH * HTTP/1.1\r\n')
        ..write('HOST: $_ssdpAddress:$_ssdpPort\r\n')
        ..write('MAN: "ssdp:discover"\r\n')
        ..write('MX: 2\r\n')
        ..write('ST: $searchTarget\r\n')
        ..write('\r\n');

      final payload = utf8.encode(request.toString());
      socket.send(payload, InternetAddress(_ssdpAddress), _ssdpPort);

      // Also broadcast to the subnet broadcast address, since some
      // routers block the 239.x multicast range.
      try {
        socket.send(payload, InternetAddress('255.255.255.255'), _ssdpPort);
      } catch (_) {
        // Some platforms don't allow this — ignore.
      }

      final completer = Completer<String?>();
      late StreamSubscription<RawSocketEvent> sub;

      sub = socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket!.receive();
        if (datagram == null) return;

        final text = utf8.decode(datagram.data, allowMalformed: true);
        final headers = _parseHeaders(text);

        if (!validator(headers)) return;

        final location = headers['location'];
        if (location == null) return;

        final ip = _extractIp(location);
        if (ip != null && !completer.isCompleted) {
          completer.complete(ip);
        }
      });

      final result = await completer.future.timeout(
        timeout,
        onTimeout: () => null,
      );

      await sub.cancel();
      return result;
    } catch (e) {
      debugPrint('[Discovery] Error during M-SEARCH: $e');
      return null;
    } finally {
      socket?.close();
    }
  }

  /// Parses an SSDP response into a lowercase-keyed header map.
  static Map<String, String> _parseHeaders(String raw) {
    final lines = raw.split(RegExp(r'\r?\n'));
    final headers = <String, String>{};

    for (final line in lines) {
      final idx = line.indexOf(':');
      if (idx <= 0) continue;
      final key = line.substring(0, idx).trim().toLowerCase();
      final value = line.substring(idx + 1).trim();
      headers[key] = value;
    }
    return headers;
  }

  /// Extracts the IP from a LOCATION header like
  /// `http://192.168.1.4:9110/ip_control`.
  static String? _extractIp(String location) {
    try {
      final uri = Uri.parse(location);
      final host = uri.host;
      if (host.isEmpty) return null;
      // Make sure it's actually an IPv4 address, not a hostname.
      if (!RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host)) return null;
      return host;
    } catch (_) {
      return null;
    }
  }
}
