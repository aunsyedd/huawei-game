import 'package:flutter/widgets.dart';

/// All UI text in English and Bahasa Malaysia.
/// Usage: `final s = S.of(context); s('play')` or `s('alive_n', {'n': '5'})`.
class S {
  const S(this.lang);
  final String lang;

  static S of(BuildContext context) => S(Localizations.localeOf(context).languageCode == 'ms' ? 'ms' : 'en');

  String call(String key, [Map<String, Object> params = const {}]) {
    var text = _strings[key]?[lang] ?? _strings[key]?['en'] ?? key;
    params.forEach((k, v) => text = text.replaceAll('{$k}', '$v'));
    return text;
  }

  static const Map<String, Map<String, String>> _strings = {
    'app_title': {'en': 'Haze Royale', 'ms': 'Haze Royale'},
    'tagline': {'en': 'Survive the haze. Plant the future.', 'ms': 'Harungi jerebu. Tanam masa depan.'},
    'play': {'en': 'Play', 'ms': 'Main'},
    'leaderboard': {'en': 'Leaderboard', 'ms': 'Papan Pendahulu'},
    'settings': {'en': 'Settings', 'ms': 'Tetapan'},
    'sign_in': {'en': 'Sign in', 'ms': 'Log masuk'},
    'sign_out': {'en': 'Sign out', 'ms': 'Log keluar'},
    'signed_in_as': {'en': 'Signed in as {name}', 'ms': 'Log masuk sebagai {name}'},
    'guest': {'en': 'Playing as guest', 'ms': 'Bermain sebagai tetamu'},
    'hms_on': {'en': 'Huawei Mobile Services', 'ms': 'Huawei Mobile Services'},
    'hms_off': {'en': 'Offline mode (no HMS)', 'ms': 'Mod luar talian (tiada HMS)'},
    'lobby_title': {'en': 'Finding players', 'ms': 'Mencari pemain'},
    'lobby_ready': {'en': 'Lobby full!', 'ms': 'Lobi penuh!'},
    'players_joined': {'en': '{n}/{total} players', 'ms': '{n}/{total} pemain'},
    'start_match': {'en': 'Start match', 'ms': 'Mula perlawanan'},
    'back': {'en': 'Back', 'ms': 'Kembali'},
    'loading': {'en': 'Loading...', 'ms': 'Memuatkan...'},
    'choose_landing': {'en': 'Tap the map to choose where to land', 'ms': 'Ketik peta untuk memilih tempat mendarat'},
    'landing_in': {'en': 'Dropping in {n}s', 'ms': 'Terjun dalam {n}s'},
    'drop_now': {'en': 'Drop now', 'ms': 'Terjun sekarang'},
    'area_forest': {'en': 'Forest', 'ms': 'Hutan'},
    'area_plantation': {'en': 'Palm oil estate', 'ms': 'Ladang sawit'},
    'area_kampung': {'en': 'Kampung', 'ms': 'Kampung'},
    'area_town': {'en': 'Town', 'ms': 'Pekan'},
    'area_beach': {'en': 'Beach', 'ms': 'Pantai'},
    'alive': {'en': 'Alive', 'ms': 'Hidup'},
    'tags': {'en': 'Tag-outs', 'ms': 'Tag keluar'},
    'haze_in': {'en': 'Haze moves in {t}', 'ms': 'Jerebu bergerak dalam {t}'},
    'haze_closing': {'en': 'Haze closing in!', 'ms': 'Jerebu menghampiri!'},
    'haze_final': {'en': 'Thick haze everywhere', 'ms': 'Jerebu tebal di mana-mana'},
    'in_haze': {'en': 'You are in the haze!', 'ms': 'Anda berada dalam jerebu!'},
    'reloading': {'en': 'Reloading', 'ms': 'Mengisi semula'},
    'reload': {'en': 'Reload', 'ms': 'Isi'},
    'swap': {'en': 'Swap', 'ms': 'Tukar'},
    'pick_up': {'en': 'Take {item}', 'ms': 'Ambil {item}'},
    'plant': {'en': 'Hold to plant', 'ms': 'Tahan untuk tanam'},
    'planting': {'en': 'Planting...', 'ms': 'Menanam...'},
    'healing': {'en': 'Drinking water...', 'ms': 'Minum air...'},
    'masking': {'en': 'Putting on mask...', 'ms': 'Memakai topeng...'},
    'no_plant_here': {'en': "Can't plant here", 'ms': 'Tidak boleh tanam di sini'},
    'tagged_out_by': {'en': '{a} tagged out {b}', 'ms': '{a} tag keluar {b}'},
    'haze_out': {'en': '{b} was overcome by haze', 'ms': '{b} tewas akibat jerebu'},
    'you_win': {'en': 'Last one breathing!', 'ms': 'Yang terakhir bernafas!'},
    'you_out': {'en': 'Tagged out!', 'ms': 'Anda ditag keluar!'},
    'placement_of': {'en': '#{p} of {n}', 'ms': '#{p} daripada {n}'},
    'see_results': {'en': 'See results', 'ms': 'Lihat keputusan'},
    'spectate': {'en': 'Spectate', 'ms': 'Tonton'},
    'spectating': {'en': 'Spectating {name}', 'ms': 'Menonton {name}'},
    'quit': {'en': 'Quit match', 'ms': 'Keluar perlawanan'},
    'quit_confirm': {'en': 'Leave this match?', 'ms': 'Tinggalkan perlawanan ini?'},
    'cancel': {'en': 'Cancel', 'ms': 'Batal'},
    'results': {'en': 'Results', 'ms': 'Keputusan'},
    'placement': {'en': 'Placement', 'ms': 'Kedudukan'},
    'time_survived': {'en': 'Time survived', 'ms': 'Masa bertahan'},
    'trees_planted': {'en': 'Trees planted', 'ms': 'Pokok ditanam'},
    'score': {'en': 'Score', 'ms': 'Skor'},
    'new_best': {'en': 'New best!', 'ms': 'Rekod baharu!'},
    'did_you_know': {'en': 'Did you know?', 'ms': 'Tahukah anda?'},
    'play_again': {'en': 'Play again', 'ms': 'Main lagi'},
    'menu': {'en': 'Menu', 'ms': 'Menu'},
    'wins': {'en': 'Wins', 'ms': 'Kemenangan'},
    'total_tags': {'en': 'Total tag-outs', 'ms': 'Jumlah tag keluar'},
    'total_trees': {'en': 'Total trees', 'ms': 'Jumlah pokok'},
    'matches': {'en': 'Matches', 'ms': 'Perlawanan'},
    'best_score': {'en': 'Best score', 'ms': 'Skor terbaik'},
    'achievements': {'en': 'Achievements', 'ms': 'Pencapaian'},
    'achievement_unlocked': {'en': 'Achievement unlocked: {name}', 'ms': 'Pencapaian dibuka: {name}'},
    'your_stats': {'en': 'Your stats', 'ms': 'Statistik anda'},
    'sound': {'en': 'Sound effects', 'ms': 'Kesan bunyi'},
    'music': {'en': 'Music', 'ms': 'Muzik'},
    'sensitivity': {'en': 'Aim sensitivity', 'ms': 'Kepekaan bidikan'},
    'language': {'en': 'Language', 'ms': 'Bahasa'},
    'haptics': {'en': 'Vibration', 'ms': 'Getaran'},
    'show_fps': {'en': 'Show FPS', 'ms': 'Tunjuk FPS'},
    'reset_tutorial': {'en': 'Show tutorial again', 'ms': 'Tunjuk tutorial semula'},
    'tutorial_reset_done': {
      'en': 'Tutorial will show next match',
      'ms': 'Tutorial akan dipaparkan perlawanan seterusnya',
    },
    'tut_move': {'en': 'Drag on the left side to move', 'ms': 'Seret di sebelah kiri untuk bergerak'},
    'tut_aim': {
      'en': 'Drag the right stick to aim. Push it further to fire',
      'ms': 'Seret kayu kanan untuk membidik. Tolak lebih jauh untuk menembak',
    },
    'tut_loot': {
      'en': 'Walk over loot to pick it up. Find better blasters in buildings',
      'ms': 'Jalan di atas barang untuk mengambilnya. Cari penembak lebih baik dalam bangunan',
    },
    'tut_haze': {
      'en': 'Stay inside the white circle. The haze drains your health!',
      'ms': 'Kekal dalam bulatan putih. Jerebu mengurangkan nyawa anda!',
    },
    'tut_plant': {
      'en': 'Have seeds? Hold the tree button to plant. Trees make clean air in the haze',
      'ms': 'Ada benih? Tahan butang pokok untuk menanam. Pokok menghasilkan udara bersih dalam jerebu',
    },
    'ok': {'en': 'Got it', 'ms': 'Faham'},
    'ach_first_match': {'en': 'First Drop', 'ms': 'Terjunan Pertama'},
    'ach_first_win': {'en': 'Clear Skies', 'ms': 'Langit Cerah'},
    'ach_pacifist_win': {'en': 'Peaceful Victory', 'ms': 'Kemenangan Aman'},
    'ach_green_thumb': {'en': 'Green Thumb (10 trees in a match)', 'ms': 'Tangan Hijau (10 pokok sepadan)'},
    'ach_forest_maker': {'en': 'Forest Maker (50 trees total)', 'ms': 'Pembina Hutan (50 pokok)'},
    'ach_sharpshooter': {'en': 'Sharpshooter (5 tag-outs in a match)', 'ms': 'Penembak Tepat (5 tag keluar)'},
    'ach_survivor': {'en': 'Survivor (3 minutes alive)', 'ms': 'Penyelamat (3 minit hidup)'},
    'ach_haze_walker': {
      'en': 'Haze Walker (30 s in haze and win)',
      'ms': 'Pengembara Jerebu (30 s dalam jerebu dan menang)',
    },
    'rotate_device': {'en': 'Turn your phone sideways to play', 'ms': 'Pusingkan telefon anda ke sisi untuk bermain'},
    'air_alert': {'en': 'Air quality alert', 'ms': 'Amaran kualiti udara'},
  };
}
