import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:uuid/uuid.dart';
import '../models/room.dart';
import '../models/message.dart';
import '../utils/constants.dart';

// 소켓 연결과 메시지 중복 문제를 해결하기 위한 ChatProvider 수정
class ChatProvider with ChangeNotifier {
  List<Room> _rooms = [];
  Map<String, List<Message>> _messages = {};
  io.Socket? _socket;
  String? _currentRoomId;

  // 메시지 중복 방지를 위한 세트 추가
  final Set<String> _processedMessageIds = {};
  bool _socketInitialized = false;

  List<Room> get rooms => [..._rooms];
  List<Message> get currentMessages => _currentRoomId != null ? [..._messages[_currentRoomId] ?? []] : [];
  String? get currentRoomId => _currentRoomId;

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

    _socket!.on('receive_message', (data) {
      debugPrint('메시지 수신: ${data.toString()}');
      final roomId = data['roomId'];
      final messageId = data['messageId'];

      // 이미 처리된 메시지인지 확인 (중복 방지)
      if (_processedMessageIds.contains(messageId)) {
        debugPrint('이미 처리된 메시지 무시: $messageId');
        return;
      }

      // 처리된 메시지 ID 기록
      _processedMessageIds.add(messageId);

      if (_messages.containsKey(roomId)) {
        try {
          final newMessage = Message(
            id: messageId,
            roomId: roomId,
            sender: data['sender'],
            content: data['content'],
            timestamp: DateTime.parse(data['createdAt']),
            senderAnonymousId: data['senderAnonymousId'],
            senderNickname: data['senderNickname'],
            senderUniqueId: data['senderUniqueId'],
          );

          // 이미 동일한 ID의 메시지가 있는지 확인
          final existingMessage = _messages[roomId]!.any((msg) => msg.id == messageId);
          if (!existingMessage) {
            _messages[roomId]!.add(newMessage);
            debugPrint('메시지가 상태에 추가됨: ${newMessage.content}');
            notifyListeners();
          } else {
            debugPrint('동일한 ID의 메시지가 이미 있음: $messageId');
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
          id: room['roomId'],
          name: room['name'],
          createdAt: DateTime.parse(room['createdAt']),
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
          id: responseData['data']['roomId'],
          name: responseData['data']['name'],
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
        final List<Message> loadedMessages = messagesData.map((message) {
          final messageId = message['messageId'];
          // 처리된 메시지 ID 기록
          _processedMessageIds.add(messageId);

          return Message(
            id: messageId,
            roomId: message['roomId'],
            sender: message['sender'],
            content: message['content'],
            timestamp: DateTime.parse(message['createdAt']),
            senderAnonymousId: message['senderAnonymousId'],
            senderNickname: message['senderNickname'],
            senderUniqueId: message['senderUniqueId'],
          );
        }).toList();

        _messages[roomId] = loadedMessages;
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

  // 메시지 전송
  Future<void> sendMessage(String content, String sender, int? senderAnonymousId, String? senderNickname, String? senderUniqueId) async {
    if (_currentRoomId == null) {
      debugPrint('오류: 현재 채팅방이 없습니다.');
      return;
    }

    try {
      final messageId = const Uuid().v4();
      final timestamp = DateTime.now();

      debugPrint('메시지 전송 시도 - 내용: $content, 방: $_currentRoomId');

      final messageData = {
        'messageId': messageId,
        'roomId': _currentRoomId,
        'sender': sender,
        'content': content,
        'senderAnonymousId': senderAnonymousId,
        'senderNickname': senderNickname,
        'senderUniqueId': senderUniqueId,
      };

      // 메시지 ID를 처리된 목록에 추가 (중복 방지)
      _processedMessageIds.add(messageId);

      // 소켓으로 메시지 전송
      debugPrint('소켓을 통해 메시지 전송 요청: $messageData');
      _socket?.emit('send_message', messageData);

      // 로컬 상태 업데이트 (즉각적인 UI 반영을 위해)
      final newMessage = Message(
        id: messageId,
        roomId: _currentRoomId!,
        sender: sender,
        content: content,
        timestamp: timestamp,
        senderAnonymousId: senderAnonymousId,
        senderNickname: senderNickname,
        senderUniqueId: senderUniqueId,
      );

      // 방이 없으면 초기화
      if (_messages[_currentRoomId] == null) {
        _messages[_currentRoomId!] = [];
      }

      // 이미 동일한 ID의 메시지가 있는지 확인
      final existingMessage = _messages[_currentRoomId]!.any((msg) => msg.id == messageId);
      if (!existingMessage) {
        _messages[_currentRoomId]!.add(newMessage);
        debugPrint('메시지가 로컬 상태에 추가됨');
        notifyListeners();
      } else {
        debugPrint('동일한 ID의 메시지가 이미 있음: $messageId');
      }
    } catch (error) {
      debugPrint('메시지 전송 중 오류 발생: $error');
      throw Exception('메시지 전송 중 오류 발생: $error');
    }
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