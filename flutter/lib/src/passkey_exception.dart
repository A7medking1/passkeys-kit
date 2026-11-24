/// Why a passkey call failed. Map these to your own words, or show
/// [PasskeyException.message] as it is.
enum PasskeyFailure {
  /// The user closed the passkey sheet, or your Dio cancelled the request.
  /// Show nothing.
  cancelled,

  /// Signing in: this phone has no passkey for your app's domain.
  noPasskey,

  /// Adding: this phone already has a passkey for this account.
  alreadyRegistered,

  /// Android: passkeys live in Google Password Manager, which needs a Google
  /// account on the phone.
  needsGoogleAccount,

  /// This phone can't use passkeys (an old OS, or no screen lock).
  notSupported,

  /// The app isn't tied to the RP ID's domain: check the `.well-known` files,
  /// the iOS entitlement and the Android signing key. A setup problem, not
  /// the user's.
  domainNotAssociated,

  /// The server said no. [PasskeyException.message] is its message.
  server,

  /// The server couldn't be reached, or took too long to answer.
  network,

  /// Anything else. [PasskeyException.cause] has the details.
  unknown,
}

/// What every [PasskeyFailure] says when the server gave no message.
const Map<PasskeyFailure, String> defaultPasskeyMessages = {
  PasskeyFailure.cancelled: '',
  PasskeyFailure.noPasskey: "There's no passkey for this app on this phone.",
  PasskeyFailure.alreadyRegistered:
      'This phone already has a passkey for your account.',
  PasskeyFailure.needsGoogleAccount:
      'Add a Google account to this phone to use passkeys.',
  PasskeyFailure.notSupported: "This phone can't use passkeys.",
  PasskeyFailure.domainNotAssociated: "This app isn't set up for passkeys yet.",
  PasskeyFailure.server: 'Something went wrong. Please try again.',
  PasskeyFailure.network:
      "We couldn't reach the server. Check your connection.",
  PasskeyFailure.unknown:
      'Something went wrong with the passkey. Please try again.',
};

/// A passkey call that failed, from the phone or from the server.
class PasskeyException implements Exception {
  /// Creates an exception for [reason].
  const PasskeyException(
    this.reason, {
    String? message,
    this.statusCode,
    this.cause,
  }) : _message = message;

  /// Why it failed.
  final PasskeyFailure reason;

  final String? _message;

  /// The HTTP status, when the server answered.
  final int? statusCode;

  /// The original error, for your logs.
  final Object? cause;

  /// The server's message, or an English default for [reason]. Empty when
  /// the user cancelled.
  String get message => _message ?? defaultPasskeyMessages[reason]!;

  /// The user closed the sheet: nothing to show.
  bool get isCancelled => reason == PasskeyFailure.cancelled;

  @override
  String toString() =>
      'PasskeyException(${reason.name}${statusCode == null ? '' : ', $statusCode'}'
      '${message.isEmpty ? '' : ': $message'})';
}
