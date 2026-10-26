import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/school_verification.dart';
import '../diagnostics.dart';

Future<String?> verifySchoolLogin(
  BuildContext context,
  SchoolVerification request,
) {
  if (!context.mounted) return Future.value(null);
  return showDialog<String>(
    context: context,
    builder: (_) => _VerificationDialog(request: request),
  );
}

class _VerificationDialog extends StatefulWidget {
  const _VerificationDialog({required this.request});

  final SchoolVerification request;

  @override
  State<_VerificationDialog> createState() => _VerificationDialogState();
}

class _VerificationDialogState extends State<_VerificationDialog> {
  final _code = TextEditingController();
  final _form = GlobalKey<FormState>();
  Uint8List? _image;
  bool _loading = false;
  bool _submitting = false;
  int _resendSeconds = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.request case SchoolImageVerification(:final image)) {
      _image = image;
    } else {
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
    });
    try {
      switch (widget.request) {
        case SchoolImageVerification(:final reload):
          final image = await reload();
          if (mounted) setState(() => _image = image);
        case SchoolSmsVerification(:final sendCode):
          await sendCode();
          if (!mounted) return;
          setState(() => _resendSeconds = 60);
          _timer?.cancel();
          _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
            if (_resendSeconds == 1) timer.cancel();
            setState(() => _resendSeconds--);
          });
      }
    } catch (failure, stack) {
      AppDiagnostics.instance.report('获取登录验证码', failure, stack);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (_submitting || _loading || !_form.currentState!.validate()) return;
    setState(() {
      _submitting = true;
    });
    try {
      final code = _code.text.trim();
      if (widget.request case SchoolSmsVerification(:final checkCode)) {
        await checkCode(code);
      }
      if (mounted) Navigator.pop(context, code);
    } catch (failure, stack) {
      AppDiagnostics.instance.report('校验登录验证码', failure, stack);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sms = widget.request is SchoolSmsVerification;
    return AlertDialog(
      scrollable: true,
      title: Text(sms ? '短信验证' : '图形验证'),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.request case SchoolSmsVerification(:final phone))
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text('发送至 $phone'),
              ),
            if (!sms) ...[
              SizedBox(
                height: 80,
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _image == null
                    ? null
                    : Image.memory(_image!, fit: BoxFit.contain),
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _code,
              autofocus: true,
              enabled: !_submitting && !_loading,
              decoration: const InputDecoration(labelText: '验证码'),
              keyboardType: sms ? TextInputType.number : TextInputType.text,
              textInputAction: TextInputAction.done,
              autofillHints: sms ? const [AutofillHints.oneTimeCode] : null,
              inputFormatters: sms
                  ? [FilteringTextInputFormatter.digitsOnly]
                  : null,
              autocorrect: false,
              enableSuggestions: false,
              validator: (value) =>
                  value == null || value.trim().isEmpty ? '请输入验证码' : null,
              onFieldSubmitted: (_) => _submit(),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _loading || _submitting || _resendSeconds > 0
                    ? null
                    : _refresh,
                child: Text(
                  !sms
                      ? '换一张'
                      : _resendSeconds > 0
                      ? '$_resendSeconds 秒后重发'
                      : '重新发送',
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _loading || _submitting ? null : _submit,
          child: Text(_submitting ? '验证中…' : '确认'),
        ),
      ],
    );
  }
}
