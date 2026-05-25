import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../infrastructure/services/locale_storage_service.dart';

part 'locale_provider.g.dart';

@Riverpod(keepAlive: true)
class LocaleNotifier extends _$LocaleNotifier {
  late final LocaleStorageService _storageService;

  @override
  Locale build() {
    _storageService = LocaleStorageService();
    _loadLocale();
    return const Locale('es');
  }

  Future<void> _loadLocale() async {
    final langCode = await _storageService.loadLanguage();
    if (langCode != null) {
      state = Locale(langCode);
    } else {
      state = const Locale('es');
      await _storageService.saveLanguage('es');
    }
  }

  Future<void> setLocale(String languageCode) async {
    state = Locale(languageCode);
    await _storageService.saveLanguage(languageCode);
  }

  Future<void> toggleLocale() async {
    if (state.languageCode == 'es') {
      await setLocale('en');
    } else {
      await setLocale('es');
    }
  }
}
