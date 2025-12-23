import 'dart:io';
import 'package:flutter/foundation.dart';

/// MP4 Sample Table Parser
/// Parses moov atom to extract time-to-byte mapping information.
///
/// Key atoms parsed:
/// - stts (Time-to-Sample): Duration of each sample
/// - stsc (Sample-to-Chunk): How samples are grouped into chunks
/// - stsz (Sample Size): Size of each sample in bytes
/// - stco/co64 (Chunk Offset): Byte offset of each chunk
/// - stss (Sync Sample): Keyframe locations (optional)
class Mp4SampleTable {
  final List<SampleEntry> samples;
  final List<int> keyframeSampleIndices;
  final int totalDurationMs;
  final int totalBytes;
  final int timescale;

  Mp4SampleTable._({
    required this.samples,
    required this.keyframeSampleIndices,
    required this.totalDurationMs,
    required this.totalBytes,
    required this.timescale,
  });

  /// Parse moov atom from file
  /// Returns null if parsing fails (unsupported format, not MP4)
  static Future<Mp4SampleTable?> parse(
    RandomAccessFile raf,
    int fileSize,
  ) async {
    try {
      // Find moov atom
      final moovInfo = await _findAtom(raf, 'moov', 0, fileSize);
      if (moovInfo == null) {
        debugPrint('Mp4SampleTable: No moov atom found');
        return null;
      }

      // Find video trak -> mdia -> minf -> stbl
      final stblInfo = await _findVideoStblAtom(
        raf,
        moovInfo.offset,
        moovInfo.size,
      );
      if (stblInfo == null) {
        debugPrint('Mp4SampleTable: No video stbl atom found');
        return null;
      }

      // Find mdhd for timescale
      final mdhdInfo = await _findMdhd(raf, moovInfo.offset, moovInfo.size);
      final timescale = mdhdInfo?.timescale ?? 1000;

      // Parse sample table atoms
      final stts = await _parseStts(raf, stblInfo.offset, stblInfo.size);
      final stsc = await _parseStsc(raf, stblInfo.offset, stblInfo.size);
      final stsz = await _parseStsz(raf, stblInfo.offset, stblInfo.size);
      final chunkOffsets = await _parseChunkOffsets(
        raf,
        stblInfo.offset,
        stblInfo.size,
      );
      final stss = await _parseStss(raf, stblInfo.offset, stblInfo.size);

      if (stts == null ||
          stsc == null ||
          stsz == null ||
          chunkOffsets == null) {
        debugPrint('Mp4SampleTable: Missing required atoms');
        return null;
      }

      // Build sample table from parsed atoms
      final samples = _buildSampleTable(
        stts,
        stsc,
        stsz,
        chunkOffsets,
        timescale,
      );

      if (samples.isEmpty) {
        debugPrint('Mp4SampleTable: No samples found');
        return null;
      }

      final totalDurationMs = samples.isNotEmpty ? samples.last.timeMs + 1 : 0;
      final totalBytes = samples.isNotEmpty
          ? samples.last.byteOffset + samples.last.size
          : fileSize;

      debugPrint(
        'Mp4SampleTable: Parsed ${samples.length} samples, '
        '${stss?.length ?? 0} keyframes, timescale=$timescale',
      );

      return Mp4SampleTable._(
        samples: samples,
        keyframeSampleIndices: stss ?? [],
        totalDurationMs: totalDurationMs,
        totalBytes: totalBytes,
        timescale: timescale,
      );
    } catch (e, stack) {
      debugPrint('Mp4SampleTable: Parse error: $e\n$stack');
      return null;
    }
  }

  /// Get byte offset for a given time in milliseconds
  /// Returns the offset of the nearest keyframe at or before the time
  int getByteOffsetForTime(int timeMs) {
    if (samples.isEmpty) return 0;

    // Binary search for sample at or before timeMs
    int targetSampleIndex = _binarySearchSample(timeMs);

    // Find nearest keyframe at or before target (if we have keyframe info)
    if (keyframeSampleIndices.isNotEmpty) {
      targetSampleIndex = _findNearestKeyframe(targetSampleIndex);
    }

    return samples[targetSampleIndex].byteOffset;
  }

  /// Get the nearest keyframe sample index at or before the given sample index
  int _findNearestKeyframe(int sampleIndex) {
    // stss indices are 1-based in MP4, but we store them 0-based
    for (int i = keyframeSampleIndices.length - 1; i >= 0; i--) {
      if (keyframeSampleIndices[i] <= sampleIndex) {
        return keyframeSampleIndices[i];
      }
    }
    return 0;
  }

  int _binarySearchSample(int timeMs) {
    int low = 0;
    int high = samples.length - 1;
    while (low < high) {
      int mid = (low + high + 1) ~/ 2;
      if (samples[mid].timeMs <= timeMs) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }

  // ============================================================
  // ATOM FINDING HELPERS
  // ============================================================

  static Future<_AtomInfo?> _findAtom(
    RandomAccessFile raf,
    String atomType,
    int searchStart,
    int searchEnd,
  ) async {
    int offset = searchStart;
    final typeBytes = Uint8List.fromList(atomType.codeUnits);

    while (offset < searchEnd - 8) {
      await raf.setPosition(offset);
      final header = await raf.read(8);
      if (header.length < 8) break;

      int size = _readUint32BE(header, 0);
      final type = header.sublist(4, 8);

      // Handle extended size (size == 1)
      if (size == 1) {
        final extSize = await raf.read(8);
        if (extSize.length < 8) break;
        size = _readUint64BE(extSize, 0);
      } else if (size == 0) {
        // Atom extends to end of file
        size = searchEnd - offset;
      }

      if (_bytesEqual(type, typeBytes)) {
        return _AtomInfo(offset: offset + 8, size: size - 8);
      }

      offset += size;
    }

    return null;
  }

  static Future<_AtomInfo?> _findVideoStblAtom(
    RandomAccessFile raf,
    int moovOffset,
    int moovSize,
  ) async {
    // Find trak atoms and look for the video track
    int offset = moovOffset;
    final endOffset = moovOffset + moovSize;

    while (offset < endOffset - 8) {
      final trakInfo = await _findAtom(raf, 'trak', offset, endOffset);
      if (trakInfo == null) break;

      // Check if this is a video track by looking at mdia/hdlr
      final mdiaInfo = await _findAtom(
        raf,
        'mdia',
        trakInfo.offset,
        trakInfo.offset + trakInfo.size,
      );

      if (mdiaInfo != null) {
        final hdlrInfo = await _findAtom(
          raf,
          'hdlr',
          mdiaInfo.offset,
          mdiaInfo.offset + mdiaInfo.size,
        );

        if (hdlrInfo != null) {
          await raf.setPosition(hdlrInfo.offset + 8);
          final hdlrData = await raf.read(4);
          if (hdlrData.length >= 4) {
            final handlerType = String.fromCharCodes(hdlrData);
            if (handlerType == 'vide') {
              // Found video track, now find stbl
              final minfInfo = await _findAtom(
                raf,
                'minf',
                mdiaInfo.offset,
                mdiaInfo.offset + mdiaInfo.size,
              );
              if (minfInfo != null) {
                final stblInfo = await _findAtom(
                  raf,
                  'stbl',
                  minfInfo.offset,
                  minfInfo.offset + minfInfo.size,
                );
                if (stblInfo != null) {
                  return stblInfo;
                }
              }
            }
          }
        }
      }

      // Move to next trak
      offset = trakInfo.offset + trakInfo.size;
    }

    return null;
  }

  static Future<_MdhdInfo?> _findMdhd(
    RandomAccessFile raf,
    int moovOffset,
    int moovSize,
  ) async {
    // Find video trak -> mdia -> mdhd
    int offset = moovOffset;
    final endOffset = moovOffset + moovSize;

    while (offset < endOffset - 8) {
      final trakInfo = await _findAtom(raf, 'trak', offset, endOffset);
      if (trakInfo == null) break;

      final mdiaInfo = await _findAtom(
        raf,
        'mdia',
        trakInfo.offset,
        trakInfo.offset + trakInfo.size,
      );

      if (mdiaInfo != null) {
        // Check if video track
        final hdlrInfo = await _findAtom(
          raf,
          'hdlr',
          mdiaInfo.offset,
          mdiaInfo.offset + mdiaInfo.size,
        );

        if (hdlrInfo != null) {
          await raf.setPosition(hdlrInfo.offset + 8);
          final hdlrData = await raf.read(4);
          if (hdlrData.length >= 4 &&
              String.fromCharCodes(hdlrData) == 'vide') {
            // Found video track, get mdhd
            final mdhdInfo = await _findAtom(
              raf,
              'mdhd',
              mdiaInfo.offset,
              mdiaInfo.offset + mdiaInfo.size,
            );

            if (mdhdInfo != null) {
              await raf.setPosition(mdhdInfo.offset);
              final mdhdData = await raf.read(24);
              if (mdhdData.length >= 24) {
                final version = mdhdData[0];
                int timescale;
                if (version == 1) {
                  // 64-bit times
                  timescale = _readUint32BE(mdhdData, 20);
                } else {
                  // 32-bit times
                  timescale = _readUint32BE(mdhdData, 12);
                }
                return _MdhdInfo(timescale: timescale);
              }
            }
          }
        }
      }

      offset = trakInfo.offset + trakInfo.size;
    }

    return null;
  }

  // ============================================================
  // SAMPLE TABLE ATOM PARSERS
  // ============================================================

  static Future<List<_SttsEntry>?> _parseStts(
    RandomAccessFile raf,
    int stblOffset,
    int stblSize,
  ) async {
    final atomInfo = await _findAtom(
      raf,
      'stts',
      stblOffset,
      stblOffset + stblSize,
    );
    if (atomInfo == null) return null;

    await raf.setPosition(atomInfo.offset);
    final data = await raf.read(atomInfo.size);
    if (data.length < 8) return null;

    final entryCount = _readUint32BE(data, 4);
    final entries = <_SttsEntry>[];

    int pos = 8;
    for (int i = 0; i < entryCount && pos + 8 <= data.length; i++) {
      final sampleCount = _readUint32BE(data, pos);
      final sampleDelta = _readUint32BE(data, pos + 4);
      entries.add(
        _SttsEntry(sampleCount: sampleCount, sampleDelta: sampleDelta),
      );
      pos += 8;
    }

    return entries;
  }

  static Future<List<_StscEntry>?> _parseStsc(
    RandomAccessFile raf,
    int stblOffset,
    int stblSize,
  ) async {
    final atomInfo = await _findAtom(
      raf,
      'stsc',
      stblOffset,
      stblOffset + stblSize,
    );
    if (atomInfo == null) return null;

    await raf.setPosition(atomInfo.offset);
    final data = await raf.read(atomInfo.size);
    if (data.length < 8) return null;

    final entryCount = _readUint32BE(data, 4);
    final entries = <_StscEntry>[];

    int pos = 8;
    for (int i = 0; i < entryCount && pos + 12 <= data.length; i++) {
      final firstChunk = _readUint32BE(data, pos);
      final samplesPerChunk = _readUint32BE(data, pos + 4);
      // sampleDescriptionIndex at pos + 8, not used
      entries.add(
        _StscEntry(firstChunk: firstChunk, samplesPerChunk: samplesPerChunk),
      );
      pos += 12;
    }

    return entries;
  }

  static Future<List<int>?> _parseStsz(
    RandomAccessFile raf,
    int stblOffset,
    int stblSize,
  ) async {
    final atomInfo = await _findAtom(
      raf,
      'stsz',
      stblOffset,
      stblOffset + stblSize,
    );
    if (atomInfo == null) return null;

    await raf.setPosition(atomInfo.offset);
    final data = await raf.read(atomInfo.size);
    if (data.length < 12) return null;

    final sampleSize = _readUint32BE(data, 4);
    final sampleCount = _readUint32BE(data, 8);

    if (sampleSize != 0) {
      // All samples have the same size
      return List.filled(sampleCount, sampleSize);
    }

    // Variable sample sizes
    final sizes = <int>[];
    int pos = 12;
    for (int i = 0; i < sampleCount && pos + 4 <= data.length; i++) {
      sizes.add(_readUint32BE(data, pos));
      pos += 4;
    }

    return sizes;
  }

  static Future<List<int>?> _parseChunkOffsets(
    RandomAccessFile raf,
    int stblOffset,
    int stblSize,
  ) async {
    // Try stco first (32-bit offsets)
    var atomInfo = await _findAtom(
      raf,
      'stco',
      stblOffset,
      stblOffset + stblSize,
    );
    bool is64Bit = false;

    if (atomInfo == null) {
      // Try co64 (64-bit offsets for large files)
      atomInfo = await _findAtom(
        raf,
        'co64',
        stblOffset,
        stblOffset + stblSize,
      );
      is64Bit = true;
    }

    if (atomInfo == null) return null;

    await raf.setPosition(atomInfo.offset);
    final data = await raf.read(atomInfo.size);
    if (data.length < 8) return null;

    final entryCount = _readUint32BE(data, 4);
    final offsets = <int>[];

    int pos = 8;
    for (int i = 0; i < entryCount; i++) {
      if (is64Bit) {
        if (pos + 8 > data.length) break;
        offsets.add(_readUint64BE(data, pos));
        pos += 8;
      } else {
        if (pos + 4 > data.length) break;
        offsets.add(_readUint32BE(data, pos));
        pos += 4;
      }
    }

    return offsets;
  }

  static Future<List<int>?> _parseStss(
    RandomAccessFile raf,
    int stblOffset,
    int stblSize,
  ) async {
    final atomInfo = await _findAtom(
      raf,
      'stss',
      stblOffset,
      stblOffset + stblSize,
    );
    if (atomInfo == null) {
      // No sync sample table = all samples are keyframes (rare)
      return null;
    }

    await raf.setPosition(atomInfo.offset);
    final data = await raf.read(atomInfo.size);
    if (data.length < 8) return null;

    final entryCount = _readUint32BE(data, 4);
    final keyframes = <int>[];

    int pos = 8;
    for (int i = 0; i < entryCount && pos + 4 <= data.length; i++) {
      // stss uses 1-based indices, convert to 0-based
      keyframes.add(_readUint32BE(data, pos) - 1);
      pos += 4;
    }

    return keyframes;
  }

  // ============================================================
  // SAMPLE TABLE BUILDER
  // ============================================================

  static List<SampleEntry> _buildSampleTable(
    List<_SttsEntry> stts,
    List<_StscEntry> stsc,
    List<int> stsz,
    List<int> chunkOffsets,
    int timescale,
  ) {
    final samples = <SampleEntry>[];
    int sampleIndex = 0;
    int currentTime = 0;
    int sttsIndex = 0;
    int sttsRemaining = stts.isNotEmpty ? stts[0].sampleCount : 0;

    // Build expanded stsc table for easier lookup
    final samplesPerChunkTable = <int>[];
    for (int i = 0; i < stsc.length; i++) {
      final current = stsc[i];
      final nextChunk = i + 1 < stsc.length
          ? stsc[i + 1].firstChunk
          : chunkOffsets.length + 1;

      for (int chunk = current.firstChunk; chunk < nextChunk; chunk++) {
        samplesPerChunkTable.add(current.samplesPerChunk);
      }
    }

    // Iterate through chunks
    for (int chunkIndex = 0; chunkIndex < chunkOffsets.length; chunkIndex++) {
      int chunkOffset = chunkOffsets[chunkIndex];
      final samplesInChunk = chunkIndex < samplesPerChunkTable.length
          ? samplesPerChunkTable[chunkIndex]
          : 1;

      for (int i = 0; i < samplesInChunk && sampleIndex < stsz.length; i++) {
        final sampleSize = stsz[sampleIndex];

        // Convert time units to milliseconds
        final timeMs = (currentTime * 1000 / timescale).round();

        samples.add(
          SampleEntry(
            timeMs: timeMs,
            byteOffset: chunkOffset,
            size: sampleSize,
          ),
        );

        chunkOffset += sampleSize;
        sampleIndex++;

        // Update time using stts
        if (sttsRemaining > 0) {
          currentTime += stts[sttsIndex].sampleDelta;
          sttsRemaining--;
          if (sttsRemaining == 0 && sttsIndex + 1 < stts.length) {
            sttsIndex++;
            sttsRemaining = stts[sttsIndex].sampleCount;
          }
        }
      }
    }

    return samples;
  }

  // ============================================================
  // BYTE READING UTILITIES
  // ============================================================

  static int _readUint32BE(Uint8List data, int offset) {
    return (data[offset] << 24) |
        (data[offset + 1] << 16) |
        (data[offset + 2] << 8) |
        data[offset + 3];
  }

  static int _readUint64BE(Uint8List data, int offset) {
    // Dart ints are 64-bit, so this is safe
    return (_readUint32BE(data, offset) << 32) |
        _readUint32BE(data, offset + 4);
  }

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// A single sample entry with timing and byte position
class SampleEntry {
  final int timeMs;
  final int byteOffset;
  final int size;

  SampleEntry({
    required this.timeMs,
    required this.byteOffset,
    required this.size,
  });
}

// ============================================================
// INTERNAL DATA CLASSES
// ============================================================

class _AtomInfo {
  final int offset;
  final int size;
  _AtomInfo({required this.offset, required this.size});
}

class _MdhdInfo {
  final int timescale;
  _MdhdInfo({required this.timescale});
}

class _SttsEntry {
  final int sampleCount;
  final int sampleDelta;
  _SttsEntry({required this.sampleCount, required this.sampleDelta});
}

class _StscEntry {
  final int firstChunk;
  final int samplesPerChunk;
  _StscEntry({required this.firstChunk, required this.samplesPerChunk});
}
