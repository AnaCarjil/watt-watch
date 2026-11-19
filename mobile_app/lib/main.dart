import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:uuid/uuid.dart';

void main() {
  runApp(const WattWatchApp());
}

class WattWatchApp extends StatelessWidget {
  const WattWatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WattWatch',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}

// ---------------------------------------------------------------------------
// FR-01: Login & Registration Screen
// ---------------------------------------------------------------------------
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController(text: 'household@wattwatch.eu');
  final _passwordController = TextEditingController(text: 'password123');
  final _homeIdController = TextEditingController(
    text: 'a767571d-c939-434b-9eaf-aec32dc1291d',
  );
  bool _isRegister = false;
  String? _errorMessage;

  void _submit() {
    final email = _emailController.text.trim();
    final pass = _passwordController.text;
    final homeId = _homeIdController.text.trim();

    if (email.isEmpty || !email.contains('@') || pass.length < 6) {
      setState(() {
        _errorMessage = 'Invalid credentials: enter a valid email and 6+ char password.';
        _passwordController.clear(); // AC-03
      });
      return;
    }
    if (homeId.isEmpty) {
      setState(() => _errorMessage = 'Please enter the Home ID from the simulator.');
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => DashboardScreen(userEmail: email, homeId: homeId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isRegister ? 'WattWatch – Register' : 'WattWatch – Sign In')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.bolt, size: 64, color: Colors.teal),
                const SizedBox(height: 16),
                TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _homeIdController,
                  decoration: const InputDecoration(
                    labelText: 'Simulator Home ID (UUID)',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _submit,
                  child: Text(_isRegister ? 'Create Account' : 'Log In'),
                ),
                TextButton(
                  onPressed: () => setState(() => _isRegister = !_isRegister),
                  child: Text(_isRegister
                      ? 'Already have an account? Log In'
                      : 'Need an account? Register'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Device Model
// ---------------------------------------------------------------------------
class SmartDevice {
  final String deviceId;
  String name;
  String type;
  String state; // 'on', 'off', 'offline'
  double watts;
  DateTime? lastSeen;
  bool pendingCommand;

  SmartDevice({
    required this.deviceId,
    required this.name,
    required this.type,
    this.state = 'offline',
    this.watts = 0.0,
    this.lastSeen,
    this.pendingCommand = false,
  });
}

// ---------------------------------------------------------------------------
// FR-02, FR-03, FR-07: Live Dashboard, Remote Control & Device Management
// ---------------------------------------------------------------------------
class DashboardScreen extends StatefulWidget {
  final String userEmail;
  final String homeId;

  const DashboardScreen({super.key, required this.userEmail, required this.homeId});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late MqttServerClient _client;
  bool _brokerConnected = false;
  bool _showReconnectedBanner = false;
  Timer? _watchdogTimer;
  final Map<String, Timer> _pendingCmdTimers = {};
  final Map<String, String> _pendingCmdPrevState = {};

  final Map<String, SmartDevice> _devices = {
    'dev-fridge-01': SmartDevice(deviceId: 'dev-fridge-01', name: 'Fridge', type: 'fridge'),
    'dev-kettle-02': SmartDevice(deviceId: 'dev-kettle-02', name: 'Kettle', type: 'kettle'),
    'dev-tv-03': SmartDevice(deviceId: 'dev-tv-03', name: 'Living Room TV', type: 'tv'),
    'dev-washer-04': SmartDevice(deviceId: 'dev-washer-04', name: 'Washing Machine', type: 'washer'),
    'dev-laptop-05': SmartDevice(deviceId: 'dev-laptop-05', name: 'Laptop Charger', type: 'charger'),
  };

  @override
  void initState() {
    super.initState();
    _connectMqtt();
    // AC-07: Check every 2s if any device hasn't published for >15s while broker is connected
    _watchdogTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_brokerConnected) return;
      final now = DateTime.now();
      bool changed = false;
      for (final dev in _devices.values) {
        if (dev.state != 'offline' &&
            dev.lastSeen != null &&
            now.difference(dev.lastSeen!).inSeconds > 15) {
          dev.state = 'offline';
          changed = true;
        }
      }
      if (changed && mounted) setState(() {});
    });
  }

  Future<void> _connectMqtt() async {
    final clientId = 'wattwatch_app_${const Uuid().v4().substring(0, 8)}';
    _client = MqttServerClient('broker.hivemq.com', clientId);
    _client.port = 1883;
    _client.keepAlivePeriod = 20;
    _client.autoReconnect = true; // NFR-05
    _client.onConnected = _onMqttConnected;
    _client.onDisconnected = _onMqttDisconnected;
    _client.onAutoReconnected = _onMqttReconnected;

    try {
      await _client.connect();
    } catch (e) {
      if (mounted) setState(() => _brokerConnected = false);
    }
  }

  void _onMqttConnected() {
    if (!mounted) return;
    setState(() => _brokerConnected = true);
    _client.subscribe('wattwatch/${widget.homeId}/#', MqttQos.atMostOnce);
    _client.updates?.listen(_onMqttMessage);
  }

  void _onMqttDisconnected() {
    if (!mounted) return;
    setState(() => _brokerConnected = false); // AC-08
  }

  void _onMqttReconnected() {
    if (!mounted) return;
    setState(() {
      _brokerConnected = true;
      _showReconnectedBanner = true; // AC-09
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showReconnectedBanner = false);
    });
  }

  void _onMqttMessage(List<MqttReceivedMessage<MqttMessage>> events) {
    for (final event in events) {
      final topic = event.topic;
      final parts = topic.split('/');
      if (parts.length != 4 || parts[0] != 'wattwatch' || parts[1] != widget.homeId) {
        continue; // AC-35: Ignore topics outside user's homeId
      }
      final devId = parts[2];
      final channel = parts[3];
      final dev = _devices[devId];
      if (dev == null) continue;

      final recMess = event.payload as MqttPublishMessage;
      final payloadStr = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);

      try {
        final data = jsonDecode(payloadStr) as Map<String, dynamic>;
        if (!mounted) return;
        setState(() {
          dev.lastSeen = DateTime.now();
          if (channel == 'power') {
            dev.watts = (data['watts'] as num).toDouble();
            if (dev.state == 'offline') {
              dev.state = dev.watts > 0 ? 'on' : 'off';
            }
          } else if (channel == 'status') {
            dev.state = data['state'] as String;
            if (dev.state == 'off' || dev.state == 'offline') dev.watts = 0.0;
          } else if (channel == 'ack') {
            final cmdId = data['cmdId'] as String?;
            final newState = data['state'] as String;
            if (cmdId != null && _pendingCmdTimers.containsKey(cmdId)) {
              _pendingCmdTimers[cmdId]?.cancel();
              _pendingCmdTimers.remove(cmdId);
              _pendingCmdPrevState.remove(cmdId);
            }
            dev.pendingCommand = false;
            dev.state = newState;
            if (newState == 'off') dev.watts = 0.0;
          }
        });
      } catch (_) {}
    }
  }

  // FR-03: Send command with 5s timeout rollback (AC-12)
  void _toggleDevice(SmartDevice dev, bool turnOn) {
    if (!_brokerConnected || dev.state == 'offline' || dev.pendingCommand) return;

    final cmdId = const Uuid().v4();
    final action = turnOn ? 'on' : 'off';
    final prevState = dev.state;

    setState(() {
      dev.pendingCommand = true;
    });

    _pendingCmdPrevState[cmdId] = prevState;
    _pendingCmdTimers[cmdId] = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() {
        dev.state = _pendingCmdPrevState[cmdId] ?? prevState;
        dev.pendingCommand = false;
      });
      _pendingCmdTimers.remove(cmdId);
      _pendingCmdPrevState.remove(cmdId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Command failed: ${dev.name} did not respond within 5s')),
      );
    });

    final builder = MqttClientPayloadBuilder();
    builder.addString(jsonEncode({'cmdId': cmdId, 'action': action}));
    _client.publishMessage(
      'wattwatch/${widget.homeId}/${dev.deviceId}/cmd',
      MqttQos.atLeastOnce,
      builder.payload!,
    );
  }

  // FR-07: Add Device Modal (AC-14)
  void _showAddDeviceDialog() {
    final idCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    String selectedType = 'plug';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Device'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: idCtrl,
              decoration: const InputDecoration(labelText: 'Simulator Device ID (e.g. dev-lamp-06)'),
            ),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Device Name'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: selectedType,
              items: const [
                DropdownMenuItem(value: 'plug', child: Text('Smart Plug')),
                DropdownMenuItem(value: 'fridge', child: Text('Fridge')),
                DropdownMenuItem(value: 'kettle', child: Text('Kettle')),
                DropdownMenuItem(value: 'tv', child: Text('TV')),
              ],
              onChanged: (v) => selectedType = v ?? 'plug',
              decoration: const InputDecoration(labelText: 'Device Type'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final id = idCtrl.text.trim();
              final name = nameCtrl.text.trim();
              if (id.isNotEmpty && name.isNotEmpty) {
                setState(() {
                  _devices[id] = SmartDevice(deviceId: id, name: name, type: selectedType);
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  // FR-07: Rename or Delete Device (AC-15, AC-16)
  void _showEditDeviceDialog(SmartDevice dev) {
    final nameCtrl = TextEditingController(text: dev.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Manage ${dev.name}'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(labelText: 'Device Name'),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () {
              setState(() => _devices.remove(dev.deviceId));
              Navigator.pop(ctx);
            },
            child: const Text('Remove Device'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (nameCtrl.text.trim().isNotEmpty) {
                setState(() => dev.name = nameCtrl.text.trim());
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  double get _totalWatts {
    // AC-06: Sum of current power of all devices that are ON
    return _devices.values
        .where((d) => d.state == 'on')
        .fold(0.0, (sum, d) => sum + d.watts);
  }

  @override
  void dispose() {
    _watchdogTimer?.cancel();
    for (final t in _pendingCmdTimers.values) {
      t.cancel();
    }
    _client.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deviceList = _devices.values.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('WattWatch Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDeviceDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add Device'),
      ),
      body: Column(
        children: [
          // AC-08: Broker disconnection banner
          if (!_brokerConnected)
            Container(
              width: double.infinity,
              color: Colors.red.shade700,
              padding: const EdgeInsets.all(10),
              child: const Text(
                'Connection lost — reconnecting to MQTT broker...',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          // AC-09: Connection restored green banner
          if (_showReconnectedBanner)
            Container(
              width: double.infinity,
              color: Colors.green.shade700,
              padding: const EdgeInsets.all(10),
              child: const Text(
                'Connection restored',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          // AC-06: Total Household Power Card
          Card(
            margin: const EdgeInsets.all(16),
            color: Colors.teal.shade50,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Total Household Power', style: TextStyle(fontSize: 16)),
                      Text(
                        '${_totalWatts.toStringAsFixed(1)} W',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal,
                        ),
                      ),
                    ],
                  ),
                  const Icon(Icons.electric_bolt, size: 48, color: Colors.teal),
                ],
              ),
            ),
          ),
          // FR-02: Device Cards
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: deviceList.length,
              itemBuilder: (ctx, idx) {
                final dev = deviceList[idx];
                final isOffline = dev.state == 'offline';
                final isOn = dev.state == 'on';

                return Card(
                  color: isOffline ? Colors.grey.shade200 : null,
                  child: ListTile(
                    onTap: () => _showEditDeviceDialog(dev),
                    leading: Icon(
                      Icons.power,
                      color: isOffline ? Colors.grey : (isOn ? Colors.teal : Colors.black45),
                    ),
                    title: Text(
                      dev.name,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isOffline ? Colors.grey : null,
                      ),
                    ),
                    subtitle: Text(
                      isOffline
                          ? 'Offline${dev.lastSeen != null ? " • Last seen ${dev.lastSeen!.hour.toString().padLeft(2, '0')}:${dev.lastSeen!.minute.toString().padLeft(2, '0')}:${dev.lastSeen!.second.toString().padLeft(2, '0')}" : ""}'
                          : '${dev.state.toUpperCase()} • ${dev.watts.toStringAsFixed(1)} W',
                      style: TextStyle(color: isOffline ? Colors.grey : null),
                    ),
                    trailing: dev.pendingCommand
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Switch(
                            value: isOn,
                            // AC-13: Disable switch when offline
                            onChanged: (isOffline || !_brokerConnected)
                                ? null
                                : (val) => _toggleDevice(dev, val),
                          ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
