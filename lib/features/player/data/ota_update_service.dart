import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/config/environment_config.dart';
import '../../../core/logging/kiosk_log.dart';
import '../../../core/websocket/realtime_command.dart';
import '../../../services/device_service.dart';
import 'kiosk_fleet_api.dart';

/// Background APK fetch + checksum + install (Android). Guarded by [EnvironmentConfig.enableOtaInstall].
class OtaUpdateService {
  OtaUpdateService({
    required EnvironmentConfig env,
    required KioskFleetApi fleetApi,
    required DeviceService device,
  })  : _env = env,
        _fleetApi = fleetApi,
        _device = device;

  final EnvironmentConfig _env;
  final KioskFleetApi _fleetApi;
  final DeviceService _device;

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(minutes: 30),
      responseType: ResponseType.bytes,
    ),
  );

  Future<void> handleUpdateApp(UpdateAppCommand cmd) async {
    if (!Platform.isAndroid || !_env.enableOtaInstall) {
      await _fleetApi.postCommandAck(
        messageId: cmd.messageId,
        commandType: 'UPDATE_APP',
        ok: false,
        detail: <String, dynamic>{
          'reason': _env.enableOtaInstall ? 'not_android' : 'disabled',
        },
      );
      return;
    }

    File? tmp;
    try {
      KioskLog.event('ota', 'download_start', meta: <String, Object?>{
        'version': cmd.version,
      });
      final dir = await getTemporaryDirectory();
      tmp = File(p.join(dir.path, 'ota_${cmd.messageId}.apk'));
      final response = await _dio.get<List<int>>(
        cmd.url,
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) {
        throw StateError('empty_body');
      }
      await tmp.writeAsBytes(bytes, flush: true);

      final hash = sha256.convert(bytes).toString();
      if (hash.toLowerCase() != cmd.sha256.toLowerCase()) {
        throw StateError('checksum_mismatch');
      }

      final installed = await _device.installApk(tmp.path);
      await _fleetApi.postCommandAck(
        messageId: cmd.messageId,
        commandType: 'UPDATE_APP',
        ok: installed,
        detail: <String, dynamic>{
          if (!installed) 'reason': 'install_intent_failed',
        },
      );
      KioskLog.event('ota', installed ? 'install_triggered' : 'install_failed');
    } catch (e, st) {
      KioskLog.e('ota', e, st);
      await _fleetApi.postCommandAck(
        messageId: cmd.messageId,
        commandType: 'UPDATE_APP',
        ok: false,
        detail: <String, dynamic>{'error': e.toString()},
      );
    } finally {
      try {
        if (tmp != null && await tmp.exists()) {
          await tmp.delete();
        }
      } catch (_) {}
    }
  }
}
