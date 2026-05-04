import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_app/infrastructure/services/streaming_lru_cache.dart';

void main() {
  group('StreamingLRUCache', () {
    late StreamingLRUCache cache;

    setUp(() {
      cache = StreamingLRUCache();
    });

    group('get()', () {
      test('returns null for empty cache', () {
        expect(cache.get(0, 100), isNull);
      });

      test('returns null for zero length', () {
        cache.put(0, Uint8List.fromList([1, 2, 3]));
        expect(cache.get(0, 0), isNull);
      });

      test('returns cached data for aligned offset', () {
        final data = Uint8List.fromList(List.generate(1024, (i) => i % 256));
        cache.put(0, data);

        final result = cache.get(0, 1024);
        expect(result, isNotNull);
        expect(result!.length, equals(1024));
        expect(result, equals(data));
      });

      test('returns correct data for non-aligned offset within same chunk', () {
        final data = Uint8List.fromList(List.generate(1000, (i) => i % 256));
        cache.put(0, data);

        final result = cache.get(100, 500);
        expect(result, isNotNull);
        expect(result!.length, equals(500));
        expect(result, equals(data.sublist(100, 600)));
      });

      test('returns null when chunk does not cover requested range', () {
        final data = Uint8List.fromList(List.generate(500, (i) => i % 256));
        cache.put(100, data);

        final result = cache.get(0, 200);
        expect(result, isNull);
      });
    });

    group('put()', () {
      test('stores data with aligned offset', () {
        final data = Uint8List.fromList(List.generate(1000, (i) => i % 256));
        cache.put(0, data);

        expect(cache.chunkCount, equals(1));
        expect(cache.size, equals(1000));
      });

      test('stores data with non-aligned offset', () {
        final data = Uint8List.fromList(List.generate(500, (i) => i % 256));
        cache.put(100, data);

        expect(cache.chunkCount, equals(1));
        expect(cache.size, equals(500));

        final result = cache.get(100, 500);
        expect(result, isNotNull);
        expect(result, equals(data));
      });

      test('merges adjacent chunks correctly', () {
        final data1 = Uint8List.fromList(List.generate(100, (i) => 1));
        cache.put(0, data1);

        final data2 = Uint8List.fromList(List.generate(100, (i) => 2));
        cache.put(100, data2);

        expect(cache.chunkCount, equals(1));
        expect(cache.size, equals(200));

        final result = cache.get(0, 200);
        expect(result, isNotNull);
        expect(result!.sublist(0, 100).every((b) => b == 1), isTrue);
        expect(result.sublist(100, 200).every((b) => b == 2), isTrue);
      });

      test('handles empty data', () {
        cache.put(0, Uint8List(0));
        expect(cache.chunkCount, equals(0));
        expect(cache.size, equals(0));
      });
    });

    group('edge cases', () {
      test('handles backward seek scenario', () {
        final data1 = Uint8List.fromList(List.generate(1000, (i) => i % 256));
        cache.put(0, data1);

        final result = cache.get(500, 200);
        expect(result, isNotNull);
        expect(result!.length, equals(200));
        expect(result, equals(data1.sublist(500, 700)));
      });

      test('handles multiple small reads from same chunk', () {
        final data = Uint8List.fromList(List.generate(1000, (i) => i % 256));
        cache.put(0, data);

        for (int offset = 0; offset < 900; offset += 100) {
          final result = cache.get(offset, 100);
          expect(result, isNotNull);
          expect(result!.length, equals(100));
          expect(result, equals(data.sublist(offset, offset + 100)));
        }
      });

      test('clear removes all data', () {
        final data = Uint8List.fromList(List.generate(1000, (i) => i % 256));
        cache.put(0, data);

        cache.clear();

        expect(cache.chunkCount, equals(0));
        expect(cache.size, equals(0));
        expect(cache.get(0, 100), isNull);
      });
    });
  });
}
