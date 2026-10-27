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
  bool _loadFailed = false;
  bool _saving = false;
  bool _enabled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final result = await studyOperation(
      context,
      '读取模型设置',
      () async => (settings: await widget.model.readSettings()),
    );
    if (!mounted) return;
    final settings = result?.settings;
    _endpoint.text = settings?.endpoint ?? '';
    _model.text = settings?.model ?? '';
    _key.text = settings?.apiKey ?? '';
    _enabled = settings != null;
    setState(() {
      _loading = false;
      _loadFailed = result == null;
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final success = await studyOperation(context, '保存模型设置', () async {
      if (_enabled) {
        await widget.model.saveSettings(
          StudyModelSettings(
            endpoint: _endpoint.text.trim(),
            model: _model.text.trim(),
            apiKey: _key.text,
          ),
        );
      } else {
        await widget.model.disconnect();
      }
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fields = Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('模型服务（可选）', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('启用模型服务'),
            subtitle: const Text('课程问答、笔记整理和复习提纲'),
            value: _enabled,
            onChanged: _saving
                ? null
                : (value) => setState(() => _enabled = value),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _endpoint,
            enabled: _enabled && !_saving,
            decoration: const InputDecoration(
              labelText: '接口地址',
              hintText: 'https://服务地址/v1',
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
            validator: (value) {
              if (!_enabled) return null;
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
          const SizedBox(height: 20),
          TextFormField(
            controller: _model,
            enabled: _enabled && !_saving,
            decoration: const InputDecoration(labelText: '模型名称'),
            autocorrect: false,
            validator: (value) =>
                _enabled && (value == null || value.trim().isEmpty)
                ? '请输入模型名称'
                : null,
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _key,
            enabled: _enabled && !_saving,
            decoration: const InputDecoration(labelText: 'API Key（本地服务可留空）'),
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '正在保存' : '保存设置'),
          ),
          const Divider(height: 48),
          Text('必剪转写', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          const Text('在课时的字幕页面选择音频后使用。上传前会提示确认。'),
        ],
      ),
    );
    final information = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('数据发送范围', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        const Text('生成时会发送所选课时的字幕和笔记。截图和录播不会发送给模型。'),
        const SizedBox(height: 24),
        Text('连接与存储', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        const Text('兼容 OpenAI 接口，也可使用本地模型。密钥保存在系统安全存储中。关闭后保存，即可移除连接。'),
      ],
    );
    return Scaffold(
      appBar: AppBar(title: const Text('学习服务')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadFailed
          ? Center(
              child: StudyEmpty(
                text: '无法读取模型设置',
                action: TextButton(onPressed: _load, child: const Text('重试')),
              ),
            )
          : SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1050),
                  child: LayoutBuilder(
                    builder: (context, size) => ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        if (size.maxWidth >= 850)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: fields),
                              const SizedBox(width: 64),
                              SizedBox(width: 260, child: information),
                            ],
                          )
                        else ...[
                          fields,
                          const Divider(height: 48),
                          information,
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
