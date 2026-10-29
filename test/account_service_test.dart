import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haze_royale/services/hms/account_service.dart';

/// HmsAccountService against a mocked `haze_royale/account` channel, standing
/// in for MainActivity's Account Kit calls.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('haze_royale/account');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void answer(Future<Object?> Function(MethodCall call) handler) =>
      messenger.setMockMethodCallHandler(channel, handler);

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('sign-in returns the HUAWEI ID nickname', () async {
    answer((call) async => {'openId': 'abc123', 'displayName': 'Aiman', 'avatarUri': null});
    final svc = HmsAccountService();
    final acc = await svc.signIn();
    expect(acc?.displayName, 'Aiman');
    expect(acc?.id, 'abc123');
    expect(acc?.huawei, isTrue);
    expect(svc.current?.displayName, 'Aiman');
  });

  test('closing the sign-in screen keeps the player a guest', () async {
    answer((call) async => throw PlatformException(code: '2012', message: 'cancelled'));
    final svc = HmsAccountService();
    expect(await svc.signIn(), isNull);
  });

  test('a real failure reports the HMS status code', () async {
    answer((call) async => throw PlatformException(code: '6003', message: 'certificate fingerprint'));
    final svc = HmsAccountService();
    await expectLater(svc.signIn(), throwsA(isA<AccountException>().having((e) => e.code, 'code', '6003')));
  });

  test('silent restore signs back in, or quietly stays a guest', () async {
    answer((call) async => call.method == 'silentSignIn' ? {'openId': 'x', 'displayName': ''} : null);
    final svc = HmsAccountService();
    await svc.restore();
    expect(svc.current?.displayName, 'HUAWEI ID'); // empty nickname falls back

    answer((call) async => null);
    final guest = HmsAccountService();
    await guest.restore();
    expect(guest.current, isNull);
  });

  test('sign-out clears the account even if HMS is unreachable', () async {
    answer((call) async => call.method == 'signOut' ? throw PlatformException(code: 'x') : {'openId': 'a', 'displayName': 'A'});
    final svc = HmsAccountService();
    await svc.signIn();
    await svc.signOut();
    expect(svc.current, isNull);
  });
}
