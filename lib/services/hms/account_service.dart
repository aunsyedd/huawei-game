import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PlayerAccount {
  const PlayerAccount({required this.id, required this.displayName, this.huawei = false});
  final String id;
  final String displayName;

  /// Signed in with a real HUAWEI ID (as opposed to the local guest profile).
  final bool huawei;
}

/// A sign-in that failed for a reason worth telling the player about.
/// A cancelled sign-in is not an error: [AccountService.signIn] returns null.
class AccountException implements Exception {
  const AccountException(this.code, [this.message]);

  /// HMS status code, e.g. 6003 (signing certificate not registered in AppGallery Connect).
  final String code;
  final String? message;

  @override
  String toString() => 'AccountException($code, $message)';
}

/// Huawei Account Kit sign-in, behind an interface.
abstract class AccountService {
  PlayerAccount? get current;

  /// Restores an earlier sign-in without any UI (called once at start-up).
  Future<void> restore();
  Future<PlayerAccount?> signIn();
  Future<void> signOut();
}

/// Local stand-in: "signs in" a guest profile stored on the device.
class FakeAccountService implements AccountService {
  FakeAccountService(this._prefs) {
    final name = _prefs.getString('fake_account_name');
    if (name != null) _current = PlayerAccount(id: 'local', displayName: name);
  }

  final SharedPreferences _prefs;
  PlayerAccount? _current;

  @override
  PlayerAccount? get current => _current;

  @override
  Future<void> restore() async {}

  @override
  Future<PlayerAccount?> signIn() async {
    await _prefs.setString('fake_account_name', 'Pemain');
    return _current = const PlayerAccount(id: 'local', displayName: 'Pemain');
  }

  @override
  Future<void> signOut() async {
    await _prefs.remove('fake_account_name');
    _current = null;
  }
}

/// Real HUAWEI ID sign-in through Account Kit. The Android side lives in
/// MainActivity.kt on the `haze_royale/account` channel.
class HmsAccountService implements AccountService {
  static const _channel = MethodChannel('haze_royale/account');

  /// Status code Account Kit returns when the player closes the sign-in screen.
  static const _cancelled = '2012';

  PlayerAccount? _current;

  @override
  PlayerAccount? get current => _current;

  @override
  Future<void> restore() async {
    try {
      final m = await _channel.invokeMapMethod<String, String?>('silentSignIn').timeout(const Duration(seconds: 4));
      if (m != null) _current = _fromMap(m);
    } on Exception {
      // No earlier sign-in, no network or HMS too old: start as a guest.
    }
  }

  @override
  Future<PlayerAccount?> signIn() async {
    try {
      final m = await _channel.invokeMapMethod<String, String?>('signIn');
      return _current = m == null ? null : _fromMap(m);
    } on PlatformException catch (e) {
      if (e.code == _cancelled) return _current;
      throw AccountException(e.code, e.message);
    } on MissingPluginException {
      throw const AccountException('unavailable');
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _channel.invokeMethod<void>('signOut');
    } on Exception {
      // Signing out locally is enough if HMS cannot be reached.
    }
    _current = null;
  }

  static PlayerAccount _fromMap(Map<String, String?> m) {
    final name = m['displayName'];
    return PlayerAccount(
      id: m['openId'] ?? 'huawei',
      displayName: name == null || name.isEmpty ? 'HUAWEI ID' : name,
      huawei: true,
    );
  }
}
