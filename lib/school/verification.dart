import 'dart:typed_data';

typedef VerifySchoolLogin = Future<String?> Function(
  SchoolVerification request,
);

enum SchoolVerificationKind { image, sms }

/// A non-interactive login stops before loading or sending a verification code.
class SchoolVerificationRequired implements Exception {
  const SchoolVerificationRequired(this.kind);

  final SchoolVerificationKind kind;
}

sealed class SchoolVerification {
  const SchoolVerification();
}

class SchoolImageVerification extends SchoolVerification {
  const SchoolImageVerification({required this.image, required this.reload});

  final Uint8List image;
  final Future<Uint8List> Function() reload;
}

class SchoolSmsVerification extends SchoolVerification {
  const SchoolSmsVerification({
    required this.phone,
    required this.sendCode,
    required this.checkCode,
  });

  final String phone;
  final Future<void> Function() sendCode;
  final Future<void> Function(String) checkCode;
}
