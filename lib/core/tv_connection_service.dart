import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/io.dart';

import '../models/tv_device.dart';
import 'tv_discovery_service.dart';

enum TvConnectionState {
  disconnected,
  connecting,
  awaitingPairing,
  connected,
  error,
}

class TvConnectionService {
  static const _prefsIpKey = 'tv_ip';
  static const _prefsNameKey = 'tv_name';
  static const _prefsMacKey = 'tv_mac';
  static const _prefsTokenKey = 'tv_token';

  static const _appName = 'myremote';
  static const _port = 8002;

  IOWebSocketChannel? _channel;
  StreamSubscription? _subscription;
  TvDevice? device;

  final _stateController = StreamController<TvConnectionState>.broadcast();
  Stream<TvConnectionState> get stateStream => _stateController.stream;

  TvConnectionState _state = TvConnectionState.disconnected;
  TvConnectionState get state => _state;

  /// Guards against concurrent connect() calls. If a connect is already
  /// in flight, the second call is a no-op.
  bool _connecting = false;

  void _setState(TvConnectionState s) {
    debugPrint('[TV] state: $_state -> $s');
    _state = s;
    _stateController.add(s);
  }

  Future<TvDevice?> loadSavedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    final ip = prefs.getString(_prefsIpKey);
    if (ip == null) return null;
    return TvDevice(
      ip: ip,
      name: prefs.getString(_prefsNameKey) ?? 'TV',
      mac: prefs.getString(_prefsMacKey),
      token: prefs.getString(_prefsTokenKey),
    );
  }

  Future<void> _saveDevice(TvDevice d) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsIpKey, d.ip);
    await prefs.setString(_prefsNameKey, d.name);
    if (d.mac != null) await prefs.setString(_prefsMacKey, d.mac!);
    if (d.token != null) await prefs.setString(_prefsTokenKey, d.token!);
    debugPrint(
      '[TV] Saved device: ip=${d.ip}, name=${d.name}, '
      'mac=${d.mac}, token=${d.token}',
    );
  }

  /// Cleans up any previous socket. Called before opening a new one and
  /// whenever a connection is considered dead.
  Future<void> _cleanupSocket() async {
    try {
      await _subscription?.cancel();
    } catch (_) {}
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _subscription = null;
  }

  /// Connects to the TV at [ip]. Always tears down the previous socket
  /// first, so we never accumulate zombie connections on the TV side.
  Future<void> connect({
    required String ip,
    String name = 'TV',
    String? mac,
    String? token,
  }) async {
    if (_connecting) {
      debugPrint('[TV] connect() ignored — already connecting');
      return;
    }
    _connecting = true;

    try {
      await _cleanupSocket();
      _setState(TvConnectionState.connecting);
      device = TvDevice(ip: ip, name: name, mac: mac, token: token);

      final encodedName = base64Encode(utf8.encode(_appName));
      final tokenParam = (token != null && token.isNotEmpty)
          ? '&token=$token'
          : '';
      final uri = Uri.parse(
        'wss://$ip:$_port/api/v2/channels/samsung.remote.control'
        '?name=$encodedName$tokenParam',
      );

      final client = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true;

      debugPrint('[TV] Connecting to: $uri');
      final socket = await WebSocket.connect(
        uri.toString(),
        customClient: client,
      ).timeout(const Duration(seconds: 10));

      _channel = IOWebSocketChannel(socket);
      _setState(TvConnectionState.awaitingPairing);

      _subscription = _channel!.stream.listen(
        _handleMessage,
        onError: (e) {
          debugPrint('[TV] stream error: $e');
          _setState(TvConnectionState.error);
        },
        onDone: () {
          debugPrint('[TV] stream closed by TV');
          _setState(TvConnectionState.disconnected);
        },
      );
    } catch (e, stack) {
      debugPrint('[TV] CONNECT FAILED: $e');
      _setState(TvConnectionState.error);
      rethrow;
    } finally {
      _connecting = false;
    }
  }

  Future<bool> connectWithDiscovery({
    required String initialIp,
    required String name,
    String? mac,
    String? token,
    Duration discoveryTimeout = const Duration(seconds: 3),
  }) async {
    // Attempt 1: saved IP
    try {
      await connect(ip: initialIp, name: name, mac: mac, token: token);
      return true;
    } catch (e) {
      debugPrint('[TV] Initial connect to $initialIp failed: $e');
    }

    // Attempt 2: SSDP discovery
    debugPrint('[TV] Running SSDP discovery...');
    _setState(TvConnectionState.connecting);

    final discoveredIp = await TvDiscoveryService.discoverTv(
      timeout: discoveryTimeout,
    );

    if (discoveredIp == null) {
      debugPrint('[TV] Discovery found nothing');
      _setState(TvConnectionState.error);
      return false;
    }

    if (discoveredIp == initialIp) {
      debugPrint(
        '[TV] Discovery returned the same IP ($discoveredIp) — '
        'giving up',
      );
      _setState(TvConnectionState.error);
      return false;
    }

    debugPrint('[TV] Discovery found TV at $discoveredIp — retrying');
    try {
      await connect(ip: discoveredIp, name: name, mac: mac, token: token);
      if (device != null) {
        await _saveDevice(device!);
      }
      return true;
    } catch (e) {
      debugPrint('[TV] Connect to discovered IP $discoveredIp failed: $e');
      _setState(TvConnectionState.error);
      return false;
    }
  }

  void _handleMessage(dynamic raw) {
    debugPrint('[TV] <- $raw');
    final msg = jsonDecode(raw as String) as Map<String, dynamic>;
    final event = msg['event'] as String?;

    if (event == 'ms.channel.connect') {
      final newToken = msg['data']?['token'] as String?;
      if (newToken != null && device != null) {
        device = device!.copyWith(token: newToken);
        _saveDevice(device!);
        debugPrint('[TV] Saved new token: $newToken');
      } else {
        debugPrint(
          '[TV] No new token in payload, using existing: '
          '${device?.token}',
        );
      }
      _setState(TvConnectionState.connected);
    } else if (event == 'ms.channel.timeOut' ||
        event == 'ms.channel.unauthorized') {
      debugPrint('[TV] TV rejected/expired the pairing ($event)');
      _setState(TvConnectionState.error);
      // Tear down the dead socket so the next connect starts fresh.
      _cleanupSocket();
    }
  }

  void sendKey(String keyCode) {
    if (_channel == null || _state != TvConnectionState.connected) {
      debugPrint(
        '[TV] sendKey($keyCode) skipped — not connected (state=$_state)',
      );
      return;
    }
    debugPrint('[TV] -> key $keyCode');
    _channel!.sink.add(
      jsonEncode({
        'method': 'ms.remote.control',
        'params': {
          'Cmd': 'Click',
          'DataOfCmd': keyCode,
          'Option': 'false',
          'TypeOfRemote': 'SendRemoteKey',
        },
      }),
    );
  }

  bool sendText(String text) {
    if (_channel == null || _state != TvConnectionState.connected) {
      debugPrint(
        '[TV] sendText("$text") skipped — not connected (state=$_state)',
      );
      return false;
    }

    final payload = jsonEncode({
      'method': 'ms.remote.control',
      'params': {
        'Cmd': 'sendText',
        'Data': text,
        'TypeOfRemote': 'SendInputString',
      },
    });

    debugPrint('[TV] -> text "$text" | payload: $payload');
    _channel!.sink.add(payload);
    return true;
  }

  /// Launches an installed app on the TV by its numeric App ID.
  ///
  /// Samsung TVs silently ignore unknown IDs — if the app doesn't open,
  /// the ID is wrong for this TV/region. There's no error returned.
  ///
  /// Returns false only if we're not connected or the ID is empty.
  bool launchApp(String appId) {
    if (_channel == null || _state != TvConnectionState.connected) {
      debugPrint('[TV] launchApp($appId) skipped — not connected');
      return false;
    }
    if (appId.isEmpty) return false;

    final payload = jsonEncode({
      'method': 'ms.channel.emit',
      'params': {
        'event': 'ed.apps.launch',
        'to': 'host',
        'data': {'appId': appId, 'action_type': 'DEEP_LINK'},
      },
    });

    debugPrint('[TV] -> launchApp($appId) | $payload');
    _channel!.sink.add(payload);
    return true;
  }

  Future<void> disconnect() async {
    await _cleanupSocket();
    _setState(TvConnectionState.disconnected);
  }

  void dispose() {
    _subscription?.cancel();
    _channel?.sink.close();
    _stateController.close();
  }
}
