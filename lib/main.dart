// main.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const MyApp());
}

/// Device model
class Device {
  String name;
  String ip;
  int port;
  int unitId;
  Device({
    required this.name,
    required this.ip,
    required this.port,
    required this.unitId,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'ip': ip,
    'port': port,
    'unitId': unitId,
  };
}

/// Single reading entry
class Reading {
  final String deviceName;
  final String ip;
  final int port;
  final int unitId;
  final DateTime timestamp;
  final List<int>? registers;
  final String? error;
  Reading({
    required this.deviceName,
    required this.ip,
    required this.port,
    required this.unitId,
    required this.timestamp,
    this.registers,
    this.error,
  });

  Map<String, dynamic> toJson() => {
    'deviceName': deviceName,
    'ip': ip,
    'port': port,
    'unitId': unitId,
    'timestamp': timestamp.toIso8601String(),
    'registers': registers,
    'error': error,
  };
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Modbus TCP Reader',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        // Mobile-optimized theme
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 2),
        cardTheme: CardTheme(
          elevation: 2,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          elevation: 6,
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final List<Device> devices = [];
  final List<Reading> readings = [];
  Timer? pollTimer;
  bool polling = false;
  int transactionIdCounter = 0;
  late TabController _tabController;

  // polling configuration
  final int pollIntervalSeconds = 5;
  final int startRegister = 0;
  final int registerCount = 10;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _stopPolling();
    _tabController.dispose();
    super.dispose();
  }

  void _startPolling() {
    if (polling) return;
    pollTimer = Timer.periodic(Duration(seconds: pollIntervalSeconds), (_) {
      _pollAllDevices();
    });
    setState(() {
      polling = true;
    });
    _pollAllDevices();
  }

  void _stopPolling() {
    pollTimer?.cancel();
    pollTimer = null;
    setState(() {
      polling = false;
    });
  }

  Future<void> _pollAllDevices() async {
    if (devices.isEmpty) return;
    for (final dev in List<Device>.from(devices)) {
      final ts = DateTime.now();
      try {
        final regs = await readHoldingRegistersTCP(
          dev.ip,
          dev.port,
          dev.unitId,
          startRegister,
          registerCount,
        );
        final r = Reading(
          deviceName: dev.name,
          ip: dev.ip,
          port: dev.port,
          unitId: dev.unitId,
          timestamp: ts,
          registers: regs,
        );
        setState(() => readings.insert(0, r));
      } catch (e) {
        final r = Reading(
          deviceName: dev.name,
          ip: dev.ip,
          port: dev.port,
          unitId: dev.unitId,
          timestamp: ts,
          error: e.toString(),
        );
        setState(() => readings.insert(0, r));
      }
    }
  }

  void _showExportOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (context) => Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Export Data',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: const Icon(Icons.file_download_outlined),
                  title: const Text('Export as JSON'),
                  subtitle: const Text('Structured data format'),
                  onTap: () {
                    Navigator.pop(context);
                    _exportJson();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.table_chart),
                  title: const Text('Export as CSV'),
                  subtitle: const Text('Spreadsheet format'),
                  onTap: () {
                    Navigator.pop(context);
                    _exportCsv();
                  },
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
    );
  }

  Future<void> _exportJson() async {
    if (readings.isEmpty) {
      _showSnackbar('No readings to export.');
      return;
    }
    final list = readings.map((r) => r.toJson()).toList();
    final jsonStr = const JsonEncoder.withIndent('  ').convert(list);
    final path = await _askSavePath(
      defaultName: 'modbus_readings.json',
      ext: 'json',
    );
    if (path == null) return;
    final file = File(path);
    await file.writeAsString(jsonStr);
    _showSnackbar('Exported JSON to: $path');
  }

  Future<void> _exportCsv() async {
    if (readings.isEmpty) {
      _showSnackbar('No readings to export.');
      return;
    }
    final header = [
      'timestamp',
      'deviceName',
      'ip',
      'port',
      'unitId',
      for (int i = 0; i < registerCount; i++) 'reg${startRegister + i}',
    ];
    final rows = <List<dynamic>>[];
    rows.add(header);
    for (final r in readings.reversed) {
      final row = <dynamic>[
        r.timestamp.toIso8601String(),
        r.deviceName,
        r.ip,
        r.port,
        r.unitId,
      ];
      if (r.registers != null) {
        row.addAll(r.registers!.map((v) => v));
      } else {
        row.addAll(List.filled(registerCount, ''));
      }
      rows.add(row);
    }
    final csvStr = const ListToCsvConverter().convert(rows);
    final path = await _askSavePath(
      defaultName: 'modbus_readings.csv',
      ext: 'csv',
    );
    if (path == null) return;
    final file = File(path);
    await file.writeAsString(csvStr);
    _showSnackbar('Exported CSV to: $path');
  }

  Future<String?> _askSavePath({
    required String defaultName,
    required String ext,
  }) async {
    try {
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Save file',
        fileName: defaultName,
        allowedExtensions: [ext],
        type: FileType.custom,
      );
      if (result != null && result.isNotEmpty) {
        return result;
      }
    } catch (_) {}
    try {
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/$defaultName';
      return path;
    } catch (e) {
      _showSnackbar('Failed to get save path: $e');
      return null;
    }
  }

  void _showSnackbar(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _openAddEditDeviceDialog({
    Device? editing,
    required int index,
  }) async {
    final nameCtrl = TextEditingController(text: editing?.name ?? '');
    final ipCtrl = TextEditingController(text: editing?.ip ?? '');
    final portCtrl = TextEditingController(
      text: (editing?.port ?? 502).toString(),
    );
    final unitCtrl = TextEditingController(
      text: (editing?.unitId ?? 1).toString(),
    );

    final formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Icon(
                  editing == null ? Icons.add_circle : Icons.edit,
                  color: Theme.of(context).primaryColor,
                ),
                const SizedBox(width: 8),
                Text(editing == null ? 'Add Device' : 'Edit Device'),
              ],
            ),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Device Name',
                        prefixIcon: Icon(Icons.device_hub),
                        border: OutlineInputBorder(),
                      ),
                      validator:
                          (v) =>
                              (v == null || v.trim().isEmpty)
                                  ? 'Required'
                                  : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: ipCtrl,
                      decoration: const InputDecoration(
                        labelText: 'IP Address',
                        prefixIcon: Icon(Icons.computer),
                        border: OutlineInputBorder(),
                        hintText: '192.168.1.100',
                      ),
                      validator:
                          (v) =>
                              (v == null || v.trim().isEmpty)
                                  ? 'Required'
                                  : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: portCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Port',
                        prefixIcon: Icon(Icons.settings_ethernet),
                        border: OutlineInputBorder(),
                        hintText: '502',
                      ),
                      keyboardType: TextInputType.number,
                      validator:
                          (v) =>
                              (int.tryParse(v ?? '') == null)
                                  ? 'Enter valid port'
                                  : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: unitCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Unit ID',
                        prefixIcon: Icon(Icons.tag),
                        border: OutlineInputBorder(),
                        hintText: '1',
                      ),
                      keyboardType: TextInputType.number,
                      validator:
                          (v) =>
                              (int.tryParse(v ?? '') == null)
                                  ? 'Enter valid unit ID'
                                  : null,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (formKey.currentState?.validate() ?? false) {
                    Navigator.of(ctx).pop(true);
                  }
                },
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Save'),
              ),
            ],
          ),
    );

    if (result == true) {
      final dev = Device(
        name: nameCtrl.text.trim(),
        ip: ipCtrl.text.trim(),
        port: int.parse(portCtrl.text.trim()),
        unitId: int.parse(unitCtrl.text.trim()),
      );
      setState(() {
        if (editing != null && index >= 0) {
          devices[index] = dev;
        } else {
          devices.add(dev);
        }
      });
    }
  }

  void _removeDevice(int idx) {
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Row(
              children: [
                Icon(Icons.warning, color: Colors.orange),
                SizedBox(width: 8),
                Text('Remove Device'),
              ],
            ),
            content: Text(
              'Are you sure you want to remove "${devices[idx].name}"?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  setState(() {
                    devices.removeAt(idx);
                  });
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Remove'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Modbus TCP Reader'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.devices), text: 'Devices'),
            Tab(icon: Icon(Icons.analytics), text: 'Readings'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: polling ? 'Stop polling' : 'Start polling',
            icon:
                polling
                    ? const Icon(Icons.pause_circle, color: Colors.orange)
                    : const Icon(Icons.play_circle, color: Colors.green),
            onPressed: polling ? _stopPolling : _startPolling,
          ),
          IconButton(
            tooltip: 'Export data',
            icon: const Icon(Icons.file_download),
            onPressed: _showExportOptions,
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildDeviceTab(), _buildReadingsTab()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddEditDeviceDialog(editing: null, index: -1),
        icon: const Icon(Icons.add),
        label: const Text('Add Device'),
      ),
    );
  }

  Widget _buildDeviceTab() {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(context).primaryColor.withOpacity(0.3),
            ),
          ),
          child: Row(
            children: [
              Icon(
                polling ? Icons.sync : Icons.sync_disabled,
                color: polling ? Colors.green : Colors.grey,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      polling ? 'Polling Active' : 'Polling Stopped',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Interval: ${pollIntervalSeconds}s | Registers: $startRegister-${startRegister + registerCount - 1}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child:
              devices.isEmpty
                  ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.device_hub_outlined,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No devices configured',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap "Add Device" to get started',
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  )
                  : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: devices.length,
                    itemBuilder: (context, idx) {
                      final d = devices[idx];
                      return Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          leading: CircleAvatar(
                            backgroundColor: Theme.of(context).primaryColor,
                            child: Text(
                              d.name.substring(0, 1).toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(
                            d.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.computer, size: 16),
                                  const SizedBox(width: 4),
                                  Text('${d.ip}:${d.port}'),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  const Icon(Icons.tag, size: 16),
                                  const SizedBox(width: 4),
                                  Text('Unit ID: ${d.unitId}'),
                                ],
                              ),
                            ],
                          ),
                          trailing: PopupMenuButton(
                            itemBuilder:
                                (context) => [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: const Row(
                                      children: [
                                        Icon(Icons.edit),
                                        SizedBox(width: 8),
                                        Text('Edit'),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: const Row(
                                      children: [
                                        Icon(Icons.delete, color: Colors.red),
                                        SizedBox(width: 8),
                                        Text('Delete'),
                                      ],
                                    ),
                                  ),
                                ],
                            onSelected: (value) {
                              if (value == 'edit') {
                                _openAddEditDeviceDialog(
                                  editing: d,
                                  index: idx,
                                );
                              } else if (value == 'delete') {
                                _removeDevice(idx);
                              }
                            },
                          ),
                        ),
                      );
                    },
                  ),
        ),
      ],
    );
  }

  Widget _buildReadingsTab() {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(context).primaryColor.withOpacity(0.3),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.analytics, color: Theme.of(context).primaryColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Data Collection',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Total readings: ${readings.length}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              if (readings.isNotEmpty)
                IconButton(
                  onPressed: () {
                    setState(() {
                      readings.clear();
                    });
                    _showSnackbar('Readings cleared');
                  },
                  icon: const Icon(Icons.clear_all),
                  tooltip: 'Clear all readings',
                ),
            ],
          ),
        ),
        Expanded(
          child:
              readings.isEmpty
                  ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.analytics_outlined,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No readings yet',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          polling
                              ? 'Waiting for data...'
                              : 'Start polling to collect data',
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  )
                  : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: readings.length,
                    itemBuilder: (context, idx) {
                      final r = readings[idx];
                      final hasError = r.error != null;
                      return Card(
                        child: ExpansionTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                hasError ? Colors.red : Colors.green,
                            child: Icon(
                              hasError ? Icons.error : Icons.check_circle,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            r.deviceName,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Unit ${r.unitId} • ${_formatTimestamp(r.timestamp)}',
                              ),
                              if (hasError)
                                Text(
                                  'Error occurred',
                                  style: TextStyle(color: Colors.red[700]),
                                )
                              else
                                Text(
                                  '${r.registers?.length ?? 0} registers read',
                                ),
                            ],
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (hasError) ...[
                                    const Text(
                                      'Error Details:',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.red[50],
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: Colors.red[200]!,
                                        ),
                                      ),
                                      child: Text(
                                        r.error!,
                                        style: TextStyle(
                                          color: Colors.red[700],
                                        ),
                                      ),
                                    ),
                                  ] else ...[
                                    const Text(
                                      'Register Values:',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.green[50],
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: Colors.green[200]!,
                                        ),
                                      ),
                                      child: Wrap(
                                        spacing: 8,
                                        runSpacing: 4,
                                        children:
                                            r.registers!.asMap().entries.map((
                                              entry,
                                            ) {
                                              return Chip(
                                                label: Text(
                                                  'R${startRegister + entry.key}: ${entry.value}',
                                                ),
                                                backgroundColor: Colors.white,
                                              );
                                            }).toList(),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(Icons.computer, size: 16),
                                      const SizedBox(width: 4),
                                      Text('${r.ip}:${r.port}'),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
        ),
      ],
    );
  }

  String _formatTimestamp(DateTime t) {
    return '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
  }

  /// Modbus TCP read implementation
  Future<List<int>> readHoldingRegistersTCP(
    String ip,
    int port,
    int unitId,
    int address,
    int quantity, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    transactionIdCounter = (transactionIdCounter + 1) & 0xFFFF;
    final int txId = transactionIdCounter;

    final request = BytesBuilder();
    final protocolId = 0;
    final pduLength = 1 + 2 + 2;
    final lengthField = 1 + pduLength;
    request.addByte((txId >> 8) & 0xFF);
    request.addByte(txId & 0xFF);
    request.addByte((protocolId >> 8) & 0xFF);
    request.addByte(protocolId & 0xFF);
    request.addByte((lengthField >> 8) & 0xFF);
    request.addByte(lengthField & 0xFF);
    request.addByte(unitId & 0xFF);
    request.addByte(0x03);
    request.addByte((address >> 8) & 0xFF);
    request.addByte(address & 0xFF);
    request.addByte((quantity >> 8) & 0xFF);
    request.addByte(quantity & 0xFF);

    final reqBytes = request.toBytes();

    final socket = await Socket.connect(ip, port, timeout: timeout);
    final completer = Completer<Uint8List>();
    final buffer = BytesBuilder();

    final expected = 7 + 2 + quantity * 2;

    late StreamSubscription sub;
    sub = socket.listen(
      (data) {
        buffer.add(data);
        if (buffer.length >= expected && !completer.isCompleted) {
          completer.complete(Uint8List.fromList(buffer.toBytes()));
        }
      },
      onError: (e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
      onDone: () {
        if (!completer.isCompleted)
          completer.complete(Uint8List.fromList(buffer.toBytes()));
      },
      cancelOnError: true,
    );

    socket.add(reqBytes);
    await socket.flush();

    Uint8List response;
    try {
      response = await completer.future.timeout(timeout);
    } on TimeoutException {
      await sub.cancel();
      socket.destroy();
      throw Exception(
        'Timeout waiting for response from $ip:$port (unit $unitId)',
      );
    } catch (e) {
      await sub.cancel();
      socket.destroy();
      rethrow;
    }

    await sub.cancel();
    socket.destroy();

    if (response.length < 9) {
      throw Exception('Invalid response (too short) from $ip');
    }
    final respTxId = (response[0] << 8) | response[1];
    final respProtocol = (response[2] << 8) | response[3];
    final respLength = (response[4] << 8) | response[5];
    final respUnitId = response[6];
    final func = response[7];
    if (func == 0x83) {
      final errCode = response[8];
      throw Exception('Modbus exception code $errCode from $ip (unit $unitId)');
    }
    if (func != 0x03) {
      throw Exception('Unexpected function code $func from $ip');
    }
    final byteCount = response[8];
    final dataStart = 9;
    final regs = <int>[];
    for (int i = 0; i < (byteCount ~/ 2); i++) {
      final hi = response[dataStart + i * 2];
      final lo = response[dataStart + i * 2 + 1];
      regs.add((hi << 8) | lo);
    }
    return regs;
  }
}
