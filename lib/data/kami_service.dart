import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// 卡密校验服务地址与应用标识。
const kamiVerifyUrl = 'https://kami-5i14.onrender.com/api/app/verify';
const kamiAppId = 'app-wangpen';

/// 校验结果。服务端约定：`ok` 为真时放行，同时可选返回到期信息。
class KamiResult {
  const KamiResult({
    required this.ok,
    this.message = '',
    this.expireText = '',
    this.daysLeft,
  });

  final bool ok;
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

class KamiService {
  KamiService({Dio? dio})
    : _dio =
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

  Future<KamiResult> verify(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      throw const KamiException('请输入卡密');
    }
    try {
      final response = await _dio.post<Object?>(
        kamiVerifyUrl,
        options: Options(
          headers: {'X-Kami-Code': trimmed, 'X-Kami-App': kamiAppId},
        ),
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
        message: result.message.isEmpty ? '卡密无效' : result.message,
        expireText: result.expireText,
        daysLeft: result.daysLeft,
      );
    } on KamiException {
      rethrow;
    } on DioException catch (error) {
      debugPrint('kami verify failed: $error');
      throw KamiException(_describe(error));
    } catch (error) {
      debugPrint('kami verify failed: $error');
      throw const KamiException('验证失败，请检查网络后重试');
    }
  }

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
