import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// PhishTank API 응답 모델
class PhishTankResponse {
  final bool isPhishing;
  final String url;
  final String? submissionTime;
  final String? verificationTime;
  final bool? verified;
  final bool? valid;

  PhishTankResponse({
    required this.isPhishing,
    required this.url,
    this.submissionTime,
    this.verificationTime,
    this.verified,
    this.valid,
  });

  factory PhishTankResponse.fromJson(Map<String, dynamic> json) {
    return PhishTankResponse(
      isPhishing: json['in_database'] ?? false,
      url: json['url'] ?? '',
      submissionTime: json['submission_time'],
      verificationTime: json['verification_time'],
      verified: json['verified'],
      valid: json['valid'],
    );
  }
}

// PhishTank 설정
class PhishTankSettings {
  bool enabled;
  String apiKey;
  bool useCache;
  int cacheExpiry; // 시간 (단위: 시간)
  bool logRequests;

  PhishTankSettings({
    this.enabled = true,
    this.apiKey = '',
    this.useCache = true,
    this.cacheExpiry = 24,
    this.logRequests = true,
  });

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'apiKey': apiKey,
      'useCache': useCache,
      'cacheExpiry': cacheExpiry,
      'logRequests': logRequests,
    };
  }

  factory PhishTankSettings.fromJson(Map<String, dynamic> json) {
    return PhishTankSettings(
      enabled: json['enabled'] ?? true,
      apiKey: json['apiKey'] ?? '',
      useCache: json['useCache'] ?? true,
      cacheExpiry: json['cacheExpiry'] ?? 24,
      logRequests: json['logRequests'] ?? true,
    );
  }
}

// PhishTank 통계
class PhishTankStats {
  int totalRequests;
  int phishingDetected;
  int cacheHits;
  int apiErrors;
  DateTime lastRequest;

  PhishTankStats({
    this.totalRequests = 0,
    this.phishingDetected = 0,
    this.cacheHits = 0,
    this.apiErrors = 0,
    DateTime? lastRequest,
  }) : lastRequest = lastRequest ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'totalRequests': totalRequests,
      'phishingDetected': phishingDetected,
      'cacheHits': cacheHits,
      'apiErrors': apiErrors,
      'lastRequest': lastRequest.toIso8601String(),
    };
  }

  factory PhishTankStats.fromJson(Map<String, dynamic> json) {
    return PhishTankStats(
      totalRequests: json['totalRequests'] ?? 0,
      phishingDetected: json['phishingDetected'] ?? 0,
      cacheHits: json['cacheHits'] ?? 0,
      apiErrors: json['apiErrors'] ?? 0,
      lastRequest: DateTime.tryParse(json['lastRequest'] ?? '') ?? DateTime.now(),
    );
  }
}

// PhishTank 서비스
class PhishTankService {
  static final PhishTankService _instance = PhishTankService._internal();
  factory PhishTankService() => _instance;
  PhishTankService._internal();

  // 설정
  PhishTankSettings _settings = PhishTankSettings();
  PhishTankStats _stats = PhishTankStats();

  // 캐시
  final Map<String, Map<String, dynamic>> _cache = {};

  // API 상수
  static const String _baseUrl = 'https://checkurl.phishtank.com/checkurl/';
  static const String _settingsKey = 'phishtank_settings';
  static const String _statsKey = 'phishtank_stats';

  // Getter
  PhishTankSettings get settings => _settings;
  PhishTankStats get stats => _stats;

  // 초기화
  Future<void> initialize() async {
    await _loadSettings();
    await _loadStats();
    debugPrint('PhishTank 서비스 초기화 완료');
  }

  // 설정 로드
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = prefs.getString(_settingsKey);
      if (settingsJson != null) {
        final settingsMap = json.decode(settingsJson);
        _settings = PhishTankSettings.fromJson(settingsMap);
      }
    } catch (e) {
      debugPrint('PhishTank 설정 로드 실패: $e');
    }
  }

  // 통계 로드
  Future<void> _loadStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final statsJson = prefs.getString(_statsKey);
      if (statsJson != null) {
        final statsMap = json.decode(statsJson);
        _stats = PhishTankStats.fromJson(statsMap);
      }
    } catch (e) {
      debugPrint('PhishTank 통계 로드 실패: $e');
    }
  }

  // 설정 저장
  Future<void> saveSettings(PhishTankSettings settings) async {
    try {
      _settings = settings;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_settingsKey, json.encode(settings.toJson()));
      debugPrint('PhishTank 설정 저장 완료');
    } catch (e) {
      debugPrint('PhishTank 설정 저장 실패: $e');
    }
  }

  // 통계 저장
  Future<void> _saveStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_statsKey, json.encode(_stats.toJson()));
    } catch (e) {
      debugPrint('PhishTank 통계 저장 실패: $e');
    }
  }

  // URL 검사 (메인 메서드)
  Future<bool> checkUrl(String url) async {
    if (!_settings.enabled) {
      debugPrint('PhishTank 검사 비활성화됨');
      return false;
    }

    if (url.isEmpty) return false;

    try {
      // 통계 업데이트
      _stats.totalRequests++;
      _stats.lastRequest = DateTime.now();

      // 캐시 확인
      if (_settings.useCache) {
        final cachedResult = _getCachedResult(url);
        if (cachedResult != null) {
          _stats.cacheHits++;
          await _saveStats();

          if (_settings.logRequests) {
            debugPrint('PhishTank 캐시 히트: $url');
          }

          return cachedResult;
        }
      }

      // API 호출
      final result = await _callPhishTankAPI(url);

      // 캐시에 저장
      if (_settings.useCache) {
        _setCachedResult(url, result);
      }

      // 통계 업데이트
      if (result) {
        _stats.phishingDetected++;
      }

      await _saveStats();

      if (_settings.logRequests) {
        debugPrint('PhishTank API 결과 - URL: $url, 피싱: $result');
      }

      return result;
    } catch (e) {
      _stats.apiErrors++;
      await _saveStats();
      debugPrint('PhishTank API 오류: $e');
      return false;
    }
  }

  // PhishTank API 호출
  Future<bool> _callPhishTankAPI(String url) async {
    try {
      final requestBody = {
        'url': url,
        'format': 'json',
      };

      // API 키가 있으면 추가
      if (_settings.apiKey.isNotEmpty) {
        requestBody['app_key'] = _settings.apiKey;
      }

      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'User-Agent': 'TreeHideout-AnonymousChat/1.0',
        },
        body: requestBody,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);

        // PhishTank API 응답 파싱
        if (responseData['results'] != null && responseData['results'].isNotEmpty) {
          final result = responseData['results'][0];
          return result['in_database'] == true;
        } else {
          // 데이터베이스에 없음 (안전)
          return false;
        }
      } else {
        debugPrint('PhishTank API 오류: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('PhishTank API 호출 실패: $e');
      return false;
    }
  }

  // 캐시에서 결과 조회
  bool? _getCachedResult(String url) {
    final cached = _cache[url];
    if (cached == null) return null;

    final expiry = DateTime.parse(cached['expiry']);
    if (DateTime.now().isAfter(expiry)) {
      _cache.remove(url);
      return null;
    }

    return cached['result'] as bool;
  }

  // 캐시에 결과 저장
  void _setCachedResult(String url, bool result) {
    final expiry = DateTime.now().add(Duration(hours: _settings.cacheExpiry));
    _cache[url] = {
      'result': result,
      'expiry': expiry.toIso8601String(),
    };

    // 캐시 크기 제한 (최대 1000개)
    if (_cache.length > 1000) {
      final oldestKey = _cache.keys.first;
      _cache.remove(oldestKey);
    }
  }

  // 캐시 초기화
  void clearCache() {
    _cache.clear();
    debugPrint('PhishTank 캐시 초기화 완료');
  }

  // 통계 초기화
  Future<void> resetStats() async {
    _stats = PhishTankStats();
    await _saveStats();
    debugPrint('PhishTank 통계 초기화 완료');
  }

  // API 키 유효성 검사
  Future<bool> validateApiKey(String apiKey) async {
    try {
      final testUrl = 'https://www.google.com';
      final requestBody = {
        'url': testUrl,
        'format': 'json',
        'app_key': apiKey,
      };

      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'User-Agent': 'TreeHideout-AnonymousChat/1.0',
        },
        body: requestBody,
      ).timeout(const Duration(seconds: 10));

      // API 키가 유효하면 200 상태 코드 반환
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('API 키 검증 실패: $e');
      return false;
    }
  }

  // 다중 URL 검사
  Future<Map<String, bool>> checkMultipleUrls(List<String> urls) async {
    final results = <String, bool>{};

    for (final url in urls) {
      results[url] = await checkUrl(url);
    }

    return results;
  }

  // 배치 URL 검사 (성능 최적화)
  Future<Map<String, bool>> checkUrlsBatch(List<String> urls) async {
    final results = <String, bool>{};
    final futures = <Future<void>>[];

    for (final url in urls) {
      futures.add(() async {
        results[url] = await checkUrl(url);
      }());
    }

    await Future.wait(futures);
    return results;
  }

  // URL 정규화
  String _normalizeUrl(String url) {
    String normalized = url.trim().toLowerCase();

    // 프로토콜 추가
    if (!normalized.startsWith('http://') && !normalized.startsWith('https://')) {
      normalized = 'http://$normalized';
    }

    // 마지막 슬래시 제거
    if (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }

    return normalized;
  }

  // 서비스 상태 확인
  Future<bool> checkServiceStatus() async {
    try {
      final response = await http.get(
        Uri.parse('https://www.phishtank.com/'),
      ).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('PhishTank 서비스 상태 확인 실패: $e');
      return false;
    }
  }

  // 로그 내보내기
  Map<String, dynamic> exportLogs() {
    return {
      'settings': _settings.toJson(),
      'stats': _stats.toJson(),
      'cache_size': _cache.length,
      'export_time': DateTime.now().toIso8601String(),
    };
  }

  // 설정 가져오기
  PhishTankSettings getSettings() {
    return _settings;
  }

  // 통계 가져오기
  PhishTankStats getStats() {
    return _stats;
  }

  // 캐시 정보
  Map<String, dynamic> getCacheInfo() {
    return {
      'size': _cache.length,
      'max_size': 1000,
      'usage_percentage': (_cache.length / 1000 * 100).toStringAsFixed(1),
    };
  }
}