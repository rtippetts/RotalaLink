// lib/devices.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'widgets/app_scaffold.dart';
import 'ble/ble_manager.dart';

class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});
  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  final _ble = BleManager.I;
  final _sb = Supabase.instance.client;

  // BLE state
  StreamSubscription<DiscoveredDevice>? _scan;
  StreamSubscription<List<int>>? _notif;
  bool _scanning = false;
  bool _connecting = false;
  String _status = 'Disconnected';
  String _connectedName = '';
  String? _deviceUid; // app-assigned UID derived from BLE id
  String?
  _deviceName; // human-friendly name (stored in DB and optionally on device)

  // Setup state
  bool _provisionSent = false; // we sent Wi-Fi creds
  bool _deviceOnline = false; // detected via readings arriving in Supabase

  // UI helpers
  String _rxBuffer = '';
  final List<String> _rxLines = [];

  // Readings state
  Timer? _pollTimer;
  List<Map<String, dynamic>> _recent = [];

  // ---------- UID helpers ----------
  String _deriveDeviceUid(String bleId) {
    final hex = bleId.replaceAll(':', '').replaceAll('-', '').toUpperCase();
    return 'esp32-$hex';
  }

  // ---------- Devices table upsert ----------
  Future<void> _upsertDevice({String? name}) async {
    final user = _sb.auth.currentUser;
    if (user == null || _deviceUid == null) return;
    try {
      final row = {
        'device_uid': _deviceUid!,
        'owner_uid': user.id,
        'is_active': true,
        if (name != null) 'name': name,
      };
      await _sb.from('devices').upsert(row);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Device registry error: $e')));
    }
  }

  // ---------- Tanks -> device (names + ids) ----------
  Future<void> _sendTanksToDevice() async {
    try {
      final user = _sb.auth.currentUser;
      if (user == null) return;

      // fetch tanks owned by the user
      final rows = await _sb
          .from('tanks')
          .select('id,name')
          .order('name', ascending: true);

      final names = <String>[];
      final ids = <String>[];
      for (final r in rows) {
        final n = (r['name'] as String?)?.trim();
        final i = r['id'] as String?;
        if (n != null && n.isNotEmpty && i != null && i.isNotEmpty) {
          names.add(n);
          ids.add(i);
        }
      }
      if (names.isEmpty) {
        // harmless fallback
        names.addAll(['Tank A', 'Tank B', 'Tank C']);
        ids.addAll(['demo-a', 'demo-b', 'demo-c']);
      }

      await _ble.writeUtf8('SET_TANKS:${names.take(10).join('|')}');
      await _ble.writeUtf8('SET_TANK_IDS:${ids.take(10).join('|')}');
    } catch (_) {
      // non-fatal; device can still operate without the list
    }
  }

  // ---------- Provision Wi-Fi ----------
  Future<void> _openProvisionSheet() async {
    final ssidCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    bool _isProvisioning = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0f172a),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                left: 16,
                right: 16,
                top: 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Provision Wi-Fi',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Enter your 2.4GHz WiFi credentials. The device will reboot and connect automatically.',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 16),

                  // WiFi Network Selection
                  TextField(
                    controller: ssidCtrl,
                    decoration: const InputDecoration(
                      labelText: 'SSID (2.4 GHz)',
                      hintText: 'Your WiFi network name',
                      prefixIcon: Icon(Icons.wifi, color: Colors.white70),
                    ),
                    style: const TextStyle(color: Colors.white),
                    enabled: !_isProvisioning,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      hintText: 'WiFi password',
                      prefixIcon: Icon(Icons.lock, color: Colors.white70),
                    ),
                    style: const TextStyle(color: Colors.white),
                    obscureText: true,
                    enabled: !_isProvisioning,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          icon:
                              _isProvisioning
                                  ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                  : const Icon(Icons.wifi),
                          label: Text(
                            _isProvisioning ? 'Sending...' : 'Send to device',
                          ),
                          onPressed:
                              _isProvisioning
                                  ? null
                                  : () async {
                                    print(
                                      'Button pressed - starting validation',
                                    );
                                    final ssid = ssidCtrl.text.trim();
                                    final pass = passCtrl.text.trim();
                                    final duid = _deviceUid;

                                    print(
                                      'SSID: "$ssid", PASS: "$pass", DUID: "$duid"',
                                    );

                                    if (ssid.isEmpty ||
                                        pass.isEmpty ||
                                        duid == null) {
                                      print(
                                        'Validation failed: empty fields or no device UID',
                                      );
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Enter SSID & password (and be connected)',
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    if (ssid.contains('|') ||
                                        pass.contains('|')) {
                                      print(
                                        'Validation failed: contains pipe character',
                                      );
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'SSID/password cannot contain "|"',
                                          ),
                                        ),
                                      );
                                      return;
                                    }

                                    print(
                                      'Validation passed, proceeding with provisioning',
                                    );

                                    setModalState(() => _isProvisioning = true);

                                    // Get Supabase credentials (matching main.dart)
                                    final supabaseUrl =
                                        'https://dbfglovgjuzqiejekflg.supabase.co';
                                    final supabaseKey =
                                        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRiZmdsb3ZnanV6cWllamVrZmxnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDM4ODI2NzQsImV4cCI6MjA1OTQ1ODY3NH0.mzRht4dDiCC9GQlX_5c1K_UJKWXvKeAHPBHqBVNsHvU';

                                    // PROVISION:SSID|PASS|DEVICE_UID|SUPABASE_URL|SUPABASE_KEY
                                    final cmd =
                                        'PROVISION:$ssid|$pass|$duid|$supabaseUrl|$supabaseKey\n';

                                    // Debug: Print all values being sent
                                    print('=== PROVISION DEBUG ===');
                                    print('SSID: "$ssid"');
                                    print('PASS: "$pass"');
                                    print('DUID: "$duid"');
                                    print('SUPABASE_URL: "$supabaseUrl"');
                                    print(
                                      'SUPABASE_KEY: "${supabaseKey.substring(0, 20)}..."',
                                    );
                                    print('FULL COMMAND: $cmd');
                                    print('COMMAND LENGTH: ${cmd.length}');
                                    print('=======================');

                                    try {
                                      print('Sending PROVISION command...');
                                      await _ble.writeUtf8(cmd);
                                      print(
                                        'PROVISION command sent successfully',
                                      );
                                      setState(() => _provisionSent = true);
                                      if (mounted) {
                                        Navigator.of(ctx).pop();
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              '✅ WiFi credentials sent! Device will reboot and connect automatically.',
                                            ),
                                            backgroundColor: Colors.green,
                                          ),
                                        );
                                      }

                                      // After provisioning, begin polling for device to come online
                                      _startPollingReadings();
                                    } catch (e) {
                                      setModalState(
                                        () => _isProvisioning = false,
                                      );
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            '❌ Provision failed: $e',
                                          ),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  },
                        ),
                      ),
                      const SizedBox(width: 12),
                      TextButton(
                        onPressed:
                            _isProvisioning
                                ? null
                                : () => Navigator.of(ctx).pop(),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ---------- Name device ----------
  Future<void> _openNameDeviceDialog() async {
    final ctrl = TextEditingController(text: _deviceName ?? '');
    final newName = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Name your device'),
            content: TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                hintText: 'e.g. Living Room Probe',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                child: const Text('Save'),
              ),
            ],
          ),
    );
    if (newName == null || newName.isEmpty) return;

    // Send to device (optional persistence on firmware side)
    try {
      await _ble.writeUtf8('SET_NAME:$newName\n');
    } catch (_) {}

    // Save to DB
    _deviceName = newName;
    await _upsertDevice(name: _deviceName);
    if (!mounted) return;
    setState(() {});
  }

  // ---------- Readings polling ----------
  void _startPollingReadings() {
    _pollTimer?.cancel();
    if (_deviceUid == null) return;

    // poll immediately and then every 10s
    Future<void> poll() async {
      try {
        final rows = await _sb
            .from('sensor_readings')
            .select('device_uid, tank_id, temperature, ph, tds, recorded_at')
            .eq('device_uid', _deviceUid!)
            .order('recorded_at', ascending: false)
            .limit(20);
        final list = List<Map<String, dynamic>>.from(rows);
        if (mounted) {
          setState(() {
            _recent = list;
            _deviceOnline = _recent.isNotEmpty; // heuristic: readings exist
          });
        }
      } catch (_) {
        // ignore transient errors
      }
    }

    poll();
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) => poll());
  }

  // ---------- BLE RX framing ----------
  Future<void> _handleIncomingText(String chunk) async {
    _rxBuffer += chunk;
    int nl;
    while ((nl = _rxBuffer.indexOf('\n')) != -1) {
      final line = _rxBuffer.substring(0, nl).trimRight();
      _rxBuffer = _rxBuffer.substring(nl + 1);
      if (line.isEmpty) continue;

      setState(() {
        _rxLines.insert(0, line);
        if (_rxLines.length > 40) _rxLines.removeLast();
      });

      // If device prints explicit success lines, we could flip flags here
      // e.g., if (line.startsWith("Supabase POST -> 20")) _deviceOnline = true;
    }
  }

  // ---------- Scan & connect ----------
  Future<void> _startScanAndPick() async {
    if (_scanning || _connecting) return;

    setState(() => _status = 'Requesting permissions…');
    if (!await _ble.ensurePermissions()) {
      setState(() => _status = 'Bluetooth permission denied');
      return;
    }

    setState(() {
      _status = 'Scanning…';
      _scanning = true;
    });

    final found = <String, DiscoveredDevice>{};
    void Function()? sheetRedraw;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0f172a),
      isScrollControlled: true,
      builder: (_) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            sheetRedraw = () => setSheetState(() {});
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.66,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const ListTile(
                      title: Text(
                        'Select your device',
                        style: TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        'Scanning…',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                    const Divider(height: 1, color: Colors.white12),
                    Expanded(
                      child:
                          found.isEmpty
                              ? const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Text(
                                    'No devices yet… keep scanning',
                                    style: TextStyle(color: Colors.white54),
                                  ),
                                ),
                              )
                              : ListView(
                                children:
                                    found.values.map((d) {
                                      final title =
                                          d.name.isEmpty ? d.id : d.name;
                                      return ListTile(
                                        title: Text(
                                          title,
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                        ),
                                        subtitle: Text(
                                          'RSSI: ${d.rssi}',
                                          style: const TextStyle(
                                            color: Colors.white70,
                                          ),
                                        ),
                                        onTap: () async {
                                          Navigator.of(ctx).pop();
                                          await _connectTo(d);
                                        },
                                      );
                                    }).toList(),
                              ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() async {
      await _ble.stopScan();
      await _scan?.cancel();
      if (mounted) setState(() => _scanning = false);
    });

    _scan?.cancel();
    _scan = _ble.startScan().listen(
      (d) {
        found[d.id] = d;
        sheetRedraw?.call();
      },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _status = 'Scan error: $e';
          _scanning = false;
        });
      },
    );
  }

  Future<void> _connectTo(DiscoveredDevice d) async {
    if (_connecting) return;
    setState(() {
      _connecting = true;
      _status = 'Connecting to ${d.name.isEmpty ? d.id : d.name}…';
    });

    try {
      print('Starting connection process...');
      await _ble.stopScan();
      print('Scan stopped');
      await _scan?.cancel();
      print('Scan cancelled');

      print('Calling _ble.connect()...');
      await _ble.connect(d);
      print('BLE connect() completed. isConnected: ${_ble.isConnected}');

      // Always set device info after connection attempt
      _connectedName = d.name.isNotEmpty ? d.name : d.id;
      _deviceUid = _deriveDeviceUid(d.id);
      print('Device info set! Name: $_connectedName, UID: $_deviceUid');

      if (_ble.isConnected) {
        print('Device connected! Name: $_connectedName, UID: $_deviceUid');

        // Enable notifications (required for ESP32)
        try {
          await _ble.enableNotifications();
          print('Notifications enabled successfully');
        } catch (e) {
          print('Failed to enable notifications: $e');
        }

        // Upsert device (owner + active). We'll add name later if user sets it.
        unawaited(_upsertDevice());
      }

      setState(() {
        _status = 'Connected to $_connectedName';
        _connecting = false;
        _scanning = false;
      });

      // Subscribe to notifications
      _rxBuffer = '';
      await _notif?.cancel();
      _notif = _ble.notifications().listen(
        (bytes) async {
          final text = String.fromCharCodes(bytes);
          // ignore: avoid_print
          print('[BLE RX] ${text.replaceAll('\n', r'\n')}');
          await _handleIncomingText(text);
        },
        onError: (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Communication error: $e'),
              backgroundColor: Colors.red,
            ),
          );
        },
      );

      // Send tanks to device for its menu
      unawaited(_sendTanksToDevice());

      // Start readings polling (in case device was already online)
      _startPollingReadings();

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Connected to $_connectedName'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Connection error: $e');
      setState(() {
        _status = 'Failed to connect';
        _connecting = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Failed to connect to device'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _disconnect() async {
    _pollTimer?.cancel();
    await _notif?.cancel();
    await _scan?.cancel();
    await _ble.stopScan();
    await _ble.disconnect();

    if (!mounted) return;
    setState(() {
      _status = 'Disconnected';
      _scanning = false;
      _connecting = false;
      _connectedName = '';
      _deviceUid = null;
      _deviceName = null;
      _rxBuffer = '';
      _rxLines.clear();
      _provisionSent = false;
      _deviceOnline = false;
      _recent.clear();
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Disconnected')));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _notif?.cancel();
    _scan?.cancel();
    _ble.stopScan();
    super.dispose();
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final connected = _ble.isConnected;

    return AppScaffold(
      currentIndex: 1,
      title: 'Devices',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!connected) ...[
            Text(_status, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.bluetooth_searching),
              label: const Text('Connect Bluetooth Device'),
              onPressed: _startScanAndPick,
            ),
          ] else ...[
            // Connected over BLE
            if (!_deviceOnline) ...[
              Card(
                color: const Color(0xFF1f2937),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.bluetooth_connected,
                              color: Colors.blueAccent,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Device Connected',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Connected to $_connectedName',
                                  style: const TextStyle(color: Colors.white70),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (_deviceUid != null)
                                  Text(
                                    'UID: $_deviceUid',
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.orange.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.wifi_off,
                              color: Colors.orange,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Device needs WiFi setup to send readings to cloud',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            icon: const Icon(Icons.wifi),
                            label: const Text('Setup WiFi'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: _openProvisionSheet,
                          ),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.edit),
                            label: const Text('Name Device'),
                            onPressed: _openNameDeviceDialog,
                          ),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.link_off),
                            label: const Text('Disconnect'),
                            onPressed: _disconnect,
                          ),
                        ],
                      ),
                      if (_provisionSent) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.green.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.green,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'WiFi credentials sent! Device is rebooting and connecting...',
                                  style: TextStyle(
                                    color: Colors.green,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // small device log (optional)
              if (_rxLines.isNotEmpty) ...[
                const Text(
                  'Device messages',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                ..._rxLines
                    .take(8)
                    .map(
                      (s) => Column(
                        children: [
                          ListTile(
                            dense: true,
                            title: Text(
                              s,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          const Divider(color: Colors.white12, height: 1),
                        ],
                      ),
                    ),
              ],
            ] else ...[
              // Online (readings are coming to Supabase)
              Card(
                color: const Color(0xFF1f2937),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.cloud_done,
                              color: Colors.greenAccent,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Device Online',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Sending readings to cloud',
                                  style: TextStyle(
                                    color: Colors.green,
                                    fontSize: 14,
                                  ),
                                ),
                                if (_deviceName != null &&
                                    _deviceName!.isNotEmpty)
                                  Text(
                                    'Name: $_deviceName',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                if (_deviceUid != null)
                                  Text(
                                    'UID: $_deviceUid',
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.green.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.wifi,
                              color: Colors.green,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Device is connected to WiFi and sending sensor data',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.link_off),
                        label: const Text('Disconnect'),
                        onPressed: _disconnect,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Recent readings',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              if (_recent.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'No readings yet',
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              else
                ..._recent.map((r) {
                  final dt = DateTime.tryParse(
                    r['recorded_at']?.toString() ?? '',
                  );
                  final when = dt != null ? '${dt.toLocal()}' : '';
                  final ph = (r['ph'] as num?)?.toStringAsFixed(2) ?? '--';
                  final tds = (r['tds'] as num?)?.toString() ?? '--';
                  final tf =
                      (r['temperature'] as num?)?.toStringAsFixed(1) ?? '--';
                  return Column(
                    children: [
                      ListTile(
                        title: Text(
                          'pH $ph • TDS $tds ppm • Temp $tf °F',
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          when,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                      const Divider(color: Colors.white12, height: 1),
                    ],
                  );
                }),
            ],
          ],
        ],
      ),
    );
  }
}
