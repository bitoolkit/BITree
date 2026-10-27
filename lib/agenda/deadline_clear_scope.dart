import 'deadline_source.dart';
import 'model.dart';

/// Clearing is a deliberate hard delete, including completed/deleted records.
/// `local` is identified by origin, not AgendaEntry.local (an edit-protection
/// flag which can also be true for a locally edited platform deadline).
enum DeadlineClearScope {
  local(
    '本地创建的 DDL',
    '手动添加和从课表生成的 DDL；保留乐学、新延河课堂的 DDL',
  ),
  lexue('乐学 DDL', '从乐学同步的 DDL，包括在本地编辑过的条目'),
  eclass('新延河课堂 DDL', '从新延河课堂同步的 DDL，包括在本地编辑过的条目'),
  all('全部 DDL', '本地创建、乐学和新延河课堂的全部 DDL');

  const DeadlineClearScope(this.label, this.description);

  final String label;
  final String description;

  bool includes(AgendaEntry entry) =>
      entry.isDeadline &&
      (switch (this) {
        DeadlineClearScope.local => entry.source == null,
        DeadlineClearScope.lexue => entry.source == DeadlineSource.lexue,
        DeadlineClearScope.eclass => entry.source == DeadlineSource.eclass,
        DeadlineClearScope.all => true,
      });
}
