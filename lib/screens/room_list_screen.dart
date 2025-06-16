import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import 'chat_screen.dart';
import 'welcome_screen.dart';
import 'security_settings_screen.dart';
import '../models/room.dart';
import 'package:intl/intl.dart';

class RoomListScreen extends StatefulWidget {
  const RoomListScreen({Key? key}) : super(key: key);

  @override
  State<RoomListScreen> createState() => _RoomListScreenState();
}

class _RoomListScreenState extends State<RoomListScreen> {
  bool _isLoading = false;
  final _roomNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchRooms();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    // 소켓 초기화
    chatProvider.initSocket();

    // 보안 시스템 초기화
    await chatProvider.initializeSecurity();
  }

  Future<void> _fetchRooms() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await Provider.of<ChatProvider>(context, listen: false).fetchRooms();
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('방 목록을 불러오는데 실패했습니다: $error')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _openCreateRoomDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('새 채팅방 만들기'),
        content: TextField(
          controller: _roomNameController,
          decoration: const InputDecoration(
            labelText: '방 이름',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _roomNameController.clear();
            },
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () async {
              if (_roomNameController.text.trim().isEmpty) {
                return;
              }

              Navigator.of(ctx).pop();

              try {
                final authProvider = Provider.of<AuthProvider>(context, listen: false);
                final chatProvider = Provider.of<ChatProvider>(context, listen: false);

                final room = await chatProvider.createRoom(
                  _roomNameController.text.trim(),
                  authProvider.tempId!,
                );

                _roomNameController.clear();

                // 방 생성 후 바로 해당 채팅방으로 이동
                await chatProvider.joinRoom(room.id, authProvider.tempId!);

                if (!mounted) return;
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (ctx) => const ChatScreen(),
                  ),
                );
              } catch (error) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('채팅방 생성에 실패했습니다: $error')),
                );
              }
            },
            child: const Text('만들기'),
          ),
        ],
      ),
    );
  }

  Future<void> _joinRoom(Room room) async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);

      await chatProvider.joinRoom(room.id, authProvider.tempId!);

      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (ctx) => const ChatScreen(),
        ),
      );
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('채팅방 입장에 실패했습니다: $error')),
      );
    }
  }

  Future<void> _logout() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    // 소켓 연결 해제
    chatProvider.disconnectSocket();

    // 로그아웃
    await authProvider.logout();

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (ctx) => const WelcomeScreen()),
    );
  }

  @override
  void dispose() {
    _roomNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rooms = Provider.of<ChatProvider>(context).rooms;
    final authProvider = Provider.of<AuthProvider>(context);
    final chatProvider = Provider.of<ChatProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('채팅방 목록'),
        actions: [
          // 보안 상태 표시
          _buildSecurityStatusButton(chatProvider),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchRooms,
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'security':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SecuritySettingsScreen(),
                    ),
                  );
                  break;
                case 'logout':
                  _logout();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'security',
                child: Row(
                  children: [
                    Icon(Icons.security),
                    SizedBox(width: 8),
                    Text('보안 설정'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.exit_to_app),
                    SizedBox(width: 8),
                    Text('로그아웃'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          // 사용자 정보 및 보안 상태
          _buildUserInfoSection(authProvider, chatProvider),

          // 보안 통계 (필요한 경우)
          _buildSecurityStatsSection(chatProvider),

          Expanded(
            child: rooms.isEmpty
                ? const Center(
              child: Text(
                '채팅방이 없습니다.\n아래 버튼을 눌러 첫 채팅방을 만들어보세요!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
            )
                : ListView.builder(
              itemCount: rooms.length,
              itemBuilder: (ctx, index) {
                final room = rooms[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: ListTile(
                    title: Text(
                      room.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      '생성 일시: ${DateFormat('yyyy-MM-dd HH:mm').format(room.createdAt)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 보안 보호 표시
                        Icon(
                          Icons.security,
                          size: 16,
                          color: chatProvider.securityEnabled
                              ? Colors.green
                              : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_ios),
                      ],
                    ),
                    onTap: () => _joinRoom(room),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreateRoomDialog,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildSecurityStatusButton(ChatProvider chatProvider) {
    final securityEnabled = chatProvider.securityEnabled;
    final dashboard = chatProvider.getSecurityDashboard();
    final blockedCount = dashboard['blocked_messages'] ?? 0;
    final warningCount = dashboard['warning_messages'] ?? 0;

    return Container(
      margin: const EdgeInsets.only(right: 8),
      child: Stack(
        children: [
          IconButton(
            icon: Icon(
              securityEnabled ? Icons.security : Icons.security_outlined,
              color: securityEnabled ? Colors.green : Colors.grey,
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SecuritySettingsScreen(),
                ),
              );
            },
          ),
          if (blockedCount > 0 || warningCount > 0)
            Positioned(
              right: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: blockedCount > 0 ? Colors.red : Colors.orange,
                  borderRadius: BorderRadius.circular(6),
                ),
                constraints: const BoxConstraints(
                  minWidth: 12,
                  minHeight: 12,
                ),
                child: Text(
                  '${blockedCount + warningCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildUserInfoSection(AuthProvider authProvider, ChatProvider chatProvider) {
    // AuthProvider에서 닉네임 정보를 가져옵니다
    final nickname = authProvider.nickname ?? '';

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.05),
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.blue,
            child: Icon(
              Icons.person,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '현재 이름: ${nickname.isNotEmpty ? nickname : '익명${authProvider.anonymousId ?? "사용자"}'}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '고유 번호: #${authProvider.uniqueIdentifier ?? "???"}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          // 보안 상태 표시
          Column(
            children: [
              Icon(
                chatProvider.securityEnabled ? Icons.security : Icons.security_outlined,
                color: chatProvider.securityEnabled ? Colors.green : Colors.grey,
                size: 20,
              ),
              Text(
                chatProvider.securityEnabled ? 'AI 보호' : '보호 해제',
                style: TextStyle(
                  fontSize: 10,
                  color: chatProvider.securityEnabled ? Colors.green : Colors.grey,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityStatsSection(ChatProvider chatProvider) {
    final dashboard = chatProvider.getSecurityDashboard();
    final totalMessages = dashboard['total_messages'] ?? 0;
    final blockedCount = dashboard['blocked_messages'] ?? 0;
    final warningCount = dashboard['warning_messages'] ?? 0;

    // 통계가 없으면 표시하지 않음
    if (totalMessages == 0) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          const Icon(Icons.analytics, size: 20, color: Colors.blue),
          const SizedBox(width: 8),
          Text(
            '보안 통계:',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 16),
          _buildStatItem('총 메시지', totalMessages.toString(), Colors.blue),
          const SizedBox(width: 12),
          if (blockedCount > 0)
            _buildStatItem('차단', blockedCount.toString(), Colors.red),
          const SizedBox(width: 12),
          if (warningCount > 0)
            _buildStatItem('경고', warningCount.toString(), Colors.orange),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: color.withOpacity(0.7),
          ),
        ),
      ],
    );
  }
}