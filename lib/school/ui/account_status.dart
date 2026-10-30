import '../controller.dart';

extension AccountStatusText on AccountStatus {
  String get label => switch (this) {
    AccountStatus.unverified => '未连接',
    AccountStatus.signedIn => '已登录',
    AccountStatus.signedOut => '未登录',
    AccountStatus.expired => '需要重新登录',
    AccountStatus.smsRequired => '需要短信验证',
    AccountStatus.imageRequired => '需要图形验证',
  };
}
