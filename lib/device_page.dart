import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'ble/ble_manager.dart';

class DevicePage extends StatefulWidget {
  const DevicePage({super.key});

  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  final _ble = BleManager.I;
  Stream<DiscoveredDevice>? _scanStream;
  final _found = <String, DiscoveredDevice>{};
  Stream<List<int>>? _notifStream;
  String _status = 'Disconnected';

  @override
  void initState() {
    super.initState();
  }

  Future<void> _startScan() async {
    final ok = await _ble.ensurePermissions();
    if (!ok) {
      setState(() => _status = 'Bluetooth permissions denied');
      return;
    }
    _found.clear();
    _scanStream = _ble.startScan();
    _scanStream!.listen((d) {
      setState(() {
        _found[d.id] = d;
      });
    }, onError: (e) {
      setState(() => _status = 'Scan error: $e');
    });
  }

  Future<void> _connect(DiscoveredDevice d) async {
    await _ble.stopScan();
    setState(() => _status = 'Connecting to ${d.name.isEmpty ? d.id : d.name}…');
    await _ble.connect(d);                     // <-- change here
    if (_ble.isConnected) {
      setState(() => _status = 'Connected: ${_ble.connectedName ?? d.name}');
      _notifStream = _ble.notifications();
      _notifStream!.listen((data) {
        final text = String.fromCharCodes(data);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('From device: $text')),
        );
      });
    } else {
      setState(() => _status = 'Failed to connect');
    }
  }


  Future<void> _disconnect() async {
    await _ble.disconnect();
    setState(() {
      _status = 'Disconnected';
      _notifStream = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        title: const Text('Device'),
        actions: [
          if (_ble.isConnected)
            IconButton(
              icon: const Icon(Icons.link_off),
              onPressed: _disconnect,
              tooltip: 'Disconnect',
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_status, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            if (!_ble.isConnected) ...[
              ElevatedButton.icon(
                onPressed: _startScan,
                icon: const Icon(Icons.search),
                label: const Text('Scan for ESP32'),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  children: _found.values.map((d) {
                    final title = d.name.isEmpty ? d.id : d.name;
                    return Card(
                      color: const Color(0xFF1f2937),
                      child: ListTile(
                        title: Text(title, style: const TextStyle(color: Colors.white)),
                        subtitle: Text('RSSI: ${d.rssi}', style: const TextStyle(color: Colors.white70)),
                        onTap: () => _connect(d),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ] else ...[
              const Text('Send a test command:', style: TextStyle(color: Colors.white)),
              const SizedBox(height: 8),
              Row(
                children: [
                  ElevatedButton(
                    onPressed: () => BleManager.I.writeUtf8('PING\n'),
                    child: const Text('PING'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _disconnect,
                    child: const Text('Disconnect'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
