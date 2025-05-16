import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../models/message.dart';
import 'package:intl/intl.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({Key? key}) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isLoading = false;
  bool _isFirstLoad = true;

  @override
  void initState() {
    super.initState();
    // 첫 로드 시 메시지 목록 맨 아래로 스크롤
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
      _isFirstLoad = false;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 메시지 목록이 변경될 때마다 스크롤 위치 업데이트
    final chatProvider = Provider.of<ChatProvider>(context);
    chatProvider.addListener(_handleChatUpdates);
  }

  void _handleChatUpdates() {
    // 주기적으로 처리된 메시지 ID 정리
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    chatProvider.cleanupProcessedMessages();

    // 스크롤 위치 업데이트
    if (_isFirstLoad || _isNearBottom()) {
      _scrollToBottom();
    }
  }

  // 현재 스크롤이 하단 근처인지 확인
  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;

    final position = _scrollController.position;
    final maxScroll = position.maxScrollExtent;
    final currentScroll = position.pixels;
    const threshold = 150.0;  // 스크롤이 하단에서 150픽셀 이내에 있으면 자동 스크롤

    return (maxScroll - currentScroll) <= threshold;
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    _messageController.clear();

    try {
      setState(() {
        _isLoading = true;
      });

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);

      debugPrint('메시지 전송 요청: $message');
      await chatProvider.sendMessage(
          message,
          authProvider.tempId!,
          authProvider.anonymousId,
          authProvider.nickname,
          authProvider.uniqueIdentifier
      );
      debugPrint('메시지 전송 성공');
    } catch (error) {
      debugPrint('메시지 전송 실패: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('메시지 전송에 실패했습니다: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    Provider.of<ChatProvider>(context, listen: false).removeListener(_handleChatUpdates);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final chatProvider = Provider.of<ChatProvider>(context);
    final messages = chatProvider.currentMessages;

    // 현재 방 찾기 (없으면 예외 대신 오류 메시지와 함께 빈 화면 표시)
    final currentRoom = chatProvider.rooms.where(
            (room) => room.id == chatProvider.currentRoomId
    ).firstOrNull;

    if (currentRoom == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('오류'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: const Center(
          child: Text('현재 방을 찾을 수 없습니다.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(currentRoom.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              // 방 정보 표시 (참가자 수 등)
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(currentRoom.name),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('생성 일시: ${DateFormat('yyyy-MM-dd HH:mm').format(currentRoom.createdAt)}'),
                      const SizedBox(height: 8),
                      const Text('모든 메시지는 E2E 암호화로 보호됩니다.'),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('닫기'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? const Center(
              child: Text(
                '아직 메시지가 없습니다.\n첫 메시지를 보내보세요!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
            )
                : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: messages.length,
              itemBuilder: (ctx, index) {
                final message = messages[index];
                final isMe = message.sender == authProvider.tempId;

                // 닉네임 또는 익명 ID와 함께 고유 식별 번호 표시
                String displayName;
                String uniqueId = "";

                if (isMe) {
                  // 내 메시지는 내 닉네임이 있으면 닉네임으로, 없으면 익명ID로 표시
                  if (authProvider.nickname != null && authProvider.nickname!.isNotEmpty) {
                    displayName = authProvider.nickname!;
                  } else {
                    displayName = '익명${authProvider.anonymousId}';
                  }
                  uniqueId = authProvider.uniqueIdentifier ?? "???";
                } else {
                  // 다른 사용자의 메시지는 닉네임이 있으면 닉네임 사용
                  if (message.senderNickname != null && message.senderNickname!.isNotEmpty) {
                    displayName = message.senderNickname!;
                  } else {
                    // 닉네임이 없는 경우 익명 ID 사용
                    int anonymousNumber = message.senderAnonymousId ?? 0;
                    if (anonymousNumber == 0) {
                      int hashCode = message.sender.hashCode.abs();
                      anonymousNumber = hashCode % 1000;
                    }
                    displayName = '익명$anonymousNumber';
                  }
                  uniqueId = message.senderUniqueId ?? "???";
                }

                return _MessageBubble(
                  message: message,
                  isMe: isMe,
                  nickname: displayName,
                  uniqueId: uniqueId,
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.5),
                  spreadRadius: 1,
                  blurRadius: 5,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(
                      hintText: '메시지를 입력하세요...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(30)),
                      ),
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Theme.of(context).primaryColor,
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : IconButton(
                    icon: const Icon(
                      Icons.send,
                      color: Colors.white,
                    ),
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMe;
  final String nickname;
  final String uniqueId;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.nickname,
    required this.uniqueId,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        if (!isMe)
          CircleAvatar(
            radius: 16,
            backgroundColor: Colors.grey,
            child: Text(
              nickname.isNotEmpty ? nickname.substring(0, 1).toUpperCase() : "?",
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (!isMe)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Row(
                    children: [
                      Text(
                        nickname,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '#$uniqueId',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  color: isMe ? Colors.blue : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      message.content,
                      style: TextStyle(
                        color: isMe ? Colors.white : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          DateFormat('HH:mm').format(message.timestamp),
                          style: TextStyle(
                            color: isMe ? Colors.white70 : Colors.black54,
                            fontSize: 10,
                          ),
                        ),
                        if (isMe) ...[
                          const SizedBox(width: 4),
                          Text(
                            '#$uniqueId',
                            style: TextStyle(
                              color: isMe ? Colors.white70 : Colors.black54,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (isMe) const SizedBox(width: 8),
      ],
    );
  }
}