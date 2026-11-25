import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/repositories/seerr_repository.dart';
import 'package:moonfin/data/services/seerr/seerr_api_models.dart';
import 'package:moonfin/data/viewmodels/seerr_media_detail_view_model.dart';
import 'package:moonfin/preference/seerr_preferences.dart';

class _FakeSeerr extends Fake implements SeerrRepository {
  final user = Completer<SeerrUser>();
  bool detailsRequested = false;

  @override
  Future<void> ensureInitialized({bool force = false}) async {}

  @override
  Future<Map<String, dynamic>> getPublicSettings() async => const {};

  @override
  Future<SeerrUser> getCurrentUser() => user.future;

  @override
  Future<(SeerrMovieDetails, bool)> getMovieDetailsWithWatchlist(
    int tmdbId,
  ) async {
    detailsRequested = true;
    return (
      const SeerrMovieDetails(
        id: 299534,
        title: 'Avengers: Endgame',
        mediaInfo: SeerrMediaInfo(status: 5),
      ),
      false,
    );
  }
}

class _FakePrefs extends Fake implements SeerrPreferences {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('details are requested without waiting for the user', () async {
    final seerr = _FakeSeerr();
    final vm = SeerrMediaDetailViewModel(seerr, _FakePrefs());
    final load = vm.load('299534', 'movie');
    await pumpEventQueue();

    expect(seerr.detailsRequested, isTrue);
    expect(vm.state.isLoading, isTrue);

    seerr.user.complete(SeerrUser(id: 7));
    await load;

    expect(vm.state.movie?.id, 299534);
    expect(vm.state.currentUser?.id, 7);
    vm.dispose();
  });

  test('a failed user fetch still shows the title', () async {
    final seerr = _FakeSeerr();
    final vm = SeerrMediaDetailViewModel(seerr, _FakePrefs());
    final load = vm.load('299534', 'movie');
    seerr.user.completeError(Exception('offline'));
    await load;

    expect(vm.state.error, isNull);
    expect(vm.state.movie?.id, 299534);
    expect(vm.state.currentUser, isNull);
    vm.dispose();
  });
}
