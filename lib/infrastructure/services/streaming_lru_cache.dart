import 'dart:math';
import 'dart:typed_data';

/// LRU Cache for streaming data.
/// Caches recently read chunks to enable instant backward seeks.
class StreamingLRUCache {
  static const int maxCacheSize = 32 * 1024 * 1024; // 32MB max per file
  static const int chunkSize = 512 * 1024; // 512KB chunks

  final Map<int, Uint8List> _chunks = {}; // chunkIndex -> data
  final Map<int, int> _chunkOffsets =
      {}; // chunkIndex -> offset within chunk (for partial chunks)
  final List<int> _lruOrder = []; // Most recently used at end
  int _currentSize = 0;

  /// Get cached data for the given range.
  /// Returns null if data is not fully cached.
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
      // FIX: Ensure copyEnd doesn't exceed actual chunk length
      final copyEnd = min(requestEnd - chunkAbsoluteStart, chunk.length);
      final copyLen = min(copyEnd - copyStart, length - resultOffset);

      if (copyStart >= 0 && copyStart < chunk.length && copyLen > 0) {
        // FIX: Ensure we don't read beyond chunk boundary
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

  /// Store data in cache, evicting old chunks if necessary.
  /// Handles non-aligned offsets by storing partial chunks with their offset.
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
          // If ranges don't overlap/adjacent, keep existing (don't fragment cache)
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

  /// Clear all cached data.
  void clear() {
    _chunks.clear();
    _chunkOffsets.clear();
    _lruOrder.clear();
    _currentSize = 0;
  }

  /// Current cache size in bytes.
  int get size => _currentSize;

  /// Number of cached chunks.
  int get chunkCount => _chunks.length;
}
