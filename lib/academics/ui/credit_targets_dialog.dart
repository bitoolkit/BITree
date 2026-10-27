import 'package:flutter/material.dart';

import '../controller.dart';

class CreditTargetsDialog extends StatefulWidget {
  const CreditTargetsDialog({super.key, required this.controller});
  final AcademicController controller;

  @override
  State<CreditTargetsDialog> createState() => _CreditTargetsDialogState();
}

class _CreditTargetsDialogState extends State<CreditTargetsDialog> {
  final _form = GlobalKey<FormState>();
  late final _total = TextEditingController(
    text: widget.controller.record.targetCredits?.toString() ?? '',
  );
  late final _targets = <String, TextEditingController>{
    for (final category in {
      ...widget.controller.record.categoryTargets.keys,
      for (final grade in widget.controller.record.grades)
        widget.controller.record.categoryOf(grade),
    })
      category: TextEditingController(
        text:
            widget.controller.record.categoryTargets[category]?.toString() ??
            '',
      ),
  };
  final _newCategory = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _total.dispose();
    _newCategory.dispose();
    for (final input in _targets.values) {
      input.dispose();
    }
    super.dispose();
  }

  String? _validateCredits(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    final value = double.tryParse(text);
    return value == null || !value.isFinite || value < 0 ? '请输入非负学分' : null;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final record = widget.controller.record;
    final saved = await widget.controller.save(
      record.withCreditTargets(
        total: _total.text.trim().isEmpty ? null : double.parse(_total.text),
        categories: {
          for (final entry in _targets.entries)
            if (entry.value.text.trim().isNotEmpty)
              entry.key: double.parse(entry.value.text),
        },
      ),
    );
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      scrollable: true,
      title: const Text('核对学分目标'),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _total,
              enabled: !_saving,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: '总学分目标',
                helperText: '留空使用学校要求',
              ),
              validator: _validateCredits,
            ),
            for (final entry in _targets.entries) ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: entry.value,
                enabled: !_saving,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: '${entry.key}要求学分',
                  helperText: '留空取消这个分类的目标',
                ),
                validator: _validateCredits,
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newCategory,
                    enabled: !_saving,
                    decoration: const InputDecoration(labelText: '添加课程类别'),
                  ),
                ),
                IconButton(
                  tooltip: '添加类别',
                  onPressed: _saving
                      ? null
                      : () {
                          final category = _newCategory.text.trim();
                          if (category.isEmpty) return;
                          setState(() {
                            _targets.putIfAbsent(
                              category,
                              TextEditingController.new,
                            );
                            _newCategory.clear();
                          });
                        },
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? '保存中…' : '保存'),
        ),
      ],
    ),
  );
}
