import '../controller.dart';

extension MoocStatusText on MoocStatus {
  String get label => switch (this) {
    MoocStatus.connected => '已连接',
    MoocStatus.signedOut => '未登录',
    MoocStatus.expired => '需要重新登录',
  };
}
