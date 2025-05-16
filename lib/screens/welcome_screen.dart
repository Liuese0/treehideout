import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'room_list_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({Key? key}) : super(key: key);

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _nicknameController = TextEditingController();
  bool _isLoading = false;
  bool _isInit = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInit) {
      _checkAuthentication();
      _isInit = true;
    }
  }

  Future<void> _checkAuthentication() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await authProvider.checkAuthentication();

    if (authProvider.isAuthenticated) {
      // 이미 인증된 사용자라면 방 목록 화면으로 이동
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (ctx) => const RoomListScreen()),
      );
    }
  }

  Future<void> _createAnonymousUser() async {
    // 닉네임이 비어있어도 진행, 빈 경우 익명으로 처리됨
    final nickname = _nicknameController.text.trim();

    setState(() {
      _isLoading = true;
    });

    try {
      await Provider.of<AuthProvider>(context, listen: false)
          .createAnonymousUser(nickname);

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (ctx) => const RoomListScreen()),
      );
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('오류가 발생했습니다: $error')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.chat_bubble_outline,
                  size: 100,
                  color: Colors.blue,
                ),
                const SizedBox(height: 16),
                const Text(
                  '익명 채팅에 오신 것을 환영합니다',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _nicknameController,
                  decoration: const InputDecoration(
                    labelText: '닉네임 (선택 사항)',
                    hintText: '비워두면 익명으로 표시됩니다',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _createAnonymousUser,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                      '익명으로 시작하기',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  '이 앱은 완전한 익명성을 보장합니다.\n개인 정보가 저장되지 않습니다.',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}