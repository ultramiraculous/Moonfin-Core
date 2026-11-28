import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/ui/navigation/play_from_card.dart';
import 'package:moonfin/ui/widgets/focus/hub_focus_memory.dart';
import 'package:moonfin/ui/widgets/focus/locked_focus_row.dart';
import 'package:moonfin/ui/widgets/media_card.dart';
import 'package:moonfin/util/platform_detection.dart';

AggregatedItem _item(
  String type, {
  String id = 'a1',
  String serverId = 's1',
  Map<String, dynamic> extra = const {},
}) => AggregatedItem(
  id: id,
  serverId: serverId,
  rawData: {'Id': id, 'Name': id, 'Type': type, ...extra},
);

void main() {
  setUp(() => PlatformDetection.setTvMode(true));
  tearDown(() => PlatformDetection.setTvMode(false));

  group('canPlayFromCard', () {
    test('starts playable items and containers that have a play queue', () {
      for (final type in [
        'Movie',
        'Episode',
        'Series',
        'Season',
        'BoxSet',
        'Playlist',
        'MusicAlbum',
        'TvChannel',
      ]) {
        expect(canPlayFromCard(_item(type)), isTrue, reason: type);
      }
    });

    test('leaves browse-only items alone', () {
      for (final type in [
        'Folder',
        'CollectionFolder',
        'UserView',
        'Person',
        'Genre',
        'Studio',
        'Photo',
        'PhotoAlbum',
        'Book',
      ]) {
        expect(canPlayFromCard(_item(type)), isFalse, reason: type);
      }
    });

    test('skips Seerr items and missing episodes', () {
      expect(canPlayFromCard(_item('Movie', serverId: 'seerr')), isFalse);
      expect(
        canPlayFromCard(_item('Episode', extra: {'LocationType': 'Virtual'})),
        isFalse,
      );
    });

    test('only on the TV layout', () {
      PlatformDetection.setTvMode(false);
      expect(canPlayFromCard(_item('Movie')), isFalse);
    });
  });

  testWidgets('playFromCard opens the item with auto play', (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () => playFromCard(context, _item('Series')),
              child: const Text('go'),
            ),
          ),
        ),
        GoRoute(
          path: '/item/:id',
          builder: (_, state) => Text(state.uri.toString()),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('/item/a1?serverId=s1&autoPlay=true'), findsOneWidget);
  });

  testWidgets('a focused MediaCard runs onPlay on Play/Pause, not onTap', (
    tester,
  ) async {
    var plays = 0;
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: MediaCard(
            title: 'Card',
            width: 120,
            aspectRatio: 2 / 3,
            itemType: 'Movie',
            autofocus: true,
            onTap: () => taps++,
            onPlay: () {
              plays++;
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
    expect((plays, taps), (1, 0));

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect((plays, taps), (1, 1));
  });

  testWidgets('LockedFocusRow hands Play/Pause the focused item', (
    tester,
  ) async {
    HubFocusMemory.set('play-key', 1);
    final node = FocusNode();
    addTearDown(node.dispose);
    final played = <(int, String)>[];
    var tapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: LockedFocusRow<String>(
          items: const ['a', 'b', 'c'],
          hubKey: 'play-key',
          itemExtent: 40,
          itemSpacing: 0,
          height: 40,
          focusNode: node,
          autofocus: true,
          onTap: (_, _) => tapped++,
          onPlay: (index, item) {
            played.add((index, item));
            return true;
          },
          itemBuilder: (_, item, _, _) =>
              SizedBox(width: 40, child: Text(item)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
    expect(played, [(1, 'b')]);
    expect(tapped, 0);
  });
}
