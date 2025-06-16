import 'dart:convert';
import 'package:flutter/material.dart';
import 'ai_security_service.dart';
import 'phishtank_service.dart';
import '../ai/ai_detector_model.dart';

// 통합 보안 결과
class IntegratedSecurityResult {
  final bool isBlocked;
  final bool hasWarning;
  final ThreatDetectionResult aiResult;
  final String action;
  final String message;
  final Color statusColor;

  IntegratedSecurityResult({
    required this.isBlocked,
    required this.hasWarning,
    required this.aiResult,
    required this.action,
    required this.message,
    required this.statusColor,
  });
}

// 보안 액션 유형
enum SecurityAction {
  allow,      // 허용
  warn,       // 경고
  block,      // 차단
  quarantine  // 격리
}

// 통합 보안 관리자
class IntegratedSecurityManager {
  static final IntegratedSecurityManager _instance = IntegratedSecurityManager._internal();
  factory IntegratedSecurityManager() => _instance;
  IntegratedSecurityManager._internal();

  // 서비스들
  final AISecurityService _aiSecurity = AISecurityService();
  final PhishTankService _phishTank = PhishTankService();

  // 초기화 상태
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  // getter 추가 - 다른 클래스에서 접근할 수 있도록
  AISecurityService get aiSecurityService => _aiSecurity;
  AISecurityService get aiSecurity => _aiSecurity;
  PhishTankService get phishTankService => _phishTank;
  PhishTankService get phishTank => _phishTank;

  // 통합 보안 관리자 초기화
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      debugPrint('통합 보안 관리자 초기화 시작...');

      // AI 보안 서비스 초기화
      final aiInitialized = await _aiSecurity.initialize();
      if (!aiInitialized) {
        debugPrint('AI 보안 서비스 초기화 실패');
        return false;
      }

      // PhishTank 서비스 초기화
      await _phishTank.initialize();

      _isInitialized = true;
      debugPrint('통합 보안 관리자 초기화 완료');
      return true;
    } catch (e) {
      debugPrint('통합 보안 관리자 초기화 실패: $e');
      return false;
    }
  }

  // 메시지 보안 검사 (메인 메서드)
  Future<IntegratedSecurityResult> checkMessageSecurity(
      String message,
      String userId,
      String roomId,
      ) async {
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) {
        return IntegratedSecurityResult(
          isBlocked: false,
          hasWarning: false,
          aiResult: ThreatDetectionResult(
            isThreat: false,
            confidenceScore: 0.0,
            threatType: 'error',
            detectedKeywords: [],
            reason: '보안 시스템 초기화 실패',
            threatLevel: ThreatLevel.safe,
          ),
          action: '초기화 실패',
          message: '보안 시스템을 초기화할 수 없습니다.',
          statusColor: Colors.red,
        );
      }
    }

    try {
      // AI 보안 검사 수행
      final aiResult = await _aiSecurity.scanMessage(message, userId, roomId);

      // 보안 액션 결정
      final action = _determineSecurityAction(aiResult);

      // 결과 생성
      return _buildSecurityResult(aiResult, action);
    } catch (e) {
      debugPrint('통합 보안 검사 실패: $e');
      return IntegratedSecurityResult(
        isBlocked: false,
        hasWarning: true,
        aiResult: ThreatDetectionResult(
          isThreat: false,
          confidenceScore: 0.0,
          threatType: 'error',
          detectedKeywords: [],
          reason: '보안 검사 중 오류 발생: $e',
          threatLevel: ThreatLevel.safe,
        ),
        action: '오류',
        message: '보안 검사 중 오류가 발생했습니다.',
        statusColor: Colors.orange,
      );
    }
  }

  // 보안 액션 결정
  SecurityAction _determineSecurityAction(ThreatDetectionResult result) {
    final settings = _aiSecurity.settings;

    if (!result.isThreat) {
      return SecurityAction.allow;
    }

    // 위험도 기반 액션 결정
    switch (result.threatLevel) {
      case ThreatLevel.critical:
        return SecurityAction.block;
      case ThreatLevel.high:
        return settings.blockHighRiskMessages ? SecurityAction.block : SecurityAction.warn;
      case ThreatLevel.medium:
        return settings.autoBlock ? SecurityAction.quarantine : SecurityAction.warn;
      case ThreatLevel.low:
        return settings.showWarnings ? SecurityAction.warn : SecurityAction.allow;
      case ThreatLevel.safe:
        return SecurityAction.allow;
    }
  }

  // 보안 결과 생성
  IntegratedSecurityResult _buildSecurityResult(
      ThreatDetectionResult aiResult,
      SecurityAction action,
      ) {
    switch (action) {
      case SecurityAction.allow:
        return IntegratedSecurityResult(
          isBlocked: false,
          hasWarning: false,
          aiResult: aiResult,
          action: '허용',
          message: '안전한 메시지입니다.',
          statusColor: Colors.green,
        );

      case SecurityAction.warn:
        return IntegratedSecurityResult(
          isBlocked: false,
          hasWarning: true,
          aiResult: aiResult,
          action: '경고',
          message: '주의가 필요한 내용이 포함되어 있습니다.',
          statusColor: Colors.orange,
        );

      case SecurityAction.block:
        return IntegratedSecurityResult(
          isBlocked: true,
          hasWarning: true,
          aiResult: aiResult,
          action: '차단',
          message: '위험한 내용으로 인해 메시지가 차단되었습니다.',
          statusColor: Colors.red,
        );

      case SecurityAction.quarantine:
        return IntegratedSecurityResult(
          isBlocked: true,
          hasWarning: true,
          aiResult: aiResult,
          action: '격리',
          message: '의심스러운 내용으로 인해 메시지가 격리되었습니다.',
          statusColor: Colors.purple,
        );
    }
  }

  // 보안 설정 업데이트
  Future<void> updateSecuritySettings({
    SecurityMode? securityMode,
    double? threatThreshold,
    bool? blockHighRiskMessages,
    bool? showWarnings,
    bool? autoBlock,
    bool? logAllMessages,
  }) async {
    final currentSettings = _aiSecurity.settings;

    final newSettings = AISecuritySettings(
      enabled: currentSettings.enabled,
      securityMode: securityMode ?? currentSettings.securityMode,
      threatThreshold: threatThreshold ?? currentSettings.threatThreshold,
      blockHighRiskMessages: blockHighRiskMessages ?? currentSettings.blockHighRiskMessages,
      logAllMessages: logAllMessages ?? currentSettings.logAllMessages,
      showWarnings: showWarnings ?? currentSettings.showWarnings,
      autoBlock: autoBlock ?? currentSettings.autoBlock,
      maxLogEntries: currentSettings.maxLogEntries,
    );

    await _aiSecurity.updateSettings(newSettings);
    debugPrint('통합 보안 설정 업데이트 완료');
  }

  // PhishTank 설정 업데이트
  Future<void> updatePhishTankSettings({
    bool? enabled,
    String? apiKey,
    bool? useCache,
    int? cacheExpiry,
    bool? logRequests,
  }) async {
    final currentSettings = _phishTank.settings;

    final newSettings = PhishTankSettings(
      enabled: enabled ?? currentSettings.enabled,
      apiKey: apiKey ?? currentSettings.apiKey,
      useCache: useCache ?? currentSettings.useCache,
      cacheExpiry: cacheExpiry ?? currentSettings.cacheExpiry,
      logRequests: logRequests ?? currentSettings.logRequests,
    );

    await _phishTank.saveSettings(newSettings);
    debugPrint('PhishTank 설정 업데이트 완료');
  }

  // 보안 상태 조회
  Map<String, dynamic> getSecurityStatus() {
    final aiSettings = _aiSecurity.settings;
    final aiStats = _aiSecurity.stats;
    final phishTankSettings = _phishTank.settings;
    final phishTankStats = _phishTank.stats;

    return {
      'is_initialized': _isInitialized,
      'ai_security': {
        'enabled': aiSettings.enabled,
        'security_mode': aiSettings.securityMode.toString(),
        'threat_threshold': aiSettings.threatThreshold,
        'total_scans': aiStats.totalMessagesScanned,
        'threats_detected': aiStats.threatsDetected,
        'messages_blocked': aiStats.messagesBlocked,
      },
      'phishtank': {
        'enabled': phishTankSettings.enabled,
        'has_api_key': phishTankSettings.apiKey.isNotEmpty,
        'use_cache': phishTankSettings.useCache,
        'total_requests': phishTankStats.totalRequests,
        'phishing_detected': phishTankStats.phishingDetected,
        'cache_hits': phishTankStats.cacheHits,
      },
    };
  }

  // 보안 통계 조회
  Map<String, dynamic> getSecurityStatistics() {
    final aiStats = _aiSecurity.stats;
    final phishTankStats = _phishTank.stats;

    return {
      'ai_security': aiStats.toJson(),
      'phishtank': phishTankStats.toJson(),
      'combined_stats': {
        'total_checks': aiStats.totalMessagesScanned + phishTankStats.totalRequests,
        'total_threats': aiStats.threatsDetected + phishTankStats.phishingDetected,
        'last_activity': aiStats.lastScan.isAfter(phishTankStats.lastRequest)
            ? aiStats.lastScan.toIso8601String()
            : phishTankStats.lastRequest.toIso8601String(),
      },
    };
  }

  // 보안 로그 조회
  List<SecurityLogEntry> getSecurityLogs({
    DateTime? startDate,
    DateTime? endDate,
    ThreatLevel? threatLevel,
    String? threatType,
  }) {
    List<SecurityLogEntry> logs = _aiSecurity.logs;

    if (startDate != null) {
      logs = logs.where((log) => log.timestamp.isAfter(startDate)).toList();
    }

    if (endDate != null) {
      logs = logs.where((log) => log.timestamp.isBefore(endDate)).toList();
    }

    if (threatLevel != null) {
      logs = logs.where((log) => log.result.threatLevel == threatLevel).toList();
    }

    if (threatType != null) {
      logs = logs.where((log) => log.result.threatType == threatType).toList();
    }

    return logs;
  }

  // 보안 대시보드 데이터
  Map<String, dynamic> getDashboardData() {
    final aiDashboard = _aiSecurity.getDashboardData();
    final phishTankInfo = _phishTank.getCacheInfo();

    return {
      'overview': {
        'security_level': _getOverallSecurityLevel(),
        'active_protections': _getActiveProtections(),
        'last_update': DateTime.now().toIso8601String(),
      },
      'ai_security': aiDashboard,
      'phishtank': {
        'enabled': _phishTank.settings.enabled,
        'cache_info': phishTankInfo,
        'stats': _phishTank.stats.toJson(),
      },
      'recommendations': _getSecurityRecommendations(),
    };
  }

  // 전체 보안 수준 평가
  String _getOverallSecurityLevel() {
    final aiSettings = _aiSecurity.settings;
    final phishTankSettings = _phishTank.settings;

    int securityScore = 0;

    // AI 보안 활성화
    if (aiSettings.enabled) securityScore += 30;

    // PhishTank 활성화
    if (phishTankSettings.enabled) securityScore += 20;

    // 하이브리드 모드
    if (aiSettings.securityMode == SecurityMode.hybrid) securityScore += 20;

    // 고위험 메시지 차단
    if (aiSettings.blockHighRiskMessages) securityScore += 15;

    // 로깅 활성화
    if (aiSettings.logAllMessages) securityScore += 10;

    // API 키 설정
    if (phishTankSettings.apiKey.isNotEmpty) securityScore += 5;

    if (securityScore >= 80) return '높음';
    if (securityScore >= 60) return '보통';
    if (securityScore >= 40) return '낮음';
    return '매우 낮음';
  }

  // 활성화된 보호 기능 목록
  List<String> _getActiveProtections() {
    final protections = <String>[];
    final aiSettings = _aiSecurity.settings;
    final phishTankSettings = _phishTank.settings;

    if (aiSettings.enabled) {
      protections.add('AI 위협 탐지');

      switch (aiSettings.securityMode) {
        case SecurityMode.basic:
          protections.add('기본 데이터셋 검사');
          break;
        case SecurityMode.phishtank:
          protections.add('PhishTank API 검사');
          break;
        case SecurityMode.hybrid:
          protections.add('하이브리드 검사');
          break;
      }
    }

    if (phishTankSettings.enabled) {
      protections.add('PhishTank 피싱 탐지');
    }

    if (aiSettings.blockHighRiskMessages) {
      protections.add('고위험 메시지 자동 차단');
    }

    if (aiSettings.showWarnings) {
      protections.add('위험 메시지 경고');
    }

    if (aiSettings.autoBlock) {
      protections.add('자동 차단');
    }

    return protections;
  }

  // 보안 권장사항
  List<String> _getSecurityRecommendations() {
    final recommendations = <String>[];
    final aiSettings = _aiSecurity.settings;
    final phishTankSettings = _phishTank.settings;

    if (!aiSettings.enabled) {
      recommendations.add('AI 보안 검사를 활성화하세요');
    }

    if (!phishTankSettings.enabled) {
      recommendations.add('PhishTank 피싱 탐지를 활성화하세요');
    }

    if (phishTankSettings.apiKey.isEmpty) {
      recommendations.add('PhishTank API 키를 설정하면 더 정확한 탐지가 가능합니다');
    }

    if (aiSettings.securityMode == SecurityMode.basic) {
      recommendations.add('하이브리드 모드를 사용하여 보안을 강화하세요');
    }

    if (!aiSettings.blockHighRiskMessages) {
      recommendations.add('고위험 메시지 자동 차단을 활성화하세요');
    }

    if (!aiSettings.logAllMessages) {
      recommendations.add('모든 메시지 로깅을 활성화하여 보안 분석을 개선하세요');
    }

    if (aiSettings.threatThreshold > 0.5) {
      recommendations.add('위험 임계값을 낮춰 더 민감한 탐지를 사용하세요');
    }

    return recommendations;
  }

  // 메시지 화이트리스트 확인
  bool isWhitelisted(String message, String userId) {
    // 시스템 메시지나 관리자 메시지는 화이트리스트 처리
    final systemKeywords = ['시스템', 'system', 'admin', '관리자'];

    for (final keyword in systemKeywords) {
      if (message.toLowerCase().contains(keyword.toLowerCase())) {
        return true;
      }
    }

    return false;
  }

  // 사용자 신뢰도 확인
  double getUserTrustScore(String userId) {
    // 사용자별 신뢰도 점수 (실제 구현에서는 데이터베이스에서 조회)
    // 기본값: 0.5 (중간 신뢰도)
    return 0.5;
  }

  // 긴급 보안 모드 활성화
  Future<void> enableEmergencyMode() async {
    await updateSecuritySettings(
      securityMode: SecurityMode.hybrid,
      threatThreshold: 0.2, // 매우 민감하게
      blockHighRiskMessages: true,
      showWarnings: true,
      autoBlock: true,
      logAllMessages: true,
    );

    debugPrint('긴급 보안 모드 활성화');
  }

  // 보안 모드 복원
  Future<void> restoreNormalMode() async {
    await updateSecuritySettings(
      securityMode: SecurityMode.basic,
      threatThreshold: 0.3,
      blockHighRiskMessages: true,
      showWarnings: true,
      autoBlock: false,
      logAllMessages: false,
    );

    debugPrint('일반 보안 모드 복원');
  }

  // 보안 시스템 상태 진단
  Future<Map<String, dynamic>> runSecurityDiagnostics() async {
    final diagnostics = <String, dynamic>{};

    // AI 모델 상태 확인
    diagnostics['ai_model_status'] = _aiSecurity.settings.enabled ? 'active' : 'disabled';

    // PhishTank 서비스 상태 확인
    final phishTankStatus = await _phishTank.checkServiceStatus();
    diagnostics['phishtank_status'] = phishTankStatus ? 'online' : 'offline';

    // API 키 유효성 확인
    if (_phishTank.settings.apiKey.isNotEmpty) {
      final apiKeyValid = await _phishTank.validateApiKey(_phishTank.settings.apiKey);
      diagnostics['api_key_valid'] = apiKeyValid;
    } else {
      diagnostics['api_key_valid'] = null;
    }

    // 메모리 사용량 확인
    diagnostics['cache_usage'] = _phishTank.getCacheInfo();
    diagnostics['log_count'] = _aiSecurity.logs.length;

    // 최근 활동 확인
    diagnostics['recent_activity'] = {
      'ai_last_scan': _aiSecurity.stats.lastScan.toIso8601String(),
      'phishtank_last_request': _phishTank.stats.lastRequest.toIso8601String(),
    };

    return diagnostics;
  }

  // 보안 설정 내보내기
  String exportSecuritySettings() {
    final exportData = {
      'export_info': {
        'exported_at': DateTime.now().toIso8601String(),
        'version': '1.0',
      },
      'ai_security_settings': _aiSecurity.settings.toJson(),
      'phishtank_settings': _phishTank.settings.toJson(),
      'security_status': getSecurityStatus(),
    };

    return json.encode(exportData);
  }

  // 보안 설정 가져오기
  Future<bool> importSecuritySettings(String settingsJson) async {
    try {
      final data = json.decode(settingsJson);

      if (data['ai_security_settings'] != null) {
        final aiSettings = AISecuritySettings.fromJson(data['ai_security_settings']);
        await _aiSecurity.updateSettings(aiSettings);
      }

      if (data['phishtank_settings'] != null) {
        final phishTankSettings = PhishTankSettings.fromJson(data['phishtank_settings']);
        await _phishTank.saveSettings(phishTankSettings);
      }

      debugPrint('보안 설정 가져오기 완료');
      return true;
    } catch (e) {
      debugPrint('보안 설정 가져오기 실패: $e');
      return false;
    }
  }

  // 리소스 정리
  void dispose() {
    debugPrint('통합 보안 관리자 리소스 정리');
  }
}