import 'dart:convert';
import 'dart:io';
import '../lib/infrastructure/services/config_obfuscator.dart';

void main() {
  print('=============================================');
  print('   Generador de Credenciales para Antigravity');
  print('=============================================');
  print('');
  print(
    'Este script te ayudará a ofuscar tus nuevas credenciales de Telegram.',
  );
  print('Puedes obtenerlas en https://my.telegram.org');
  print('');

  stdout.write('Introduce tu nuevo API ID: ');
  final apiId = stdin.readLineSync()?.trim() ?? '';

  if (apiId.isEmpty) {
    print('Error: El API ID no puede estar vacío.');
    return;
  }

  stdout.write('Introduce tu nuevo API HASH: ');
  final apiHash = stdin.readLineSync()?.trim() ?? '';

  if (apiHash.isEmpty) {
    print('Error: El API HASH no puede estar vacío.');
    return;
  }

  print('');
  print('Generando credenciales ofuscadas...');
  print('');

  final encodedId = ConfigObfuscator.encode(apiId);
  final encodedHash = ConfigObfuscator.encode(apiHash);

  print('=============================================');
  print('Copia y pega estas líneas en tu archivo .env:');
  print('=============================================');
  print('');
  print('TELEGRAM_API_ID=$encodedId');
  print('TELEGRAM_API_HASH=$encodedHash');
  print('');
  print('=============================================');
  print('Después de actualizar el archivo .env, reinicia la aplicación.');
}
