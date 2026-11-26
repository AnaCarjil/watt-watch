import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_browser_client.dart';
import 'package:uuid/uuid.dart';

void main() {
  runApp(const MyApp());
}

// Application configuration
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WattWatch',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F7F5),
      ),
      home: const DashboardPage(),
    );
  }
}

// Model for a household device
class Device {
  final String id;
  final String name;
  final IconData icon;

  double? watts;
  String status;

  Device({
    required this.id,
    required this.name,
    required this.icon,
    this.watts,
    this.status = 'Waiting for data',
  });
}

// Main dashboard
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool isConnected = false;

  // Home ID is supplied when launching Flutter
  final String homeId = const String.fromEnvironment('HOME_ID');

  MqttBrowserClient? client;

  String connectionMessage = 'Connecting to MQTT...';

  // Pending commands and timeout timers
  final Map<String, String> pendingCommands = {};
  final Map<String, Timer> commandTimers = {};

  StreamSubscription? mqttSubscription;

  // Household devices
  final List<Device> devices = [
    Device(id: 'dev-fridge-01', name: 'Fridge', icon: Icons.kitchen),
    Device(id: 'dev-kettle-02', name: 'Kettle', icon: Icons.coffee),
    Device(id: 'dev-tv-03', name: 'Living Room TV', icon: Icons.tv),
    Device(
      id: 'dev-washer-04',
      name: 'Washing Machine',
      icon: Icons.local_laundry_service,
    ),
    Device(id: 'dev-laptop-05', name: 'Laptop Charger', icon: Icons.laptop_mac),
  ];

  @override
  void initState() {
    super.initState();
    connectMQTT();
  }

  // Connect to MQTT broker
  Future<void> connectMQTT() async {
    if (homeId.isEmpty) {
      setState(() {
        connectionMessage = 'Missing simulator Home ID';
      });

      debugPrint(
        'Missing Home ID. Launch Flutter with '
        '--dart-define=HOME_ID=YOUR_HOME_ID',
      );

      return;
    }

    final clientId = 'wattwatch-${const Uuid().v4()}';

    final mqttClient = MqttBrowserClient(
      'ws://broker.hivemq.com/mqtt',
      clientId,
    );

    client = mqttClient;

    mqttClient.port = 8000;
    mqttClient.keepAlivePeriod = 20;
    mqttClient.logging(on: false);
    mqttClient.setProtocolV311();
    mqttClient.websocketProtocols = ['mqtt'];

    mqttClient.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean();

    mqttClient.onDisconnected = () {
      if (mounted) {
        setState(() {
          isConnected = false;
          connectionMessage = 'Connection lost';
        });
      }
    };

    try {
      await mqttClient.connect();

      if (mqttClient.connectionStatus?.state == MqttConnectionState.connected) {
        if (!mounted) {
          mqttClient.disconnect();
          return;
        }

        setState(() {
          isConnected = true;
          connectionMessage = 'Connected to MQTT';
        });

        // Listen for incoming MQTT messages
        mqttSubscription = mqttClient.updates!.listen((messages) {
          for (final message in messages) {
            final received = message.payload as MqttPublishMessage;

            final payload = MqttPublishPayload.bytesToStringAsString(
              received.payload.message,
            );

            handleMessage(message.topic, payload);
          }
        });

        // Subscribe to device power readings
        mqttClient.subscribe('wattwatch/$homeId/+/power', MqttQos.atMostOnce);

        // Subscribe to device status updates
        mqttClient.subscribe('wattwatch/$homeId/+/status', MqttQos.atMostOnce);

        // Subscribe to command acknowledgments
        mqttClient.subscribe('wattwatch/$homeId/+/ack', MqttQos.atMostOnce);

        debugPrint('Connected to MQTT successfully');
        debugPrint('Home ID: $homeId');
      } else {
        mqttClient.disconnect();

        if (mounted) {
          setState(() {
            isConnected = false;
            connectionMessage = 'Unable to connect to MQTT';
          });
        }
      }
    } catch (e) {
      debugPrint('MQTT connection error: $e');

      mqttClient.disconnect();

      if (mounted) {
        setState(() {
          isConnected = false;
          connectionMessage = 'Unable to connect to MQTT';
        });
      }
    }
  }

  // Process incoming MQTT messages
  void handleMessage(String topic, String payload) {
    final parts = topic.split('/');

    // Ignore invalid topics and other households
    if (parts.length != 4 || parts[0] != 'wattwatch' || parts[1] != homeId) {
      return;
    }

    final deviceId = parts[2];
    final messageType = parts[3];

    final index = devices.indexWhere((device) => device.id == deviceId);

    if (index == -1 || !mounted) return;

    try {
      final data = jsonDecode(payload);
      final device = devices[index];

      setState(() {
        // Update power consumption
        if (messageType == 'power') {
          device.watts = (data['watts'] as num).toDouble();
        }

        // Update device status
        if (messageType == 'status') {
          if (!pendingCommands.containsKey(deviceId)) {
            device.status = data['state'] as String;
          }
        }

        // Process command acknowledgment
        if (messageType == 'ack') {
          if (pendingCommands.containsKey(deviceId) &&
              pendingCommands[deviceId] == data['cmdId']) {
            final confirmedState = data['state'];

            if (confirmedState != 'on' && confirmedState != 'off') {
              return;
            }

            commandTimers.remove(deviceId)?.cancel();
            pendingCommands.remove(deviceId);

            device.status = confirmedState as String;

            if (device.status == 'off') {
              device.watts = 0.0;
            }

            debugPrint(
              'Command confirmed: '
              '${device.name} ${device.status}',
            );
          }
        }
      });
    } catch (e) {
      debugPrint('Invalid MQTT message: $e');
    }
  }

  // Send an on/off command to the simulator
  void sendCommand(Device device, bool turnOn) {
    final mqttClient = client;

    if (!isConnected ||
        mqttClient == null ||
        pendingCommands.containsKey(device.id)) {
      return;
    }

    final commandId = const Uuid().v4();
    final action = turnOn ? 'on' : 'off';

    final payload = jsonEncode({'cmdId': commandId, 'action': action});

    final builder = MqttClientPayloadBuilder();
    builder.addString(payload);

    setState(() {
      pendingCommands[device.id] = commandId;
    });

    // Wait a maximum of five seconds for confirmation
    commandTimers[device.id] = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;

      setState(() {
        pendingCommands.remove(device.id);
        commandTimers.remove(device.id);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No response from ${device.name}')),
      );
    });

    try {
      mqttClient.publishMessage(
        'wattwatch/$homeId/${device.id}/cmd',
        MqttQos.atMostOnce,
        builder.payload!,
      );

      debugPrint('Command sent: ${device.name} $action');
    } catch (e) {
      commandTimers.remove(device.id)?.cancel();

      setState(() {
        pendingCommands.remove(device.id);
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unable to send command')));
    }
  }

  // Calculate total household power
  double get totalPower {
    return devices.fold(
      0.0,
      (total, device) =>
          total + (device.status == 'on' ? (device.watts ?? 0) : 0),
    );
  }

  // Count active devices
  int get activeDevices {
    return devices.where((device) => device.status == 'on').length;
  }

  // Check whether readings have been received
  bool get hasReadings {
    return devices.any((device) => device.watts != null);
  }

  // Clean up resources
  @override
  void dispose() {
    for (final timer in commandTimers.values) {
      timer.cancel();
    }

    mqttSubscription?.cancel();

    client?.onDisconnected = null;
    client?.disconnect();

    super.dispose();
  }

  // Build the main dashboard interface
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.green.shade800,
        foregroundColor: Colors.white,
        title: const Row(
          children: [
            Icon(Icons.bolt, size: 30),
            SizedBox(width: 8),
            Text('WattWatch', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 750),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Household Energy Tracker',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 8),

              const Text(
                'Monitor and manage your energy consumption.',
                style: TextStyle(color: Colors.grey),
              ),

              const SizedBox(height: 20),

              // MQTT connection status
              Row(
                children: [
                  Icon(
                    Icons.circle,
                    size: 12,
                    color: isConnected ? Colors.green : Colors.orange,
                  ),

                  const SizedBox(width: 8),

                  Expanded(child: Text(connectionMessage)),
                ],
              ),

              // Missing Home ID warning
              if (homeId.isEmpty) ...[
                const SizedBox(height: 12),

                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Start the simulator and launch Flutter '
                    'with --dart-define=HOME_ID=YOUR_HOME_ID.',
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // Total household consumption card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.green.shade800,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Total household power',
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),

                    const SizedBox(height: 12),

                    Text(
                      hasReadings
                          ? '${totalPower.toStringAsFixed(1)} W'
                          : '-- W',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      !isConnected && hasReadings
                          ? 'Connection lost — last known values'
                          : hasReadings
                          ? '$activeDevices of '
                                '${devices.length} devices active'
                          : 'Waiting for device readings',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              const Text(
                'My Devices',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 12),

              // Display all device cards
              ...devices.map((device) => buildDeviceCard(device)),
            ],
          ),
        ),
      ),
    );
  }

  // Build an individual device card
  Widget buildDeviceCard(Device device) {
    final bool isOn = device.status == 'on';

    final bool isPending = pendingCommands.containsKey(device.id);

    final bool canControl =
        isConnected &&
        (device.status == 'on' || device.status == 'off') &&
        !isPending;

    return Card(
      color: Colors.white,
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Device icon
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(device.icon, color: Colors.green.shade800, size: 28),
            ),

            const SizedBox(width: 16),

            // Device information
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.name,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 5),

                  Text(
                    device.watts == null
                        ? '-- W'
                        : '${device.watts!.toStringAsFixed(1)} W',
                    style: TextStyle(
                      fontSize: 16,
                      color: isConnected ? Colors.black87 : Colors.grey,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    isPending
                        ? 'Waiting for confirmation...'
                        : device.status == 'on'
                        ? 'On'
                        : device.status == 'off'
                        ? 'Off'
                        : device.status,
                    style: TextStyle(
                      color: isPending
                          ? Colors.orange
                          : isConnected && isOn
                          ? Colors.green
                          : Colors.grey,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),

            // Loading indicator for pending commands
            if (isPending)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),

            const SizedBox(width: 10),

            // Remote on/off control
            Switch(
              value: isOn,
              onChanged: canControl
                  ? (value) => sendCommand(device, value)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
