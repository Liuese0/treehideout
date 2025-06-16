import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../ai/ai_detector_model.dart';
import 'security_settings_screen.dart';
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
    _initializeSecurity();

    // 첫 로드 시 메시지 목록 맨 아래로 스크롤
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
      _isFirstLoad = false;
    });
  }

  Future<void> _initializeSecurity() async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    await chatProvider.initializeSecurity();
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
      final success = await chatProvider.sendMessage(
          message,
          authProvider.tempId!,
          authProvider.anonymousId,
          authProvider.nickname,
          authProvider.uniqueIdentifier
      );

      if (success) {
        debugPrint('메시지 전송 성공');
      } else {
        debugPrint('메시지가 보안 검사에 의해 차단됨');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('메시지가 보안 정책에 의해 차단되었습니다'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
          // 보안 상태 표시
          _buildSecurityStatusIndicator(chatProvider),
          IconButton(
            icon: const Icon(Icons.security),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SecuritySettingsScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showRoomInfo(currentRoom),
          ),
        ],
      ),
      body: Column(
        children: [
          // 보안 통계 바
          _buildSecurityStatsBar(chatProvider),

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

                return _SecureMessageBubble(
                  message: message,
                  isMe: isMe,
                  nickname: displayName,
                  uniqueId: uniqueId,
                  onRetry: () => _retryMessage(message),
                  onShowSecurityDetails: () => _showSecurityDetails(message),
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

  Widget _buildSecurityStatusIndicator(ChatProvider chatProvider) {
    final securityEnabled = chatProvider.securityEnabled;

    return Container(
      margin: const EdgeInsets.only(right: 8),
      child: Icon(
        securityEnabled ? Icons.security : Icons.security_outlined,
        color: securityEnabled ? Colors.green : Colors.grey,
        size: 20,
      ),
    );
  }

  Widget _buildSecurityStatsBar(ChatProvider chatProvider) {
    final dashboard = chatProvider.getSecurityDashboard();
    final blockedCount = dashboard['blocked_messages'] ?? 0;
    final warningCount = dashboard['warning_messages'] ?? 0;

    if (blockedCount == 0 && warningCount == 0) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.blue.withOpacity(0.1),
      child: Row(
        children: [
          const Icon(Icons.security, size: 16, color: Colors.blue),
          const SizedBox(width: 8),
          Text(
            '보안 통계: ',
            style: TextStyle(
              fontSize: 12,
              color: Colors.blue.shade700,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (blockedCount > 0) ...[
            Text(
              '차단 $blockedCount',
              style: const TextStyle(fontSize: 12, color: Colors.red),
            ),
            const SizedBox(width: 8),
          ],
          if (warningCount > 0) ...[
            Text(
              '경고 $warningCount',
              style: const TextStyle(fontSize: 12, color: Colors.orange),
            ),
          ],
        ],
      ),
    );
  }

  void _showRoomInfo(room) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(room.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('생성 일시: ${DateFormat('yyyy-MM-dd HH:mm').format(room.createdAt)}'),
            const SizedBox(height: 8),
            const Text('모든 메시지는 AI 보안 검사를 통과합니다.'),
            const SizedBox(height: 8),
            const Text('E2E 암호화로 보호됩니다.'),
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
  }

  Future<void> _retryMessage(SecureMessage message) async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final success = await chatProvider.retryBlockedMessage(message.id);

    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('메시지 재전송에 실패했습니다'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showSecurityDetails(SecureMessage message) {
    final result = message.securityResult;
    if (result == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('보안 검사 결과'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSecurityDetailRow('위험 레벨', _getThreatLevelText(result.threatLevel)),
              _buildSecurityDetailRow('위험 유형', result.threatType),
              _buildSecurityDetailRow('위험도', '${(result.confidenceScore * 100).toInt()}%'),

              const SizedBox(height: 16),
              const Text('검사 결과:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(result.reason),

              if (result.detectedKeywords.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('탐지된 키워드:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: result.detectedKeywords.map((keyword) =>
                      Chip(
                        label: Text(keyword, style: const TextStyle(fontSize: 12)),
                        backgroundColor: Colors.red.withOpacity(0.1),
                      ),
                  ).toList(),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  String _getThreatLevelText(ThreatLevel level) {
    switch (level) {
      case ThreatLevel.safe:
        return '안전';
      case ThreatLevel.low:
        return '낮음';
      case ThreatLevel.medium:
        return '보통';
      case ThreatLevel.high:
        return '높음';
      case ThreatLevel.critical:
        return '심각';
    }
  }
}

class _SecureMessageBubble extends StatelessWidget {
  final SecureMessage message;
  final bool isMe;
  final String nickname;
  final String uniqueId;
  final VoidCallback? onRetry;
  final VoidCallback? onShowSecurityDetails;

  const _SecureMessageBubble({
    required this.message,
    required this.isMe,
    required this.nickname,
    required this.uniqueId,
    this.onRetry,
    this.onShowSecurityDetails,
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
                  color: _getMessageBackgroundColor(),
                  borderRadius: BorderRadius.circular(16),
                  border: _getMessageBorder(),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // 보안 상태 표시
                    if (message.status == MessageStatus.blocked ||
                        message.status == MessageStatus.warning ||
                        message.status == MessageStatus.failed)
                      _buildSecurityStatusRow(),

                    // 메시지 내용
                    Text(
                      message.status == MessageStatus.blocked
                          ? '[차단된 메시지]'
                          : message.content,
                      style: TextStyle(
                        color: _getMessageTextColor(),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 메시지 상태 아이콘
                        _buildStatusIcon(),
                        const SizedBox(width: 4),
                        Text(
                          DateFormat('HH:mm').format(message.timestamp),
                          style: TextStyle(
                            color: _getMessageTextColor().withOpacity(0.7),
                            fontSize: 10,
                          ),
                        ),
                        if (isMe) ...[
                          const SizedBox(width: 4),
                          Text(
                            '#$uniqueId',
                            style: TextStyle(
                              color: _getMessageTextColor().withOpacity(0.7),
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

  Widget _buildSecurityStatusRow() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getSecurityIcon(),
            size: 16,
            color: _getSecurityIconColor(),
          ),
          const SizedBox(width: 4),
          Text(
            _getSecurityStatusText(),
            style: TextStyle(
              fontSize: 12,
              color: _getSecurityIconColor(),
              fontWeight: FontWeight.bold,
            ),
          ),
          if (message.status == MessageStatus.blocked && onRetry != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onRetry,
              child: Icon(
                Icons.refresh,
                size: 16,
                color: _getSecurityIconColor(),
              ),
            ),
          ],
          if (message.securityResult != null && onShowSecurityDetails != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onShowSecurityDetails,
              child: Icon(
                Icons.info_outline,
                size: 16,
                color: _getSecurityIconColor(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusIcon() {
    switch (message.status) {
      case MessageStatus.sending:
        return const SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case MessageStatus.sent:
        return const Icon(Icons.check, size: 12, color: Colors.green);
      case MessageStatus.blocked:
        return const Icon(Icons.block, size: 12, color: Colors.red);
      case MessageStatus.warning:
        return const Icon(Icons.warning, size: 12, color: Colors.orange);
      case MessageStatus.failed:
        return const Icon(Icons.error, size: 12, color: Colors.red);
    }
  }

  Color _getMessageBackgroundColor() {
    switch (message.status) {
      case MessageStatus.blocked:
        return Colors.red.withOpacity(0.1);
      case MessageStatus.warning:
        return Colors.orange.withOpacity(0.1);
      case MessageStatus.failed:
        return Colors.red.withOpacity(0.1);
      default:
        return isMe ? Colors.blue : Colors.grey.shade200;
    }
  }

  Color _getMessageTextColor() {
    switch (message.status) {
      case MessageStatus.blocked:
      case MessageStatus.failed:
        return Colors.red.shade700;
      case MessageStatus.warning:
        return Colors.orange.shade700;
      default:
        return isMe ? Colors.white : Colors.black;
    }
  }

  Border? _getMessageBorder() {
    switch (message.status) {
      case MessageStatus.blocked:
        return Border.all(color: Colors.red, width: 1);
      case MessageStatus.warning:
        return Border.all(color: Colors.orange, width: 1);
      case MessageStatus.failed:
        return Border.all(color: Colors.red.shade300, width: 1);
      default:
        return null;
    }
  }

  IconData _getSecurityIcon() {
    switch (message.status) {
      case MessageStatus.blocked:
        return Icons.block;
      case MessageStatus.warning:
        return Icons.warning;
      case MessageStatus.failed:
        return Icons.error;
      default:
        return Icons.security;
    }
  }

  Color _getSecurityIconColor() {
    switch (message.status) {
      case MessageStatus.blocked:
      case MessageStatus.failed:
        return Colors.red;
      case MessageStatus.warning:
        return Colors.orange;
      default:
        return Colors.green;
    }
  }

  String _getSecurityStatusText() {
    switch (message.status) {
      case MessageStatus.blocked:
        return '차단됨';
      case MessageStatus.warning:
        return '경고';
      case MessageStatus.failed:
        return '실패';
      default:
        return '안전';
    }
  }
}