import 'package:shared_preferences/shared_preferences.dart';

class PlayerAccount {
  const PlayerAccount({required this.id, required this.displayName});
  final String id;
  final String displayName;
}

/// Huawei Account Kit sign-in, behind an interface.
abstract class AccountService {
  PlayerAccount? get current;
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
