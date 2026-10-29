import 'deadline_source.dart';
import 'model.dart';
import 'physics_lab_deadlines.dart';

/// Disjoint origin groups, independent of the local-edit protection flag.
/// Clearing includes completed entries and soft-deleted records.
enum DeadlineClearScope {
  manual('手动创建的 DDL', '手动添加的 DDL，不包括大物实验和平台同步的条目'),
  physicsLab('大物实验 DDL', '从课表生成的大物实验 DDL，包括本地编辑过的条目'),
  lexue('乐学 DDL', '从乐学同步的 DDL，包括在本地编辑过的条目'),
  eclass('新延河课堂 DDL', '从新延河课堂同步的 DDL，包括在本地编辑过的条目'),
  mooc('中国大学MOOC DDL', '从中国大学MOOC 同步的 DDL，包括在本地编辑过的条目');

  const DeadlineClearScope(this.label, this.description);

  final String label;
  final String description;

  bool includes(AgendaEntry entry) =>
      entry.isDeadline &&
      (switch (this) {
        DeadlineClearScope.manual =>
          entry.source == null && !isPhysicsLabDeadline(entry),
        DeadlineClearScope.physicsLab => isPhysicsLabDeadline(entry),
        DeadlineClearScope.lexue => entry.source == DeadlineSource.lexue,
        DeadlineClearScope.eclass => entry.source == DeadlineSource.eclass,
        DeadlineClearScope.mooc => entry.source == DeadlineSource.mooc,
      });
}
