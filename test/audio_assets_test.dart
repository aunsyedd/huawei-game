import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every sound the code asks for must exist in assets/audio, and every file
/// there should be used (catches typos that would silently play nothing).
void main() {
  test('all referenced sounds exist and all sound files are used', () {
    final files = Directory('assets/audio')
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((n) => n.endsWith('.wav'))
        .map((n) => n.substring(0, n.length - 4))
        .toSet();
    expect(files, isNotEmpty);

    final referenced = <String>{};
    final call = RegExp(r"""(?:sfx|play|music|_play3d)\(\s*'([a-z_]+)'""");
    final mapped = RegExp(r"""=>\s*'((?:shot)_[a-z]+)'""");
    final listed = RegExp(r"""'([a-z_]+)'\s*:\s*\d""");
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      for (final m in call.allMatches(src)) {
        referenced.add(m.group(1)!);
      }
      for (final m in mapped.allMatches(src)) {
        referenced.add(m.group(1)!);
      }
      if (f.path.endsWith('audio_service.dart')) {
        for (final m in listed.allMatches(src)) {
          referenced.add(m.group(1)!);
        }
      }
    }
    // Ternaries like r.won ? 'win' : 'lose'.
    referenced.addAll(['win', 'lose']);

    final missing = referenced.difference(files);
    expect(missing, isEmpty, reason: 'sounds referenced in code but missing from assets/audio');
    final unused = files.difference(referenced);
    expect(unused, isEmpty, reason: 'sound files nobody plays');
  });
}
