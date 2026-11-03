import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/kami_service.dart';
import 'common.dart';
import 'loading_indicator.dart';

/// 启动门禁：卡密校验通过前不构建主界面。
///
/// 每次冷启动都会先用本地保存的卡密自动校验一次；校验失败或已过期时清除
/// 本地记录并停留在输入页，避免旧卡密被反复提交。
class KamiGate extends StatefulWidget {
  const KamiGate({
    super.key,
    required this.service,
    required this.savedCode,
    required this.onPassed,
    this.onSave,
    this.deviceReady,
  });

  final KamiService service;

  /// 上次校验通过并保存的卡密，没有则为空串。
  final String savedCode;

  /// 校验通过后进入应用，参数为本次使用的卡密。
  final void Function(String code) onPassed;

  /// 保存卡密到本地，供下次启动自动校验；同时带上校验结果（含到期信息）。
  final Future<void> Function(String code, KamiResult result)? onSave;

  /// 设备号就绪信号；发起任何请求前先等它，避免首包缺 `device` 字段。
  final Future<void>? deviceReady;

  @override
  State<KamiGate> createState() => _KamiGateState();
}

class _KamiGateState extends State<KamiGate> {
  late final _controller = TextEditingController();
  final _focus = FocusNode();

  /// 正在自动校验本地卡密，此时不展示输入框，避免闪烁。
  bool _autoChecking = false;
  bool _submitting = false;
  String? _error;

  /// 校验通过后的到期提示，短暂展示后进入主界面。
  String _passedRemain = '';

  @override
  void initState() {
    super.initState();
    final saved = widget.savedCode.trim();
    _controller.text = saved;
    if (saved.isNotEmpty) {
      _autoChecking = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _verify(saved, auto: true));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _verify(String code, {bool auto = false}) async {
    final value = code.trim();
    if (value.isEmpty) {
      setState(() {
        _autoChecking = false;
        _error = '请输入卡密';
      });
      return;
    }
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.deviceReady;
      // 自动复核走 /check（不重复计时）；手动输入的卡密走 /verify（首次激活）。
      final result = auto
          ? await widget.service.check(value)
          : await widget.service.verify(value);
      if (!mounted) return;
      if (result.ok) {
        await widget.onSave?.call(value, result);
        if (!mounted) return;
        // 到期信息只在本次会话首次进入时提示，随后进入主界面。
        final remain = result.remainText;
        if (remain.isNotEmpty) {
          setState(() {
            _submitting = false;
            _error = null;
            _passedRemain = remain;
          });
          await Future<void>.delayed(const Duration(milliseconds: 900));
          if (!mounted) return;
        }
        widget.onPassed(value);
        return;
      }
      setState(() {
        _submitting = false;
        _autoChecking = false;
        _controller.clear();
        _error = _reason(result.message);
      });
      _focus.requestFocus();
    } on KamiException catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _autoChecking = false;
        _error = error.message;
      });
      if (auto) _focus.requestFocus();
    }
  }

  /// 兜底文案，避免服务端返回空说明时输入框下方一片空白。
  static String _reason(String message) =>
      message.trim().isEmpty ? '卡密无效，请检查后重试' : message.trim();

  void _submit() => _verify(_controller.text);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: .05),
                        borderRadius: BorderRadius.circular(32),
                      ),
                      child: Image.asset(
                        'assets/icons/app.png',
                        width: 68,
                        height: 68,
                        excludeFromSemantics: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    '文析助手',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colors.onSurface,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '请输入卡密以继续使用',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 28),
                  if (_passedRemain.isNotEmpty)
                    _passedView(context)
                  else if (_autoChecking)
                    _autoCheckingView(context)
                  else
                    _inputView(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _passedView(BuildContext context) => Column(
    key: const ValueKey('kami-passed'),
    children: [
      Icon(
        Icons.check_circle_rounded,
        size: 40,
        color: Theme.of(context).colorScheme.primary,
      ),
      const SizedBox(height: 12),
      Text(
        '验证通过',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: secondary(context),
        ),
      ),
      const SizedBox(height: 6),
      Text(
        _passedRemain,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: secondary(context)),
      ),
    ],
  );

  Widget _autoCheckingView(BuildContext context) => Column(
    key: const ValueKey('kami-auto-checking'),
    children: [
      const AppLoadingIndicator(size: 26),
      const SizedBox(height: 14),
      Text(
        '正在验证已保存的卡密…',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: secondary(context)),
      ),
      if (_error != null) ...[
        const SizedBox(height: 14),
        Text(
          _error!,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            height: 1.35,
            color: Theme.of(context).colorScheme.error,
          ),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: _submitting
              ? null
              : () => _verify(widget.savedCode, auto: true),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('重试'),
        ),
      ],
    ],
  );

  Widget _inputView(BuildContext context) => Column(
    key: const ValueKey('kami-input'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        key: const ValueKey('kami-input-field'),
        controller: _controller,
        focusNode: _focus,
        autofocus: true,
        enabled: !_submitting,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.go,
        inputFormatters: [
          // 卡密为可见字符，去掉首尾空白并限制长度。
          LengthLimitingTextInputFormatter(128),
        ],
        decoration: InputDecoration(
          hintText: '卡密',
          prefixIcon: const Icon(Icons.vpn_key_outlined, size: 20),
          border: const OutlineInputBorder(),
          errorText: _error,
          errorMaxLines: 3,
        ),
        onSubmitted: (_) => _submit(),
      ),
      const SizedBox(height: 16),
      FilledButton(
        key: const ValueKey('kami-submit'),
        onPressed: _submitting ? null : _submit,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(46),
        ),
        child: _submitting
            ? const AppLoadingIndicator(size: 18, semanticLabel: '正在验证')
            : const Text('验证并进入'),
      ),
      if (_submitting) ...[
        const SizedBox(height: 14),
        Text(
          '正在连接验证服务，首次连接可能需要等待…',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: secondary(context)),
        ),
      ],
    ],
  );
}
