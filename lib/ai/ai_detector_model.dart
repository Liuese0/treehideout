import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/phishtank_service.dart';

// AI 위협 탐지 결과
class ThreatDetectionResult {
  final bool isThreat;
  final double confidenceScore;
  final String threatType;
  final List<String> detectedKeywords;
  final String reason;
  final ThreatLevel threatLevel;

  ThreatDetectionResult({
    required this.isThreat,
    required this.confidenceScore,
    required this.threatType,
    required this.detectedKeywords,
    required this.reason,
    required this.threatLevel,
  });

  Map<String, dynamic> toJson() {
    return {
      'isThreat': isThreat,
      'confidenceScore': confidenceScore,
      'threatType': threatType,
      'detectedKeywords': detectedKeywords,
      'reason': reason,
      'threatLevel': threatLevel.toString(),
    };
  }
}

// 위협 수준
enum ThreatLevel {
  safe,      // 안전
  low,       // 낮음
  medium,    // 보통
  high,      // 높음
  critical   // 심각
}

// 보안 모드
enum SecurityMode {
  basic,     // 기본 datasets 사용
  phishtank, // PhishTank API 사용
  hybrid     // 둘 다 사용
}

// AI 위협 탐지 모델
class AIDetectorModel {
  static final AIDetectorModel _instance = AIDetectorModel._internal();
  factory AIDetectorModel() => _instance;
  AIDetectorModel._internal();

  // 데이터셋
  Map<String, dynamic>? _vocabulary;
  Map<String, dynamic>? _phishingKeywords;
  Map<String, dynamic>? _malwarePatterns;
  Map<String, dynamic>? _scamKeywords;

  // PhishTank 서비스
  final PhishTankService _phishTankService = PhishTankService();

  // 현재 보안 모드
  SecurityMode _securityMode = SecurityMode.basic;

  // 초기화 상태
  bool _isInitialized = false;

  SecurityMode get securityMode => _securityMode;

  // 보안 모드 설정
  void setSecurityMode(SecurityMode mode) {
    _securityMode = mode;
    debugPrint('보안 모드 변경: $_securityMode');
  }

  // 모델 초기화
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      debugPrint('AI 탐지 모델 초기화 시작...');

      // 데이터셋 로드
      await _loadDatasets();

      _isInitialized = true;
      debugPrint('AI 탐지 모델 초기화 완료');
      return true;
    } catch (e) {
      debugPrint('AI 탐지 모델 초기화 실패: $e');
      return false;
    }
  }

  // 데이터셋 로드
  Future<void> _loadDatasets() async {
    try {
      // 어휘 사전 로드
      final vocabularyString = await rootBundle.loadString('assets/datasets/vocabulary.json');
      _vocabulary = json.decode(vocabularyString);

      // 피싱 키워드 로드
      final phishingString = await rootBundle.loadString('assets/datasets/phishing_keywords.json');
      _phishingKeywords = json.decode(phishingString);

      // 멀웨어 패턴 로드
      final malwareString = await rootBundle.loadString('assets/datasets/malware_patterns.json');
      _malwarePatterns = json.decode(malwareString);

      // 사기 키워드 로드
      final scamString = await rootBundle.loadString('assets/datasets/scam_keywords.json');
      _scamKeywords = json.decode(scamString);

      debugPrint('모든 데이터셋 로드 완료');
    } catch (e) {
      debugPrint('데이터셋 로드 실패: $e');
      // 빈 데이터셋으로 초기화
      _vocabulary = {'vocabulary': [], 'word_to_index': {}};
      _phishingKeywords = {'high_risk_keywords': [], 'medium_risk_keywords': []};
      _malwarePatterns = {'malware_extensions': [], 'suspicious_domains': []};
      _scamKeywords = {'romance_scam_keywords': [], 'financial_emergency_scams': []};
    }
  }

  // 메시지 위협 탐지 (메인 메서드)
  Future<ThreatDetectionResult> detectThreat(String message) async {
    if (!_isInitialized) {
      final initSuccess = await initialize();
      if (!initSuccess) {
        return ThreatDetectionResult(
          isThreat: false,
          confidenceScore: 0.0,
          threatType: 'unknown',
          detectedKeywords: [],
          reason: '모델 초기화 실패',
          threatLevel: ThreatLevel.safe,
        );
      }
    }

    debugPrint('위협 탐지 시작: ${message.length > 50 ? message.substring(0, 50) + "..." : message}');

    switch (_securityMode) {
      case SecurityMode.basic:
        return await _detectWithBasicDatasets(message);
      case SecurityMode.phishtank:
        return await _detectWithPhishTank(message);
      case SecurityMode.hybrid:
        return await _detectWithHybrid(message);
    }
  }

  // 기본 데이터셋을 사용한 탐지
  Future<ThreatDetectionResult> _detectWithBasicDatasets(String message) async {
    final cleanMessage = message.toLowerCase().trim();

    List<String> detectedKeywords = [];
    double totalScore = 0.0;
    String threatType = 'safe';
    String reason = '';

    // 1. 피싱 키워드 검사
    final phishingResult = _checkPhishingKeywords(cleanMessage);
    detectedKeywords.addAll(phishingResult['keywords']);
    totalScore += phishingResult['score'];
    if (phishingResult['score'] > 0) {
      threatType = 'phishing';
      reason += '피싱 키워드 탐지. ';
    }

    // 2. 멀웨어 패턴 검사
    final malwareResult = _checkMalwarePatterns(cleanMessage);
    detectedKeywords.addAll(malwareResult['keywords']);
    totalScore += malwareResult['score'];
    if (malwareResult['score'] > 0) {
      threatType = 'malware';
      reason += '멀웨어 패턴 탐지. ';
    }

    // 3. 사기 키워드 검사
    final scamResult = _checkScamKeywords(cleanMessage);
    detectedKeywords.addAll(scamResult['keywords']);
    totalScore += scamResult['score'];
    if (scamResult['score'] > 0) {
      threatType = 'scam';
      reason += '사기 키워드 탐지. ';
    }

    // 4. URL 패턴 검사
    final urlResult = _checkSuspiciousUrls(cleanMessage);
    detectedKeywords.addAll(urlResult['keywords']);
    totalScore += urlResult['score'];
    if (urlResult['score'] > 0) {
      threatType = 'suspicious_url';
      reason += '의심스러운 URL 탐지. ';
    }

    // 5. 감정 조작 패턴 검사
    final emotionResult = _checkEmotionalManipulation(cleanMessage);
    detectedKeywords.addAll(emotionResult['keywords']);
    totalScore += emotionResult['score'];
    if (emotionResult['score'] > 0) {
      reason += '감정 조작 패턴 탐지. ';
    }

    // 점수 정규화 (0~1 사이)
    double confidenceScore = math.min(totalScore / 10.0, 1.0);

    // 위협 레벨 결정
    ThreatLevel threatLevel = _determineThreatLevel(confidenceScore);

    // 위협 여부 결정
    bool isThreat = confidenceScore >= 0.3;

    if (!isThreat) {
      reason = '안전한 메시지입니다.';
      threatType = 'safe';
    }

    return ThreatDetectionResult(
      isThreat: isThreat,
      confidenceScore: confidenceScore,
      threatType: threatType,
      detectedKeywords: detectedKeywords.toSet().toList(),
      reason: reason.isEmpty ? '안전한 메시지입니다.' : reason,
      threatLevel: threatLevel,
    );
  }

  // PhishTank를 사용한 탐지
  Future<ThreatDetectionResult> _detectWithPhishTank(String message) async {
    final cleanMessage = message.toLowerCase().trim();

    List<String> detectedKeywords = [];
    double totalScore = 0.0;
    String threatType = 'safe';
    String reason = '';

    // URL 추출 및 PhishTank 검사
    final urls = _extractUrls(message);
    for (final url in urls) {
      final isPhishing = await _phishTankService.checkUrl(url);
      if (isPhishing) {
        detectedKeywords.add(url);
        totalScore += 10.0; // 최고 위험도
        threatType = 'phishing_url';
        reason += 'PhishTank에서 확인된 피싱 URL 탐지. ';
      }
    }

    // 기본 키워드 검사도 수행 (보조적)
    final basicResult = await _detectWithBasicDatasets(message);
    if (basicResult.isThreat && totalScore == 0.0) {
      totalScore += basicResult.confidenceScore * 5.0; // 가중치 적용
      detectedKeywords.addAll(basicResult.detectedKeywords);
      threatType = basicResult.threatType;
      reason += basicResult.reason;
    }

    double confidenceScore = math.min(totalScore / 10.0, 1.0);
    ThreatLevel threatLevel = _determineThreatLevel(confidenceScore);
    bool isThreat = confidenceScore >= 0.3;

    if (!isThreat) {
      reason = 'PhishTank 검사 결과 안전한 메시지입니다.';
      threatType = 'safe';
    }

    return ThreatDetectionResult(
      isThreat: isThreat,
      confidenceScore: confidenceScore,
      threatType: threatType,
      detectedKeywords: detectedKeywords.toSet().toList(),
      reason: reason.isEmpty ? 'PhishTank 검사 결과 안전한 메시지입니다.' : reason,
      threatLevel: threatLevel,
    );
  }

  // 하이브리드 탐지 (기본 + PhishTank)
  Future<ThreatDetectionResult> _detectWithHybrid(String message) async {
    // 기본 데이터셋 탐지
    final basicResult = await _detectWithBasicDatasets(message);

    // PhishTank 탐지
    final phishTankResult = await _detectWithPhishTank(message);

    // 두 결과 중 더 높은 위험도를 선택
    if (phishTankResult.confidenceScore > basicResult.confidenceScore) {
      return ThreatDetectionResult(
        isThreat: phishTankResult.isThreat || basicResult.isThreat,
        confidenceScore: phishTankResult.confidenceScore,
        threatType: phishTankResult.threatType,
        detectedKeywords: [...phishTankResult.detectedKeywords, ...basicResult.detectedKeywords].toSet().toList(),
        reason: 'PhishTank + 기본 검사: ${phishTankResult.reason} ${basicResult.reason}',
        threatLevel: phishTankResult.threatLevel,
      );
    } else {
      return ThreatDetectionResult(
        isThreat: basicResult.isThreat || phishTankResult.isThreat,
        confidenceScore: basicResult.confidenceScore,
        threatType: basicResult.threatType,
        detectedKeywords: [...basicResult.detectedKeywords, ...phishTankResult.detectedKeywords].toSet().toList(),
        reason: '기본 + PhishTank 검사: ${basicResult.reason} ${phishTankResult.reason}',
        threatLevel: basicResult.threatLevel,
      );
    }
  }

  // 피싱 키워드 검사
  Map<String, dynamic> _checkPhishingKeywords(String message) {
    List<String> detectedKeywords = [];
    double score = 0.0;

    if (_phishingKeywords == null) return {'keywords': detectedKeywords, 'score': score};

    // 고위험 키워드 검사
    final highRiskKeywords = _phishingKeywords!['high_risk_keywords'] as List<dynamic>? ?? [];
    for (final keyword in highRiskKeywords) {
      if (message.contains(keyword.toString().toLowerCase())) {
        detectedKeywords.add(keyword.toString());
        score += 3.0; // 고위험은 3점
      }
    }

    // 중위험 키워드 검사
    final mediumRiskKeywords = _phishingKeywords!['medium_risk_keywords'] as List<dynamic>? ?? [];
    for (final keyword in mediumRiskKeywords) {
      if (message.contains(keyword.toString().toLowerCase())) {
        detectedKeywords.add(keyword.toString());
        score += 1.5; // 중위험은 1.5점
      }
    }

    // 금융 키워드 검사
    final financialKeywords = _phishingKeywords!['financial_keywords'] as List<dynamic>? ?? [];
    for (final keyword in financialKeywords) {
      if (message.contains(keyword.toString().toLowerCase())) {
        detectedKeywords.add(keyword.toString());
        score += 1.0; // 금융 키워드는 1점
      }
    }

    return {'keywords': detectedKeywords, 'score': score};
  }

  // 멀웨어 패턴 검사
  Map<String, dynamic> _checkMalwarePatterns(String message) {
    List<String> detectedKeywords = [];
    double score = 0.0;

    if (_malwarePatterns == null) return {'keywords': detectedKeywords, 'score': score};

    // 멀웨어 확장자 검사
    final malwareExtensions = _malwarePatterns!['malware_extensions'] as List<dynamic>? ?? [];
    for (final ext in malwareExtensions) {
      if (message.contains(ext.toString().toLowerCase())) {
        detectedKeywords.add(ext.toString());
        score += 2.5;
      }
    }

    // 의심스러운 도메인 검사
    final suspiciousDomains = _malwarePatterns!['suspicious_domains'] as List<dynamic>? ?? [];
    for (final domain in suspiciousDomains) {
      if (message.contains(domain.toString().toLowerCase())) {
        detectedKeywords.add(domain.toString());
        score += 2.0;
      }
    }

    // 명령어 인젝션 패턴 검사
    final commandPatterns = _malwarePatterns!['command_injection_patterns'] as List<dynamic>? ?? [];
    for (final pattern in commandPatterns) {
      if (message.contains(pattern.toString().toLowerCase())) {
        detectedKeywords.add(pattern.toString());
        score += 4.0; // 명령어 인젝션은 고위험
      }
    }

    // SQL 인젝션 패턴 검사
    final sqlPatterns = _malwarePatterns!['sql_injection_patterns'] as List<dynamic>? ?? [];
    for (final pattern in sqlPatterns) {
      if (message.contains(pattern.toString().toLowerCase())) {
        detectedKeywords.add(pattern.toString());
        score += 4.0; // SQL 인젝션은 고위험
      }
    }

    // XSS 패턴 검사
    final xssPatterns = _malwarePatterns!['xss_patterns'] as List<dynamic>? ?? [];
    for (final pattern in xssPatterns) {
      if (message.contains(pattern.toString().toLowerCase())) {
        detectedKeywords.add(pattern.toString());
        score += 3.5; // XSS는 고위험
      }
    }

    return {'keywords': detectedKeywords, 'score': score};
  }

  // 사기 키워드 검사
  Map<String, dynamic> _checkScamKeywords(String message) {
    List<String> detectedKeywords = [];
    double score = 0.0;

    if (_scamKeywords == null) return {'keywords': detectedKeywords, 'score': score};

    // 로맨스 사기 키워드
    final romanceScamKeywords = _scamKeywords!['romance_scam_keywords'] as List<dynamic>? ?? [];
    for (final keyword in romanceScamKeywords) {
      if (message.contains(keyword.toString().toLowerCase())) {
        detectedKeywords.add(keyword.toString());
        score += 2.0;
      }
    }

    // 금융 응급상황 사기
    final emergencyScamKeywords = _scamKeywords!['financial_emergency_scams'] as List<dynamic>? ?? [];
    for (final keyword in emergencyScamKeywords) {
      if (message.contains(keyword.toString().toLowerCase())) {
        detectedKeywords.add(keyword.toString());
        score += 2.5;
      }
    }

    // 복권 사기
    final lotteryScamKeywords = _scamKeywords!['lottery_prize_scams'] as List<dynamic>? ?? [];
    for (final keyword in lotteryScamKeywords) {
      if (message.contains(keyword.toString().toLowerCase())) {
        detectedKeywords.add(keyword.toString());
        score += 2.0;
      }
    }

    // 투자 사기
    final investmentScamKeywords = _scamKeywords!['investment_fraud_keywords'] as List<dynamic>? ?? [];
    for (final keyword in investmentScamKeywords) {
      if (message.contains(keyword.toString().toLowerCase())) {
        detectedKeywords.add(keyword.toString());
        score += 3.0;
      }
    }

    // 정부기관 사칭
    final govScamKeywords = _scamKeywords!['government_impersonation'] as List<dynamic>? ?? [];
    for (final keyword in govScamKeywords) {
      if (message.contains(keyword.toString().toLowerCase())) {
        detectedKeywords.add(keyword.toString());
        score += 3.5;
      }
    }

    return {'keywords': detectedKeywords, 'score': score};
  }

  // 의심스러운 URL 검사
  Map<String, dynamic> _checkSuspiciousUrls(String message) {
    List<String> detectedKeywords = [];
    double score = 0.0;

    if (_phishingKeywords == null) return {'keywords': detectedKeywords, 'score': score};

    final urlPatterns = _phishingKeywords!['url_patterns'] as List<dynamic>? ?? [];
    for (final pattern in urlPatterns) {
      if (message.contains(pattern.toString().toLowerCase())) {
        detectedKeywords.add(pattern.toString());
        score += 2.0;
      }
    }

    // URL 단축 서비스 패턴 검사
    final shortUrlPatterns = ['bit.ly', 'tinyurl', 't.co', 'goo.gl', 'ow.ly'];
    for (final pattern in shortUrlPatterns) {
      if (message.contains(pattern)) {
        detectedKeywords.add(pattern);
        score += 1.5; // 단축 URL은 중간 위험도
      }
    }

    return {'keywords': detectedKeywords, 'score': score};
  }

  // 감정 조작 패턴 검사
  Map<String, dynamic> _checkEmotionalManipulation(String message) {
    List<String> detectedKeywords = [];
    double score = 0.0;

    if (_phishingKeywords == null) return {'keywords': detectedKeywords, 'score': score};

    final socialEngineeringPhrases = _phishingKeywords!['social_engineering_phrases'] as List<dynamic>? ?? [];
    for (final phrase in socialEngineeringPhrases) {
      if (message.contains(phrase.toString().toLowerCase())) {
        detectedKeywords.add(phrase.toString());
        score += 1.5;
      }
    }

    // 긴급성을 강조하는 패턴
    final urgencyPatterns = ['즉시', '긴급', '지금', '빨리', 'urgent', 'immediately', 'now', 'quick'];
    for (final pattern in urgencyPatterns) {
      if (message.contains(pattern)) {
        score += 0.5;
      }
    }

    // 과도한 이모지 사용 (감정 조작)
    final emojiCount = '😀😃😄😁😆😅😂🤣😊😇🙂🙃😉😌😍🥰😘😗😙😚😋😛😝😜🤪🤨🧐🤓😎🤩🥳😏😒😞😔😟😕🙁☹️😣😖😫😩🥺😢😭😤😠😡🤬🤯😳🥵🥶😱😨😰😥😓🤗🤔🤭🤫🤥😶😐😑😬🙄😯😦😧😮😲🥱😴🤤😪😵🤐🥴🤢🤮🤧😷🤒🤕🤑🤠😈👿👹👺🤡💩👻💀☠️👽👾🤖🎃😺😸😹😻😼😽🙀😿😾'
        .split('')
        .where((char) => message.contains(char))
        .length;

    if (emojiCount > 5) {
      score += 0.5;
    }

    return {'keywords': detectedKeywords, 'score': score};
  }

  // URL 추출
  List<String> _extractUrls(String text) {
    final urlRegex = RegExp(
      r'https?://[^\s]+|www\.[^\s]+|[a-zA-Z0-9-]+\.[a-zA-Z]{2,}[^\s]*',
      caseSensitive: false,
    );

    return urlRegex.allMatches(text).map((match) => match.group(0)!).toList();
  }

  // 위협 레벨 결정
  ThreatLevel _determineThreatLevel(double score) {
    if (score >= 0.8) return ThreatLevel.critical;
    if (score >= 0.6) return ThreatLevel.high;
    if (score >= 0.4) return ThreatLevel.medium;
    if (score >= 0.2) return ThreatLevel.low;
    return ThreatLevel.safe;
  }

  // 위협 레벨을 색상으로 변환
  Color getThreatLevelColor(ThreatLevel level) {
    switch (level) {
      case ThreatLevel.safe:
        return Colors.green;
      case ThreatLevel.low:
        return Colors.yellow;
      case ThreatLevel.medium:
        return Colors.orange;
      case ThreatLevel.high:
        return Colors.red;
      case ThreatLevel.critical:
        return Colors.red.shade900;
    }
  }

  // 위협 레벨을 텍스트로 변환
  String getThreatLevelText(ThreatLevel level) {
    switch (level) {
      case ThreatLevel.safe:
        return '안전';
      case ThreatLevel.low:
        return '낮음';
      case ThreatLevel.medium:
        return '보통';
      case ThreatLevel.high:
        return '높음';
      case ThreatLevel.critical:
        return '심각';
    }
  }

  // 보안 모드를 텍스트로 변환
  String getSecurityModeText(SecurityMode mode) {
    switch (mode) {
      case SecurityMode.basic:
        return '기본 (로컬 데이터셋)';
      case SecurityMode.phishtank:
        return 'PhishTank API';
      case SecurityMode.hybrid:
        return '하이브리드 (기본 + PhishTank)';
    }
  }

  // 통계 정보 조회
  Map<String, dynamic> getModelStatistics() {
    return {
      'vocabulary_size': _vocabulary?['vocabulary']?.length ?? 0,
      'phishing_keywords': _phishingKeywords?['high_risk_keywords']?.length ?? 0,
      'malware_patterns': _malwarePatterns?['malware_extensions']?.length ?? 0,
      'scam_keywords': _scamKeywords?['romance_scam_keywords']?.length ?? 0,
      'security_mode': _securityMode.toString(),
      'is_initialized': _isInitialized,
    };
  }
}