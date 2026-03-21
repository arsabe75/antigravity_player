import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../use_case.dart';
import '../../../infrastructure/services/telegram_service.dart';

part 'load_chat_messages_use_case.g.dart';

class LoadChatMessagesParams {
  final int chatId;
  final int? messageThreadId;
  final int nextVideoFromId;
  final int nextDocFromId;
  final String query;

  const LoadChatMessagesParams({
    required this.chatId,
    this.messageThreadId,
    this.nextVideoFromId = 0,
    this.nextDocFromId = 0,
    this.query = '',
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
    // If a search query is provided, we use the standard searchChatMessages (even for topics)
    // with the thread specified (if applicable, though TDLib searchChatMessages supports message_thread_id).
    // If it's a regular thread history load with no generic search, use _fetchTopicHistory.
    if (params.query.isEmpty && params.messageThreadId != null && params.messageThreadId != 0) {
      return _fetchTopicHistory(params);
    }

    bool hasMoreVideos = true;
    bool hasMoreDocs = true;
    int currentNextVideoFromId = params.nextVideoFromId;
    int currentNextDocFromId = params.nextDocFromId;

    final results = await Future.wait([
      currentNextVideoFromId != -1
          ? _fetchBatch(
              chatId: params.chatId,
              messageThreadId: params.messageThreadId,
              fromMessageId: currentNextVideoFromId,
              query: params.query,
              filter: {'@type': 'searchMessagesFilterVideo'},
            ).then((batch) {
              if (batch.length < 100) hasMoreVideos = false;
              if (batch.isNotEmpty) currentNextVideoFromId = batch.last['id'];
              return batch;
            })
          : Future.value(<Map<String, dynamic>>[]).then((batch) {
              hasMoreVideos = false;
              return batch;
            }),
      currentNextDocFromId != -1
          ? _fetchBatch(
              chatId: params.chatId,
              messageThreadId: params.messageThreadId,
              fromMessageId: currentNextDocFromId,
              query: params.query,
              filter: {'@type': 'searchMessagesFilterDocument'},
            ).then((batch) {
              if (batch.length < 100) hasMoreDocs = false;
              if (batch.isNotEmpty) currentNextDocFromId = batch.last['id'];
              return batch;
            })
          : Future.value(<Map<String, dynamic>>[]).then((batch) {
              hasMoreDocs = false;
              return batch;
            }),
    ]);

    final allMsgs = <Map<String, dynamic>>[];
    for (final batch in results) {
      allMsgs.addAll(batch);
    }

    final validMsgs = allMsgs.where((msg) {
      if (!_isVideoMessage(msg)) return false;
      if (params.messageThreadId != null && params.messageThreadId != 0) {
        int? msgThreadId = msg['message_thread_id'] as int?;
        if (msgThreadId == null && msg.containsKey('topic_id')) {
          final topicObj = msg['topic_id'];
          if (topicObj is Map) {
            msgThreadId = topicObj['forum_topic_id'] as int?;
          } else if (topicObj is int) {
            msgThreadId = topicObj;
          }
        }
        final finalThreadId = msgThreadId ?? 0;
        if (finalThreadId != params.messageThreadId) {
          return false;
        }
      }
      return true;
    }).toList();
    return LoadChatMessagesResult(
      messages: validMsgs,
      nextVideoFromId: currentNextVideoFromId,
      nextDocFromId: currentNextDocFromId,
      hasMoreVideos: hasMoreVideos,
      hasMoreDocs: hasMoreDocs,
    );
  }

  Future<LoadChatMessagesResult> _fetchTopicHistory(
    LoadChatMessagesParams params,
  ) async {
    if (params.nextVideoFromId == -1) {
      return LoadChatMessagesResult(
        messages: [],
        nextVideoFromId: -1,
        nextDocFromId: -1,
        hasMoreVideos: false,
        hasMoreDocs: false,
      );
    }

    try {
      final topicMessageId = params.messageThreadId! * 1048576;
      final result = await _service.sendWithResult({
        '@type': 'getMessageThreadHistory',
        'chat_id': params.chatId,
        'message_id': topicMessageId,
        'from_message_id': params.nextVideoFromId,
        'offset': 0,
        'limit': 100, // Fetch large batches to locate videos quickly
      });

      if (result['@type'] == 'error') {
        debugPrint(
          'TDLib getMessageThreadHistory error: ${result['code']} - ${result['message']}',
        );
        return LoadChatMessagesResult(
          messages: [],
          nextVideoFromId: -1,
          nextDocFromId: -1,
          hasMoreVideos: false,
          hasMoreDocs: false,
        );
      }

      final msgsList = result['messages'] as List?;
      if (msgsList == null) {
        return LoadChatMessagesResult(
          messages: [],
          nextVideoFromId: -1,
          nextDocFromId: -1,
          hasMoreVideos: false,
          hasMoreDocs: false,
        );
      }

      final typedMsgs = msgsList.cast<Map<String, dynamic>>();
      bool hasMore = typedMsgs.length == 100;
      int nextId = typedMsgs.isNotEmpty
          ? typedMsgs.last['id']
          : params.nextVideoFromId;

      final validMsgs = typedMsgs.where(_isVideoMessage).toList();

      return LoadChatMessagesResult(
        messages: validMsgs,
        nextVideoFromId: hasMore ? nextId : -1,
        nextDocFromId: hasMore ? nextId : -1,
        hasMoreVideos: hasMore,
        hasMoreDocs: hasMore,
      );
    } catch (e) {
      return LoadChatMessagesResult(
        messages: [],
        nextVideoFromId: -1,
        nextDocFromId: -1,
        hasMoreVideos: false,
        hasMoreDocs: false,
      );
    }
  }

  Future<List<Map<String, dynamic>>> _fetchBatch({
    required int chatId,
    int? messageThreadId,
    required int fromMessageId,
    String query = '',
    required Map<String, dynamic>? filter,
  }) async {
    if (fromMessageId == -1) return [];

    try {
      final request = <String, dynamic>{
        '@type': 'searchChatMessages',
        'chat_id': chatId,
        'query': query,
        'from_message_id': fromMessageId,
        'offset': 0,
        'limit': 100,
        'filter': filter,
      };

      if (messageThreadId != null && messageThreadId != 0) {
        request['message_thread_id'] = messageThreadId;
      }

      final result = await _service.sendWithResult(request);

      if (result['@type'] == 'error') {
        debugPrint(
          'TDLib searchChatMessages error: ${result['code']} - ${result['message']}',
        );
        return [];
      }

      final msgsList = result['messages'] as List?;
      debugPrint(
        'TDLib searchChatMessages result limit 100 got ${msgsList?.length} messages for global chat',
      );
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
      if (mimeType == 'application/x-matroska' ||
          mimeType == 'application/matroska') {
        return true;
      }

      const videoExtensions = [
        '.mkv',
        '.avi',
        '.mp4',
        '.mov',
        '.webm',
        '.flv',
        '.wmv',
        '.ts',
        '.m2ts',
        '.m4v',
        '.mpg',
        '.mpeg',
        '.3gp',
      ];
      for (final ext in videoExtensions) {
        if (fileName.endsWith(ext)) return true;
      }

      final size = document['document']['size'] ?? 0;
      if (size > 20 * 1024 * 1024 && !fileName.contains('.')) {
        return true;
      }
    }
    return false;
  }
}

@riverpod
LoadChatMessagesUseCase loadChatMessagesUseCase(Ref ref) {
  return LoadChatMessagesUseCase(TelegramService());
}
