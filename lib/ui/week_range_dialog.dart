import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../schedule/model.dart';

Future<({int first, int last})?> showWeekRangeDialog(
  BuildContext context, {
  required int first,
  required int last,
  AppController? controller,
}) => showDialog<({int first, int last})>(
  context: context,
  builder: (_) =>
      _WeekRangeDialog(first: first, last: last, controller: controller),
);

Future<void> manageTermWeeks(
  BuildContext context,
  AppController controller,
) async {
  final schedule = controller.schedule!;
  await showWeekRangeDialog(
    context,
    first: schedule.firstWeek,
    last: schedule.lastWeek,
    controller: controller,
  );
}

class _WeekRangeDialog extends StatefulWidget {
  const _WeekRangeDialog({
    required this.first,
    required this.last,
    this.controller,
  });

  final int first;
  final int last;
  final AppController? controller;

  @override
  State<_WeekRangeDialog> createState() => _WeekRangeDialogState();
}

class _WeekRangeDialogState extends State<_WeekRangeDialog> {
  final _form = GlobalKey<FormState>();
  late final _first = TextEditingController(text: '${widget.first}');
  late final _last = TextEditingController(text: '${widget.last}');
  bool _saving = false;

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    super.dispose();
  }

  String? _validateWeek(String? value) {
    final week = int.tryParse(value!.trim());
    if (week == null) return '请输入整数周次';
    if (week == 0) return '没有第 0 周';
    return null;
  }

  void _step(TextEditingController field, int delta) {
    final current =
        int.tryParse(field.text.trim()) ??
        (field == _first ? widget.first : widget.last);
    final next = weekFromOffset(weekOffset(current) + delta);
    field.value = TextEditingValue(
      text: '$next',
      selection: TextSelection.collapsed(offset: '$next'.length),
    );
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final range = (
      first: int.parse(_first.text.trim()),
      last: int.parse(_last.text.trim()),
    );
    final controller = widget.controller;
    if (controller != null) {
      setState(() {
        _saving = true;
      });
      final saved = await controller.setWeekRange(
        first: range.first,
        last: range.last,
      );
      if (!mounted) return;
      if (!saved) {
        setState(() {
          _saving = false;
        });
        return;
      }
    }
    if (mounted) Navigator.pop(context, range);
  }

  Widget _input(
    String label,
    TextEditingController field, {
    bool last = false,
  }) {
    final firstWeek = int.tryParse(_first.text.trim());
    final lastWeek = int.tryParse(_last.text.trim());
    final canMoveInward =
        firstWeek == null || lastWeek == null || firstWeek < lastWeek;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Semantics(
          label: label,
          child: TextFormField(
            controller: field,
            enabled: !_saving,
            textAlign: TextAlign.center,
            keyboardType: const TextInputType.numberWithOptions(signed: true),
            textInputAction: last ? TextInputAction.done : TextInputAction.next,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              errorMaxLines: 3,
              prefixIcon: IconButton(
                tooltip: '减少一周',
                onPressed: _saving || (last && !canMoveInward)
                    ? null
                    : () => _step(field, -1),
                icon: const Icon(Icons.remove_rounded, size: 20),
              ),
              suffixIcon: IconButton(
                tooltip: '增加一周',
                onPressed: _saving || (!last && !canMoveInward)
                    ? null
                    : () => _step(field, 1),
                icon: const Icon(Icons.add_rounded, size: 20),
              ),
            ),
            validator: (value) {
              final error = _validateWeek(value);
              if (error != null || !last) return error;
              final first = int.tryParse(_first.text.trim());
              return first != null && int.parse(value!.trim()) < first
                  ? '截止周不能早于开始周'
                  : null;
            },
            onFieldSubmitted: last ? (_) => _save() : null,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final contentWidth =
        math.min(560.0, MediaQuery.sizeOf(context).width - 48) - 48;
    final minimumFieldWidth =
        96 + MediaQuery.textScalerOf(context).scale(15) * 4 + 16;
    final first = _input('开始周', _first);
    final last = _input('截止周', _last, last: true);

    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: const Text('周数管理'),
        constraints: const BoxConstraints(maxWidth: 560),
        insetPadding: const EdgeInsets.all(24),
        scrollable: true,
        content: SizedBox(
          width: double.maxFinite,
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (contentWidth >= minimumFieldWidth * 2 + 24)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: first),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(8, 42, 8, 0),
                        child: Text('—'),
                      ),
                      Expanded(child: last),
                    ],
                  )
                else ...[
                  first,
                  const SizedBox(height: 16),
                  last,
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '保存中…' : '确定'),
          ),
        ],
      ),
    );
  }
}
