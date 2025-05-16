import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import 'chat_screen.dart';
import 'welcome_screen.dart';
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

    // 소켓 초기화
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    chatProvider.initSocket();
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
    final nickname = authProvider.nickname;

    return Scaffold(
      appBar: AppBar(
        title: const Text('채팅방 목록'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchRooms,
          ),
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            onPressed: _logout,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const Icon(Icons.person, color: Colors.blue),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '현재 이름: ${nickname != null && nickname.isNotEmpty ? nickname : '익명${authProvider.anonymousId}'}',
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
              ],
            ),
          ),
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
                    trailing: const Icon(Icons.arrow_forward_ios),
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
}