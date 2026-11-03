import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// 卡密校验服务地址与应用标识。
const kamiBaseUrl = 'https://kami-5i14.onrender.com';
const kamiAppId = 'app-wangpen';

/// 校验结果。服务端约定：`ok` 为真时放行，同时可选返回到期信息。
class KamiResult {
  const KamiResult({
    required this.ok,
    this.key = '',
    this.message = '',
    this.expireText = '',
    this.daysLeft,
  });

  final bool ok;

  /// 服务端返回的卡密状态（`invalid` / `net` / 其他）。
  final String key;

  final String message;

  /// 服务端返回的到期时间文本，例如 `2026-12-31 23:59`。
  final String expireText;

  /// 剩余天数，服务端未提供时为 null。
  final int? daysLeft;

  /// 剩余天数的可读描述。
  String get remainText {
    if (daysLeft == null) return expireText;
    final days = daysLeft!;
    if (expireText.isEmpty) return '剩余 $days 天';
    return '$expireText · 剩余 $days 天';
  }

  /// 根据本地保存的到期时间文本，动态计算当前剩余天数描述。
  ///
  /// 服务端返回 `days_left` 是校验那一刻的快照，隔几天再看会失真，
  /// 所以持久化只存 `expire_text`，展示时重新计算。
  static String remainTextFor(String expireText) {
    final text = expireText.trim();
    if (text.isEmpty) return '长期有效';
    final expire = DateTime.tryParse(text) ?? _parseChinese(text);
    if (expire == null) return text;
    final now = DateTime.now();
    final days = expire.difference(now).inDays;
    if (days < 0) return '已过期';
    if (days == 0) return '今日到期（$text）';
    return '剩余 $days 天（至 $text）';
  }

  /// 解析 `2026-12-31 23:59` 这类空格分隔的中文习惯格式。
  static DateTime? _parseChinese(String text) {
    final match = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})').firstMatch(text);
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final time = RegExp(
      r'(\d{1,2}):(\d{2})',
    ).firstMatch(text.substring(match.end));
    return DateTime(
      year,
      month,
      day,
      time != null ? int.parse(time.group(1)!) : 23,
      time != null ? int.parse(time.group(2)!) : 59,
    );
  }

  static KamiResult fromJson(Object? value) {
    final data = value is Map ? value : const <String, dynamic>{};
    final days = data['days_left'];
    return KamiResult(
      ok: data['ok'] == true,
      key: (data['key'] ?? '').toString().trim(),
      message: (data['message'] ?? '').toString().trim(),
      expireText: (data['expire_text'] ?? '').toString().trim(),
      daysLeft: days is num ? days.toInt() : int.tryParse('${days ?? ''}'),
    );
  }
}

/// 网络或服务异常，与「卡密无效」区分开，便于界面给出重试入口。
class KamiException implements Exception {
  const KamiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 卡密校验服务。
///
/// 与服务端约定（见卡密后台接入文档）：
/// - `/api/app/verify`：首次激活，开始计时；成功后服务端绑定设备。
/// - `/api/app/check`：启动/定时复核，不重复计时。
/// - 两者都要求 JSON body `{code, app, device}`，并带
///   `X-Kami-Code` / `X-Kami-App` / `X-Kami-Device` 三个请求头。
class KamiService {
  KamiService({Dio? dio, String? deviceId})
    : _deviceId = deviceId ?? '' ,
      _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              sendTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 30),
              // 自行判定状态码，4xx 也能读到服务端的说明文字。
              validateStatus: (_) => true,
              responseType: ResponseType.json,
              headers: const {'Accept': 'application/json'},
            ),
          );

  final Dio _dio;

  /// 设备唯一标识，由调用方在启动时注入（Android 用 ANDROID_ID，
  /// 桌面端用持久化的随机 ID）。为空时退化为只带请求头。
  String _deviceId;

  set deviceId(String value) => _deviceId = value;

  Map<String, String> _headers(String code) => {
    'X-Kami-Code': code,
    'X-Kami-App': kamiAppId,
    if (_deviceId.isNotEmpty) 'X-Kami-Device': _deviceId,
  };

  Map<String, dynamic> _body(String code) => {
    'code': code,
    'app': kamiAppId,
    if (_deviceId.isNotEmpty) 'device': _deviceId,
  };

  Future<KamiResult> _post(String path, String code) async {
    try {
      final response = await _dio.post<Object?>(
        kamiBaseUrl + path,
        options: Options(headers: _headers(code)),
        data: _body(code),
      );
      final result = KamiResult.fromJson(response.data);
      if (result.ok) return result;
      final status = response.statusCode ?? 0;
      // 服务端用 400 表示请求头缺失等调用问题，其余情况按卡密无效处理。
      if (status >= 500) {
        throw const KamiException('验证服务暂时不可用，请稍后重试');
      }
      return KamiResult(
        ok: false,
        key: result.key,
        message: result.message.isEmpty ? '卡密无效' : result.message,
        expireText: result.expireText,
        daysLeft: result.daysLeft,
      );
    } on KamiException {
      rethrow;
    } on DioException catch (error) {
      debugPrint('kami request failed: $error');
      throw KamiException(_describe(error));
    } catch (error) {
      debugPrint('kami request failed: $error');
      throw const KamiException('验证失败，请检查网络后重试');
    }
  }

  /// 首次激活（开始计时）。成功后服务端记录设备绑定。
  Future<KamiResult> verify(String code) =>
      _post('/api/app/verify', code.trim().toUpperCase());

  /// 启动/定时复核，不重复计时。
  Future<KamiResult> check(String code) =>
      _post('/api/app/check', code.trim().toUpperCase());

  static String _describe(DioException error) {
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return '连接验证服务超时，请检查网络后重试';
    }
    if (error.type == DioExceptionType.connectionError ||
        error.error is SocketException) {
      return '无法连接验证服务，请检查网络后重试';
    }
    return '验证失败，请稍后重试';
  }
}
