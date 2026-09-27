import 'package:flutter/material.dart';

import '../core/tv_connection_service.dart';
import '../core/tv_key_codes.dart';
import '../core/wake_on_lan_service.dart';
import '../models/tv_device.dart';
import '../widgets/dpad.dart';
import '../widgets/volume_channel_rocker.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';

class RemoteScreen extends StatefulWidget {
  const RemoteScreen({super.key});

  @override
  State<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends State<RemoteScreen> {
  final _service = TvConnectionService();
  final _textController = TextEditingController();
  TvConnectionState _state = TvConnectionState.disconnected;
  TvDevice? _device;

  @override
  void initState() {
    super.initState();
    _service.stateStream.listen((s) => setState(() => _state = s));
    _init();
  }

  Future<void> _init() async {
    final saved = await _service.loadSavedDevice();

    // Fallback values come from .env (gitignored).
    final defaultIp = dotenv.env['TV_DEFAULT_IP'] ?? '';
    final defaultMac = dotenv.env['TV_DEFAULT_MAC'];
    final defaultName = dotenv.env['TV_DEFAULT_NAME'] ?? 'TV';

    _device =
        saved ?? TvDevice(ip: defaultIp, name: defaultName, mac: defaultMac);
    _connect();
  }

  Future<void> _connect() async {
    final d = _device!;
    try {
      await _service.connect(
        ip: d.ip,
        name: d.name,
        mac: d.mac,
        token: d.token,
      );
    } catch (_) {}
  }

  Future<void> _powerPressed() async {
    // If we're already connected, just send the power key.
    if (_state == TvConnectionState.connected) {
      _service.sendKey(TvKey.power);
      return;
    }

    // Otherwise, try to wake the TV.
    if (_device?.mac == null) return;

    debugPrint('[APP] Sending Wake-on-LAN to ${_device!.mac}');
    await WakeOnLanService.wake(_device!.mac!);

    // Retry connecting for up to ~30 seconds.
    for (int attempt = 0; attempt < 10; attempt++) {
      await Future.delayed(const Duration(seconds: 3));
      debugPrint('[APP] Connect attempt ${attempt + 1}/10');
      await _connect();

      if (_state == TvConnectionState.connected) {
        debugPrint('[APP] TV is up after ${(attempt + 1) * 3}s');
        return;
      }
    }

    debugPrint('[APP] Gave up after 30s — TV did not respond to WoL');
  }

  void _sendText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final sent = _service.sendText(text);
    if (!sent) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('TV desconectada — não foi possível enviar o texto'),
          ),
        );
      }
      return;
    }

    await Future.delayed(const Duration(milliseconds: 500));
    _service.sendKey(TvKey.enter);
    _textController.clear();
  }

  @override
  void dispose() {
    _service.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final darkTheme = ThemeData.dark().copyWith(
      scaffoldBackgroundColor: const Color(0xFF0F0F0F),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1A1A1A),
        elevation: 0,
        centerTitle: true,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1A1A1A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );

    return Theme(
      data: darkTheme,
      child: Scaffold(
        appBar: AppBar(title: Text(_device?.name ?? 'TV remote')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              children: [
                _buildStatusBanner(),
                const SizedBox(height: 24),
                _buildQuickRow(),
                const SizedBox(height: 24),
                DpadWidget(
                  onUp: () => _service.sendKey(TvKey.up),
                  onDown: () => _service.sendKey(TvKey.down),
                  onLeft: () => _service.sendKey(TvKey.left),
                  onRight: () => _service.sendKey(TvKey.right),
                  onOk: () => _service.sendKey(TvKey.enter),
                ),
                const SizedBox(height: 24),
                VolumeChannelRockerWidget(
                  onVolumeUp: () => _service.sendKey(TvKey.volumeUp),
                  onVolumeDown: () => _service.sendKey(TvKey.volumeDown),
                  onChannelUp: () => _service.sendKey(TvKey.channelUp),
                  onChannelDown: () => _service.sendKey(TvKey.channelDown),
                  onMute: () => _service.sendKey(TvKey.mute),
                ),
                const SizedBox(height: 24),
                _buildTextInput(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBanner() {
    late final String label;
    late final Color color;
    switch (_state) {
      case TvConnectionState.connected:
        label = 'Conectado';
        color = Colors.green;
        break;
      case TvConnectionState.connecting:
        label = 'Conectando...';
        color = Colors.orange;
        break;
      case TvConnectionState.awaitingPairing:
        label = 'Confirme o pareamento na TV';
        color = Colors.orange;
        break;
      case TvConnectionState.error:
        label = 'Falha na conexão';
        color = Colors.red;
        break;
      case TvConnectionState.disconnected:
        label = 'Desconectado';
        color = Colors.grey;
        break;
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 14)),
        if (_state == TvConnectionState.error) ...[
          const SizedBox(width: 12),
          TextButton(
            onPressed: _connect,
            child: const Text('Tentar de novo', style: TextStyle(fontSize: 12)),
          ),
        ],
      ],
    );
  }

  Widget _buildQuickRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _circleButton(
          Icons.power_settings_new,
          _powerPressed,
          color: Colors.redAccent,
          isOutlined: true,
        ),
        _circleButton(Icons.home, () => _service.sendKey(TvKey.home)),
        _circleButton(Icons.input, () => _service.sendKey(TvKey.source)),
        _circleButton(Icons.undo, () => _service.sendKey(TvKey.back)),
      ],
    );
  }

  Widget _buildTextInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _textController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Digitar na TV...',
                  hintStyle: TextStyle(color: Colors.grey),
                  suffixIcon: Icon(Icons.send, color: Colors.grey),
                ),
                onSubmitted: (_) => _sendText(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Funciona só com um campo de texto já ativo na TV.',
          style: TextStyle(color: Colors.grey[600], fontSize: 12),
        ),
      ],
    );
  }

  Widget _circleButton(
    IconData icon,
    VoidCallback onPressed, {
    Color? color,
    bool isOutlined = false,
  }) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isOutlined ? Colors.transparent : const Color(0xFF1E1E1E),
        border: isOutlined
            ? Border.all(color: Colors.grey[800]!, width: 1.5)
            : null,
      ),
      child: IconButton(
        icon: Icon(icon, color: color ?? Colors.grey[400]),
        onPressed: onPressed,
        iconSize: 24,
      ),
    );
  }
}
