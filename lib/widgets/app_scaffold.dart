import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../home.dart';
import '../devices.dart';
import '../login_page.dart';
import '../theme/rotala_brand.dart';
import '../ble/ble_manager.dart';

enum _BleSheetStep { pickDevice, provision, sending, success, failure }

class AppScaffold extends StatefulWidget {
  final int currentIndex;
  final String title;
  final Widget body;

  final String aquaspecNamePrefix;
  final Map<String, dynamic>? initialCredentials;

  const AppScaffold({
    super.key,
    required this.currentIndex,
    required this.title,
    required this.body,
    this.aquaspecNamePrefix = 'AquaSpec',
    this.initialCredentials,
  });

  @override
  State<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends State<AppScaffold> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _bleSheetOpen = false;

  Future<void> _linkDeviceToUser(String deviceUid) async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;

    if (uid == null) return;
    if (deviceUid.trim().isEmpty) return;

    // Important:
    // Do not write to public.devices from the client.
    // Many setups keep devices as a global registry locked behind RLS.
    // The client should only write the relationship row in user_devices.

    await client.from('user_devices').upsert(
      {
        'user_id': uid,
        'device_uid': deviceUid,
        'is_active': true,
        'connected_at': DateTime.now().toIso8601String(),
        'last_seen': DateTime.now().toIso8601String(),
      },
      onConflict: 'user_id,device_uid',
    );
  }

  Future<_DeviceStatus> _fetchDeviceStatus() async {
    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser?.id;
      if (uid == null) return const _DeviceStatus.unknown();

      final rows = await client
          .from('user_devices')
          .select('device_uid,is_active,last_seen,connected_at')
          .eq('user_id', uid)
          .eq('is_active', true)
          .order('last_seen', ascending: false)
          .order('connected_at', ascending: false)
          .limit(1);

      if (rows is List && rows.isNotEmpty) {
        final r = rows.first as Map<String, dynamic>;
        final lastSeenStr = r['last_seen']?.toString();
        final lastSeen = DateTime.tryParse(lastSeenStr ?? '');
        return _DeviceStatus(online: true, lastSeen: lastSeen);
      }

      return const _DeviceStatus.unknown();
    } catch (_) {
      return const _DeviceStatus.unknown();
    }
  }

  void _goTab(int index) {
    if (index == widget.currentIndex) {
      return;
    }

    if (index == 2 || index == 3) {
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Coming soon'),
          duration: Duration(milliseconds: 800),
        ),
      );
      return;
    }

    HapticFeedback.selectionClick();

    Widget page;
    switch (index) {
      case 0:
        page = const HomePage();
        break;
      case 1:
        page = const DevicesPage();
        break;
      default:
        page = const HomePage();
    }

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => page,
        transitionDuration: const Duration(milliseconds: 260),
        transitionsBuilder: (_, animation, __, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          final offsetAnimation = Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved);
          return SlideTransition(
            position: offsetAnimation,
            child: child,
          );
        },
      ),
    );
  }

  Future<void> _signOut() async {
    HapticFeedback.mediumImpact();

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }

    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  void _openBleSheet() {
    if (_bleSheetOpen) return;
    _bleSheetOpen = true;

    final ble = BleManager.I;
    StreamSubscription<DiscoveredDevice>? scanSub;

    final ssidCtrl = TextEditingController(
      text: (widget.initialCredentials?['ssid'] ?? '').toString(),
    );
    final passCtrl = TextEditingController(
      text: (widget.initialCredentials?['password'] ?? '').toString(),
    );
    final ssidFocus = FocusNode();

    bool scanning = false;
    bool busy = false;
    String status = 'Scan for your AquaSpec';
    String errorMsg = '';
    _BleSheetStep step = _BleSheetStep.pickDevice;

    List<DiscoveredDevice> devices = [];
    DiscoveredDevice? selected;

    bool isAquaSpec(DiscoveredDevice d) {
      final name = d.name.trim();
      if (name.isEmpty) return false;
      return name.startsWith(widget.aquaspecNamePrefix);
    }

    Future<bool> waitForConnected({Duration timeout = const Duration(seconds: 6)}) async {
      final start = DateTime.now();
      while (DateTime.now().difference(start) < timeout) {
        if (ble.isConnected) return true;
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      return ble.isConnected;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1f2937),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        Future<void> startScan(StateSetter setSheet) async {
          if (scanning || busy) return;

          setSheet(() {
            scanning = true;
            status = 'Scanning…';
            devices = [];
            errorMsg = '';
            step = _BleSheetStep.pickDevice;
          });

          final ok = await ble.ensurePermissions();
          if (!ok) {
            setSheet(() {
              scanning = false;
              status = 'Bluetooth permission denied';
              step = _BleSheetStep.failure;
              errorMsg = 'Please allow Bluetooth permissions in Settings.';
            });
            return;
          }

          await scanSub?.cancel();
          scanSub = ble.startScan(onlyAquaSpecUart: true).listen((d) {
            if (!isAquaSpec(d)) return;
            setSheet(() {
              if (!devices.any((x) => x.id == d.id)) {
                devices.add(d);
              }
            });
          }, onError: (e) {
            setSheet(() {
              scanning = false;
              status = 'Scan error';
              step = _BleSheetStep.failure;
              errorMsg = e.toString();
            });
          });
        }

        Future<void> stopScan(StateSetter setSheet) async {
          await scanSub?.cancel();
          setSheet(() {
            scanning = false;
            status = devices.isEmpty ? 'No AquaSpec found' : 'Scan stopped';
          });
        }

        Future<void> connectThenShowProvision(
          DiscoveredDevice d,
          StateSetter setSheet,
        ) async {
          if (busy) return;

          setSheet(() {
            busy = true;
            scanning = false;
            status = 'Connecting…';
            errorMsg = '';
          });

          await scanSub?.cancel();

          try {
            await ble.connect(d);

            final connected = await waitForConnected();
            if (!connected) {
              setSheet(() {
                busy = false;
                status = 'Could not connect';
                step = _BleSheetStep.failure;
                errorMsg = 'Try again with the device closer to your phone.';
              });
              return;
            }

            setSheet(() {
              busy = false;
              selected = d;
              step = _BleSheetStep.provision;
              status = 'Enter WiFi info';
            });

            await Future<void>.delayed(const Duration(milliseconds: 200));
            if (ssidCtrl.text.trim().isEmpty) {
              FocusScope.of(ctx).requestFocus(ssidFocus);
            }
          } catch (e) {
            setSheet(() {
              busy = false;
              status = 'Could not connect';
              step = _BleSheetStep.failure;
              errorMsg = e.toString();
            });
          }
        }

        Future<void> sendWifi(StateSetter setSheet) async {
          if (!ble.isConnected) {
            setSheet(() {
              step = _BleSheetStep.failure;
              status = 'Not connected';
              errorMsg = 'Please connect to your AquaSpec first.';
            });
            return;
          }

          final ssid = ssidCtrl.text.trim();
          final pass = passCtrl.text;

          if (ssid.isEmpty || pass.isEmpty) {
            setSheet(() {
              step = _BleSheetStep.failure;
              status = 'Missing info';
              errorMsg = 'WiFi name and password are required.';
            });
            return;
          }

          final userId = Supabase.instance.client.auth.currentUser?.id ?? '';

          setSheet(() {
            busy = true;
            step = _BleSheetStep.sending;
            status = 'Sending…';
            errorMsg = '';
          });

          try {
            final msg = 'PROVISION:$ssid|$pass|$userId||||';
            await ble.writeUtf8(msg);

            final deviceUid = selected?.id ?? '';
            await _linkDeviceToUser(deviceUid);

            setSheet(() {
              busy = false;
              step = _BleSheetStep.success;
              status = 'Sent';
            });

            await Future<void>.delayed(const Duration(milliseconds: 450));
            await ble.disconnect();

            if (!mounted) return;
            Navigator.of(context).pop();

            if (!mounted) return;
            setState(() {});

            _goTab(0);
          } on PostgrestException catch (e) {
            // Most common failure now is FK violation if devices row does not exist.
            // If that happens, you should ensure the AquaSpec registers itself into public.devices using service role.
            setSheet(() {
              busy = false;
              step = _BleSheetStep.failure;
              status = 'Send failed';
              errorMsg = e.message;
            });
          } catch (e) {
            setSheet(() {
              busy = false;
              step = _BleSheetStep.failure;
              status = 'Send failed';
              errorMsg = e.toString();
            });
          }
        }

        Widget header() {
          return Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text(
                'Connect AquaSpec',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                status,
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ],
          );
        }

        Widget devicePicker(StateSetter setSheet) {
          return Column(
            children: [
              const SizedBox(height: 14),
              if (busy || scanning)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: CircularProgressIndicator(),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Found ${devices.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (devices.isEmpty)
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.search, color: Colors.white70),
                  title: Text('No device yet', style: TextStyle(color: Colors.white)),
                  subtitle: Text(
                    'Turn AquaSpec on, then tap Scan',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                )
              else
                SizedBox(
                  height: 200,
                  child: ListView.builder(
                    itemCount: devices.length,
                    itemBuilder: (ctx, index) {
                      final d = devices[index];
                      final name = d.name.isEmpty ? 'AquaSpec' : d.name;
                      return Card(
                        color: const Color(0xFF111827),
                        child: ListTile(
                          title: Text(name, style: const TextStyle(color: Colors.white)),
                          subtitle: Text(
                            d.id,
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                          trailing: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: RotalaColors.teal,
                            ),
                            onPressed: busy ? null : () => connectThenShowProvision(d, setSheet),
                            child: const Text('Connect', style: TextStyle(fontSize: 13)),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: scanning ? const Color(0xFFFF6F4D) : RotalaColors.teal,
                  ),
                  icon: Icon(scanning ? Icons.stop : Icons.refresh, size: 18),
                  label: Text(scanning ? 'Stop' : 'Scan'),
                  onPressed: busy ? null : () => scanning ? stopScan(setSheet) : startScan(setSheet),
                ),
              ),
            ],
          );
        }

        Widget provisionForm(StateSetter setSheet) {
          final deviceName = selected?.name.isNotEmpty == true ? selected!.name : 'AquaSpec';

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 14),
              Card(
                color: const Color(0xFF111827),
                child: ListTile(
                  leading: const Icon(Icons.bluetooth_connected, color: Colors.tealAccent),
                  title: Text(deviceName, style: const TextStyle(color: Colors.white)),
                  subtitle: const Text(
                    'Connected',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                focusNode: ssidFocus,
                controller: ssidCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'WiFi name',
                  labelStyle: TextStyle(color: Colors.white70),
                  filled: true,
                  fillColor: Color(0xFF0b1220),
                  border: OutlineInputBorder(borderSide: BorderSide.none),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: passCtrl,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'WiFi password',
                  labelStyle: TextStyle(color: Colors.white70),
                  filled: true,
                  fillColor: Color(0xFF0b1220),
                  border: OutlineInputBorder(borderSide: BorderSide.none),
                ),
                onSubmitted: (_) => busy ? null : sendWifi(setSheet),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: RotalaColors.teal),
                  onPressed: busy ? null : () => sendWifi(setSheet),
                  child: const Text('Send'),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: busy
                    ? null
                    : () async {
                        await ble.disconnect();
                        setSheet(() {
                          step = _BleSheetStep.pickDevice;
                          status = 'Scan for your AquaSpec';
                          errorMsg = '';
                          selected = null;
                        });
                      },
                child: const Text('Back', style: TextStyle(color: Colors.white70)),
              ),
            ],
          );
        }

        Widget sendingState() {
          return Column(
            children: const [
              SizedBox(height: 18),
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Sending WiFi info…', style: TextStyle(color: Colors.white70)),
            ],
          );
        }

        Widget successState() {
          return Column(
            children: const [
              SizedBox(height: 18),
              Icon(Icons.check_circle, color: Colors.tealAccent, size: 48),
              SizedBox(height: 10),
              Text('Sent successfully', style: TextStyle(color: Colors.white70)),
            ],
          );
        }

        Widget errorState(StateSetter setSheet) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 14),
              Card(
                color: const Color(0xFF111827),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    errorMsg.isEmpty ? 'Something went wrong.' : errorMsg,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 46,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: RotalaColors.teal),
                  onPressed: () {
                    setSheet(() {
                      step = ble.isConnected ? _BleSheetStep.provision : _BleSheetStep.pickDevice;
                      status = ble.isConnected ? 'Enter WiFi info' : 'Scan for your AquaSpec';
                      errorMsg = '';
                    });
                  },
                  child: const Text('Try again'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () async {
                  await ble.disconnect();
                  if (!mounted) return;
                  Navigator.of(context).pop();
                },
                child: const Text('Close', style: TextStyle(color: Colors.white70)),
              ),
            ],
          );
        }

        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: StatefulBuilder(
            builder: (ctx, setSheet) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  header(),
                  if (step == _BleSheetStep.pickDevice) devicePicker(setSheet),
                  if (step == _BleSheetStep.provision) provisionForm(setSheet),
                  if (step == _BleSheetStep.sending) sendingState(),
                  if (step == _BleSheetStep.success) successState(),
                  if (step == _BleSheetStep.failure) errorState(setSheet),
                ],
              );
            },
          ),
        );
      },
    ).whenComplete(() async {
      _bleSheetOpen = false;
      await scanSub?.cancel();
      await ble.disconnect();
      ssidCtrl.dispose();
      passCtrl.dispose();
      ssidFocus.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFF0b1220),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0b1220),
        elevation: 0,
        leading: IconButton(
          tooltip: 'Menu',
          icon: const Icon(Icons.menu, color: Colors.white),
          onPressed: () {
            HapticFeedback.selectionClick();
            _scaffoldKey.currentState?.openDrawer();
          },
        ),
        title: Transform.translate(
          offset: const Offset(0, -4),
          child: Image.asset(
            'assets/brand/rotalanew2.png',
            height: 60,
            fit: BoxFit.contain,
          ),
        ),
        centerTitle: true,
        actions: [
          FutureBuilder<_DeviceStatus>(
            future: _fetchDeviceStatus(),
            builder: (context, snapshot) {
              final st = snapshot.data ?? const _DeviceStatus.unknown();
              final icon = st.online ? Icons.bluetooth_connected : Icons.bluetooth_disabled;
              final color = st.online ? RotalaColors.teal : Colors.white70;

              return IconButton(
                tooltip: st.online ? 'Device connected' : 'Connect your AquaSpec',
                icon: Icon(icon, color: color),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  if (_bleSheetOpen) return;
                  _openBleSheet();
                },
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: Drawer(
        backgroundColor: const Color(0xFF0b1220),
        child: SafeArea(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                color: const Color(0xFF111827),
                child: Row(
                  children: [
                    Image.asset(
                      'assets/brand/rotalalink.png',
                      height: 35,
                      fit: BoxFit.contain,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.white24),
              _DrawerItem(
                icon: Icons.home_rounded,
                label: 'Home',
                selected: widget.currentIndex == 0,
                onTap: () => _goTab(0),
              ),
              _DrawerItem(
                icon: Icons.smart_toy_rounded,
                label: 'RALA',
                selected: widget.currentIndex == 2,
                comingSoon: true,
                onTap: () => _goTab(2),
              ),
              _DrawerItem(
                icon: Icons.groups_rounded,
                label: 'Community',
                selected: widget.currentIndex == 3,
                comingSoon: true,
                onTap: () => _goTab(3),
              ),
              const Spacer(),
              const Divider(height: 1, color: Colors.white24),
              ListTile(
                leading: const Icon(Icons.logout_rounded, color: Colors.white70),
                title: const Text('Log out', style: TextStyle(color: Colors.white)),
                onTap: _signOut,
              ),
            ],
          ),
        ),
      ),
      body: widget.body,
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.label,
    this.comingSoon = false,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool comingSoon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? RotalaColors.teal : Colors.white70;
    final bg = selected ? const Color(0xFF111827) : Colors.transparent;

    return Material(
      color: bg,
      child: ListTile(
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color),
            if (comingSoon) ...[
              const SizedBox(width: 6),
              _comingSoonChip(),
            ],
          ],
        ),
        title: Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.of(context).pop();
          onTap();
        },
      ),
    );
  }

  Widget _comingSoonChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFFF6F4D),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'Soon',
        style: TextStyle(
          fontSize: 10,
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _DeviceStatus {
  final bool online;
  final DateTime? lastSeen;

  const _DeviceStatus({required this.online, this.lastSeen});
  const _DeviceStatus.unknown()
      : online = false,
        lastSeen = null;
}
