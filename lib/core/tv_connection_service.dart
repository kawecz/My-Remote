import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/io.dart';

import '../models/tv_device.dart';

enum TvConnectionState {
  disconnected,
  connecting,
  awaitingPairing,
  connected,
  error,
}

/// Handles the WebSocket connection to a Samsung Tizen TV, the one-time
/// pairing handshake, token persistence, and sending remote-key / text
/// commands.
class TvConnectionService {
  static const _prefsIpKey = 'tv_ip';
  static const _prefsNameKey = 'tv_name';
  static const _prefsMacKey = 'tv_mac';
  static const _prefsTokenKey = 'tv_token';

  static const _appName = 'myremote';
  static const _port = 8002; // TLS port used by 2018+ Tizen TVs

  IOWebSocketChannel? _channel;
  StreamSubscription? _subscription;
  TvDevice? device;

  final _stateController = StreamController<TvConnectionState>.broadcast();
  Stream<TvConnectionState> get stateStream => _stateController.stream;

  TvConnectionState _state = TvConnectionState.disconnected;
  TvConnectionState get state => _state;

  void _setState(TvConnectionState s) {
    debugPrint('[TV] state: $_state -> $s');
    _state = s;
    _stateController.add(s);
  }

  /// Loads a previously paired device (ip/name/mac/token) from local storage.
  /// Returns null if none was saved yet.
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
  }

  /// Connects (or reconnects) to the TV at [ip]. If a [token] is already
  /// known, it's sent along so the TV skips the on-screen pairing prompt.
  /// On first-ever connection, accept the prompt on the TV itself; the
  /// token arriving in the `ms.channel.connect` event is then persisted.
  Future<void> connect({
    required String ip,
    String name = 'TV',
    String? mac,
    String? token,
  }) async {
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

    // Samsung TVs use a self-signed certificate on the control port, so a
    // plain WebSocket.connect fails TLS verification. We accept it here
    // because we're talking to a device we already trust on the local
    // network.
    final client = HttpClient()
      ..badCertificateCallback = (cert, host, port) => true;

    try {
      final socket = await WebSocket.connect(
        uri.toString(),
        customClient: client,
      ).timeout(const Duration(seconds: 8));
      _channel = IOWebSocketChannel(socket);
      _setState(TvConnectionState.awaitingPairing);

      _subscription = _channel!.stream.listen(
        _handleMessage,
        onError: (_) => _setState(TvConnectionState.error),
        onDone: () => _setState(TvConnectionState.disconnected),
      );
    } catch (e) {
      _setState(TvConnectionState.error);
      rethrow;
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
      }
      _setState(TvConnectionState.connected);
    } else if (event == 'ms.channel.timeOut' ||
        event == 'ms.channel.unauthorized') {
      _setState(TvConnectionState.error);
    }
    // Other events (ms.remote.touchEnable, ms.error, etc.) can be handled
    // here as needed.
  }

  /// Sends a single remote-control key press, e.g. TvKey.volumeUp.
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

  /// Types [text] into whatever input field is currently focused/active on
  /// the TV's own screen (e.g. a search box the user has already tapped
  /// into). It does NOT open a keyboard by itself — there has to be a text
  /// field already active on the TV side, same as a physical remote's
  /// virtual keyboard input would require.
  ///
  /// Returns false without sending anything if there's no live connection,
  /// so the UI can tell the user instead of failing silently.
  /// Types [text] into whatever input field is currently focused/active on
  /// the TV's own screen (e.g. a search box the user has already tapped
  /// into). It does NOT open a keyboard by itself — there has to be a text
  /// field already active on the TV side, same as a physical remote's
  /// virtual keyboard input would require.
  ///
  /// Returns false without sending anything if there's no live connection,
  /// so the UI can tell the user instead of failing silently.
  bool sendText(String text) {
    if (_channel == null || _state != TvConnectionState.connected) {
      debugPrint(
        '[TV] sendText("$text") skipped — not connected (state=$_state)',
      );
      return false;
    }

    // A API da Samsung espera o texto puro, NÃO em base64.
    // O comando é sempre "sendText" e o TypeOfRemote é "SendInputString".
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

  Future<void> disconnect() async {
    await _subscription?.cancel();
    await _channel?.sink.close();
    _channel = null;
    _setState(TvConnectionState.disconnected);
  }

  void dispose() {
    _subscription?.cancel();
    _channel?.sink.close();
    _stateController.close();
  }
}
