import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class SewingExpensesSection extends StatefulWidget {
    final String role;

  const SewingExpensesSection({Key? key, required this.role}) : super(key: key);

  @override
  State<SewingExpensesSection> createState() => _SewingExpensesSectionState();
}

class _SewingExpensesSectionState extends State<SewingExpensesSection> {
  List expenses = [];
  List allExpenses = [];
  final String apiUrl = 'http://127.0.0.1:8888/expenses/';
  bool isLoading = false;

  // Scroll controllers for the table
  final ScrollController _verticalController = ScrollController();
  final ScrollController _horizontalController = ScrollController();

  // Year & Month selectors
  List<int> _yearOptions = [];
  List<String> _monthOptions = [];
  int selectedYear = DateTime.now().year;
  String selectedYearMonth =
      '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';

  // Expense types labels and colors
  final Map<String, Map<String, dynamic>> typeLabels = {
    'electricity': {
      'label': 'الكهرباء',
      'lightColor': Colors.blue[50],
      'darkColor': Colors.blue[800],
      'darkerColor': Colors.blue[900],
    },
    'rent': {
      'label': 'الإيجار',
      'lightColor': Colors.green[50],
      'darkColor': Colors.green[800],
      'darkerColor': Colors.green[900],
    },
    'water': {
      'label': 'الماء',
      'lightColor': Colors.cyan[50],
      'darkColor': Colors.cyan[800],
      'darkerColor': Colors.cyan[900],
    },
    'maintenance': {
      'label': 'الصيانة',
      'lightColor': Colors.orange[50],
      'darkColor': Colors.orange[800],
      'darkerColor': Colors.orange[900],
    },
    'transport': {
      'label': 'النقل',
      'lightColor': Colors.purple[50],
      'darkColor': Colors.purple[800],
      'darkerColor': Colors.purple[900],
    },
    'custom': {
      'label': 'أخرى',
      'lightColor': Colors.grey[50],
      'darkColor': Colors.grey[800],
      'darkerColor': Colors.grey[900],
    },
  };

  @override
  void initState() {
    super.initState();
    _fetchAllExpenses();
  }

  @override
  void dispose() {
    _verticalController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  Future<void> _fetchAllExpenses() async {
    try {
      final res = await http.get(Uri.parse(apiUrl));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded is List) {
          allExpenses = decoded;
        } else {
          allExpenses = [];
        }
      }
    } catch (_) {
      allExpenses = [];
    }

    // Extract unique years from allExpenses
    final years = allExpenses
        .map((e) {
          final date = e['expense_date'] as String?;
          return date != null && date.contains('-')
              ? int.tryParse(date.split('-').first) ?? DateTime.now().year
              : DateTime.now().year;
        })
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
    _yearOptions = years.isNotEmpty ? years : [DateTime.now().year];

    // Default selectedYear
    selectedYear = _yearOptions.contains(DateTime.now().year)
        ? DateTime.now().year
        : _yearOptions.first;

    _buildMonthOptions();
    fetchExpenses();
  }

  void _buildMonthOptions() {
    _monthOptions = allExpenses
        .where((e) {
          final date = e['expense_date'] as String?;
          if (date == null) return false;
          final year = int.tryParse(date.split('-').first);
          return year == selectedYear;
        })
        .map((e) => (e['expense_date'] as String).substring(5, 7))
        .toSet()
        .toList()
      ..sort();

    // Default to current month if present
    final nowMon = DateTime.now().month.toString().padLeft(2, '0');
    if (selectedYear == DateTime.now().year &&
        _monthOptions.contains(nowMon)) {
      selectedYearMonth = '${selectedYear}-$nowMon';
    } else {
      selectedYearMonth = '$selectedYear-${_monthOptions.first}';
    }
  }

  Future<void> fetchExpenses() async {
    setState(() => isLoading = true);
    try {
      final parts = selectedYearMonth.split('-');
      final year = parts[0], month = parts[1];
      final uri = Uri.parse('$apiUrl?year=$year&month=$month');
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded is List) {
          setState(() => expenses = decoded);
        } else {
          _showSnackBar('خطأ: البيانات ليست قائمة', color: Colors.red);
        }
      } else {
        _showSnackBar('خطأ في الخادم: ${res.statusCode}', color: Colors.red);
      }
    } catch (e) {
      _showSnackBar('خطأ في جلب المصروفات: $e', color: Colors.red);
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _showSnackBar(String message, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  double calculateTotalExpenses(String type) {
    return expenses
        .where((e) => e['expense_type'] == type)
        .fold(0.0, (sum, e) => sum + (e['amount'] as num).toDouble());
  }

  Future<void> addOrEditExpense({Map? existing}) async {
  String type = existing?['expense_type'] ?? typeLabels.keys.first;
  final descriptionCtrl =
      TextEditingController(text: existing?['description'] ?? '');
  final amountCtrl =
      TextEditingController(text: existing?['amount']?.toString() ?? '');
  DateTime selectedDate = existing != null
      ? DateTime.tryParse(existing['expense_date'] ?? '') ?? DateTime.now()
      : DateTime.now();
  final _formKey = GlobalKey<FormState>();

  await showDialog(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(existing == null ? 'إضافة مصروف' : 'تعديل مصروف'),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'النوع'),
                value: type,
                items: typeLabels.entries
                    .map((e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value['label'] as String),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => type = v!),
              ),
              if (type == 'transport' || type == 'custom') ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: descriptionCtrl,
                  decoration: const InputDecoration(labelText: 'وصف المصروف'),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'الوصف مطلوب';
                    }
                    return null;
                  },
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: amountCtrl,
                decoration: const InputDecoration(labelText: 'المبلغ'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  final parsed = double.tryParse(v ?? '');
                  if (v == null || v.trim().isEmpty) return 'المبلغ مطلوب';
                  if (parsed == null || parsed <= 0) return 'المبلغ غير صالح';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'التاريخ: ${selectedDate.toLocal().toIso8601String().substring(0, 10)}',
                ),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                    locale: const Locale('ar'),
                  );
                  if (picked != null) setState(() => selectedDate = picked);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              if (!_formKey.currentState!.validate()) return;

              final rawAmount = double.parse(amountCtrl.text);
              final payload = {
                'expense_type': type,
                'description': (type == 'transport' || type == 'custom')
                    ? descriptionCtrl.text.trim()
                    : '',
                'amount': rawAmount,
                'expense_date': selectedDate.toIso8601String(),
              };
              try {
                if (existing == null) {
                  final response = await http.post(
                    Uri.parse(apiUrl),
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode(payload),
                  );
                  if (response.statusCode == 201) {
                    _showSnackBar('تم إضافة المصروف بنجاح', color: Colors.green);
                  } else {
                    _showSnackBar('فشل الإضافة: ${response.body}', color: Colors.red);
                  }
                } else {
                  final uri = Uri.parse('$apiUrl${existing['id']}');
                  final response = await http.put(
                    uri,
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode(payload),
                  );
                  if (response.statusCode == 200) {
                    _showSnackBar('تم التحديث بنجاح', color: Colors.green);
                  } else {
                    _showSnackBar('فشل التحديث: ${response.body}', color: Colors.red);
                  }
                }
                Navigator.pop(context);
                await _fetchAllExpenses();
              } catch (e) {
                _showSnackBar('خطأ في الاتصال: $e', color: Colors.red);
              }
            },
            child: Text(existing == null ? '+ إضافة مصروف' : 'تحديث'),
          ),
        ],
      ),
    ),
  );
}

  Future<void> deleteExpense(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text('هل أنت متأكد من حذف هذا المصروف؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        final uri = Uri.parse('$apiUrl$id');
        final response = await http.delete(uri);
        if (response.statusCode == 200) {
          _showSnackBar('تم حذف المصروف بنجاح', color: Colors.green);
          await fetchExpenses();
        } else {
          _showSnackBar('فشل حذف المصروف: ${response.body}',
              color: Colors.red);
        }
      } catch (e) {
        _showSnackBar('خطأ في الاتصال: $e', color: Colors.red);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const monthNames = [
      'جانفي', 'فيفري', 'مارس', 'أفريل',
      'ماي', 'جوان', 'جويلية', 'أوت',
      'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
    ];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Add button on left, then filters on right
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: () => addOrEditExpense(),
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: const Text('+ إضافة مصروف'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  DropdownButton<int>(
                    value: selectedYear,
                    items: _yearOptions
                        .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                        .toList(),
                    onChanged: (y) {
                      if (y == null) return;
                      setState(() {
                        selectedYear = y;
                        _buildMonthOptions();
                        fetchExpenses();
                      });
                    },
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    value: selectedYearMonth.substring(5, 7),
                    items: _monthOptions.map((m) {
                      final idx = int.parse(m);
                      return DropdownMenuItem(
                          value: m, child: Text(monthNames[idx - 1]));
                    }).toList(),
                    onChanged: (mon) {
                      if (mon == null) return;
                      setState(() {
                        selectedYearMonth = '$selectedYear-$mon';
                        fetchExpenses();
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Statistics Cards
              if (widget.role == 'Admin' || widget.role == 'SuperAdmin') ...[

              Row(
                
                children: typeLabels.entries.map((entry) {
                  return Expanded(
                    child: Card(
                      color: entry.value['lightColor'] as Color,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            Text(
                              entry.value['label'] as String,
                              style: TextStyle(
                                color: entry.value['darkColor'] as Color,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${calculateTotalExpenses(entry.key).toStringAsFixed(2)} دج',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: entry.value['darkerColor'] as Color,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),],
              const SizedBox(height: 24),
              // Expenses Table
              Expanded(
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : expenses.isEmpty
                        ? const Center(child: Text('لا توجد مصروفات'))
                        : Scrollbar(
                            controller: _verticalController,
                            thumbVisibility: true,
                            child: SingleChildScrollView(
                              controller: _verticalController,
                              scrollDirection: Axis.vertical,
                              child: Center(
                                child: SingleChildScrollView(
                                  controller: _horizontalController,
                                  scrollDirection: Axis.horizontal,
                                  child: Card(
                                    child: Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: DataTable(
                                        headingRowColor: MaterialStateProperty.all(
                                          Theme.of(context).colorScheme.primary,
                                        ),
                                        headingTextStyle: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        columns: const [
                                          DataColumn(label: Text('النوع')),
                                          DataColumn(label: Text('الوصف')),
                                          DataColumn(label: Text('المبلغ')),
                                          DataColumn(label: Text('التاريخ')),
                                          DataColumn(label: Text('إجراءات')),
                                        ],
                                        rows: expenses.map((e) {
                                          final dateOnly = (e['expense_date'] as String)
                                              .split(RegExp(r'[T ]'))
                                              .first;
                                          final label = typeLabels[e['expense_type']]
                                                  ?['label'] as String? ??
                                              e['expense_type'];
                                          return DataRow(cells: [
                                            DataCell(
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                    horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: typeLabels[e['expense_type']]
                                                          ?['lightColor'] as Color? ??
                                                      Colors.grey[100],
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: Text(
                                                  label,
                                                  style: TextStyle(
                                                    color: typeLabels[e['expense_type']]
                                                            ?['darkColor'] as Color? ??
                                                        Colors.grey[800],
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            DataCell(Text(e['description']?.isNotEmpty ==
                                                    true
                                                ? e['description']
                                                : '-')),
                                            DataCell(Text(
                                                '${(e['amount'] as num).toStringAsFixed(2)} دج')),
                                            DataCell(Text(dateOnly)),
                                            DataCell(Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                  icon: Icon(Icons.edit,
                                                      color:
                                                          Theme.of(context)
                                                              .colorScheme
                                                              .primary),
                                                  tooltip: 'تعديل',
                                                  onPressed: () =>
                                                      addOrEditExpense(existing: e),
                                                ),
                                                IconButton(
                                                  icon: const Icon(Icons.delete,
                                                      color: Colors.red),
                                                  tooltip: 'حذف',
                                                  onPressed: () =>
                                                      deleteExpense(e['id']),
                                                ),
                                              ],
                                            )),
                                          ]);
                                        }).toList(),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
