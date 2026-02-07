import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_app/infrastructure/services/proxy_file_state.dart';
import 'package:video_player_app/domain/value_objects/loading_progress.dart';

void main() {
  group('ProxyFileState', () {
    late ProxyFileState state;

    setUp(() {
      state = ProxyFileState(123);
    });

    group('constructor and initial state', () {
      test('creates with correct fileId', () {
        expect(state.fileId, equals(123));
      });

      test('has idle load state initially', () {
        expect(state.loadState, equals(FileLoadState.idle));
      });

      test('has zero priority initially', () {
        expect(state.activePriority, equals(0));
      });

      test('has null offsets initially', () {
        expect(state.activeDownloadOffset, isNull);
        expect(state.primaryPlaybackOffset, isNull);
        expect(state.lastServedOffset, isNull);
      });

      test('has no MOOV flags set initially', () {
        expect(state.isMoovAtEnd, isFalse);
        expect(state.moovPosition, isNull);
        expect(state.earlyMoovDetectionTriggered, isFalse);
      });
    });

    group('reset()', () {
      test('clears all timing fields', () {
        state.openTime = DateTime.now();
        state.downloadStartTime = DateTime.now();
        state.lastSeekTime = DateTime.now();

        state.reset();

        expect(state.openTime, isNull);
        expect(state.downloadStartTime, isNull);
        expect(state.lastSeekTime, isNull);
      });

      test('clears download tracking fields', () {
        state.activeDownloadOffset = 1000;
        state.primaryPlaybackOffset = 2000;
        state.activePriority = 20;

        state.reset();

        expect(state.activeDownloadOffset, isNull);
        expect(state.primaryPlaybackOffset, isNull);
        expect(state.activePriority, equals(0));
      });

      test('clears MOOV detection fields', () {
        state.isMoovAtEnd = true;
        state.moovPosition = MoovPosition.end;
        state.forcedMoovOffset = 5000;

        state.reset();

        expect(state.isMoovAtEnd, isFalse);
        expect(state.moovPosition, isNull);
        expect(state.forcedMoovOffset, isNull);
      });

      test('resets load state to idle', () {
        state.loadState = FileLoadState.playing;

        state.reset();

        expect(state.loadState, equals(FileLoadState.idle));
      });
    });

    group('isWithinGracePeriod()', () {
      test('returns false when openTime is null', () {
        expect(state.isWithinGracePeriod(const Duration(seconds: 30)), isFalse);
      });

      test('returns true when within grace period', () {
        state.openTime = DateTime.now();

        expect(state.isWithinGracePeriod(const Duration(seconds: 30)), isTrue);
      });

      test('returns false when outside grace period', () {
        state.openTime = DateTime.now().subtract(const Duration(minutes: 1));

        expect(state.isWithinGracePeriod(const Duration(seconds: 30)), isFalse);
      });
    });

    group('isRecentDownload()', () {
      test('returns false when downloadStartTime is null', () {
        expect(state.isRecentDownload(const Duration(seconds: 5)), isFalse);
      });

      test('returns true when download started recently', () {
        state.downloadStartTime = DateTime.now();

        expect(state.isRecentDownload(const Duration(seconds: 5)), isTrue);
      });

      test('returns false when download started long ago', () {
        state.downloadStartTime = DateTime.now().subtract(
          const Duration(seconds: 10),
        );

        expect(state.isRecentDownload(const Duration(seconds: 5)), isFalse);
      });
    });

    group('isRecentSeek()', () {
      test('returns false when lastSeekTime is null', () {
        expect(state.isRecentSeek(const Duration(seconds: 2)), isFalse);
      });

      test('returns true when seek happened recently', () {
        state.lastSeekTime = DateTime.now();

        expect(state.isRecentSeek(const Duration(seconds: 2)), isTrue);
      });

      test('returns false when seek happened long ago', () {
        state.lastSeekTime = DateTime.now().subtract(
          const Duration(seconds: 5),
        );

        expect(state.isRecentSeek(const Duration(seconds: 2)), isFalse);
      });
    });

    group('toString()', () {
      test('returns readable string representation', () {
        state.loadState = FileLoadState.playing;
        state.activeDownloadOffset = 1024000;
        state.activePriority = 20;

        final str = state.toString();

        expect(str, contains('123'));
        expect(str, contains('playing'));
        expect(str, contains('1024000'));
        expect(str, contains('20'));
      });
    });
  });
}
