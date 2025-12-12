import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../providers/telegram_content_notifier.dart';

import 'package:window_manager/window_manager.dart';

class TelegramSelectionScreen extends ConsumerStatefulWidget {
  const TelegramSelectionScreen({super.key});

  @override
  ConsumerState<TelegramSelectionScreen> createState() =>
      _TelegramSelectionScreenState();
}

class _TelegramSelectionScreenState
    extends ConsumerState<TelegramSelectionScreen> {
  @override
  void initState() {
    super.initState();
    debugPrint('TelegramSelectionScreen: initState');
    // Load chats on init, deferred to avoid navigation jank or race conditions
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        debugPrint('TelegramSelectionScreen: Calling loadChats()');
        ref.read(telegramContentProvider.notifier).loadChats();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(telegramContentProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Chats'),
        flexibleSpace: GestureDetector(
          onPanStart: (_) => windowManager.startDragging(),
          behavior: HitTestBehavior.translucent,
        ),
      ),
      body: state.isLoading && state.chats.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: state.chats.length,
              itemBuilder: (context, index) {
                final chat = state.chats[index];
                final title = chat['title'] ?? 'Unknown Chat';
                // TODO: Parse photo, etc.

                return ListTile(
                  leading: const CircleAvatar(
                    child: Icon(LucideIcons.messageCircle),
                  ),
                  title: Text(title),
                  subtitle: Text('ID: ${chat['id']}'),
                  trailing: IconButton(
                    icon: const Icon(LucideIcons.plus),
                    onPressed: () {
                      // TODO: Add to favorites logic
                      // For now just pop with result
                      Navigator.of(context).pop(chat);
                    },
                  ),
                );
              },
            ),
    );
  }
}
