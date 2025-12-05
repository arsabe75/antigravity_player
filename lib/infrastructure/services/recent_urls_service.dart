import 'package:shared_preferences/shared_preferences.dart';

/// Servicio para guardar y obtener URLs recientes
class RecentUrlsService {
  static const _key = 'recent_urls';
  static const _maxUrls = 10;

  /// Obtiene las URLs recientes
  Future<List<String>> getRecentUrls() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? [];
  }

  /// Añade una URL a la lista de recientes
  Future<void> addUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final urls = await getRecentUrls();

    // Remove if already exists (to move to top)
    urls.remove(url);

    // Add to beginning
    urls.insert(0, url);

    // Keep only max URLs
    if (urls.length > _maxUrls) {
      urls.removeRange(_maxUrls, urls.length);
    }

    await prefs.setStringList(_key, urls);
  }

  /// Elimina una URL de la lista de recientes
  Future<void> removeUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final urls = await getRecentUrls();
    urls.remove(url);
    await prefs.setStringList(_key, urls);
  }

  /// Limpia todas las URLs recientes
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
