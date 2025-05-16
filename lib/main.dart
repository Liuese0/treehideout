import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/welcome_screen.dart';
import 'providers/auth_provider.dart';
import 'providers/chat_provider.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
      ],
      child: MaterialApp(
        title: '익명 채팅',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          visualDensity: VisualDensity.adaptivePlatformDensity,
          scaffoldBackgroundColor: Colors.white,
          appBarTheme: const AppBarTheme(
            color: Colors.blue,
            elevation: 0,
          ),
        ),
        home: const AppLifecycleManager(child: WelcomeScreen()),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

// 앱 생명주기 관리를 위한 클래스
class AppLifecycleManager extends StatefulWidget {
  final Widget child;

  const AppLifecycleManager({Key? key, required this.child}) : super(key: key);

  @override
  State<AppLifecycleManager> createState() => _AppLifecycleManagerState();
}

class _AppLifecycleManagerState extends State<AppLifecycleManager> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    switch (state) {
      case AppLifecycleState.resumed:
      // 앱이 포그라운드로 돌아올 때
        debugPrint('앱 생명주기: resumed');
        // 현재 채팅방이 있으면 소켓 재연결
        if (chatProvider.currentRoomId != null) {
          chatProvider.initSocket();
        }
        break;
      case AppLifecycleState.inactive:
      // 앱이 비활성화될 때 (다른 앱으로 전환 등)
        debugPrint('앱 생명주기: inactive');
        break;
      case AppLifecycleState.paused:
      // 앱이 백그라운드로 갈 때
        debugPrint('앱 생명주기: paused');
        chatProvider.disconnectSocket();
        break;
      case AppLifecycleState.detached:
      // 앱이 완전히 종료될 때
        debugPrint('앱 생명주기: detached');
        chatProvider.disconnectSocket();
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}