import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../use_case.dart';
import '../../../infrastructure/services/telegram_service.dart';

part 'load_chat_messages_use_case.g.dart';

class LoadChatMessagesParams {
  final int chatId;
  final int? messageThreadId;
  final int nextVideoFromId;
  final int nextDocFromId;

  const LoadChatMessagesParams({
    required this.chatId,
    this.messageThreadId,
    this.nextVideoFromId = 0,
    this.nextDocFromId = 0,
  });
}

class LoadChatMessagesResult {
  final List<Map<String, dynamic>> messages;
  final int nextVideoFromId;
  final int nextDocFromId;
  final bool hasMoreVideos;
  final bool hasMoreDocs;

  const LoadChatMessagesResult({
    required this.messages,
    required this.nextVideoFromId,
    required this.nextDocFromId,
    required this.hasMoreVideos,
    required this.hasMoreDocs,
  });
}

class LoadChatMessagesUseCase
    implements UseCase<LoadChatMessagesResult, LoadChatMessagesParams> {
  final TelegramService _service;

  LoadChatMessagesUseCase(this._service);

  @override
  Future<LoadChatMessagesResult> call(LoadChatMessagesParams params) async {
    bool hasMoreVideos = true;
    bool hasMoreDocs = true;
    int currentNextVideoFromId = params.nextVideoFromId;
    int currentNextDocFromId = params.nextDocFromId;

    final results = await Future.wait([
      _fetchBatch(
        chatId: params.chatId,
        messageThreadId: params.messageThreadId,
        fromMessageId: currentNextVideoFromId,
        filter: {'@type': 'searchMessagesFilterVideo'},
      ).then((batch) {
        if (batch.length < 20) hasMoreVideos = false;
        if (batch.isNotEmpty) currentNextVideoFromId = batch.last['id'];
        return batch;
      }),
      _fetchBatch(
        chatId: params.chatId,
        messageThreadId: params.messageThreadId,
        fromMessageId: currentNextDocFromId,
        filter: {'@type': 'searchMessagesFilterDocument'},
      ).then((batch) {
        if (batch.length < 20) hasMoreDocs = false;
        if (batch.isNotEmpty) currentNextDocFromId = batch.last['id'];
        return batch;
      }),
    ]);

    final allMsgs = <Map<String, dynamic>>[];
    for (final batch in results) {
      allMsgs.addAll(batch);
    }

    final validMsgs = allMsgs.where((msg) {
      if (params.messageThreadId != null) {
        final msgThreadId = msg['message_thread_id'] as int?;
        if (msgThreadId != null && msgThreadId != params.messageThreadId) {
          return false;
        }
      }
      return _isVideoMessage(msg);
    }).toList();

    return LoadChatMessagesResult(
      messages: validMsgs,
      nextVideoFromId: currentNextVideoFromId,
      nextDocFromId: currentNextDocFromId,
      hasMoreVideos: hasMoreVideos,
      hasMoreDocs: hasMoreDocs,
    );
  }

  Future<List<Map<String, dynamic>>> _fetchBatch({
    required int chatId,
    required int? messageThreadId,
    required int fromMessageId,
    required Map<String, dynamic>? filter,
  }) async {
    try {
      final result = await _service.sendWithResult({
        '@type': 'searchChatMessages',
        'chat_id': chatId,
        'topic_id': messageThreadId != null
            ? {'@type': 'messageTopicForum', 'forum_topic_id': messageThreadId}
            : null,
        'query': '',
        'sender_id': null,
        'fromMessageId': fromMessageId,
        'offset': 0,
        'limit': 20,
        'filter': filter,
      });

      if (result['@type'] == 'error') {
        return [];
      }

      final msgsList = result['messages'] as List?;
      if (msgsList == null) return [];
      return msgsList.cast<Map<String, dynamic>>();
    } catch (e) {
      return [];
    }
  }

  bool _isVideoMessage(Map<String, dynamic> message) {
    final content = message['content'];
    if (content == null) return false;

    if (content['@type'] == 'messageVideo') return true;

    if (content['@type'] == 'messageDocument') {
      final document = content['document'];
      final mimeType = (document['mime_type'] as String? ?? '').toLowerCase();
      final fileName = (document['file_name'] as String? ?? '').toLowerCase();

      if (mimeType.startsWith('video/')) return true;

      const videoExtensions = ['.mkv', '.avi', '.mp4', '.mov', '.webm', '.flv'];
      for (final ext in videoExtensions) {
        if (fileName.endsWith(ext)) return true;
      }
    }
    return false;
  }
}

@riverpod
LoadChatMessagesUseCase loadChatMessagesUseCase(Ref ref) {
  return LoadChatMessagesUseCase(TelegramService());
}
