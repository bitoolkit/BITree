import 'package:flutter/material.dart';

import '../../agenda/deadline_source.dart';
import '../../app/controller.dart';
import '../../ui/app_notice.dart';
import '../storage.dart';
import '../verification.dart';
import 'school_verification_dialog.dart';

enum SchoolAction {
  signIn('登录学校账号'),
  importSchedule('导入课表'),
  importExams('获取考试安排'),
  importGrades('导入成绩'),
  importStudyPlan('更新学分进度'),
  importLexueDeadlines('更新乐学 DDL', source: DeadlineSource.lexue),
  importEclassDeadlines('更新新延河课堂 DDL', source: DeadlineSource.eclass);

  const SchoolAction(this.label, {this.source});
  final String label;
  final DeadlineSource? source;
}

Future<bool> _fetchSchoolData(
  AppController controller,
  SchoolAction action,
  String? term,
  VerifySchoolLogin verify,
) => switch (action) {
  SchoolAction.signIn => throw StateError('登录不获取业务数据'),
  SchoolAction.importSchedule => controller.school.synchronize(
    term: term,
    verify: verify,
  ),
  SchoolAction.importExams => controller.school.importExams(
    term: term,
    verify: verify,
  ),
  SchoolAction.importGrades => controller.school.importGrades(verify: verify),
  SchoolAction.importStudyPlan => controller.school.importStudyPlan(
    verify: verify,
  ),
  SchoolAction.importLexueDeadlines || SchoolAction.importEclassDeadlines =>
    controller.school.importDeadlines(action.source!, verify: verify),
};

Future<bool?> openSchoolPage(
  BuildContext context,
  AppController controller, {
  required SchoolAction action,
  String? term,
}) async {
  if (controller.timetable.busy || controller.school.busy) return null;
  bool? success;
  if (action != SchoolAction.signIn && controller.school.username != null) {
    success = await _fetchSchoolData(
      controller,
      action,
      term,
      (request) => verifySchoolLogin(context, request),
    );
    if (!context.mounted || (!success && !controller.school.loginExpired)) {
      return success;
    }
  }

  if (success != true) {
    success = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            _SchoolScreen(controller: controller, action: action, term: term),
      ),
    );
  }
  if (success == true && action != SchoolAction.signIn && context.mounted) {
    showAppNotice(context, switch (action) {
      SchoolAction.importSchedule => '已更新课表',
      SchoolAction.importExams => '已更新考试安排',
      SchoolAction.importGrades => '已更新成绩',
      SchoolAction.importStudyPlan => '已更新学分进度',
      _ => '已更新${action.source!.label} DDL',
    });
  }
  return success;
}

class _SchoolScreen extends StatefulWidget {
  const _SchoolScreen({
    required this.controller,
    required this.action,
    this.term,
  });

  final AppController controller;
  final SchoolAction action;
  final String? term;

  @override
  State<_SchoolScreen> createState() => _SchoolScreenState();
}

class _SchoolScreenState extends State<_SchoolScreen> {
  final _form = GlobalKey<FormState>();
  late final _username = TextEditingController(
    text: widget.controller.school.username,
  );
  final _password = TextEditingController();
  SchoolAction? _operation;
  bool _hidePassword = true;

  bool get _importing => widget.action != SchoolAction.signIn;
  bool get _running => _operation != null;

  Future<void> _run() async {
    if (_running || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _operation = SchoolAction.signIn;
    });
    final controller = widget.controller;
    Future<String?> verify(SchoolVerification request) =>
        verifySchoolLogin(context, request);
    try {
      final signedIn = await controller.school.signIn(
        SchoolCredentials(username: _username.text, password: _password.text),
        verify,
        source: widget.action.source,
      );
      if (!mounted) return;
      if (!signedIn) return;
      _password.clear();
      if (_importing) setState(() => _operation = widget.action);
      final success =
          !_importing ||
          await _fetchSchoolData(
            controller,
            widget.action,
            widget.term,
            verify,
          );
      if (!mounted) return;
      _operation = null;
      Navigator.of(context).pop(success);
    } finally {
      if (mounted) setState(() => _operation = null);
    }
  }

  @override
  void dispose() {
    if (_running) widget.controller.school.cancel();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.action.label),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(3),
        child: SizedBox(
          height: 3,
          child: _running ? const LinearProgressIndicator(minHeight: 3) : null,
        ),
      ),
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: _buildForm(),
          ),
        ),
      ),
    ),
  );

  Widget _buildForm() => AutofillGroup(
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _username,
            enabled: !_running,
            readOnly: widget.controller.school.username != null,
            decoration: const InputDecoration(labelText: '学号'),
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.username],
            autocorrect: false,
            enableSuggestions: false,
            validator: (value) =>
                value == null || value.isEmpty ? '请输入学号' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _password,
            enabled: !_running,
            autofocus: widget.controller.school.username != null,
            obscureText: _hidePassword,
            decoration: InputDecoration(
              labelText: '密码',
              suffixIcon: IconButton(
                tooltip: _hidePassword ? '显示密码' : '隐藏密码',
                icon: Icon(
                  _hidePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: _running
                    ? null
                    : () => setState(() => _hidePassword = !_hidePassword),
              ),
            ),
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            validator: (value) =>
                value == null || value.isEmpty ? '请输入密码' : null,
            onFieldSubmitted: (_) => _run(),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _running ? null : _run,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_running) ...[
                  const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                ],
                Text(switch (_operation) {
                  SchoolAction.signIn => '登录中…',
                  SchoolAction.importSchedule => '导入中…',
                  SchoolAction.importExams ||
                  SchoolAction.importGrades ||
                  SchoolAction.importStudyPlan ||
                  SchoolAction.importLexueDeadlines ||
                  SchoolAction.importEclassDeadlines => '获取中…',
                  null => switch (widget.action) {
                    SchoolAction.signIn => '登录',
                    SchoolAction.importSchedule => '登录并导入',
                    SchoolAction.importExams ||
                    SchoolAction.importGrades ||
                    SchoolAction.importStudyPlan ||
                    SchoolAction.importLexueDeadlines ||
                    SchoolAction.importEclassDeadlines => '登录并获取',
                  },
                }),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
