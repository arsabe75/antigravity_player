/// Rangos descargados conocidos para un archivo.
///
/// Mantiene una lista ordenada de intervalos [start, end) no superpuestos.
/// Todas las operaciones de consulta son O(log n) mediante búsqueda binaria.
class DownloadedRanges {
  final List<_Range> _ranges = [];

  /// Agrega el rango [start, end). Fusiona con rangos superpuestos o adyacentes.
  void addRange(int start, int end) {
    if (start >= end) return;

    // Buscar el primer rango que podría superponerse o ser adyacente
    int lo = 0;
    int hi = _ranges.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_ranges[mid].end < start) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }

    int mergeStart = start;
    int mergeEnd = end;
    int removeFrom = lo;
    int removeTo = lo; // exclusive

    // Fusionar con todos los rangos que se superponen o son adyacentes
    for (int i = lo; i < _ranges.length; i++) {
      final r = _ranges[i];
      if (r.start > mergeEnd) break; // ya no hay superposición posible
      mergeStart = mergeStart < r.start ? mergeStart : r.start;
      mergeEnd = mergeEnd > r.end ? mergeEnd : r.end;
      removeTo = i + 1;
    }

    // Reemplazar rangos fusionados con uno solo
    if (removeTo > removeFrom) {
      _ranges.removeRange(removeFrom, removeTo);
    }
    _ranges.insert(removeFrom, _Range(mergeStart, mergeEnd));
  }

  /// Bytes contiguos disponibles desde [offset]. O(log n).
  /// Retorna 0 si [offset] no está en ningún rango.
  int availableBytesFrom(int offset) {
    final idx = _findRangeContaining(offset);
    if (idx < 0) return 0;
    return _ranges[idx].end - offset;
  }

  /// Verifica si [offset] está dentro de algún rango descargado.
  bool containsOffset(int offset) => _findRangeContaining(offset) >= 0;

  /// Retorna lista de huecos (gaps) dentro de [start, end).
  List<({int start, int end})> gaps(int start, int end) {
    if (start >= end) return [];

    final result = <({int start, int end})>[];
    int cursor = start;

    for (final r in _ranges) {
      if (r.end <= cursor) continue;
      if (r.start >= end) break;

      if (r.start > cursor) {
        result.add((start: cursor, end: r.start < end ? r.start : end));
      }
      cursor = r.end;
      if (cursor >= end) break;
    }

    if (cursor < end) {
      result.add((start: cursor, end: end));
    }

    return result;
  }

  /// Suma total de bytes en todos los rangos.
  int get totalBytes {
    int total = 0;
    for (final r in _ranges) {
      total += r.end - r.start;
    }
    return total;
  }

  /// Número de rangos (para diagnóstico).
  int get rangeCount => _ranges.length;

  /// Limpia todos los rangos.
  void clear() => _ranges.clear();

  /// Marca el archivo como completo: un solo rango [0, totalSize).
  void markComplete(int totalSize) {
    _ranges.clear();
    if (totalSize > 0) {
      _ranges.add(_Range(0, totalSize));
    }
  }

  /// Verifica si el archivo está completo (un solo rango desde 0).
  bool isComplete(int totalSize) {
    if (totalSize <= 0) return false;
    return _ranges.length == 1 &&
        _ranges[0].start == 0 &&
        _ranges[0].end >= totalSize;
  }

  /// Búsqueda binaria del rango que contiene [offset]. Retorna -1 si no existe.
  int _findRangeContaining(int offset) {
    int lo = 0;
    int hi = _ranges.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final r = _ranges[mid];
      if (offset < r.start) {
        hi = mid - 1;
      } else if (offset >= r.end) {
        lo = mid + 1;
      } else {
        return mid;
      }
    }
    return -1;
  }
}

class _Range {
  int start;
  int end; // exclusive

  _Range(this.start, this.end);

  @override
  String toString() => '[$start, $end)';
}
