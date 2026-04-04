import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'terminal_log_provider.g.dart';

@Riverpod(keepAlive: true)
class TerminalLogController extends _$TerminalLogController {
  @override
  List<String> build() {
    return [];
  }

  void addLog(String log) {
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    state = [...state, '[$timeStr] $log'];
    if (state.length > 200) {
      state = state.sublist(state.length - 200);
    }
  }

  void clear() {
    state = [];
  }
}
