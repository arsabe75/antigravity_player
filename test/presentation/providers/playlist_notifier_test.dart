import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_app/domain/entities/playlist_entity.dart';
import 'package:video_player_app/presentation/providers/playlist_notifier.dart';
import 'package:riverpod/riverpod.dart';

void main() {
  group('PlaylistNotifier', () {
    late ProviderContainer container;
    late PlaylistNotifier notifier;

    setUp(() {
      container = ProviderContainer();
      notifier = container.read(playlistProvider.notifier);
    });

    tearDown(() {
      container.dispose();
    });

    group('addItem', () {
      test('adds single item to empty playlist', () {
        notifier.addItem('/path/video.mp4');
        final playlist = container.read(playlistProvider);
        
        expect(playlist.length, 1);
        expect(playlist.items.first.path, '/path/video.mp4');
        expect(playlist.items.first.isNetwork, false);
      });

      test('adds network item correctly', () {
        notifier.addItem('https://example.com/video.mp4', isNetwork: true);
        final playlist = container.read(playlistProvider);
        
        expect(playlist.items.first.isNetwork, true);
      });

      test('adds multiple items', () {
        notifier.addItem('/path/video1.mp4');
        notifier.addItem('/path/video2.mp4');
        notifier.addItem('/path/video3.mp4');
        final playlist = container.read(playlistProvider);
        
        expect(playlist.length, 3);
      });

      test('sets title from path basename', () {
        notifier.addItem('/home/user/videos/MyMovie.mp4');
        final playlist = container.read(playlistProvider);
        
        expect(playlist.items.first.title, 'MyMovie.mp4');
      });

      test('uses custom title when provided', () {
        notifier.addItem('/path/video.mp4', title: 'Custom Title');
        final playlist = container.read(playlistProvider);
        
        expect(playlist.items.first.title, 'Custom Title');
      });
    });

    group('removeItem', () {
      setUp(() {
        notifier.addItem('/path/video1.mp4');
        notifier.addItem('/path/video2.mp4');
        notifier.addItem('/path/video3.mp4');
      });

      test('removes item at index', () {
        notifier.removeItem(1);
        final playlist = container.read(playlistProvider);
        
        expect(playlist.length, 2);
        expect(playlist.items[0].path, '/path/video1.mp4');
        expect(playlist.items[1].path, '/path/video3.mp4');
      });

      test('adjusts currentIndex when removing before current', () {
        notifier.goToIndex(2);
        notifier.removeItem(0);
        final playlist = container.read(playlistProvider);
        
        expect(playlist.currentIndex, 1);
      });

      test('ignores invalid index', () {
        notifier.removeItem(10);
        final playlist = container.read(playlistProvider);
        
        expect(playlist.length, 3);
      });

      test('ignores negative index', () {
        notifier.removeItem(-1);
        final playlist = container.read(playlistProvider);
        
        expect(playlist.length, 3);
      });
    });

    group('goToIndex', () {
      setUp(() {
        notifier.addItem('/path/video1.mp4');
        notifier.addItem('/path/video2.mp4');
        notifier.addItem('/path/video3.mp4');
      });

      test('changes current index', () {
        notifier.goToIndex(2);
        final playlist = container.read(playlistProvider);
        
        expect(playlist.currentIndex, 2);
      });

      test('ignores invalid index', () {
        notifier.goToIndex(10);
        final playlist = container.read(playlistProvider);
        
        expect(playlist.currentIndex, 0);
      });
    });

    group('next', () {
      setUp(() {
        notifier.addItem('/path/video1.mp4');
        notifier.addItem('/path/video2.mp4');
        notifier.addItem('/path/video3.mp4');
      });

      test('moves to next item', () {
        final result = notifier.next();
        final playlist = container.read(playlistProvider);
        
        expect(result, true);
        expect(playlist.currentIndex, 1);
      });

      test('returns false at end with repeat none', () {
        notifier.goToIndex(2);
        final result = notifier.next();
        final playlist = container.read(playlistProvider);
        
        expect(result, false);
        expect(playlist.currentIndex, 2);
      });

      test('loops to beginning with repeat all', () {
        notifier.setRepeatMode(RepeatMode.all);
        notifier.goToIndex(2);
        final result = notifier.next();
        final playlist = container.read(playlistProvider);
        
        expect(result, true);
        expect(playlist.currentIndex, 0);
      });
    });

    group('previous', () {
      setUp(() {
        notifier.addItem('/path/video1.mp4');
        notifier.addItem('/path/video2.mp4');
        notifier.addItem('/path/video3.mp4');
        notifier.goToIndex(1);
      });

      test('moves to previous item', () {
        final result = notifier.previous();
        final playlist = container.read(playlistProvider);
        
        expect(result, true);
        expect(playlist.currentIndex, 0);
      });

      test('returns false at beginning with repeat none', () {
        notifier.goToIndex(0);
        final result = notifier.previous();
        final playlist = container.read(playlistProvider);
        
        expect(result, false);
        expect(playlist.currentIndex, 0);
      });

      test('loops to end with repeat all', () {
        notifier.setRepeatMode(RepeatMode.all);
        notifier.goToIndex(0);
        final result = notifier.previous();
        final playlist = container.read(playlistProvider);
        
        expect(result, true);
        expect(playlist.currentIndex, 2);
      });
    });

    group('clear', () {
      test('clears all items', () {
        notifier.addItem('/path/video1.mp4');
        notifier.addItem('/path/video2.mp4');
        notifier.clear();
        final playlist = container.read(playlistProvider);
        
        expect(playlist.isEmpty, true);
        expect(playlist.currentIndex, 0);
      });
    });

    group('toggleShuffle', () {
      test('enables shuffle', () {
        notifier.addItem('/path/video1.mp4');
        notifier.addItem('/path/video2.mp4');
        notifier.toggleShuffle();
        final playlist = container.read(playlistProvider);
        
        expect(playlist.shuffle, true);
      });

      test('disables shuffle', () {
        notifier.addItem('/path/video1.mp4');
        notifier.toggleShuffle();
        notifier.toggleShuffle();
        final playlist = container.read(playlistProvider);
        
        expect(playlist.shuffle, false);
      });
    });

    group('toggleRepeat', () {
      test('cycles through repeat modes', () {
        expect(container.read(playlistProvider).repeatMode, RepeatMode.none);
        
        notifier.toggleRepeat();
        expect(container.read(playlistProvider).repeatMode, RepeatMode.all);
        
        notifier.toggleRepeat();
        expect(container.read(playlistProvider).repeatMode, RepeatMode.one);
        
        notifier.toggleRepeat();
        expect(container.read(playlistProvider).repeatMode, RepeatMode.none);
      });
    });

    group('PlaylistEntity helpers', () {
      test('hasPrevious returns correct value', () {
        notifier.addItem('/path/video1.mp4');
        notifier.addItem('/path/video2.mp4');
        
        expect(container.read(playlistProvider).hasPrevious, false);
        
        notifier.goToIndex(1);
        expect(container.read(playlistProvider).hasPrevious, true);
      });

      test('hasNext returns correct value', () {
        notifier.addItem('/path/video1.mp4');
        notifier.addItem('/path/video2.mp4');
        
        expect(container.read(playlistProvider).hasNext, true);
        
        notifier.goToIndex(1);
        expect(container.read(playlistProvider).hasNext, false);
      });

      test('currentItem returns correct item', () {
        notifier.addItem('/path/video1.mp4');
        notifier.addItem('/path/video2.mp4');
        notifier.goToIndex(1);
        
        expect(container.read(playlistProvider).currentItem?.path, '/path/video2.mp4');
      });
    });
  });
}
