import 'package:flutter/foundation.dart';

/// Where the example server runs.
///
/// Set it with `--dart-define=SERVER_URL=https://api.example.com`. Without it,
/// the iOS Simulator uses `http://localhost:3000` and the Android emulator
/// `http://10.0.2.2:3000` (your computer, seen from the emulator).
Uri serverUrl() {
  const defined = String.fromEnvironment('SERVER_URL');
  final url = defined.isNotEmpty
      ? defined
      : defaultTargetPlatform == TargetPlatform.android
      ? 'http://10.0.2.2:3000'
      : 'http://localhost:3000';
  return Uri.parse(url.endsWith('/') ? url : '$url/');
}
