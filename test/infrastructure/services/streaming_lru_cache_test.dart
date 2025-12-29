// ignore_for_file: unnecessary_cast

import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';

// Test helper to expose _StreamingLRUCache for testing
// Since _StreamingLRUCache is private, we re-implement the logic here for testing
// This mirrors the exact implementation in local_streaming_proxy.dart

class TestStreamingLRUCache {
  static const int maxCacheSize = 32 * 1024 * 1024; // 32MB max per file
  static const int chunkSize = 512 * 1024; // 512KB chunks

  final Map<int, Uint8List> _chunks = {}; // chunkIndex -> data
  final Map<int, int> _chunkOffsets = {}; // chunkIndex -> offset within chunk
  final List<int> _lruOrder = []; // Most recently used at end
  int _currentSize = 0;

  int min(int a, int b) => a < b ? a : b;
  int max(int a, int b) => a > b ? a : b;

  Uint8List? get(int offset, int length) {
    if (length <= 0) return null;

    final startChunk = offset ~/ chunkSize;
    final endChunk = (offset + length - 1) ~/ chunkSize;

    // Check if all required chunks are cached AND contain the data we need
    for (int i = startChunk; i <= endChunk; i++) {
      if (!_chunks.containsKey(i)) {
        return null; // Cache miss
      }

      // Verify the chunk contains the range we need
      final chunk = _chunks[i]!;
      final chunkStartOffset = _chunkOffsets[i] ?? 0;
      final chunkStart = i * chunkSize + chunkStartOffset;
      final chunkEnd = chunkStart + chunk.length;

      // Calculate the range we need from this chunk
      final needStart = i == startChunk ? offset : i * chunkSize;
      final needEnd = i == endChunk ? offset + length : (i + 1) * chunkSize;

      if (needStart < chunkStart || needEnd > chunkEnd) {
        return null; // Chunk doesn't cover required range
      }
    }

    // All chunks are cached - assemble the result
    final result = Uint8List(length);
    int resultOffset = 0;

    for (int i = startChunk; i <= endChunk; i++) {
      final chunk = _chunks[i]!;
      final chunkStartOffset = _chunkOffsets[i] ?? 0;
      final chunkAbsoluteStart = i * chunkSize + chunkStartOffset;

      // Calculate which part of this chunk we need
      final requestStart = i == startChunk ? offset : i * chunkSize;
      final requestEnd = i == endChunk ? offset + length : (i + 1) * chunkSize;

      // Convert to chunk-local offsets
      final copyStart = requestStart - chunkAbsoluteStart;
      final copyEnd = min(requestEnd - chunkAbsoluteStart, chunk.length);
      final copyLen = min(copyEnd - copyStart, length - resultOffset);

      if (copyStart >= 0 && copyStart < chunk.length && copyLen > 0) {
        final safeEnd = min(copyStart + copyLen, chunk.length);
        result.setRange(
          resultOffset,
          resultOffset + (safeEnd - copyStart),
          chunk.sublist(copyStart, safeEnd),
        );
        resultOffset += safeEnd - copyStart;
      }

      // Update LRU order
      _lruOrder.remove(i);
      _lruOrder.add(i);
    }

    // Verify we got all the data we expected
    if (resultOffset < length) {
      return null; // Incomplete data
    }

    return result;
  }

  void put(int offset, Uint8List data) {
    if (data.isEmpty) return;

    final startChunk = offset ~/ chunkSize;
    final startChunkOffset = offset % chunkSize;

    int dataOffset = 0;
    int chunkIndex = startChunk;

    while (dataOffset < data.length) {
      final isFirstChunk = chunkIndex == startChunk;

      // For the first chunk, we may start from a non-zero offset within the chunk
      final offsetInChunk = isFirstChunk ? startChunkOffset : 0;

      // Calculate how much data goes into this chunk
      final spaceInChunk = chunkSize - offsetInChunk;
      final remaining = data.length - dataOffset;
      final chunkLen = min(spaceInChunk, remaining);

      if (chunkLen > 0) {
        final chunkData = data.sublist(dataOffset, dataOffset + chunkLen);

        // Check if we should merge with existing chunk
        if (_chunks.containsKey(chunkIndex)) {
          final existingChunk = _chunks[chunkIndex]!;
          final existingOffset = _chunkOffsets[chunkIndex] ?? 0;

          // Try to merge if ranges are adjacent or overlapping
          final existingStart = existingOffset;
          final existingEnd = existingOffset + existingChunk.length;
          final newStart = offsetInChunk;
          final newEnd = offsetInChunk + chunkLen;

          if (newEnd >= existingStart && newStart <= existingEnd) {
            // Ranges overlap or are adjacent - merge
            final mergedStart = min(existingStart, newStart);
            final mergedEnd = max(existingEnd, newEnd);
            final mergedLen = mergedEnd - mergedStart;

            final merged = Uint8List(mergedLen);

            // Copy existing data
            merged.setRange(
              existingStart - mergedStart,
              existingStart - mergedStart + existingChunk.length,
              existingChunk,
            );

            // Copy new data (may overwrite some existing data)
            merged.setRange(
              newStart - mergedStart,
              newStart - mergedStart + chunkLen,
              chunkData,
            );

            // Update size tracking
            _currentSize = _currentSize - existingChunk.length + merged.length;
            _chunks[chunkIndex] = merged;
            _chunkOffsets[chunkIndex] = mergedStart;
          }
        } else {
          // No existing chunk - store new data

          // Evict if necessary
          while (_currentSize + chunkLen > maxCacheSize &&
              _lruOrder.isNotEmpty) {
            final evictIndex = _lruOrder.removeAt(0);
            final evicted = _chunks.remove(evictIndex);
            _chunkOffsets.remove(evictIndex);
            if (evicted != null) {
              _currentSize -= evicted.length;
            }
          }

          _chunks[chunkIndex] = chunkData;
          _chunkOffsets[chunkIndex] = offsetInChunk;
          _currentSize += chunkLen;
        }

        _lruOrder.remove(chunkIndex);
        _lruOrder.add(chunkIndex);
      }

      dataOffset += chunkLen;
      chunkIndex++;
    }
  }

  void clear() {
    _chunks.clear();
    _chunkOffsets.clear();
    _lruOrder.clear();
    _currentSize = 0;
  }

  int get size => _currentSize;
  int get chunkCount => _chunks.length;
}

void main() {
  group('_StreamingLRUCache', () {
    late TestStreamingLRUCache cache;

    setUp(() {
      cache = TestStreamingLRUCache();
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
        // Store data starting at offset 0
        final data = Uint8List.fromList(List.generate(1000, (i) => i % 256));
        cache.put(0, data);

        // Request data starting at offset 100
        final result = cache.get(100, 500);
        expect(result, isNotNull);
        expect(result!.length, equals(500));
        expect(result, equals(data.sublist(100, 600)));
      });

      test('returns null when chunk does not cover requested range', () {
        // Store data starting at offset 100
        final data = Uint8List.fromList(List.generate(500, (i) => i % 256));
        cache.put(100, data);

        // Request data starting at offset 0 (before cached data)
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
        // Store data at offset 100 (non-aligned)
        final data = Uint8List.fromList(List.generate(500, (i) => i % 256));
        cache.put(100, data);

        expect(cache.chunkCount, equals(1));
        expect(cache.size, equals(500));

        // Should be able to retrieve it
        final result = cache.get(100, 500);
        expect(result, isNotNull);
        expect(result, equals(data));
      });

      test('merges adjacent chunks correctly', () {
        // Store first part
        final data1 = Uint8List.fromList(List.generate(100, (i) => 1));
        cache.put(0, data1);

        // Store adjacent part
        final data2 = Uint8List.fromList(List.generate(100, (i) => 2));
        cache.put(100, data2);

        // Should have merged into one chunk
        expect(cache.chunkCount, equals(1));
        expect(cache.size, equals(200));

        // Verify data integrity
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
        // Simulate forward read
        final data1 = Uint8List.fromList(List.generate(1000, (i) => i % 256));
        cache.put(0, data1);

        // Simulate backward seek and read
        final result = cache.get(500, 200);
        expect(result, isNotNull);
        expect(result!.length, equals(200));
        expect(result, equals(data1.sublist(500, 700)));
      });

      test('handles multiple small reads from same chunk', () {
        final data = Uint8List.fromList(List.generate(1000, (i) => i % 256));
        cache.put(0, data);

        // Multiple small reads
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
