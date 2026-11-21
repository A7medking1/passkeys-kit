import 'package:flutter_test/flutter_test.dart';
import 'package:passkeys_kit/passkeys_kit.dart';

/// The server, step by step in [calls].
class FakeServer implements PasskeyServerApi {
  final List<String> calls = [];
  Map<String, dynamic>? verified;
  String? verifiedName;

  @override
  Future<Map<String, dynamic>> loginOptions() async {
    calls.add('login/options');
    return {'challenge': 'login-challenge', 'rpId': 'example.com'};
  }

  @override
  Future<Map<String, dynamic>> loginVerify(
    Map<String, dynamic> response,
  ) async {
    calls.add('login/verify');
    verified = response;
    return {'token': 'session-token'};
  }

  @override
  Future<Map<String, dynamic>> registerOptions() async {
    calls.add('register/options');
    return {'challenge': 'register-challenge'};
  }

  @override
  Future<PasskeyInfo> registerVerify(
    Map<String, dynamic> response, {
    String? name,
  }) async {
    calls.add('register/verify');
    verified = response;
    verifiedName = name;
    return PasskeyInfo(id: 'new', name: name ?? '');
  }

  @override
  Future<List<PasskeyInfo>> list() async => const [];

  @override
  Future<void> delete(String id) async => calls.add('delete $id');
}

/// The phone, answering with [failure] instead when it's set.
class FakeDevice implements PasskeyDevice {
  PasskeyException? failure;
  Map<String, dynamic>? options;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<Map<String, dynamic>> authenticate(
    Map<String, dynamic> options,
  ) async {
    this.options = options;
    if (failure != null) throw failure!;
    return {'id': 'passkey-1', 'type': 'public-key'};
  }

  @override
  Future<Map<String, dynamic>> register(Map<String, dynamic> options) async {
    this.options = options;
    if (failure != null) throw failure!;
    return {'id': 'passkey-2', 'type': 'public-key'};
  }

  @override
  Future<String?> name() async => 'iPhone 17 Pro';
}

void main() {
  late FakeServer server;
  late FakeDevice device;
  late PasskeyClient passkeys;

  setUp(() {
    server = FakeServer();
    device = FakeDevice();
    passkeys = PasskeyClient(server: server, device: device);
  });

  test(
    'signIn: the options go to the phone, its answer to the server',
    () async {
      final session = await passkeys.signIn();

      expect(session, {'token': 'session-token'});
      expect(server.calls, ['login/options', 'login/verify']);
      expect(device.options?['challenge'], 'login-challenge');
      expect(server.verified?['id'], 'passkey-1');
    },
  );

  test('closing the sheet stops before the server is asked again', () async {
    device.failure = const PasskeyException(PasskeyFailure.cancelled);

    await expectLater(
      passkeys.signIn(),
      throwsA(
        isA<PasskeyException>().having(
          (e) => e.isCancelled,
          'isCancelled',
          true,
        ),
      ),
    );
    expect(server.calls, ['login/options']);
  });

  test('register names the passkey after the phone', () async {
    final passkey = await passkeys.register();

    expect(passkey.name, 'iPhone 17 Pro');
    expect(server.calls, ['register/options', 'register/verify']);
    expect(device.options?['challenge'], 'register-challenge');
    expect(server.verified?['id'], 'passkey-2');
  });

  test('register takes your own name too', () async {
    await passkeys.register(name: 'Work phone');
    expect(server.verifiedName, 'Work phone');
  });

  test('delete goes to the server', () async {
    await passkeys.delete('passkey-1');
    expect(server.calls, ['delete passkey-1']);
  });
}
