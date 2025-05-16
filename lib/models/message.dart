

// lib/models/message.dart
class Message {
  final String id;
  final String roomId;
  final String sender; // 보낸 사람의 tempId
  final String content;
  final DateTime timestamp;
  final int? senderAnonymousId; // 보낸 사람의 익명 ID
  final String? senderNickname; // 보낸 사람의 닉네임
  final String? senderUniqueId; // 보낸 사람의 고유 식별 번호

  Message({
    required this.id,
    required this.roomId,
    required this.sender,
    required this.content,
    required this.timestamp,
    this.senderAnonymousId,
    this.senderNickname,
    this.senderUniqueId,
  });
}