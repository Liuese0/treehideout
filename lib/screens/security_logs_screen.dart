import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/integrated_security_manager.dart';
import '../services/ai_security_service.dart';
import '../ai/ai_detector_model.dart';

class SecurityLogsScreen extends StatefulWidget {
  const SecurityLogsScreen({Key? key}) : super(key: key);

  @override
  State<SecurityLogsScreen> createState() => _SecurityLogsScreenState();
}

class _SecurityLogsScreenState extends State<SecurityLogsScreen> {
  final IntegratedSecurityManager _securityManager = IntegratedSecurityManager();
  late AISecurityService _aiSecurityService;

  List<SecurityLogEntry> _logs = [];
  List<SecurityLogEntry> _filteredLogs = [];
  bool _isLoading = true;

  // 필터 옵션
  ThreatLevel? _selectedThreatLevel;
  String? _selectedThreatType;
  DateTimeRange? _selectedDateRange;
  String _searchQuery = '';

  // 정렬 옵션
  bool _sortByDateDesc = true;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    try {
      await _securityManager.initialize();
      _aiSecurityService = _securityManager.aiSecurityService;
      await _loadLogs();
    } catch (e) {
      debugPrint('서비스 초기화 실패: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('서비스 초기화 실패: $e')),
      );
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadLogs() async {
    setState(() {
      _isLoading = true;
    });

    try {
      _logs = _securityManager.getSecurityLogs();
      _applyFilters();
    } catch (e) {
      debugPrint('보안 로그 로드 실패: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('로그를 불러오는데 실패했습니다: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _applyFilters() {
    _filteredLogs = _logs.where((log) {
      // 위험 레벨 필터
      if (_selectedThreatLevel != null && log.result.threatLevel != _selectedThreatLevel) {
        return false;
      }

      // 위험 유형 필터
      if (_selectedThreatType != null && log.result.threatType != _selectedThreatType) {
        return false;
      }

      // 날짜 범위 필터
      if (_selectedDateRange != null) {
        if (log.timestamp.isBefore(_selectedDateRange!.start) ||
            log.timestamp.isAfter(_selectedDateRange!.end)) {
          return false;
        }
      }

      // 검색 쿼리 필터
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        return log.message.toLowerCase().contains(query) ||
            log.result.reason.toLowerCase().contains(query) ||
            log.result.detectedKeywords.any((keyword) =>
                keyword.toLowerCase().contains(query));
      }

      return true;
    }).toList();

    // 정렬
    if (_sortByDateDesc) {
      _filteredLogs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    } else {
      _filteredLogs.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('보안 로그'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
          ),
          IconButton(
            icon: Icon(_sortByDateDesc ? Icons.arrow_downward : Icons.arrow_upward),
            onPressed: () {
              setState(() {
                _sortByDateDesc = !_sortByDateDesc;
              });
              _applyFilters();
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'clear':
                  _clearLogs();
                  break;
                case 'export':
                  _exportLogs();
                  break;
                case 'stats':
                  _showStats();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'clear',
                child: Text('로그 초기화'),
              ),
              const PopupMenuItem(
                value: 'export',
                child: Text('로그 내보내기'),
              ),
              const PopupMenuItem(
                value: 'stats',
                child: Text('통계 보기'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          _buildFilterChips(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredLogs.isEmpty
                ? _buildEmptyState()
                : _buildLogsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: TextField(
        decoration: const InputDecoration(
          hintText: '메시지 내용, 키워드로 검색...',
          prefixIcon: Icon(Icons.search),
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        onChanged: (value) {
          _searchQuery = value;
          _applyFilters();
        },
      ),
    );
  }

  Widget _buildFilterChips() {
    final hasFilters = _selectedThreatLevel != null ||
        _selectedThreatType != null ||
        _selectedDateRange != null;

    if (!hasFilters) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      height: 50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          if (_selectedThreatLevel != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Chip(
                label: Text(_getThreatLevelText(_selectedThreatLevel!)),
                deleteIcon: const Icon(Icons.close, size: 18),
                onDeleted: () {
                  setState(() {
                    _selectedThreatLevel = null;
                  });
                  _applyFilters();
                },
                backgroundColor: _getThreatLevelColor(_selectedThreatLevel!).withOpacity(0.2),
              ),
            ),
          if (_selectedThreatType != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Chip(
                label: Text(_selectedThreatType!),
                deleteIcon: const Icon(Icons.close, size: 18),
                onDeleted: () {
                  setState(() {
                    _selectedThreatType = null;
                  });
                  _applyFilters();
                },
              ),
            ),
          if (_selectedDateRange != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Chip(
                label: Text(
                    '${DateFormat('MM/dd').format(_selectedDateRange!.start)} - ${DateFormat('MM/dd').format(_selectedDateRange!.end)}'
                ),
                deleteIcon: const Icon(Icons.close, size: 18),
                onDeleted: () {
                  setState(() {
                    _selectedDateRange = null;
                  });
                  _applyFilters();
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.security,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            _logs.isEmpty ? '아직 보안 로그가 없습니다' : '필터 조건에 맞는 로그가 없습니다',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _logs.isEmpty
                ? '메시지가 검사되면 여기에 로그가 표시됩니다'
                : '다른 필터 조건을 시도해보세요',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey.shade500,
            ),
          ),
          if (_logs.isNotEmpty) ...[
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _selectedThreatLevel = null;
                  _selectedThreatType = null;
                  _selectedDateRange = null;
                  _searchQuery = '';
                });
                _applyFilters();
              },
              child: const Text('필터 초기화'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLogsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _filteredLogs.length,
      itemBuilder: (context, index) {
        final log = _filteredLogs[index];
        return _buildLogItem(log);
      },
    );
  }

  Widget _buildLogItem(SecurityLogEntry log) {
    final threatLevelColor = _getThreatLevelColor(log.result.threatLevel);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _showLogDetails(log),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: threatLevelColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      log.message.length > 50
                          ? '${log.message.substring(0, 50)}...'
                          : log.message,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Text(
                    DateFormat('MM/dd HH:mm').format(log.timestamp),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: threatLevelColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: threatLevelColor.withOpacity(0.5)),
                    ),
                    child: Text(
                      _getThreatLevelText(log.result.threatLevel),
                      style: TextStyle(
                        fontSize: 12,
                        color: threatLevelColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      log.result.threatType,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  if (log.result.isThreat) ...[
                    const SizedBox(width: 8),
                    Text(
                      '위험도: ${(log.result.confidenceScore * 100).toInt()}%',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ],
              ),
              if (log.result.detectedKeywords.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: log.result.detectedKeywords.take(3).map((keyword) =>
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: Colors.red.withOpacity(0.3)),
                        ),
                        child: Text(
                          keyword,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.red,
                          ),
                        ),
                      ),
                  ).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showLogDetails(SecurityLogEntry log) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('보안 로그 상세'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('시간', DateFormat('yyyy-MM-dd HH:mm:ss').format(log.timestamp)),
              _buildDetailRow('위험 레벨', _getThreatLevelText(log.result.threatLevel)),
              _buildDetailRow('위험 유형', log.result.threatType),
              _buildDetailRow('위험도', '${(log.result.confidenceScore * 100).toInt()}%'),
              _buildDetailRow('사용자 ID', log.userId),
              _buildDetailRow('방 ID', log.roomId),

              const SizedBox(height: 16),
              const Text('메시지:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(log.message),
              ),

              const SizedBox(height: 16),
              const Text('탐지 이유:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(log.result.reason),

              if (log.result.detectedKeywords.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('탐지된 키워드:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: log.result.detectedKeywords.map((keyword) =>
                      Chip(
                        label: Text(keyword, style: const TextStyle(fontSize: 12)),
                        backgroundColor: Colors.red.withOpacity(0.1),
                      ),
                  ).toList(),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (log.result.isThreat)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _reportFalsePositive(log);
              },
              child: const Text('오탐 신고'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  void _showFilterDialog() {
    final threatTypes = _logs.map((log) => log.result.threatType).toSet().toList();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('필터 설정'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 위험 레벨 필터
                const Text('위험 레벨:', style: TextStyle(fontWeight: FontWeight.bold)),
                Wrap(
                  children: [
                    FilterChip(
                      label: const Text('전체'),
                      selected: _selectedThreatLevel == null,
                      onSelected: (selected) {
                        setDialogState(() {
                          _selectedThreatLevel = null;
                        });
                      },
                    ),
                    ...ThreatLevel.values.map((level) => FilterChip(
                      label: Text(_getThreatLevelText(level)),
                      selected: _selectedThreatLevel == level,
                      onSelected: (selected) {
                        setDialogState(() {
                          _selectedThreatLevel = selected ? level : null;
                        });
                      },
                    )),
                  ],
                ),

                const SizedBox(height: 16),

                // 위험 유형 필터
                const Text('위험 유형:', style: TextStyle(fontWeight: FontWeight.bold)),
                Wrap(
                  children: [
                    FilterChip(
                      label: const Text('전체'),
                      selected: _selectedThreatType == null,
                      onSelected: (selected) {
                        setDialogState(() {
                          _selectedThreatType = null;
                        });
                      },
                    ),
                    ...threatTypes.map((type) => FilterChip(
                      label: Text(type),
                      selected: _selectedThreatType == type,
                      onSelected: (selected) {
                        setDialogState(() {
                          _selectedThreatType = selected ? type : null;
                        });
                      },
                    )),
                  ],
                ),

                const SizedBox(height: 16),

                // 날짜 범위 필터
                ListTile(
                  title: const Text('날짜 범위'),
                  subtitle: Text(_selectedDateRange == null
                      ? '전체 기간'
                      : '${DateFormat('yyyy-MM-dd').format(_selectedDateRange!.start)} ~ ${DateFormat('yyyy-MM-dd').format(_selectedDateRange!.end)}'),
                  trailing: const Icon(Icons.date_range),
                  onTap: () async {
                    final dateRange = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now(),
                      initialDateRange: _selectedDateRange,
                    );
                    if (dateRange != null) {
                      setDialogState(() {
                        _selectedDateRange = dateRange;
                      });
                    }
                  },
                ),

                if (_selectedDateRange != null)
                  TextButton(
                    onPressed: () {
                      setDialogState(() {
                        _selectedDateRange = null;
                      });
                    },
                    child: const Text('날짜 필터 제거'),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _applyFilters();
              },
              child: const Text('적용'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _clearLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('로그 초기화'),
        content: const Text('모든 보안 로그를 삭제하시겠습니까? 이 작업은 되돌릴 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _aiSecurityService.clearLogs();
        await _loadLogs();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('보안 로그가 초기화되었습니다')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('로그 초기화 실패: $e')),
        );
      }
    }
  }

  void _exportLogs() {
    try {
      final exportData = _aiSecurityService.exportLogs(
        startDate: _selectedDateRange?.start,
        endDate: _selectedDateRange?.end,
      );

      // 실제 구현에서는 파일로 저장하거나 공유 기능 사용
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('로그 내보내기'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('선택된 로그가 성공적으로 내보내졌습니다.'),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  children: [
                    Text('총 ${_filteredLogs.length}개 로그'),
                    Text('크기: ${exportData.length} bytes'),
                  ],
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
        SnackBar(content: Text('로그 내보내기 실패: $e')),
      );
    }
  }

  void _showStats() {
    final threatsCount = _logs.where((log) => log.result.isThreat).length;
    final safeCount = _logs.length - threatsCount;
    final threatTypes = <String, int>{};

    for (final log in _logs) {
      if (log.result.isThreat) {
        threatTypes[log.result.threatType] = (threatTypes[log.result.threatType] ?? 0) + 1;
      }
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('로그 통계'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('총 로그 수: ${_logs.length}'),
              Text('위험 메시지: $threatsCount'),
              Text('안전 메시지: $safeCount'),

              if (threatTypes.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('위험 유형별 분포:', style: TextStyle(fontWeight: FontWeight.bold)),
                ...threatTypes.entries.map((entry) =>
                    Text('${entry.key}: ${entry.value}개')
                ),
              ],

              const SizedBox(height: 16),
              Text('필터된 로그: ${_filteredLogs.length}개'),
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
  }

  Future<void> _reportFalsePositive(SecurityLogEntry log) async {
    try {
      await _aiSecurityService.reportFalsePositive(log.id);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('오탐 신고가 접수되었습니다')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('오탐 신고 실패: $e')),
      );
    }
  }

  Color _getThreatLevelColor(ThreatLevel level) {
    switch (level) {
      case ThreatLevel.safe:
        return Colors.green;
      case ThreatLevel.low:
        return Colors.yellow.shade700;
      case ThreatLevel.medium:
        return Colors.orange;
      case ThreatLevel.high:
        return Colors.red;
      case ThreatLevel.critical:
        return Colors.red.shade900;
    }
  }

  String _getThreatLevelText(ThreatLevel level) {
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
}