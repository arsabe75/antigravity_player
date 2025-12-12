import 'dart:io';
import 'dart:typed_data';

void main() async {
  final file = File('test_hole.dat');
  if (await file.exists()) await file.delete();

  // Create a file with a "hole" (zeros) in the middle
  final raf = await file.open(mode: FileMode.write);

  // Write 1KB of data
  await raf.writeFrom(List.filled(1024, 255)); // 0xFF

  // Seek forward 2KB (creating a 1KB hole of zeros)
  await raf.setPosition(2048);

  // Write 1KB of data
  await raf.writeFrom(List.filled(1024, 255)); // 0xFF

  await raf.close();

  // Test reading the hole
  final reader = await file.open(mode: FileMode.read);

  await reader.setPosition(1024); // Start of hole
  final data = await reader.read(1024);

  // Check if all zeros
  bool allZeros = true;
  for (var b in data) {
    if (b != 0) {
      allZeros = false;
      break;
    }
  }

  print('Hole (1024 bytes) all zeros? $allZeros');

  if (allZeros) {
    print('Hole detection logic VALID.');
  } else {
    print('Hole detection logic INVALID.');
  }

  await reader.close();
  await file.delete();
}
