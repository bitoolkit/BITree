import 'package:flutter/material.dart';

import '../llm.dart';
import 'study_common.dart';

class StudyServices extends StatefulWidget {
  const StudyServices({super.key, required this.model});
  final StudyModel model;
  @override
  State<StudyServices> createState() => _StudyServicesState();
}

class _StudyServicesState extends State<StudyServices> {
  final _endpoint = TextEditingController();
  final _model = TextEditingController();
  final _key = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await studyOperation(
      context,
      '读取模型设置',
      widget.model.readSettings,
    );
    if (!mounted) return;
    _endpoint.text = settings?.endpoint ?? '';
    _model.text = settings?.model ?? '';
    _key.text = settings?.apiKey ?? '';
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final success = await studyOperation(context, '保存模型设置', () async {
      await widget.model.saveSettings(
        StudyModelSettings(
          endpoint: _endpoint.text.trim(),
          model: _model.text.trim(),
          apiKey: _key.text,
        ),
      );
      return true;
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (success == true) Navigator.pop(context, true);
  }

  @override
  void dispose() {
    _endpoint.dispose();
    _model.dispose();
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('学习服务')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Form(
                  key: _form,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        '大模型',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _endpoint,
                        decoration: const InputDecoration(
                          labelText: '接口地址',
                          hintText: 'https://服务地址/v1',
                        ),
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        validator: (value) {
                          final url = Uri.tryParse(value?.trim() ?? '');
                          if (url == null ||
                              !['http', 'https'].contains(url.scheme) ||
                              url.host.isEmpty ||
                              url.userInfo.isNotEmpty ||
                              url.hasQuery ||
                              url.hasFragment) {
                            return '请输入完整的接口地址';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _model,
                        decoration: const InputDecoration(labelText: '模型名称'),
                        autocorrect: false,
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? '请输入模型名称'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _key,
                        decoration: const InputDecoration(
                          labelText: 'API Key（本地服务可留空）',
                        ),
                        obscureText: true,
                        autocorrect: false,
                        enableSuggestions: false,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '兼容 OpenAI 接口，包括本地模型服务。密钥只存入系统安全存储。生成时会发送所选课时的字幕和笔记。',
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _saving ? null : _save,
                        child: Text(_saving ? '正在保存' : '保存'),
                      ),
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () async {
                                final success = await studyOperation(
                                  context,
                                  '移除模型设置',
                                  () async {
                                    await widget.model.disconnect();
                                    return true;
                                  },
                                );
                                if (context.mounted && success == true) {
                                  Navigator.pop(context, true);
                                }
                              },
                        child: const Text('移除配置'),
                      ),
                      const Divider(height: 40),
                      Text(
                        '必剪转写',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      const Text('在课时的字幕页面选择音频后使用。上传前会提示确认；不会自动发送录音。'),
                    ],
                  ),
                ),
              ),
            ),
          ),
  );
}
