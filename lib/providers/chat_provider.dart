import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:uuid/uuid.dart';
import '../models/room.dart';
import '../models/message.dart';
import '../utils/constants.dart';
import '../services/integrated_security_manager.dart';
import '../ai/ai_detector_model.dart';

// 메시지 상태
enum MessageStatus {
  sending,    // 전송 중
  sent,       // 전송 완료
  blocked,    // 차단됨
  warning,    // 경고
  failed      // 실패
}

// 확장된 메시지 클래스
class SecureMessage extends Message {
  final MessageStatus status;
  final ThreatDetectionResult? securityResult;
  final bool isSecurityChecked;

  SecureMessage({
    required String id,
    required String roomId,
    required String sender,
    required String content,
    required DateTime timestamp,
    int? senderAnonymousId,
    String? senderNickname,
    String? senderUniqueId,
    this.status = MessageStatus.sent,
    this.securityResult,
    this.isSecurityChecked = false,
  }) : super(
    id: id,
    roomId: roomId,
    sender: sender,
    content: content,
    timestamp: timestamp,
    senderAnonymousId: senderAnonymousId,
    senderNickname: senderNickname,
    senderUniqueId: senderUniqueId,
  );

  // Message에서 SecureMessage로 변환
  factory SecureMessage.fromMessage(Message message, {
    MessageStatus status = MessageStatus.sent,
    ThreatDetectionResult? securityResult,
    bool isSecurityChecked = false,
  }) {
    return SecureMessage(
      id: message.id,
      roomId: message.roomId,
      sender: message.sender,
      content: message.content,
      timestamp: message.timestamp,
      senderAnonymousId: message.senderAnonymousId,
      senderNickname: message.senderNickname,
      senderUniqueId: message.senderUniqueId,
      status: status,
      securityResult: securityResult,
      isSecurityChecked: isSecurityChecked,
    );
  }

  SecureMessage copyWith({
    MessageStatus? status,
    ThreatDetectionResult? securityResult,
    bool? isSecurityChecked,
  }) {
    return SecureMessage(
      id: id,
      roomId: roomId,
      sender: sender,
      content: content,
      timestamp: timestamp,
      senderAnonymousId: senderAnonymousId,
      senderNickname: senderNickname,
      senderUniqueId: senderUniqueId,
      status: status ?? this.status,
      securityResult: securityResult ?? this.securityResult,
      isSecurityChecked: isSecurityChecked ?? this.isSecurityChecked,
    );
  }
}

// 보안 통합 ChatProvider
class ChatProvider with ChangeNotifier {
  List<Room> _rooms = [];
  Map<String, List<SecureMessage>> _messages = {};
  io.Socket? _socket;
  String? _currentRoomId;

  // 보안 관리자
  final IntegratedSecurityManager _securityManager = IntegratedSecurityManager();

  // 메시지 중복 방지를 위한 세트 추가
  final Set<String> _processedMessageIds = {};
  bool _socketInitialized = false;

  // 보안 관련 상태
  bool _securityEnabled = true;
  int _blockedMessagesCount = 0;
  int _warningMessagesCount = 0;

  List<Room> get rooms => [..._rooms];
  List<SecureMessage> get currentMessages =>
      _currentRoomId != null ? [...(_messages[_currentRoomId] ?? [])] : [];
  String? get currentRoomId => _currentRoomId;
  bool get securityEnabled => _securityEnabled;
  int get blockedMessagesCount => _blockedMessagesCount;
  int get warningMessagesCount => _warningMessagesCount;

  // 보안 관리자 초기화
  Future<bool> initializeSecurity() async {
    try {
      debugPrint('보안 시스템 초기화 시작...');
      final initialized = await _securityManager.initialize();
      if (initialized) {
        debugPrint('보안 시스템 초기화 완료');
      }
      return initialized;
    } catch (e) {
      debugPrint('보안 시스템 초기화 실패: $e');
      return false;
    }
  }

  // 소켓 초기화 및 연결
  void initSocket() {
    // 이미 초기화된 소켓이 있으면 재초기화하지 않음
    if (_socketInitialized && _socket != null) {
      debugPrint('소켓이 이미 초기화되어 있습니다.');
      return;
    }

    debugPrint('소켓 초기화 시작...');
    // 기존 소켓 연결 해제
    if (_socket != null) {
      _socket!.disconnect();
      _socket!.dispose();
      _socket = null;
    }

    _socket = io.io(socketBaseUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
      'forceNew': true,  // 새 연결 강제
    });

    _socket!.onConnect((_) {
      debugPrint('소켓 연결됨: ${_socket!.id}');
      _socketInitialized = true;
    });

    _socket!.onConnectError((data) {
      debugPrint('소켓 연결 오류: $data');
    });

    _socket!.onDisconnect((_) {
      debugPrint('소켓 연결 해제됨');
      _socketInitialized = false;
    });

    _socket!.on('receive_message', (data) async {
      debugPrint('메시지 수신: ${data.toString()}');
      final roomId = data['roomId'] as String?;
      final messageId = data['messageId'] as String?;

      // null 체크
      if (roomId == null || messageId == null) {
        debugPrint('잘못된 메시지 데이터: roomId 또는 messageId가 null');
        return;
      }

      // 이미 처리된 메시지인지 확인 (중복 방지)
      if (_processedMessageIds.contains(messageId)) {
        debugPrint('이미 처리된 메시지 무시: $messageId');
        return;
      }

      // 처리된 메시지 ID 기록
      _processedMessageIds.add(messageId);

      if (_messages.containsKey(roomId)) {
        try {
          final newMessage = SecureMessage(
            id: messageId,
            roomId: roomId,
            sender: data['sender'] ?? '',
            content: data['content'] ?? '',
            timestamp: DateTime.tryParse(data['createdAt'] ?? '') ?? DateTime.now(),
            senderAnonymousId: data['senderAnonymousId'],
            senderNickname: data['senderNickname'],
            senderUniqueId: data['senderUniqueId'],
            status: MessageStatus.sent,
            isSecurityChecked: false,
          );

          // 이미 동일한 ID의 메시지가 있는지 확인
          final roomMessages = _messages[roomId];
          if (roomMessages != null) {
            final existingMessage = roomMessages.any((msg) => msg.id == messageId);
            if (!existingMessage) {
              roomMessages.add(newMessage);
              debugPrint('메시지가 상태에 추가됨: ${newMessage.content}');

              // 수신된 메시지에 대해 보안 검사 수행 (백그라운드)
              _performSecurityCheck(newMessage, roomId);

              notifyListeners();
            } else {
              debugPrint('동일한 ID의 메시지가 이미 있음: $messageId');
            }
          }
        } catch (e) {
          debugPrint('메시지 파싱 오류: $e');
        }
      } else {
        debugPrint('방 ID가 로컬에 없음: $roomId, 현재 방 목록: ${_messages.keys.toList()}');
      }
    });

    _socket!.on('message_error', (data) {
      debugPrint('메시지 오류 발생: $data');
    });

    _socket!.connect();
    debugPrint('소켓 연결 요청됨');
  }

  // 메시지 보안 검사 수행
  Future<void> _performSecurityCheck(SecureMessage message, String roomId) async {
    if (!_securityEnabled) return;

    try {
      final securityResult = await _securityManager.checkMessageSecurity(
        message.content,
        message.sender,
        roomId,
      );

      // 메시지 상태 업데이트
      final roomMessages = _messages[roomId];
      if (roomMessages != null) {
        final messageIndex = roomMessages.indexWhere((msg) => msg.id == message.id);
        if (messageIndex >= 0) {
          MessageStatus newStatus = MessageStatus.sent;

          if (securityResult.isBlocked) {
            newStatus = MessageStatus.blocked;
            _blockedMessagesCount++;
          } else if (securityResult.hasWarning) {
            newStatus = MessageStatus.warning;
            _warningMessagesCount++;
          }

          roomMessages[messageIndex] = message.copyWith(
            status: newStatus,
            securityResult: securityResult.aiResult,
            isSecurityChecked: true,
          );

          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('보안 검사 실패: $e');
    }
  }

  // 소켓 연결 해제
  void disconnectSocket() {
    if (_socket != null) {
      _socket!.disconnect();
      _socketInitialized = false;
      debugPrint('소켓 연결 해제 요청됨');
    }
  }

  // 방 목록 조회
  Future<void> fetchRooms() async {
    final url = Uri.parse('$apiBaseUrl/api/rooms');

    try {
      debugPrint('방 목록 조회 요청: $url');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        final List<dynamic> roomsData = responseData['data'];

        debugPrint('받은 방 목록 개수: ${roomsData.length}');
        _rooms = roomsData.map((room) => Room(
          id: room['roomId'] ?? '',
          name: room['name'] ?? '',
          createdAt: DateTime.tryParse(room['createdAt'] ?? '') ?? DateTime.now(),
        )).toList();

        notifyListeners();
      } else {
        debugPrint('방 목록 조회 실패: ${response.statusCode}, ${response.body}');
        throw Exception('방 목록 조회 실패: ${response.statusCode}');
      }
    } catch (error) {
      debugPrint('방 목록 조회 중 오류 발생: $error');
      throw Exception('방 목록 조회 중 오류 발생: $error');
    }
  }

  // 새 채팅방 생성
  Future<Room> createRoom(String name, String creatorTempId) async {
    final url = Uri.parse('$apiBaseUrl/api/rooms');

    try {
      debugPrint('채팅방 생성 요청: $url, 이름: $name');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'name': name,
          'creatorTempId': creatorTempId,
        }),
      );

      if (response.statusCode == 201) {
        final responseData = json.decode(response.body);

        final newRoom = Room(
          id: responseData['data']?['roomId'] ?? '',
          name: responseData['data']?['name'] ?? '',
          createdAt: DateTime.now(),
        );

        _rooms.add(newRoom);
        _messages[newRoom.id] = [];
        debugPrint('채팅방 생성 성공: ${newRoom.id}');

        notifyListeners();
        return newRoom;
      } else {
        debugPrint('채팅방 생성 실패: ${response.statusCode}, ${response.body}');
        throw Exception('채팅방 생성 실패: ${response.statusCode}');
      }
    } catch (error) {
      debugPrint('채팅방 생성 중 오류 발생: $error');
      throw Exception('채팅방 생성 중 오류 발생: $error');
    }
  }

  // 채팅방의 이전 메시지 조회
  Future<void> fetchMessages(String roomId) async {
    final url = Uri.parse('$apiBaseUrl/api/rooms/$roomId/messages');

    try {
      debugPrint('메시지 이력 조회 요청: $url');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        final List<dynamic> messagesData = responseData['data'];

        debugPrint('받은 메시지 개수: ${messagesData.length}');
        final List<SecureMessage> loadedMessages = messagesData.map((message) {
          final messageId = message['messageId'];
          // 처리된 메시지 ID 기록
          _processedMessageIds.add(messageId);

          return SecureMessage(
            id: message['messageId'] ?? '',
            roomId: message['roomId'] ?? '',
            sender: message['sender'] ?? '',
            content: message['content'] ?? '',
            timestamp: DateTime.tryParse(message['createdAt'] ?? '') ?? DateTime.now(),
            senderAnonymousId: message['senderAnonymousId'],
            senderNickname: message['senderNickname'],
            senderUniqueId: message['senderUniqueId'],
            status: MessageStatus.sent,
            isSecurityChecked: false,
          );
        }).toList();

        _messages[roomId] = loadedMessages;

        // 백그라운드에서 이전 메시지들에 대해 보안 검사 수행
        _performBatchSecurityCheck(loadedMessages, roomId);

        notifyListeners();
      } else {
        debugPrint('메시지 이력 조회 실패: ${response.statusCode}, ${response.body}');
        throw Exception('메시지 이력 조회 실패: ${response.statusCode}');
      }
    } catch (error) {
      debugPrint('메시지 이력 조회 중 오류 발생: $error');
      throw Exception('메시지 이력 조회 중 오류 발생: $error');
    }
  }

  // 배치 보안 검사
  Future<void> _performBatchSecurityCheck(List<SecureMessage> messages, String roomId) async {
    if (!_securityEnabled) return;

    for (final message in messages) {
      await _performSecurityCheck(message, roomId);
      // 너무 많은 요청을 방지하기 위해 약간의 지연
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  // 채팅방 입장
  Future<void> joinRoom(String roomId, String tempId) async {
    final url = Uri.parse('$apiBaseUrl/api/rooms/$roomId/join');

    try {
      debugPrint('채팅방 입장 요청: $url, tempId: $tempId');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'tempId': tempId}),
      );

      if (response.statusCode == 200) {
        // 이전 방에서 나가기
        if (_currentRoomId != null && _currentRoomId != roomId) {
          _socket?.emit('leave_room', _currentRoomId);
        }

        _currentRoomId = roomId;

        // 이 방의 메시지 컬렉션이 없으면 초기화
        if (!_messages.containsKey(roomId)) {
          _messages[roomId] = [];

          // 이전 메시지 이력 가져오기
          await fetchMessages(roomId);
        }

        // 소켓 초기화 확인
        if (!_socketInitialized) {
          initSocket();
        }

        // 소켓으로 방 입장 이벤트 전송
        debugPrint('소켓을 통해 방 입장 요청: $roomId');
        _socket?.emit('join_room', roomId);

        notifyListeners();
      } else {
        debugPrint('채팅방 입장 실패: ${response.statusCode}, ${response.body}');
        throw Exception('채팅방 입장 실패: ${response.statusCode}');
      }
    } catch (error) {
      debugPrint('채팅방 입장 중 오류 발생: $error');
      throw Exception('채팅방 입장 중 오류 발생: $error');
    }
  }

  // 메시지 전송 (보안 검사 포함)
  Future<bool> sendMessage(String content, String sender, int? senderAnonymousId, String? senderNickname, String? senderUniqueId) async {
    if (_currentRoomId == null) {
      debugPrint('오류: 현재 채팅방이 없습니다.');
      return false;
    }

    try {
      final messageId = const Uuid().v4();
      final timestamp = DateTime.now();

      debugPrint('메시지 전송 시도 - 내용: $content, 방: $_currentRoomId');

      // 임시 메시지 생성 (전송 중 상태)
      final tempMessage = SecureMessage(
        id: messageId,
        roomId: _currentRoomId!,
        sender: sender,
        content: content,
        timestamp: timestamp,
        senderAnonymousId: senderAnonymousId,
        senderNickname: senderNickname,
        senderUniqueId: senderUniqueId,
        status: MessageStatus.sending,
        isSecurityChecked: false,
      );

      // 방이 없으면 초기화
      _messages[_currentRoomId!] ??= [];

      // 임시 메시지 추가
      final currentRoomMessages = _messages[_currentRoomId!];
      if (currentRoomMessages != null) {
        currentRoomMessages.add(tempMessage);
      } else {
        _messages[_currentRoomId!] = [tempMessage];
      }
      notifyListeners();

      // 보안 검사 수행
      if (_securityEnabled) {
        final securityResult = await _securityManager.checkMessageSecurity(
          content,
          sender,
          _currentRoomId!,
        );

        // 메시지가 차단되었는지 확인
        if (securityResult.isBlocked) {
          // 차단된 메시지 상태 업데이트
          final roomMessages = _messages[_currentRoomId];
          if (roomMessages != null) {
            final messageIndex = roomMessages.indexWhere((msg) => msg.id == messageId);
            if (messageIndex >= 0) {
              roomMessages[messageIndex] = tempMessage.copyWith(
                status: MessageStatus.blocked,
                securityResult: securityResult.aiResult,
                isSecurityChecked: true,
              );
              _blockedMessagesCount++;
              notifyListeners();
            }
          }

          debugPrint('메시지가 보안 검사에 의해 차단됨: ${securityResult.message}');
          return false; // 메시지 전송 중단
        }

        // 경고가 있지만 차단되지 않은 경우
        if (securityResult.hasWarning) {
          final roomMessages = _messages[_currentRoomId];
          if (roomMessages != null) {
            final messageIndex = roomMessages.indexWhere((msg) => msg.id == messageId);
            if (messageIndex >= 0) {
              roomMessages[messageIndex] = tempMessage.copyWith(
                securityResult: securityResult.aiResult,
                isSecurityChecked: true,
              );
              _warningMessagesCount++;
              notifyListeners();
            }
          }
        }
      }

      // 메시지 ID를 처리된 목록에 추가 (중복 방지)
      _processedMessageIds.add(messageId);

      // 소켓으로 메시지 전송
      final messageData = {
        'messageId': messageId,
        'roomId': _currentRoomId,
        'sender': sender,
        'content': content,
        'senderAnonymousId': senderAnonymousId,
        'senderNickname': senderNickname,
        'senderUniqueId': senderUniqueId,
      };

      debugPrint('소켓을 통해 메시지 전송 요청: $messageData');
      _socket?.emit('send_message', messageData);

      // 메시지 상태를 전송 완료로 업데이트
      final roomMessages = _messages[_currentRoomId];
      if (roomMessages != null) {
        final messageIndex = roomMessages.indexWhere((msg) => msg.id == messageId);
        if (messageIndex >= 0) {
          roomMessages[messageIndex] = roomMessages[messageIndex].copyWith(
            status: MessageStatus.sent,
          );
          debugPrint('메시지가 성공적으로 전송됨');
          notifyListeners();
        }
      }

      return true;
    } catch (error) {
      // 오류 발생 시 메시지 상태를 실패로 업데이트
      final roomMessages = _messages[_currentRoomId];
      if (roomMessages != null) {
        final messageIndex = roomMessages.indexWhere((msg) =>
        msg.sender == sender && msg.content == content);
        if (messageIndex >= 0) {
          roomMessages[messageIndex] = roomMessages[messageIndex].copyWith(
            status: MessageStatus.failed,
          );
          notifyListeners();
        }
      }

      debugPrint('메시지 전송 중 오류 발생: $error');
      throw Exception('메시지 전송 중 오류 발생: $error');
    }
  }

  // 차단된 메시지 재전송 시도
  Future<bool> retryBlockedMessage(String messageId) async {
    final roomMessages = _messages[_currentRoomId];
    if (roomMessages == null) return false;

    final messageIndex = roomMessages.indexWhere((msg) => msg.id == messageId);
    if (messageIndex == -1) return false;

    final message = roomMessages[messageIndex];
    if (message.status != MessageStatus.blocked) return false;

    // 메시지 제거
    roomMessages.removeAt(messageIndex);
    notifyListeners();

    // 다시 전송 시도
    return await sendMessage(
      message.content,
      message.sender,
      message.senderAnonymousId,
      message.senderNickname,
      message.senderUniqueId,
    );
  }

  // 채팅방 나가기
  void leaveRoom() {
    if (_currentRoomId != null) {
      debugPrint('채팅방 나가기: $_currentRoomId');
      _socket?.emit('leave_room', _currentRoomId);
      _currentRoomId = null;
      notifyListeners();
    }
  }

  // 보안 기능 활성화/비활성화
  void setSecurityEnabled(bool enabled) {
    _securityEnabled = enabled;
    debugPrint('보안 기능 ${enabled ? '활성화' : '비활성화'}');
    notifyListeners();
  }

  // 보안 통계 초기화
  void resetSecurityStats() {
    _blockedMessagesCount = 0;
    _warningMessagesCount = 0;
    notifyListeners();
  }

  // 메시지 상태별 개수 조회 - null 안전성 완전 해결
  Map<MessageStatus, int> getMessageStatusCounts() {
    final counts = <MessageStatus, int>{
      MessageStatus.sending: 0,
      MessageStatus.sent: 0,
      MessageStatus.blocked: 0,
      MessageStatus.warning: 0,
      MessageStatus.failed: 0,
    };

    for (final messageList in _messages.values) {
      for (final message in messageList) {
        final currentCount = counts[message.status] ?? 0;
        counts[message.status] = currentCount + 1;
      }
    }

    return counts;
  }

  // 특정 위험 레벨의 메시지 조회
  List<SecureMessage> getMessagesByThreatLevel(ThreatLevel level) {
    final result = <SecureMessage>[];

    for (final messageList in _messages.values) {
      for (final message in messageList) {
        if (message.securityResult?.threatLevel == level) {
          result.add(message);
        }
      }
    }

    return result;
  }

  // 보안 대시보드 데이터
  Map<String, dynamic> getSecurityDashboard() {
    final statusCounts = getMessageStatusCounts();
    final totalMessages = statusCounts.values.fold<int>(0, (int sum, int count) => sum + count);

    return {
      'total_messages': totalMessages,
      'blocked_messages': _blockedMessagesCount,
      'warning_messages': _warningMessagesCount,
      'security_enabled': _securityEnabled,
      'status_counts': statusCounts.map((key, value) => MapEntry(key.toString(), value)),
      'security_rate': totalMessages > 0 ? ((_blockedMessagesCount + _warningMessagesCount) / totalMessages * 100).toStringAsFixed(1) : '0.0',
    };
  }

  // 주기적으로 오래된 처리된 메시지 ID 정리 (메모리 관리)
  void cleanupProcessedMessages() {
    // 처리된 메시지 ID가 너무 많아지면 정리
    if (_processedMessageIds.length > 1000) {
      debugPrint('처리된 메시지 ID 정리 중...');

      // 현재 표시된 메시지의 ID만 유지
      Set<String> currentDisplayedIds = {};
      _messages.forEach((roomId, messages) {
        for (var message in messages) {
          currentDisplayedIds.add(message.id);
        }
      });

      // 현재 표시된 메시지 ID만 유지하고 나머지는 삭제
      _processedMessageIds.removeWhere((id) => !currentDisplayedIds.contains(id));

      debugPrint('처리된 메시지 ID 정리 완료. 남은 ID 수: ${_processedMessageIds.length}');
    }
  }

  @override
  void dispose() {
    disconnectSocket();
    super.dispose();
  }
}