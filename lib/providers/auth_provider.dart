import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:crypto/crypto.dart';
import 'dart:io';
import '../utils/constants.dart';

class AuthProvider with ChangeNotifier {
  String? _userId;
  String? _nickname;
  String? _tempId;
  int? _anonymousId;
  String? _uniqueIdentifier; // 고유 식별 번호
  bool _isAuthenticated = false;

  final _storage = const FlutterSecureStorage();
  final _deviceInfoPlugin = DeviceInfoPlugin();

  bool get isAuthenticated => _isAuthenticated;
  String? get userId => _userId;
  String? get nickname => _nickname;
  String? get tempId => _tempId;
  int? get anonymousId => _anonymousId;
  String? get uniqueIdentifier => _uniqueIdentifier;

  // 앱 시작 시 저장된 사용자 정보 확인
  Future<void> checkAuthentication() async {
    final userId = await _storage.read(key: 'userId');
    final nickname = await _storage.read(key: 'nickname');
    final tempId = await _storage.read(key: 'tempId');
    final anonymousIdStr = await _storage.read(key: 'anonymousId');

    // 디바이스 기반 고유 식별자 확인 또는 생성
    String? uniqueId = await _storage.read(key: 'uniqueIdentifier');
    if (uniqueId == null) {
      // 고유 식별자가 없으면 새로 생성하고 저장
      uniqueId = await _generateUniqueIdentifier();
      await _storage.write(key: 'uniqueIdentifier', value: uniqueId);
    }
    _uniqueIdentifier = uniqueId;

    if (userId != null && tempId != null) {
      _userId = userId;
      _nickname = nickname;
      _tempId = tempId;
      _anonymousId = anonymousIdStr != null ? int.parse(anonymousIdStr) : null;
      _isAuthenticated = true;
      notifyListeners();
    }
  }

  // 디바이스 정보를 기반으로 고유 식별자 생성
  Future<String> _generateUniqueIdentifier() async {
    String deviceData = "";

    try {
      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await _deviceInfoPlugin.androidInfo;
        deviceData = androidInfo.id + androidInfo.brand + androidInfo.model;
      } else if (Platform.isIOS) {
        IosDeviceInfo iosInfo = await _deviceInfoPlugin.iosInfo;
        deviceData = iosInfo.identifierForVendor ?? 'unknown';
      }

      // 디바이스 데이터를 해시하여 고유 식별자 생성 (4자리 알파벳 + 3자리 숫자 형식 유지)
      var bytes = utf8.encode(deviceData);
      var digest = sha256.convert(bytes);
      String hash = digest.toString();

      // 알파벳 부분 생성 (해시의 첫 부분에서 4개 추출)
      String alphabetPart = '';
      const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ'; // 혼동되기 쉬운 I, O 제외
      for (int i = 0; i < 4; i++) {
        int charCode = hash.codeUnitAt(i % hash.length);
        alphabetPart += alphabet[charCode % alphabet.length];
      }

      // 숫자 부분 생성 (해시의 나머지 부분에서 숫자 추출 - 100~999 범위)
      int numericValue = int.parse(hash.substring(hash.length - 6, hash.length - 3), radix: 16);
      int normalizedNumber = 100 + (numericValue % 900); // 100-999 범위 보장

      return '$alphabetPart$normalizedNumber';
    } catch (e) {
      // 디바이스 정보를 얻는 데 실패한 경우 랜덤 식별자 생성
      const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
      String randomId = '';

      // 4자리 알파벳 생성
      for (int i = 0; i < 4; i++) {
        randomId += alphabet[DateTime.now().millisecondsSinceEpoch % alphabet.length];
      }

      // 3자리 숫자 생성 (100-999)
      randomId += (100 + DateTime.now().millisecondsSinceEpoch % 900).toString();

      return randomId;
    }
  }

  // 익명 사용자 등록
  Future<void> createAnonymousUser(String nickname) async {
    final url = Uri.parse('$apiBaseUrl/api/users');

    try {
      // 기존에 저장된 고유 식별자 가져오기 또는 생성
      String uniqueId = _uniqueIdentifier ?? await _generateUniqueIdentifier();

      // 서버에 요청 보낼 때 고유 식별자를 포함
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'nickname': nickname,
          'uniqueIdentifier': uniqueId, // 서버에 고유 식별자 전달
        }),
      );

      if (response.statusCode == 201) {
        final responseData = json.decode(response.body);

        _userId = responseData['data']['userId'];
        _nickname = responseData['data']['nickname'];
        _tempId = responseData['data']['tempId'];
        _anonymousId = responseData['data']['anonymousId'];

        // 서버에서 반환한 고유 식별자 대신 로컬에서 생성한 식별자 사용
        _uniqueIdentifier = uniqueId;

        _isAuthenticated = true;

        // 사용자 정보를 안전하게 저장
        await _storage.write(key: 'userId', value: _userId);
        await _storage.write(key: 'nickname', value: _nickname);
        await _storage.write(key: 'tempId', value: _tempId);
        await _storage.write(key: 'anonymousId', value: _anonymousId.toString());
        await _storage.write(key: 'uniqueIdentifier', value: uniqueId);

        notifyListeners();
      } else {
        throw Exception('사용자 등록 실패: ${response.statusCode}');
      }
    } catch (error) {
      throw Exception('사용자 등록 중 오류 발생: $error');
    }
  }

  // 로그아웃
  Future<void> logout() async {
    // 고유 식별자는 유지하고 나머지 정보만 삭제
    String? uniqueId = await _storage.read(key: 'uniqueIdentifier');
    await _storage.deleteAll();

    // 고유 식별자 다시 저장
    if (uniqueId != null) {
      await _storage.write(key: 'uniqueIdentifier', value: uniqueId);
      _uniqueIdentifier = uniqueId;
    }

    _userId = null;
    _nickname = null;
    _tempId = null;
    _anonymousId = null;
    _isAuthenticated = false;

    notifyListeners();
  }

  // 닉네임 변경 (익명성 유지하면서 닉네임만 변경)
  Future<void> changeNickname(String newNickname) async {
    // 실제 구현에서는 서버에 요청을 보내 닉네임을 업데이트해야 함
    _nickname = newNickname;
    await _storage.write(key: 'nickname', value: _nickname);
    notifyListeners();
  }
}