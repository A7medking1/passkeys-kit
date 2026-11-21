import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passkeys_kit/passkeys_kit.dart';
import 'package:passkeys_kit_example/main.dart';
import 'package:passkeys_kit_example/src/app_state.dart';

/// The server: a passkey sign-in answers like the example server does.
class FakeServer implements PasskeyServerApi {
  final List<PasskeyInfo> passkeys = [];

  @override
  Future<Map<String, dynamic>> loginOptions() async => {'challenge': 'c'};

  @override
  Future<Map<String, dynamic>> loginVerify(
    Map<String, dynamic> response,
  ) async => {
    'token': 'token-1',
    'user': {
      'id': 'u1',
      'name': 'Ahmed Nasr',
      'email': 'ahmed.nasr@example.com',
    },
  };

  @override
  Future<Map<String, dynamic>> registerOptions() async => {'challenge': 'c'};

  @override
  Future<PasskeyInfo> registerVerify(
    Map<String, dynamic> response, {
    String? name,
  }) async {
    final passkey = PasskeyInfo(
      id: 'pk${passkeys.length + 1}',
      name: name ?? 'Passkey',
      deviceType: 'multiDevice',
      createdAt: DateTime.now(),
    );
    passkeys.insert(0, passkey);
    return passkey;
  }

  @override
  Future<List<PasskeyInfo>> list() async => [...passkeys];

  @override
  Future<void> delete(String id) async =>
      passkeys.removeWhere((passkey) => passkey.id == id);
}

class FakeDevice implements PasskeyDevice {
  FakeDevice({this.available = true});

  final bool available;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<Map<String, dynamic>> authenticate(
    Map<String, dynamic> options,
  ) async => {'id': 'pk1'};

  @override
  Future<Map<String, dynamic>> register(Map<String, dynamic> options) async => {
    'id': 'pk1',
  };

  @override
  Future<String?> name() async => 'iPhone 17 Pro';
}

Future<void> pumpExample(WidgetTester tester, {bool available = true}) async {
  final state = AppState(
    serverUrl: Uri.parse('http://localhost:3000/'),
    passkeys: PasskeyClient(
      server: FakeServer(),
      device: FakeDevice(available: available),
    ),
  );
  await tester.pumpWidget(PasskeysKitExample(state: state));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('signs in with a passkey, then adds one on this phone', (
    tester,
  ) async {
    await pumpExample(tester);

    await tester.tap(find.byKey(const Key('passkey-sign-in')));
    await tester.pumpAndSettle();
    expect(find.text('Ahmed Nasr'), findsOneWidget);
    expect(find.text('Signed in with a passkey'), findsOneWidget);
    expect(find.text('No passkeys yet'), findsOneWidget);

    await tester.tap(find.byKey(const Key('add-passkey')));
    await tester.pumpAndSettle();
    expect(find.text('iPhone 17 Pro'), findsOneWidget);
    expect(find.text('Synced'), findsOneWidget);
  });

  testWidgets('no passkey button on a phone that cannot use them', (
    tester,
  ) async {
    await pumpExample(tester, available: false);

    expect(find.byKey(const Key('passkey-sign-in')), findsNothing);
    expect(find.byKey(const Key('password-sign-in')), findsOneWidget);
  });
}
