import 'package:video_player_app/infrastructure/services/downloaded_ranges.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DownloadedRanges ranges;

  setUp(() {
    ranges = DownloadedRanges();
  });

  group('addRange', () {
    test('rango simple', () {
      ranges.addRange(0, 100);
      expect(ranges.rangeCount, 1);
      expect(ranges.totalBytes, 100);
    });

    test('ignora rangos inválidos (start >= end)', () {
      ranges.addRange(100, 100);
      ranges.addRange(200, 50);
      expect(ranges.rangeCount, 0);
      expect(ranges.totalBytes, 0);
    });

    test('rangos no superpuestos se mantienen separados', () {
      ranges.addRange(0, 100);
      ranges.addRange(200, 300);
      expect(ranges.rangeCount, 2);
      expect(ranges.totalBytes, 200);
    });

    test('rangos superpuestos se fusionan', () {
      ranges.addRange(0, 100);
      ranges.addRange(50, 200);
      expect(ranges.rangeCount, 1);
      expect(ranges.totalBytes, 200);
    });

    test('rangos adyacentes se fusionan', () {
      ranges.addRange(0, 100);
      ranges.addRange(100, 200);
      expect(ranges.rangeCount, 1);
      expect(ranges.totalBytes, 200);
    });

    test('fusión en cascada de múltiples rangos', () {
      ranges.addRange(0, 100);
      ranges.addRange(200, 300);
      ranges.addRange(400, 500);
      expect(ranges.rangeCount, 3);

      // Un rango que cubre los tres
      ranges.addRange(50, 450);
      expect(ranges.rangeCount, 1);
      expect(ranges.totalBytes, 500);
    });

    test('insertar rango al inicio', () {
      ranges.addRange(200, 300);
      ranges.addRange(0, 100);
      expect(ranges.rangeCount, 2);
      expect(ranges.availableBytesFrom(0), 100);
    });

    test('rango contenido completamente no cambia nada', () {
      ranges.addRange(0, 1000);
      ranges.addRange(100, 200);
      expect(ranges.rangeCount, 1);
      expect(ranges.totalBytes, 1000);
    });

    test('rango que envuelve existentes', () {
      ranges.addRange(100, 200);
      ranges.addRange(300, 400);
      ranges.addRange(0, 500);
      expect(ranges.rangeCount, 1);
      expect(ranges.totalBytes, 500);
    });
  });

  group('availableBytesFrom', () {
    test('offset dentro de rango', () {
      ranges.addRange(100, 500);
      expect(ranges.availableBytesFrom(200), 300);
    });

    test('offset fuera de rango retorna 0', () {
      ranges.addRange(100, 500);
      expect(ranges.availableBytesFrom(50), 0);
      expect(ranges.availableBytesFrom(600), 0);
    });

    test('offset al inicio de rango', () {
      ranges.addRange(100, 500);
      expect(ranges.availableBytesFrom(100), 400);
    });

    test('offset al final de rango (exclusive) retorna 0', () {
      ranges.addRange(100, 500);
      expect(ranges.availableBytesFrom(500), 0);
    });

    test('sin rangos retorna 0', () {
      expect(ranges.availableBytesFrom(0), 0);
    });

    test('offset entre dos rangos retorna 0', () {
      ranges.addRange(0, 100);
      ranges.addRange(200, 300);
      expect(ranges.availableBytesFrom(150), 0);
    });

    test('offset en segundo de múltiples rangos', () {
      ranges.addRange(0, 100);
      ranges.addRange(200, 500);
      expect(ranges.availableBytesFrom(250), 250);
    });
  });

  group('containsOffset', () {
    test('verdadero cuando offset está en rango', () {
      ranges.addRange(100, 500);
      expect(ranges.containsOffset(100), true);
      expect(ranges.containsOffset(300), true);
      expect(ranges.containsOffset(499), true);
    });

    test('falso cuando offset no está en rango', () {
      ranges.addRange(100, 500);
      expect(ranges.containsOffset(99), false);
      expect(ranges.containsOffset(500), false);
      expect(ranges.containsOffset(0), false);
    });
  });

  group('gaps', () {
    test('sin huecos cuando rango completo', () {
      ranges.addRange(0, 1000);
      expect(ranges.gaps(0, 1000), isEmpty);
    });

    test('todo es hueco sin rangos', () {
      final g = ranges.gaps(0, 1000);
      expect(g.length, 1);
      expect(g[0].start, 0);
      expect(g[0].end, 1000);
    });

    test('huecos entre rangos', () {
      ranges.addRange(0, 100);
      ranges.addRange(200, 300);
      ranges.addRange(400, 500);

      final g = ranges.gaps(0, 500);
      expect(g.length, 2);
      expect(g[0].start, 100);
      expect(g[0].end, 200);
      expect(g[1].start, 300);
      expect(g[1].end, 400);
    });

    test('hueco parcial al inicio y final', () {
      ranges.addRange(200, 400);

      final g = ranges.gaps(100, 500);
      expect(g.length, 2);
      expect(g[0].start, 100);
      expect(g[0].end, 200);
      expect(g[1].start, 400);
      expect(g[1].end, 500);
    });

    test('rango vacío retorna lista vacía', () {
      expect(ranges.gaps(100, 100), isEmpty);
      expect(ranges.gaps(200, 100), isEmpty);
    });
  });

  group('totalBytes', () {
    test('suma correcta de múltiples rangos', () {
      ranges.addRange(0, 100);
      ranges.addRange(200, 350);
      ranges.addRange(500, 600);
      expect(ranges.totalBytes, 350); // 100 + 150 + 100
    });

    test('cero sin rangos', () {
      expect(ranges.totalBytes, 0);
    });
  });

  group('clear', () {
    test('resetea todo', () {
      ranges.addRange(0, 1000);
      ranges.addRange(2000, 3000);
      ranges.clear();
      expect(ranges.rangeCount, 0);
      expect(ranges.totalBytes, 0);
      expect(ranges.availableBytesFrom(0), 0);
    });
  });

  group('markComplete / isComplete', () {
    test('markComplete crea un solo rango [0, totalSize)', () {
      ranges.addRange(100, 200);
      ranges.markComplete(1000);
      expect(ranges.rangeCount, 1);
      expect(ranges.totalBytes, 1000);
      expect(ranges.availableBytesFrom(0), 1000);
    });

    test('isComplete verdadero tras markComplete', () {
      ranges.markComplete(1000);
      expect(ranges.isComplete(1000), true);
    });

    test('isComplete falso con rangos parciales', () {
      ranges.addRange(0, 500);
      expect(ranges.isComplete(1000), false);
    });

    test('isComplete falso sin rangos', () {
      expect(ranges.isComplete(1000), false);
    });

    test('markComplete con 0 limpia rangos', () {
      ranges.addRange(0, 100);
      ranges.markComplete(0);
      expect(ranges.rangeCount, 0);
    });
  });

  group('escenario MOOV-at-end', () {
    const fileSize = 100 * 1024 * 1024; // 100MB
    const moovStart = 95 * 1024 * 1024; // 95MB

    test('descarga inicio + MOOV, ambos consultables', () {
      // Descarga secuencial inicial: [0, 5MB)
      ranges.addRange(0, 5 * 1024 * 1024);
      // TDLib cambia a descargar MOOV: [95MB, 100MB)
      ranges.addRange(moovStart, fileSize);

      expect(ranges.rangeCount, 2);
      expect(ranges.availableBytesFrom(0), 5 * 1024 * 1024);
      expect(ranges.availableBytesFrom(moovStart), 5 * 1024 * 1024);
      expect(ranges.availableBytesFrom(50 * 1024 * 1024), 0);
    });
  });

  group('escenario seek', () {
    test('descarga inicio + seek, ambos consultables', () {
      // Descarga secuencial: [0, 10MB)
      ranges.addRange(0, 10 * 1024 * 1024);
      // Seek a 50MB, descarga: [50MB, 55MB)
      ranges.addRange(50 * 1024 * 1024, 55 * 1024 * 1024);

      expect(ranges.rangeCount, 2);
      expect(ranges.availableBytesFrom(0), 10 * 1024 * 1024);
      expect(ranges.availableBytesFrom(50 * 1024 * 1024), 5 * 1024 * 1024);
    });

    test('gaps entre rangos reporta hueco correctamente', () {
      ranges.addRange(0, 10 * 1024 * 1024);
      ranges.addRange(50 * 1024 * 1024, 55 * 1024 * 1024);

      final g = ranges.gaps(0, 55 * 1024 * 1024);
      expect(g.length, 1);
      expect(g[0].start, 10 * 1024 * 1024);
      expect(g[0].end, 50 * 1024 * 1024);
    });
  });

  group('actualizaciones incrementales (simula TDLib updateFile)', () {
    test('prefix creciente se fusiona correctamente', () {
      // Simulamos TDLib reportando prefix creciente
      ranges.addRange(0, 1024 * 1024); // 1MB
      ranges.addRange(0, 2 * 1024 * 1024); // 2MB
      ranges.addRange(0, 3 * 1024 * 1024); // 3MB

      expect(ranges.rangeCount, 1);
      expect(ranges.totalBytes, 3 * 1024 * 1024);
    });

    test('prefix creciente desde offset no-cero', () {
      // TDLib descargando desde offset 50MB
      ranges.addRange(50 * 1024 * 1024, 51 * 1024 * 1024);
      ranges.addRange(50 * 1024 * 1024, 52 * 1024 * 1024);
      ranges.addRange(50 * 1024 * 1024, 53 * 1024 * 1024);

      expect(ranges.rangeCount, 1);
      expect(ranges.totalBytes, 3 * 1024 * 1024);
    });
  });
}
