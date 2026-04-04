import 'package:latlong2/latlong.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'ui_state_provider.g.dart';

@riverpod
class MapTarget extends _$MapTarget {
  @override
  LatLng? build() => null;

  void setTarget(LatLng target) {
    state = target;
  }
}

@riverpod
class NavigationIndex extends _$NavigationIndex {
  @override
  int build() => 0;

  void setIndex(int index) => state = index;
}

@riverpod
class ShowOfflineRegions extends _$ShowOfflineRegions {
  @override
  bool build() => true;

  void toggle() => state = !state;
}

@riverpod
class ShowHeatmap extends _$ShowHeatmap {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

@riverpod
class ShowTerminalOverlay extends _$ShowTerminalOverlay {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

enum DrawingMode { none, area, path }

class DrawingState {
  final DrawingMode mode;
  final String? editingId;
  final List<LatLng> points;

  DrawingState({
    this.mode = DrawingMode.none,
    this.editingId,
    this.points = const [],
  });

  DrawingState copyWith({
    DrawingMode? mode,
    String? editingId,
    List<LatLng>? points,
    bool clearEditingId = false,
  }) {
    return DrawingState(
      mode: mode ?? this.mode,
      editingId: clearEditingId ? null : (editingId ?? this.editingId),
      points: points ?? this.points,
    );
  }
}

@riverpod
class DrawingController extends _$DrawingController {
  @override
  DrawingState build() => DrawingState();

  void startDrawingArea([String? id, List<LatLng>? initialPoints]) {
    state = DrawingState(
      mode: DrawingMode.area,
      editingId: id,
      points: initialPoints ?? [],
    );
  }

  void startDrawingPath([String? id, List<LatLng>? initialPoints]) {
    state = DrawingState(
      mode: DrawingMode.path,
      editingId: id,
      points: initialPoints ?? [],
    );
  }

  void addPoint(LatLng point) {
    state = state.copyWith(points: [...state.points, point]);
  }

  void removeLastPoint() {
    if (state.points.isNotEmpty) {
      state = state.copyWith(
        points: state.points.sublist(0, state.points.length - 1),
      );
    }
  }

  void updatePoint(int index, LatLng newPoint) {
    if (index >= 0 && index < state.points.length) {
      final newPoints = List<LatLng>.from(state.points);
      newPoints[index] = newPoint;
      state = state.copyWith(points: newPoints);
    }
  }

  void cancel() {
    state = DrawingState();
  }
}
