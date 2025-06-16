import 'package:flutter/material.dart';
import '../services/phishtank_service.dart';

class PhishTankSettingsScreen extends StatefulWidget {
  const PhishTankSettingsScreen({Key? key}) : super(key: key);

  @override
  State<PhishTankSettingsScreen> createState() => _PhishTankSettingsScreenState();
}

class _PhishTankSettingsScreenState extends State<PhishTankSettingsScreen> {
  final PhishTankService _phishTankService = PhishTankService();
  final TextEditingController _apiKeyController = TextEditingController();

  bool _isLoading = true;
  bool _isValidatingApiKey = false;
  PhishTankSettings? _currentSettings;
  PhishTankStats? _currentStats;
  Map<String, dynamic>? _cacheInfo;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await _phishTankService.initialize();
      _currentSettings = _phishTankService.getSettings();
      _currentStats = _phishTankService.getStats();
      _cacheInfo = _phishTankService.getCacheInfo();
      _apiKeyController.text = _currentSettings!.apiKey;
    } catch (e) {
      debugPrint('PhishTank 설정 로드 실패: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('설정을 불러오는데 실패했습니다: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    if (_currentSettings == null) return;

    try {
      final newSettings = PhishTankSettings(
        enabled: _currentSettings!.enabled,
        apiKey: _apiKeyController.text.trim(),
        useCache: _currentSettings!.useCache,
        cacheExpiry: _currentSettings!.cacheExpiry,
        logRequests: _currentSettings!.logRequests,
      );

      await _phishTankService.saveSettings(newSettings);
      await _loadSettings();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('설정이 저장되었습니다')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('설정 저장 실패: $e')),
      );
    }
  }

  Future<void> _validateApiKey() async {
    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('API 키를 입력해주세요')),
      );
      return;
    }

    setState(() {
      _isValidatingApiKey = true;
    });

    try {
      final isValid = await _phishTankService.validateApiKey(apiKey);

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(isValid ? '유효한 API 키' : '무효한 API 키'),
          content: Text(
            isValid
                ? 'API 키가 정상적으로 작동합니다.'
                : 'API 키가 유효하지 않거나 PhishTank 서비스에 문제가 있습니다.',
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
        SnackBar(content: Text('API 키 검증 실패: $e')),
      );
    } finally {
      setState(() {
        _isValidatingApiKey = false;
      });
    }
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('캐시 초기화'),
        content: const Text('모든 캐시된 데이터를 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _phishTankService.clearCache();
      await _loadSettings();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('캐시가 초기화되었습니다')),
      );
    }
  }

  Future<void> _resetStats() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('통계 초기화'),
        content: const Text('모든 통계 데이터를 초기화하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('초기화'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _phishTankService.resetStats();
      await _loadSettings();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('통계가 초기화되었습니다')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PhishTank 설정'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveSettings,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _currentSettings == null
          ? const Center(child: Text('설정을 불러올 수 없습니다'))
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildBasicSettings(),
            const SizedBox(height: 24),
            _buildApiKeySettings(),
            const SizedBox(height: 24),
            _buildCacheSettings(),
            const SizedBox(height: 24),
            _buildStatsCard(),
            const SizedBox(height: 24),
            _buildAdvancedSettings(),
          ],
        ),
      ),
    );
  }

  Widget _buildBasicSettings() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PhishTank 기본 설정',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),

            SwitchListTile(
              title: const Text('PhishTank 서비스 활성화'),
              subtitle: const Text('URL 피싱 탐지 서비스를 사용합니다'),
              value: _currentSettings!.enabled,
              onChanged: (value) {
                setState(() {
                  _currentSettings = PhishTankSettings(
                    enabled: value,
                    apiKey: _currentSettings!.apiKey,
                    useCache: _currentSettings!.useCache,
                    cacheExpiry: _currentSettings!.cacheExpiry,
                    logRequests: _currentSettings!.logRequests,
                  );
                });
              },
            ),

            SwitchListTile(
              title: const Text('요청 로깅'),
              subtitle: const Text('PhishTank API 요청을 로그에 기록합니다'),
              value: _currentSettings!.logRequests,
              onChanged: _currentSettings!.enabled ? (value) {
                setState(() {
                  _currentSettings = PhishTankSettings(
                    enabled: _currentSettings!.enabled,
                    apiKey: _currentSettings!.apiKey,
                    useCache: _currentSettings!.useCache,
                    cacheExpiry: _currentSettings!.cacheExpiry,
                    logRequests: value,
                  );
                });
              } : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApiKeySettings() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'API 키 설정',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'PhishTank API 키를 입력하면 더 정확하고 빠른 탐지가 가능합니다.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _apiKeyController,
              decoration: InputDecoration(
                labelText: 'API 키',
                hintText: 'PhishTank API 키를 입력하세요',
                border: const OutlineInputBorder(),
                suffixIcon: _isValidatingApiKey
                    ? const CircularProgressIndicator()
                    : IconButton(
                  icon: const Icon(Icons.check),
                  onPressed: _validateApiKey,
                  tooltip: 'API 키 검증',
                ),
              ),
              obscureText: true,
              enabled: _currentSettings!.enabled,
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('API 키 발급받기'),
                  onPressed: () {
                    // 실제 구현에서는 웹 브라우저로 PhishTank 사이트 열기
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('API 키 발급'),
                        content: const Text(
                            'PhishTank 웹사이트(www.phishtank.com)에서 '
                                '무료 계정을 만들고 API 키를 발급받으세요.'
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('확인'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const Spacer(),
                ElevatedButton.icon(
                  icon: const Icon(Icons.verified),
                  label: const Text('검증'),
                  onPressed: _currentSettings!.enabled && !_isValidatingApiKey
                      ? _validateApiKey
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCacheSettings() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '캐시 설정',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),

            SwitchListTile(
              title: const Text('캐시 사용'),
              subtitle: const Text('API 요청 결과를 캐시하여 성능을 향상시킵니다'),
              value: _currentSettings!.useCache,
              onChanged: _currentSettings!.enabled ? (value) {
                setState(() {
                  _currentSettings = PhishTankSettings(
                    enabled: _currentSettings!.enabled,
                    apiKey: _currentSettings!.apiKey,
                    useCache: value,
                    cacheExpiry: _currentSettings!.cacheExpiry,
                    logRequests: _currentSettings!.logRequests,
                  );
                });
              } : null,
            ),

            const Divider(),

            ListTile(
              title: const Text('캐시 만료 시간'),
              subtitle: Text('${_currentSettings!.cacheExpiry}시간 후 캐시가 만료됩니다'),
              enabled: _currentSettings!.enabled && _currentSettings!.useCache,
            ),

            Slider(
              value: _currentSettings!.cacheExpiry.toDouble(),
              min: 1,
              max: 72,
              divisions: 71,
              label: '${_currentSettings!.cacheExpiry}시간',
              onChanged: _currentSettings!.enabled && _currentSettings!.useCache
                  ? (value) {
                setState(() {
                  _currentSettings = PhishTankSettings(
                    enabled: _currentSettings!.enabled,
                    apiKey: _currentSettings!.apiKey,
                    useCache: _currentSettings!.useCache,
                    cacheExpiry: value.toInt(),
                    logRequests: _currentSettings!.logRequests,
                  );
                });
              }
                  : null,
            ),

            const SizedBox(height: 16),

            if (_cacheInfo != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '캐시 정보',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Text('크기: ${_cacheInfo!['size']}/${_cacheInfo!['max_size']}'),
                    Text('사용률: ${_cacheInfo!['usage_percentage']}%'),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              ElevatedButton.icon(
                icon: const Icon(Icons.clear),
                label: const Text('캐시 초기화'),
                onPressed: _currentSettings!.enabled && _currentSettings!.useCache
                    ? _clearCache
                    : null,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCard() {
    if (_currentStats == null) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'PhishTank 통계',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('초기화'),
                  onPressed: _resetStats,
                ),
              ],
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    '총 요청',
                    '${_currentStats!.totalRequests}',
                    Icons.send,
                    Colors.blue,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    '피싱 탐지',
                    '${_currentStats!.phishingDetected}',
                    Icons.warning,
                    Colors.red,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    '캐시 히트',
                    '${_currentStats!.cacheHits}',
                    Icons.speed,
                    Colors.green,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'API 오류',
                    '${_currentStats!.apiErrors}',
                    Icons.error,
                    Colors.orange,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  const Icon(Icons.access_time, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    '마지막 요청: ${_formatDateTime(_currentStats!.lastRequest)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color.withOpacity(0.8),
            ),
            textAlign: TextAlign.center,
          ),
        ],
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

            ListTile(
              leading: const Icon(Icons.info),
              title: const Text('PhishTank 정보'),
              subtitle: const Text('PhishTank는 피싱 URL 데이터베이스 서비스입니다'),
              onTap: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('PhishTank 정보'),
                    content: const Text(
                        'PhishTank는 OpenDNS에서 운영하는 무료 피싱 URL 데이터베이스입니다. '
                            '전 세계 사용자들이 신고한 피싱 사이트 정보를 실시간으로 공유합니다.\n\n'
                            '• 무료 API 제공\n'
                            '• 실시간 피싱 URL 탐지\n'
                            '• 커뮤니티 기반 신고 시스템'
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('확인'),
                      ),
                    ],
                  ),
                );
              },
            ),

            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('설정 내보내기'),
              subtitle: const Text('현재 PhishTank 설정을 파일로 저장'),
              onTap: () {
                final exportData = _phishTankService.exportLogs();
                // 실제 구현에서는 파일 저장 로직 추가
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('설정이 내보내져졌습니다')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return '방금 전';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}분 전';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}시간 전';
    } else {
      return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
    }
  }
}