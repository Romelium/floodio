import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'hero_stats_provider.g.dart';

class HeroStats {
  final int dataCarriedBytes;
  final int peersSyncedWith;
  final int reportsRelayed;

  HeroStats({
    required this.dataCarriedBytes,
    required this.peersSyncedWith,
    required this.reportsRelayed,
  });

  String get status {
    if (reportsRelayed > 100 || peersSyncedWith > 20) return 'Lifesaver';
    if (reportsRelayed > 50 || peersSyncedWith > 10) return 'Community Hero';
    if (reportsRelayed > 10 || peersSyncedWith > 3) return 'Active Relay';
    return 'Citizen Node';
  }
}

@riverpod
class HeroStatsController extends _$HeroStatsController {
  @override
  Future<HeroStats> build() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return HeroStats(
      dataCarriedBytes: prefs.getInt('hero_data_carried') ?? 0,
      peersSyncedWith: prefs.getInt('hero_peers_synced') ?? 0,
      reportsRelayed: prefs.getInt('hero_reports_relayed') ?? 0,
    );
  }
}
