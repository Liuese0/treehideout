import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../ai/ai_detector_model.dart';

// AI 보안 로그 항목
class SecurityLogEntry {
  final String id;
  final DateTime timestamp;
  final String message;
  final ThreatDetectionResult result;
  final String userId;
  final String roomId;

  SecurityLogEntry({
    required this.id,
    required this.timestamp,
    required this.message,
    required this.result,
    required this.userId,
    required this.roomId,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'message': message,
      'result': result.toJson(),
      'userId': userId,
      'roomId': roomId,
    };
  }

  factory SecurityLogEntry.fromJson(Map<String, dynamic> json) {
    return SecurityLogEntry(
      id: json['id'],
      timestamp: DateTime.parse(json['timestamp']),
      message: json['message'],
      result: ThreatDetectionResult(
        isThreat: json['result']['isThreat'],
        confidenceScore: json['result']['confidenceScore'],
        threatType: json['result']['threatType'],
        detectedKeywords: List<String>.from(json['result']['detectedKeywords']),
        reason: json['result']['reason'],
        threatLevel: ThreatLevel.values.firstWhere(
              (e) => e.toString() == json['result']['threatLevel'],
          orElse: () => ThreatLevel.safe,
        ),
      ),
      userId: json['userId'],
      roomId: json['roomId'],
    );
  }
}

// AI 보안 설정
class AISecuritySettings {
  bool enabled;
  SecurityMode securityMode;
  double threatThreshold;
  bool blockHighRiskMessages;
  bool logAllMessages;
  bool showWarnings;
  bool autoBlock;
  int maxLogEntries;

  AISecuritySettings({
    this.enabled = true,
    this.securityMode = SecurityMode.basic,
    this.threatThreshold = 0.3,
    this.blockHighRiskMessages = true,
    this.logAllMessages = false,
    this.showWarnings = true,
    this.autoBlock = false,
    this.maxLogEntries = 1000,
  });

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'securityMode': securityMode.toString(),
      'threatThreshold': threatThreshold,
      'blockHighRiskMessages': blockHighRiskMessages,
      'logAllMessages': logAllMessages,
      'showWarnings': showWarnings,
      'autoBlock': autoBlock,
      'maxLogEntries': maxLogEntries,
    };
  }

  factory AISecuritySettings.fromJson(Map<String, dynamic> json) {
    return AISecuritySettings(
      enabled: json['enabled'] ?? true,
      securityMode: SecurityMode.values.firstWhere(
            (e) => e.toString() == json['securityMode'],
        orElse: () => SecurityMode.basic,
      ),
      threatThreshold: json['threatThreshold'] ?? 0.3,
      blockHighRiskMessages: json['blockHighRiskMessages'] ?? true,
      logAllMessages: json['logAllMessages'] ?? false,
      showWarnings: json['showWarnings'] ?? true,
      autoBlock: json['autoBlock'] ?? false,
      maxLogEntries: json['maxLogEntries'] ?? 1000,
    );
  }
}

// AI 보안 통계
class AISecurityStats {
  int totalMessagesScanned;
  int threatsDetected;
  int messagesBlocked;
  int falsePositives;
  Map<String, int> threatTypeCount;
  DateTime lastScan;

  AISecurityStats({
    this.totalMessagesScanned = 0,
    this.threatsDetected = 0,
    this.messagesBlocked = 0,
    this.falsePositives = 0,
    Map<String, int>? threatTypeCount,
    DateTime? lastScan,
  }) : threatTypeCount = threatTypeCount ?? {},
        lastScan = lastScan ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'totalMessagesScanned': totalMessagesScanned,
      'threatsDetected': threatsDetected,
      'messagesBlocked': messagesBlocked,
      'falsePositives': falsePositives,
      'threatTypeCount': threatTypeCount,
      'lastScan': lastScan.toIso8601String(),
    };
  }

  factory AISecurityStats.fromJson(Map<String, dynamic> json) {
    return AISecurityStats(
      totalMessagesScanned: json['totalMessagesScanned'] ?? 0,
      threatsDetected: json['threatsDetected'] ?? 0,
      messagesBlocked: json['messagesBlocked'] ?? 0,
      falsePositives: json['falsePositives'] ?? 0,
      threatTypeCount: Map<String, int>.from(json['threatTypeCount'] ?? {}),
      lastScan: DateTime.tryParse(json['lastScan'] ?? '') ?? DateTime.now(),
    );
  }
}

// AI 보안 서비스
class AISecurityService {
  static final AISecurityService _instance = AISecurityService._internal();
  factory AISecurityService() => _instance;
  AISecurityService._internal();

  // AI 모델
  final AIDetectorModel _aiModel = AIDetectorModel();

  // 설정 및 통계
  AISecuritySettings _settings = AISecuritySettings();
  AISecurityStats _stats = AISecurityStats();

  // 로그
  final List<SecurityLogEntry> _logs = [];

  // 상수
  static const String _settingsKey = 'ai_security_settings';
  static const String _statsKey = 'ai_security_stats';
  static const String _logsKey = 'ai_security_logs';

  // Getters
  AISecuritySettings get settings => _settings;
  AISecurityStats get stats => _stats;
  List<SecurityLogEntry> get logs => List.unmodifiable(_logs);

  // 초기화
  Future<bool> initialize() async {
    try {
      debugPrint('AI 보안 서비스 초기화 시작...');

      // AI 모델 초기화
      final modelInitialized = await _aiModel.initialize();
      if (!modelInitialized) {
        debugPrint('AI 모델 초기화 실패');
        return false;
      }

      // 설정 및 통계 로드
      await _loadSettings();
      await _loadStats();
      await _loadLogs();

      // AI 모델에 보안 모드 설정
      _aiModel.setSecurityMode(_settings.securityMode);

      debugPrint('AI 보안 서비스 초기화 완료');
      return true;
    } catch (e) {
      debugPrint('AI 보안 서비스 초기화 실패: $e');
      return false;
    }
  }

  // 메시지 검사 (메인 메서드)
  Future<ThreatDetectionResult> scanMessage(
      String message,
      String userId,
      String roomId,
      ) async {
    if (!_settings.enabled) {
      return ThreatDetectionResult(
        isThreat: false,
        confidenceScore: 0.0,
        threatType: 'safe',
        detectedKeywords: [],
        reason: 'AI 보안 검사 비활성화됨',
        threatLevel: ThreatLevel.safe,
      );
    }

    try {
      // 통계 업데이트
      _stats.totalMessagesScanned++;
      _stats.lastScan = DateTime.now();

      // AI 모델로 위협 탐지
      final result = await _aiModel.detectThreat(message);

      // 위협 감지 시 통계 업데이트
      if (result.isThreat) {
        _stats.threatsDetected++;
        _stats.threatTypeCount[result.threatType] =
            (_stats.threatTypeCount[result.threatType] ?? 0) + 1;

        // 고위험 메시지 차단 설정 확인
        if (_settings.blockHighRiskMessages &&
            result.confidenceScore >= _settings.threatThreshold) {
          _stats.messagesBlocked++;
        }
      }

      // 로그 기록
      if (_settings.logAllMessages || result.isThreat) {
        await _addLogEntry(SecurityLogEntry(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          timestamp: DateTime.now(),
          message: message,
          result: result,
          userId: userId,
          roomId: roomId,
        ));
      }

      // 통계 저장
      await _saveStats();

      return result;
    } catch (e) {
      debugPrint('메시지 검사 실패: $e');
      return ThreatDetectionResult(
        isThreat: false,
        confidenceScore: 0.0,
        threatType: 'error',
        detectedKeywords: [],
        reason: '검사 중 오류 발생: $e',
        threatLevel: ThreatLevel.safe,
      );
    }
  }

  // 설정 업데이트
  Future<void> updateSettings(AISecuritySettings settings) async {
    _settings = settings;
    _aiModel.setSecurityMode(settings.securityMode);
    await _saveSettings();
    debugPrint('AI 보안 설정 업데이트 완료');
  }

  // 통계 초기화
  Future<void> resetStats() async {
    _stats = AISecurityStats();
    await _saveStats();
    debugPrint('AI 보안 통계 초기화 완료');
  }

  // 로그 초기화
  Future<void> clearLogs() async {
    _logs.clear();
    await _saveLogs();
    debugPrint('AI 보안 로그 초기화 완료');
  }

  // 거짓 긍정 신고
  Future<void> reportFalsePositive(String logId) async {
    final logIndex = _logs.indexWhere((log) => log.id == logId);
    if (logIndex >= 0) {
      _stats.falsePositives++;
      await _saveStats();
      debugPrint('거짓 긍정 신고 완료: $logId');
    }
  }

  // 특정 기간 로그 조회
  List<SecurityLogEntry> getLogsByDateRange(DateTime start, DateTime end) {
    return _logs.where((log) =>
    log.timestamp.isAfter(start) && log.timestamp.isBefore(end)
    ).toList();
  }

  // 위협 유형별 로그 조회
  List<SecurityLogEntry> getLogsByThreatType(String threatType) {
    return _logs.where((log) => log.result.threatType == threatType).toList();
  }

  // 위협 레벨별 로그 조회
  List<SecurityLogEntry> getLogsByThreatLevel(ThreatLevel level) {
    return _logs.where((log) => log.result.threatLevel == level).toList();
  }

  // 보안 대시보드 데이터
  Map<String, dynamic> getDashboardData() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayLogs = getLogsByDateRange(today, now);

    return {
      'total_scans': _stats.totalMessagesScanned,
      'threats_detected': _stats.threatsDetected,
      'messages_blocked': _stats.messagesBlocked,
      'false_positives': _stats.falsePositives,
      'today_scans': todayLogs.length,
      'today_threats': todayLogs.where((log) => log.result.isThreat).length,
      'threat_types': _stats.threatTypeCount,
      'security_mode': _settings.securityMode.toString(),
      'last_scan': _stats.lastScan.toIso8601String(),
    };
  }

  // 설정 로드
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = prefs.getString(_settingsKey);
      if (settingsJson != null) {
        final settingsMap = json.decode(settingsJson);
        _settings = AISecuritySettings.fromJson(settingsMap);
      }
    } catch (e) {
      debugPrint('AI 보안 설정 로드 실패: $e');
    }
  }

  // 통계 로드
  Future<void> _loadStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final statsJson = prefs.getString(_statsKey);
      if (statsJson != null) {
        final statsMap = json.decode(statsJson);
        _stats = AISecurityStats.fromJson(statsMap);
      }
    } catch (e) {
      debugPrint('AI 보안 통계 로드 실패: $e');
    }
  }

  // 로그 로드
  Future<void> _loadLogs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final logsJson = prefs.getString(_logsKey);
      if (logsJson != null) {
        final logsList = json.decode(logsJson) as List;
        _logs.clear();
        _logs.addAll(logsList.map((log) => SecurityLogEntry.fromJson(log)));
      }
    } catch (e) {
      debugPrint('AI 보안 로그 로드 실패: $e');
    }
  }

  // 설정 저장
  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_settingsKey, json.encode(_settings.toJson()));
    } catch (e) {
      debugPrint('AI 보안 설정 저장 실패: $e');
    }
  }

  // 통계 저장
  Future<void> _saveStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_statsKey, json.encode(_stats.toJson()));
    } catch (e) {
      debugPrint('AI 보안 통계 저장 실패: $e');
    }
  }

  // 로그 저장
  Future<void> _saveLogs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final logsJson = json.encode(_logs.map((log) => log.toJson()).toList());
      await prefs.setString(_logsKey, logsJson);
    } catch (e) {
      debugPrint('AI 보안 로그 저장 실패: $e');
    }
  }

  // 로그 항목 추가
  Future<void> _addLogEntry(SecurityLogEntry entry) async {
    _logs.add(entry);

    // 최대 로그 개수 제한
    if (_logs.length > _settings.maxLogEntries) {
      _logs.removeAt(0);
    }

    await _saveLogs();
  }

  // 로그 내보내기
  String exportLogs({DateTime? startDate, DateTime? endDate}) {
    List<SecurityLogEntry> logsToExport = _logs;

    if (startDate != null || endDate != null) {
      logsToExport = _logs.where((log) {
        if (startDate != null && log.timestamp.isBefore(startDate)) return false;
        if (endDate != null && log.timestamp.isAfter(endDate)) return false;
        return true;
      }).toList();
    }

    final exportData = {
      'export_info': {
        'exported_at': DateTime.now().toIso8601String(),
        'total_logs': logsToExport.length,
        'start_date': startDate?.toIso8601String(),
        'end_date': endDate?.toIso8601String(),
      },
      'settings': _settings.toJson(),
      'stats': _stats.toJson(),
      'logs': logsToExport.map((log) => log.toJson()).toList(),
    };

    return json.encode(exportData);
  }
}