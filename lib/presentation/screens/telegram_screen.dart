import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:window_manager/window_manager.dart';

import '../providers/telegram_auth_notifier.dart';
import '../../infrastructure/services/local_streaming_proxy.dart';
import 'telegram_login_screen.dart';
import 'telegram_selection_screen.dart';
import 'telegram_chat_screen.dart';

class TelegramScreen extends ConsumerStatefulWidget {
  const TelegramScreen({super.key});

  @override
  ConsumerState<TelegramScreen> createState() => _TelegramScreenState();
}

class _TelegramScreenState extends ConsumerState<TelegramScreen> {
  List<Map<String, dynamic>> _favorites = []; // No longer final

  @override
  void initState() {
    super.initState();
    // Start Proxy
    LocalStreamingProxy().start();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final String? favoritesJson = prefs.getString('telegram_favorites');
    if (favoritesJson != null) {
      setState(() {
        _favorites = List<Map<String, dynamic>>.from(jsonDecode(favoritesJson));
      });
    }
  }

  Future<void> _saveFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('telegram_favorites', jsonEncode(_favorites));
  }

  @override
  void dispose() {
    // Stop Proxy? Or keep it running?
    // Usually keep it if we want background downloads,
    // but specific requirements say "clean up resources".
    // For now, we'll keep it running as stopping it might break pending downloads if we come back.
    // LocalStreamingProxy().stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(telegramAuthProvider);

    // If not authenticated, show login
    if (authState.list != AuthState.ready) {
      // If initial, it might briefly show login before checking params,
      // but auth notifier handles that quickly.
      return const TelegramLoginScreen();
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.pop(),
        ),
        title: const Text('Telegram Channels'),
        flexibleSpace: GestureDetector(
          onPanStart: (_) => windowManager.startDragging(),
          behavior: HitTestBehavior.translucent,
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.plus),
            onPressed: () async {
              final result = await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const TelegramSelectionScreen(),
                ),
              );

              if (result != null && result is Map<String, dynamic>) {
                setState(() {
                  if (!_favorites.any((c) => c['id'] == result['id'])) {
                    _favorites.add(result);
                    _saveFavorites();
                  }
                });
              }
            },
          ),
          IconButton(
            icon: const Icon(LucideIcons.logOut),
            onPressed: () {
              ref.read(telegramAuthProvider.notifier).logout();
            },
          ),
        ],
      ),
      body: _favorites.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    LucideIcons.messageSquare,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No favorites yet.\nClick + to add channels.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _favorites.length,
              itemBuilder: (context, index) {
                final chat = _favorites[index];
                final title = chat['title'] ?? 'Unknown';
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(LucideIcons.tv)),
                    title: Text(title),
                    subtitle: Text('ID: ${chat['id']}'),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => TelegramChatScreen(
                            chatId: chat['id'],
                            title: title,
                          ),
                        ),
                      );
                    },
                    trailing: IconButton(
                      icon: const Icon(LucideIcons.trash2, size: 20),
                      onPressed: () {
                        setState(() {
                          _favorites.removeAt(index);
                          _saveFavorites();
                        });
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }
}
