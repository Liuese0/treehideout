import 'package:flutter/material.dart';
import '../services/integrated_security_manager.dart';
import '../services/ai_security_service.dart';
import '../ai/ai_detector_model.dart';
import 'phishtank_settings_screen.dart';
import 'security_logs_screen.dart';

class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({Key? key}) : super(key: key);

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  final IntegratedSecurityManager _securityManager = IntegratedSecurityManager();

  bool _isLoading = true;
  AISecuritySettings? _currentSettings;
  Map<String, dynamic>? _securityStatus;
  Map<String, dynamic>? _dashboardData;

  @override
  void initState() {
    super.initState();
    _loadSecurityData();
  }

  Future<void> _loadSecurityData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await _securityManager.initialize();
      _currentSettings = _securityManager.aiSecurity.settings;
      _securityStatus = _securityManager.getSecurityStatus();
      _dashboardData = _securityManager.getDashboardData();
    } catch (e) {
      debugPrint('보안 데이터 로드 실패: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('보안 설정을 불러오는데 실패했습니다: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _updateSetting<T>(String settingName, T value) async {
    if (_currentSettings == null) return;

    try {
      switch (settingName) {
        case 'enabled':
          _currentSettings = AISecuritySettings(
            enabled: value as bool,
            securityMode: _currentSettings!.securityMode,
            threatThreshold: _currentSettings!.threatThreshold,
            blockHighRiskMessages: _currentSettings!.blockHighRiskMessages,
            logAllMessages: _currentSettings!.logAllMessages,
            showWarnings: _currentSettings!.showWarnings,
            autoBlock: _currentSettings!.autoBlock,
            maxLogEntries: _currentSettings!.maxLogEntries,
          );
          break;
        case 'securityMode':
          await _securityManager.updateSecuritySettings(securityMode: value as SecurityMode);
          break;
        case 'threatThreshold':
          await _securityManager.updateSecuritySettings(threatThreshold: value as double);
          break;
        case 'blockHighRiskMessages':
          await _securityManager.updateSecuritySettings(blockHighRiskMessages: value as bool);
          break;
        case 'showWarnings':
          await _securityManager.updateSecuritySettings(showWarnings: value as bool);
          break;
        case 'autoBlock':
          await _securityManager.updateSecuritySettings(autoBlock: value as bool);
          break;
        case 'logAllMessages':
          await _securityManager.updateSecuritySettings(logAllMessages: value as bool);
          break;
      }

      await _loadSecurityData();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('설정이 저장되었습니다')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('설정 저장 실패: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('보안 설정'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSecurityData,
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'emergency':
                  _enableEmergencyMode();
                  break;
                case 'normal':
                  _restoreNormalMode();
                  break;
                case 'diagnostics':
                  _runDiagnostics();
                  break;
                case 'export':
                  _exportSettings();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'emergency',
                child: Text('긴급 보안 모드'),
              ),
              const PopupMenuItem(
                value: 'normal',
                child: Text('일반 모드 복원'),
              ),
              const PopupMenuItem(
                value: 'diagnostics',
                child: Text('시스템 진단'),
              ),
              const PopupMenuItem(
                value: 'export',
                child: Text('설정 내보내기'),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _currentSettings == null
          ? const Center(child: Text('보안 설정을 불러올 수 없습니다'))
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSecurityOverview(),
            const SizedBox(height: 24),
            _buildMainSettings(),
            const SizedBox(height: 24),
            _buildAdvancedSettings(),
            const SizedBox(height: 24),
            _buildQuickActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildSecurityOverview() {
    final overview = _dashboardData?['overview'] ?? {};
    final securityLevel = overview['security_level'] ?? '알 수 없음';
    final activeProtections = List<String>.from(overview['active_protections'] ?? []);

    Color levelColor;
    switch (securityLevel) {
      case '높음':
        levelColor = Colors.green;
        break;
      case '보통':
        levelColor = Colors.orange;
        break;
      case '낮음':
        levelColor = Colors.red;
        break;
      default:
        levelColor = Colors.grey;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.security, color: levelColor),
                const SizedBox(width: 8),
                Text(
                  '보안 상태',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('보안 수준: '),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: levelColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: levelColor),
                  ),
                  child: Text(
                    securityLevel,
                    style: TextStyle(
                      color: levelColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '활성화된 보호 기능:',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: activeProtections.map((protection) => Chip(
                label: Text(protection, style: const TextStyle(fontSize: 12)),
                backgroundColor: Colors.blue.withOpacity(0.1),
              )).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainSettings() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '기본 보안 설정',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),

            // AI 보안 활성화
            SwitchListTile(
              title: const Text('AI 보안 검사'),
              subtitle: const Text('메시지를 AI로 분석하여 위협을 탐지합니다'),
              value: _currentSettings!.enabled,
              onChanged: (value) => _updateSetting('enabled', value),
            ),

            const Divider(),

            // 보안 모드 선택
            ListTile(
              title: const Text('보안 모드'),
              subtitle: Text(_getSecurityModeDescription(_currentSettings!.securityMode)),
              trailing: DropdownButton<SecurityMode>(
                value: _currentSettings!.securityMode,
                onChanged: _currentSettings!.enabled ? (SecurityMode? value) {
                  if (value != null) {
                    _updateSetting('securityMode', value);
                  }
                } : null,
                items: SecurityMode.values.map((mode) => DropdownMenuItem(
                  value: mode,
                  child: Text(_getSecurityModeText(mode)),
                )).toList(),
              ),
            ),

            const Divider(),

            // 위험 임계값
            ListTile(
              title: const Text('위험 임계값'),
              subtitle: Text('${(_currentSettings!.threatThreshold * 100).toInt()}% - 이 값 이상일 때 위험으로 판정'),
            ),
            Slider(
              value: _currentSettings!.threatThreshold,
              min: 0.1,
              max: 0.9,
              divisions: 8,
              label: '${(_currentSettings!.threatThreshold * 100).toInt()}%',
              onChanged: _currentSettings!.enabled ? (value) {
                _updateSetting('threatThreshold', value);
              } : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdvancedSettings() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '고급 설정',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),

            SwitchListTile(
              title: const Text('고위험 메시지 자동 차단'),
              subtitle: const Text('위험도가 높은 메시지를 자동으로 차단합니다'),
              value: _currentSettings!.blockHighRiskMessages,
              onChanged: _currentSettings!.enabled ? (value) => _updateSetting('blockHighRiskMessages', value) : null,
            ),

            SwitchListTile(
              title: const Text('위험 메시지 경고 표시'),
              subtitle: const Text('의심스러운 메시지에 경고를 표시합니다'),
              value: _currentSettings!.showWarnings,
              onChanged: _currentSettings!.enabled ? (value) => _updateSetting('showWarnings', value) : null,
            ),

            SwitchListTile(
              title: const Text('자동 차단'),
              subtitle: const Text('중간 위험도 메시지도 자동으로 차단합니다'),
              value: _currentSettings!.autoBlock,
              onChanged: _currentSettings!.enabled ? (value) => _updateSetting('autoBlock', value) : null,
            ),

            SwitchListTile(
              title: const Text('모든 메시지 로깅'),
              subtitle: const Text('안전한 메시지도 로그에 기록합니다'),
              value: _currentSettings!.logAllMessages,
              onChanged: _currentSettings!.enabled ? (value) => _updateSetting('logAllMessages', value) : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '빠른 액션',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.settings),
                    label: const Text('PhishTank 설정'),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const PhishTankSettingsScreen(),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.list),
                    label: const Text('보안 로그'),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SecurityLogsScreen(),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.warning, color: Colors.orange),
                    label: const Text('긴급 모드'),
                    onPressed: _enableEmergencyMode,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('일반 모드'),
                    onPressed: _restoreNormalMode,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _getSecurityModeText(SecurityMode mode) {
    switch (mode) {
      case SecurityMode.basic:
        return '기본 (로컬)';
      case SecurityMode.phishtank:
        return 'PhishTank';
      case SecurityMode.hybrid:
        return '하이브리드';
    }
  }

  String _getSecurityModeDescription(SecurityMode mode) {
    switch (mode) {
      case SecurityMode.basic:
        return '로컬 데이터셋을 사용한 기본 검사';
      case SecurityMode.phishtank:
        return 'PhishTank API를 사용한 온라인 검사';
      case SecurityMode.hybrid:
        return '기본 검사 + PhishTank API 조합';
    }
  }

  Future<void> _enableEmergencyMode() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('긴급 보안 모드'),
        content: const Text(
            '긴급 보안 모드를 활성화하면 모든 보안 기능이 최대로 설정됩니다. '
                '이는 채팅 경험에 영향을 줄 수 있습니다. 계속하시겠습니까?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('활성화'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _securityManager.enableEmergencyMode();
        await _loadSecurityData();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('긴급 보안 모드가 활성화되었습니다'),
            backgroundColor: Colors.orange,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('긴급 모드 활성화 실패: $e')),
        );
      }
    }
  }

  Future<void> _restoreNormalMode() async {
    try {
      await _securityManager.restoreNormalMode();
      await _loadSecurityData();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('일반 보안 모드로 복원되었습니다')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('일반 모드 복원 실패: $e')),
      );
    }
  }

  Future<void> _runDiagnostics() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('시스템 진단 중...'),
          ],
        ),
      ),
    );

    try {
      final diagnostics = await _securityManager.runSecurityDiagnostics();

      Navigator.of(context).pop(); // 로딩 다이얼로그 닫기

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('시스템 진단 결과'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDiagnosticItem('AI 모델 상태', diagnostics['ai_model_status']),
                _buildDiagnosticItem('PhishTank 상태', diagnostics['phishtank_status']),
                _buildDiagnosticItem('API 키 유효성', diagnostics['api_key_valid']),
                _buildDiagnosticItem('캐시 사용량', '${diagnostics['cache_usage']['usage_percentage']}%'),
                _buildDiagnosticItem('로그 개수', '${diagnostics['log_count']}개'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('확인'),
            ),
          ],
        ),
      );
    } catch (e) {
      Navigator.of(context).pop(); // 로딩 다이얼로그 닫기
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('진단 실패: $e')),
      );
    }
  }

  Widget _buildDiagnosticItem(String label, dynamic value) {
    Color statusColor = Colors.grey;
    String displayValue = value.toString();

    if (value == 'active' || value == 'online' || value == true) {
      statusColor = Colors.green;
      displayValue = '정상';
    } else if (value == 'disabled' || value == 'offline' || value == false) {
      statusColor = Colors.red;
      displayValue = value == 'disabled' ? '비활성화' : '오프라인';
    } else if (value == null) {
      statusColor = Colors.orange;
      displayValue = '설정되지 않음';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text('$label: '),
          Text(
            displayValue,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: statusColor,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportSettings() async {
    try {
      final settings = _securityManager.exportSecuritySettings();

      // 실제 구현에서는 파일로 저장하거나 공유 기능 사용
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('설정 내보내기'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('설정이 성공적으로 내보내졌습니다.'),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '설정 크기: ${settings.length} bytes',
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('확인'),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('설정 내보내기 실패: $e')),
      );
    }
  }
}