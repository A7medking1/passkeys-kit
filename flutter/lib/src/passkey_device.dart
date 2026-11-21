import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:passkeys/authenticator.dart';
import 'package:passkeys/types.dart';

import 'passkey_exception.dart';

/// The phone's side of passkeys: the system sheet, Face ID or a fingerprint.
/// The tests swap it for a fake; your app uses [SystemPasskeyDevice].
abstract interface class PasskeyDevice {
  /// Whether this phone can use passkeys.
  Future<bool> isAvailable();

  /// Makes a passkey for `register/options`, and returns what
  /// `register/verify` takes as `response`.
  Future<Map<String, dynamic>> register(Map<String, dynamic> options);

  /// Signs `login/options` with a passkey the user picks, and returns what
  /// `login/verify` takes as `response`.
  Future<Map<String, dynamic>> authenticate(Map<String, dynamic> options);

  /// The phone's model ("iPhone 17 Pro"), to name a new passkey. Null when
  /// the phone won't say.
  Future<String?> name();
}

/// [PasskeyDevice] on the real phone, through the `passkeys` package
/// (iCloud Keychain on iOS 16+, Google Password Manager on Android 9+).
class SystemPasskeyDevice implements PasskeyDevice {
  /// [authenticator] defaults to the package's, checking the domain setup and
  /// printing what it finds in debug builds.
  SystemPasskeyDevice({PasskeyAuthenticator? authenticator})
    : _authenticator =
          authenticator ?? PasskeyAuthenticator(debugMode: kDebugMode);

  final PasskeyAuthenticator _authenticator;

  Future<bool>? _available;

  /// Asked once: it doesn't change while the app runs, and one future keeps a
  /// FutureBuilder from asking again on every build.
  @override
  Future<bool> isAvailable() => _available ??= _checkAvailability();

  Future<bool> _checkAvailability() async {
    try {
      switch (defaultTargetPlatform) {
        case TargetPlatform.iOS:
          return (await _authenticator.getAvailability().iOS())
              .hasPasskeySupport;
        case TargetPlatform.android:
          return (await _authenticator.getAvailability().android())
              .hasPasskeySupport;
        default:
          return false;
      }
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>> register(Map<String, dynamic> options) =>
      _run(() async {
        final response = await _authenticator.register(
          RegisterRequestType.fromJson(options),
        );
        return response.toJson();
      });

  @override
  Future<Map<String, dynamic>> authenticate(Map<String, dynamic> options) =>
      _run(() async {
        final response = await _authenticator.authenticate(
          AuthenticateRequestType.fromJson(options),
        );
        return response.toJson();
      });

  @override
  Future<String?> name() async {
    try {
      switch (defaultTargetPlatform) {
        case TargetPlatform.iOS:
          return (await DeviceInfoPlugin().iosInfo).modelName;
        case TargetPlatform.android:
          final android = await DeviceInfoPlugin().androidInfo;
          return '${android.manufacturer} ${android.model}';
        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }

  Future<T> _run<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PasskeyAuthCancelledException catch (error) {
      throw PasskeyException(PasskeyFailure.cancelled, cause: error);
    } on NoCredentialsAvailableException catch (error) {
      throw PasskeyException(PasskeyFailure.noPasskey, cause: error);
    } on ExcludeCredentialsCanNotBeRegisteredException catch (error) {
      throw PasskeyException(PasskeyFailure.alreadyRegistered, cause: error);
    } on SyncAccountNotAvailableException catch (error) {
      throw PasskeyException(PasskeyFailure.needsGoogleAccount, cause: error);
    } on MissingGoogleSignInException catch (error) {
      throw PasskeyException(PasskeyFailure.needsGoogleAccount, cause: error);
    } on DeviceNotSupportedException catch (error) {
      throw PasskeyException(PasskeyFailure.notSupported, cause: error);
    } on PasskeyUnsupportedException catch (error) {
      throw PasskeyException(PasskeyFailure.notSupported, cause: error);
    } on DomainNotAssociatedException catch (error) {
      debugPrint(
        'passkeys_kit: the app is not associated with the RP ID domain. '
        'Check the .well-known files and the entitlement. $error',
      );
      throw PasskeyException(PasskeyFailure.domainNotAssociated, cause: error);
    } catch (error) {
      debugPrint('passkeys_kit: $error');
      throw PasskeyException(PasskeyFailure.unknown, cause: error);
    }
  }
}
