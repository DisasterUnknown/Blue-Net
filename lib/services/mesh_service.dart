import 'dart:async';
import 'dart:convert';

import 'package:bluetooth_chat_app/core/enums/logs_enums.dart';
import 'package:flutter/foundation.dart';

import 'package:bluetooth_chat_app/data/data_base/db_helper.dart';
import 'package:bluetooth_chat_app/data/data_base/db_crypto.dart';
import 'package:bluetooth_chat_app/services/log_service.dart';
import 'package:bluetooth_chat_app/services/uuid_service.dart';

// 🔥 Prefix imports to avoid collisions
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart' as fperiph;
import 'package:ble_peripheral/ble_peripheral.dart' as periph;

class MeshStats {
  final int totalMessagesSent;
  final int totalMessagesReceived;
  final int totalMessagesDeliveredToMe;
  final int successfulDeliveries;
  final double avgDeliveryMillis;
  final int currentConnectedDevices;
  final DateTime? lastSendTime;
  final DateTime? lastReceiveTime;
  final DateTime? lastCleanupTime;
  final DateTime? nextCleanupTime;
  final int lastCleanupRemovedCount;

  const MeshStats({
    required this.totalMessagesSent,
    required this.totalMessagesReceived,
    required this.totalMessagesDeliveredToMe,
    required this.successfulDeliveries,
    required this.avgDeliveryMillis,
    required this.currentConnectedDevices,
    required this.lastSendTime,
    required this.lastReceiveTime,
    required this.lastCleanupTime,
    required this.nextCleanupTime,
    required this.lastCleanupRemovedCount,
  });

  factory MeshStats.initial() => const MeshStats(
    totalMessagesSent: 0,
    totalMessagesReceived: 0,
    totalMessagesDeliveredToMe: 0,
    successfulDeliveries: 0,
    avgDeliveryMillis: 0,
    currentConnectedDevices: 0,
    lastSendTime: null,
    lastReceiveTime: null,
    lastCleanupTime: null,
    nextCleanupTime: null,
    lastCleanupRemovedCount: 0,
  );

  MeshStats copyWith({
    int? totalMessagesSent,
    int? totalMessagesReceived,
    int? totalMessagesDeliveredToMe,
    int? successfulDeliveries,
    double? avgDeliveryMillis,
    int? currentConnectedDevices,
    DateTime? lastSendTime,
    DateTime? lastReceiveTime,
    DateTime? lastCleanupTime,
    DateTime? nextCleanupTime,
    int? lastCleanupRemovedCount,
  }) => MeshStats(
    totalMessagesSent: totalMessagesSent ?? this.totalMessagesSent,
    totalMessagesReceived: totalMessagesReceived ?? this.totalMessagesReceived,
    totalMessagesDeliveredToMe:
        totalMessagesDeliveredToMe ?? this.totalMessagesDeliveredToMe,
    successfulDeliveries: successfulDeliveries ?? this.successfulDeliveries,
    avgDeliveryMillis: avgDeliveryMillis ?? this.avgDeliveryMillis,
    currentConnectedDevices:
        currentConnectedDevices ?? this.currentConnectedDevices,
    lastSendTime: lastSendTime ?? this.lastSendTime,
    lastReceiveTime: lastReceiveTime ?? this.lastReceiveTime,
    lastCleanupTime: lastCleanupTime ?? this.lastCleanupTime,
    nextCleanupTime: nextCleanupTime ?? this.nextCleanupTime,
    lastCleanupRemovedCount:
        lastCleanupRemovedCount ?? this.lastCleanupRemovedCount,
  );
}

class MeshService {
  MeshService._();
  static final MeshService instance = MeshService._();

  static const String _serviceUuid = '0000feed-0000-1000-8000-00805f9b34fb';
  static const String _characteristicUuid =
      '0000beef-0000-1000-8000-00805f9b34fb';
  static const int _maxChunkSize = 180;

  bool _running = false;
  Timer? _scanTimer;
  Timer? _cleanupTimer;
  StreamSubscription<List<fbp.ScanResult>>? _scanSub;

  final fperiph.FlutterBlePeripheral _blePeripheral =
      fperiph.FlutterBlePeripheral();

  final ValueNotifier<MeshStats> stats = ValueNotifier<MeshStats>(
    MeshStats.initial(),
  );

  final Set<String> _connectedDeviceIds = <String>{};
  final Map<String, List<int>> _incomingBuffers = {};

  String? _myIdCache;
  Future<String> _getMyId() async {
    _myIdCache ??= await AppIdentifier.getId();
    return _myIdCache!;
  }

  Future<void> start() async {
    if (_running) return;
    _running = true;

    await _startAdvertising();
    _setupGattServerListener();

    _scanTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => _runScanBurst(),
    );
    _cleanupTimer = Timer.periodic(
      const Duration(minutes: 10),
      (_) => _runCleanup(),
    );

    unawaited(_runScanBurst());
  }

  Future<void> stop() async {
    _running = false;
    _scanTimer?.cancel();
    _cleanupTimer?.cancel();
    await _scanSub?.cancel();
    await _stopAdvertising();
    try {
      await fbp.FlutterBluePlus.stopScan();
    } catch (_) {}
  }

  // ───────────────── Advertising ─────────────────

  Future<void> _startAdvertising() async {
    final myId = await _getMyId();

    final advertiseData = fperiph.AdvertiseData(
      localName: 'Mesh-$myId',
      serviceUuid: _serviceUuid,
      manufacturerId: 0xFFFF,
      manufacturerData: Uint8List.fromList(utf8.encode(myId)),
    );

    await _blePeripheral.start(advertiseData: advertiseData);
    LogService.log(logTypes.info, 'Advertising as Mesh-$myId');
  }

  Future<void> _stopAdvertising() async {
    await _blePeripheral.stop();
  }

  // ───────────────── GATT Server ─────────────────

  void _setupGattServerListener() async {
    await periph.BlePeripheral.initialize();

    // 1. Add Service first
    await periph.BlePeripheral.addService(
      periph.BleService(
        uuid: _serviceUuid,
        primary: true,
        characteristics: [
          periph.BleCharacteristic(
            uuid: _characteristicUuid,
            properties: [
              periph.CharacteristicProperties.write.index,
              periph.CharacteristicProperties.writeWithoutResponse.index,
            ],
            permissions: [periph.AttributePermissions.writeable.index],
          ),
        ],
      ),
    );

    // 2. Correct Callback Signature
    periph.BlePeripheral.setWriteRequestCallback((
      String deviceId,
      String characteristicUuid,
      int requestId,
      Uint8List? value,
    ) {
      if (value == null || value.isEmpty) {
        return periph.WriteRequestResult(status: 0);
      }

      final buffer = _incomingBuffers[deviceId] ?? <int>[];
      buffer.addAll(value);
      _incomingBuffers[deviceId] = buffer;

      // 125 = '}'
      if (value.last == 125) {
        try {
          final raw = utf8.decode(buffer);
          _incomingBuffers.remove(deviceId);

          _getMyId().then((id) {
            handleIncomingBatch(raw, id);
          });
        } catch (_) {
          LogService.log(logTypes.info, 'Chunk decode failed');
        }
      }

      // ✅ REQUIRED — must return enum
      return periph.WriteRequestResult(status: 0);
    });
  }

  // ───────────────── Central / Scan ─────────────────

  Future<void> _runScanBurst() async {
    if (!_running) return;

    await fbp.FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 8),
      androidScanMode: fbp.AndroidScanMode.lowPower,
    );

    _scanSub?.cancel();
    _scanSub = fbp.FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        unawaited(_handleScanResult(r));
      }
    });
  }

  void _updateConnectedCount() {
    stats.value = stats.value.copyWith(
      currentConnectedDevices: _connectedDeviceIds.length,
    );
  }

  Future<void> _handleScanResult(fbp.ScanResult result) async {
    final device = result.device;

    try {
      await device.connect(timeout: const Duration(seconds: 8));
      await device.requestMtu(250);
      _connectedDeviceIds.add(device.remoteId.str);
      _updateConnectedCount();

      final services = await device.discoverServices();
      final svc = services.firstWhere(
        (s) => s.serviceUuid.str128 == _serviceUuid,
      );

      final char = svc.characteristics.firstWhere(
        (c) => c.characteristicUuid.str128 == _characteristicUuid,
      );

      await _forwardPendingMessagesToPeer(char);
      await _receiveFromPeer(char);
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (_) {
    } finally {
      try {
        await device.disconnect();
      } catch (_) {}
      _connectedDeviceIds.remove(device.remoteId.str);
      _updateConnectedCount();
    }
  }

  // ───────────────── Messaging ─────────────────

  Future<void> _forwardPendingMessagesToPeer(
    fbp.BluetoothCharacteristic characteristic,
  ) async {
    final db = DBHelper();
    final pending = await db.getPendingNonUserMsgs();
    if (pending.isEmpty) return;

    final jsonStr = jsonEncode({'type': 'mesh_batch', 'messages': pending});
    final bytes = utf8.encode(jsonStr);

    for (var i = 0; i < bytes.length; i += _maxChunkSize) {
      await characteristic.write(
        bytes.sublist(i, (i + _maxChunkSize).clamp(0, bytes.length)),
        withoutResponse: true,
      );
    }
  }

  Future<void> _receiveFromPeer(
    fbp.BluetoothCharacteristic characteristic,
  ) async {
    final data = await characteristic.read();
    if (data.isEmpty) return;

    final payload = utf8.decode(data);
    await handleIncomingBatch(payload, await _getMyId());
  }

  // ───────────────── Business Logic ─────────────────

  Future<void> handleIncomingBatch(String payload, String myUserCode) async {
    final decoded = jsonDecode(payload);
    if (decoded['type'] != 'mesh_batch') return;

    final db = DBHelper();
    for (final raw in decoded['messages']) {
      final msgId = raw['msgId'];
      if (await db.isMsgInHash(msgId)) continue;

      await db.insertHashMsg(msgId);

      if (raw['receiverUserCode'] == myUserCode) {
        await db.insertChatMsg(raw['senderUserCode'], raw, encrypt: false);
      } else if ((raw['hops'] ?? 0) > 0) {
        await db.insertNonUserMsg({...raw, 'hops': raw['hops'] - 1});
      }
    }
  }

  Future<void> _runCleanup() async {
    await DBHelper().removeOldNonUserMsgs(olderThanDays: 3);
  }

  Future<void> sendNewMessage({
    required String myUserCode,
    required String targetUserCode,
    required String plainText,
  }) async {
    final msgId = generateMsgId(myUserCode);
    final encrypted = CryptoHelper.encryptMsg(plainText, targetUserCode);

    await DBHelper().insertNonUserMsg({
      'msgId': msgId,
      'msg': encrypted,
      'senderUserCode': myUserCode,
      'receiverUserCode': targetUserCode,
      'hops': 4,
    });
  }
}
