import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../providers/telegram_chat_notifier.dart';
import '../providers/telegram_content_notifier.dart'; // For getStreamUrl helper if needed

class TelegramChatScreen extends ConsumerWidget {
  final int chatId;
  final String title;

  const TelegramChatScreen({
    super.key,
    required this.chatId,
    required this.title,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(telegramChatProvider(chatId));

    // Filter for video or video note messages
    final videoMessages = state.messages.where((m) {
      final content = m['content'];
      return content != null &&
          (content['@type'] ==
              'messageVideo' // || content['@type'] == 'messageVideoNote'
              );
    }).toList();

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: state.isLoading && state.messages.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : videoMessages.isEmpty
          ? const Center(child: Text('No videos found in this chat.'))
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 16 / 9,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: videoMessages.length,
              itemBuilder: (context, index) {
                final msg = videoMessages[index];
                final video = msg['content']['video'];
                final fileId = video['video']['id'];
                final size = video['video']['size'];
                // final thumbnail = ... (handle thumbnail later)

                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () async {
                      // Get Stream URL
                      // We access the content provider mostly for the helper,
                      // or just construct it directly since we know the proxy port logic.
                      // Better to use the helper to be distinct.
                      final url = await ref
                          .read(telegramContentProvider.notifier)
                          .getStreamUrl(fileId, size);

                      if (context.mounted) {
                        context.push('/player', extra: url);
                      }
                    },
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Container(color: Colors.black12), // Placeholder
                        const Center(
                          child: Icon(
                            LucideIcons.playCircle,
                            size: 48,
                            color: Colors.white70,
                          ),
                        ),
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _formatDuration(video['duration'] ?? 0),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  String _formatDuration(int seconds) {
    final d = Duration(seconds: seconds);
    final min = d.inMinutes;
    final sec = d.inSeconds % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }
}
