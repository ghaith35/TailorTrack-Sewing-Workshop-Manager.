import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../main.dart';
import 'package:flutter/services.dart'; // for rootBundle
import 'package:file_picker/file_picker.dart'; // for directory chooser
import 'dart:io' as io;

class SewingEmployeesSection extends StatefulWidget {
  const SewingEmployeesSection({super.key});
  @override
  State<SewingEmployeesSection> createState() => _SewingEmployeesSectionState();
}

class _SewingEmployeesSectionState extends State<SewingEmployeesSection> {
  int selectedTab = 0;
  int selectedInfoTab = 0;
  int attType = 0;
late pw.Font _arabicFont;
List<dynamic> _filteredAttEmployees = [];

  // Attendance year/month selection
  List<int> _availableYears = [];
  List<String> _availableMonths = [];
  int? selectedYear;
  String? selectedYearMonth;

  // Presence filters
  List<int> _presenceYears = [];
  List<String> _presenceMonths = [];
  List<int> _presenceDays = [];
  int? selectedPresenceYear;
  String? selectedPresenceMonth;
  int? selectedPresenceDay;

  int? selectedEmployeeId;
  List<dynamic> attEmployees = [];
  bool attLoading = false;
  List<dynamic> employees = [];
  bool isLoading = false;
  int selectedDataTab = 0;
  List<dynamic> loans = [];
  List<dynamic> pieces = [];
  List<dynamic> debts = [];
  List<dynamic> allEmployees = [];
  List<dynamic> pieceEmployees = [];
  List<dynamic> allModels = [];
  bool isDataLoading = false;
  int selectedSalariesTab = 0;
  
  // Salary year/month selection
  List<int> _salaryYears = [];
  List<String> _salaryMonths = [];
  int? selectedSalaryYear;
  String? selectedSalaryMonth;
  
  bool salaryLoading = false;
  List<dynamic> monthlyAttendance = [];
  List<dynamic> pieceAttendance = [];
  Map<int, Map<String, num>> loanData = {};
  List<Map<String, dynamic>> monthlyTableRows = [];
  List<Map<String, dynamic>> pieceTableRows = [];

  // Search controllers
  final TextEditingController _infoSearchController = TextEditingController();
  final TextEditingController _loansSearchController = TextEditingController();
  final TextEditingController _piecesSearchController = TextEditingController();
  final TextEditingController _debtsSearchController = TextEditingController();
  final TextEditingController _presenceSearchController = TextEditingController();

  // Filtered lists
  List<dynamic> _filteredEmployees = [];
  List<dynamic> _filteredLoans = [];
  List<dynamic> _filteredPieces = [];
  List<dynamic> _filteredDebts = [];
  List<dynamic> _filteredPresence = [];

  // Scroll controllers
  final ScrollController infoTableController = ScrollController();
  final ScrollController loansTableController = ScrollController();
  final ScrollController piecesTableController = ScrollController();
  final ScrollController debtsTableController = ScrollController();
  final ScrollController monthlySalaryTableController = ScrollController();
  final ScrollController pieceSalaryTableController = ScrollController();
  final ScrollController monthlyAttTableController = ScrollController();
  final ScrollController pieceAttTableController = ScrollController();
  final ScrollController presenceTableController = ScrollController();

  // Dynamic URL getters
  String get _employeesUrl => '${globalServerUri.toString()}/employees/';
  String get _attendanceUrl => '${globalServerUri.toString()}/employees/attendance';
  String get _loansUrl => '${globalServerUri.toString()}/employees/loans';
  String get _piecesUrl => '${globalServerUri.toString()}/employees/pieces';
  String get _debtsUrl => '${globalServerUri.toString()}/employees/debts';
  String get _modelsUrl => '${globalServerUri.toString()}/employees/models';
  String get _pieceEmployeesUrl => '${globalServerUri.toString()}/employees/list?seller_type=piece';
  String get _attendanceBulkUrl => '${globalServerUri.toString()}/employees/attendance/bulk';

  @override
  void dispose() {
    infoTableController.dispose();
    loansTableController.dispose();
    piecesTableController.dispose();
    debtsTableController.dispose();
    monthlySalaryTableController.dispose();
    pieceSalaryTableController.dispose();
    monthlyAttTableController.dispose();
    pieceAttTableController.dispose();
    presenceTableController.dispose();
    
    _infoSearchController.dispose();
    _loansSearchController.dispose();
    _piecesSearchController.dispose();
    _debtsSearchController.dispose();
    _presenceSearchController.dispose();

    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadPdfFont();
    _infoSearchController.addListener(_filterEmployees);
    _loansSearchController.addListener(_filterLoans);
    _piecesSearchController.addListener(_filterPieces);
    _debtsSearchController.addListener(_filterDebts);
    _presenceSearchController.addListener(_filterPresence);
    
    _initializeData();
  }

Future<void> _loadPdfFont() async {
  final fontData = await rootBundle.load('assets/fonts/NotoSansArabic_Condensed-Black.ttf');
  _arabicFont = pw.Font.ttf(fontData);
}

  Future<void> _initializeData() async {
    await fetchEmployees();
    await _fetchAttendanceYears();
    await _fetchSalaryYears();
    await _fetchPresenceYears();
    await fetchDataSection();
    
    if (_availableYears.isNotEmpty) {
      await fetchAttendance();
    }
    if (_salaryYears.isNotEmpty) {
      await fetchSalariesData();
    }
    if (_presenceYears.isNotEmpty) {
      await fetchPresence();
    }
  }

  // Filter methods
  void _filterEmployees() {
    final query = _infoSearchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredEmployees = employees;
      } else {
        _filteredEmployees = employees.where((emp) {
          final fullName = '${emp['first_name']} ${emp['last_name']}'.toLowerCase();
          final phone = (emp['phone'] ?? '').toLowerCase();
          final address = (emp['address'] ?? '').toLowerCase();
          final salary = emp['salary']?.toString() ?? '';
          final role = (emp['role'] ?? '').toLowerCase();
          return fullName.contains(query) || phone.contains(query) || address.contains(query) || salary.contains(query) || role.contains(query);
        }).toList();
      }
    });
  }

  void _filterLoans() {
    final query = _loansSearchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredLoans = loans;
      } else {
        _filteredLoans = loans.where((loan) {
          final empName = (loan['employee_name'] ?? '').toLowerCase();
          final amount = loan['amount'].toString();
          final date = (loan['loan_date'] ?? '').toLowerCase();
          return empName.contains(query) || amount.contains(query) || date.contains(query);
        }).toList();
      }
    });
  }

  void _filterPieces() {
    final query = _piecesSearchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredPieces = pieces;
      } else {
        _filteredPieces = pieces.where((piece) {
          final empName = (piece['employee_name'] ?? '').toLowerCase();
          final modelName = (piece['model_name'] ?? '').toLowerCase();
          final qty = piece['quantity'].toString();
          final price = piece['piece_price'].toString();
          return empName.contains(query) || modelName.contains(query) || qty.contains(query) || price.contains(query);
        }).toList();
      }
    });
  }

  void _filterDebts() {
    final query = _debtsSearchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredDebts = debts;
      } else {
        _filteredDebts = debts.where((debt) {
          final empName = (debt['employee_name'] ?? '').toLowerCase();
          final amount = debt['amount'].toString();
          final date = (debt['debt_date'] ?? '').toLowerCase();
          return empName.contains(query) || amount.contains(query) || date.contains(query);
        }).toList();
      }
    });
  }

  void _filterPresence() {
    final query = _presenceSearchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredPresence = attEmployees;
      } else {
        _filteredPresence = attEmployees.where((att) {
          final empName = (att['employee_name'] ?? '').toLowerCase();
          final date = (att['date'] ?? '').toLowerCase();
          return empName.contains(query) || date.contains(query);
        }).toList();
      }
    });
  }

  // Helper method to fetch employees by search query
  Future<List<dynamic>> _fetchEmployeesByQuery(String searchQuery, {String? sellerType}) async {
    try {
      String url = _employeesUrl;
      Map<String, String> queryParams = {};
      
      if (searchQuery.isNotEmpty) {
        queryParams['q'] = searchQuery;
      }
      if (sellerType != null) {
        queryParams['seller_type'] = sellerType;
      }
      
      if (queryParams.isNotEmpty) {
        final uri = Uri.parse(url).replace(queryParameters: queryParams);
        url = uri.toString();
      }
      
      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
    } catch (_) {}
    
    // Fallback to local filtering if API doesn't support search
    List<dynamic> employeeList = sellerType == 'piece' ? pieceEmployees : allEmployees;
    if (searchQuery.isEmpty) return employeeList;
    
    return employeeList.where((emp) {
      final fullName = '${emp['first_name']} ${emp['last_name']}'.toLowerCase();
      return fullName.contains(searchQuery.toLowerCase());
    }).toList();
  }

  Future<void> _fetchAttendanceYears() async {
    try {
      final res = await http.get(Uri.parse('${globalServerUri.toString()}/employees/attendance/years?type=${attType == 0 ? "monthly" : "piece"}'));
      if (res.statusCode == 200) {
        final years = (jsonDecode(res.body) as List).cast<int>();
        setState(() {
          _availableYears = years;
          if (years.isNotEmpty) {
            selectedYear = years.contains(DateTime.now().year) ? DateTime.now().year : years.first;
            _fetchAttendanceMonths();
          }
        });
      }
    } catch (e) {
      print('Error fetching attendance years: $e');
    }
  }

  Future<void> _fetchAttendanceMonths() async {
    if (selectedYear == null) return;
    try {
      final res = await http.get(Uri.parse('${globalServerUri.toString()}/employees/attendance/months?year=$selectedYear&type=${attType == 0 ? "monthly" : "piece"}'));
      if (res.statusCode == 200) {
        final months = (jsonDecode(res.body) as List).cast<String>();
        setState(() {
          _availableMonths = months;
          if (months.isNotEmpty) {
            final currentMonth = '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';
            selectedYearMonth = months.contains(currentMonth) ? currentMonth : months.first;
          }
        });
      }
    } catch (e) {
      print('Error fetching attendance months: $e');
    }
  }

  Future<void> _fetchPresenceYears() async {
    try {
      final res = await http.get(Uri.parse('${globalServerUri.toString()}/employees/attendance/years?type=monthly'));
      if (res.statusCode == 200) {
        final years = (jsonDecode(res.body) as List).cast<int>();
        setState(() {
          _presenceYears = years;
          if (years.isNotEmpty) {
            selectedPresenceYear = years.contains(DateTime.now().year) ? DateTime.now().year : years.first;
            _fetchPresenceMonths();
          }
        });
      }
    } catch (e) {
      print('Error fetching presence years: $e');
    }
  }

  Future<void> _fetchPresenceMonths() async {
    if (selectedPresenceYear == null) return;
    try {
      final res = await http.get(Uri.parse('${globalServerUri.toString()}/employees/attendance/months?year=$selectedPresenceYear&type=monthly'));
      if (res.statusCode == 200) {
        final months = (jsonDecode(res.body) as List).cast<String>();
        setState(() {
          _presenceMonths = months;
          if (months.isNotEmpty) {
            final currentMonth = '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';
            selectedPresenceMonth = months.contains(currentMonth) ? currentMonth : months.first;
            _fetchPresenceDays();
          }
        });
      }
    } catch (e) {
      print('Error fetching presence months: $e');
    }
  }

  Future<void> _fetchPresenceDays() async {
    if (selectedPresenceYear == null || selectedPresenceMonth == null) return;
    try {
      final daysInMonth = DateTime(selectedPresenceYear!, int.parse(selectedPresenceMonth!.split('-')[1]) + 1, 0).day;
      setState(() {
        _presenceDays = List.generate(daysInMonth, (i) => i + 1);
        selectedPresenceDay = _presenceDays.contains(DateTime.now().day) ? DateTime.now().day : _presenceDays.first;
        fetchPresence();
      });
    } catch (e) {
      print('Error fetching presence days: $e');
    }
  }

  Future<void> _addAttendanceForAllEmployees(DateTime selectedDate) async {
    final startTime = DateTime(selectedDate.year, selectedDate.month, selectedDate.day, 8, 0);
    final endTime = DateTime(selectedDate.year, selectedDate.month, selectedDate.day, 16, 0);

    final attendanceRecords = allEmployees.where((employee) => employee['seller_type'] == 'month').map((employee) {
      return {
        'employee_id': employee['id'],
        'date': selectedDate.toIso8601String().substring(0, 10),
        'check_in': startTime.toIso8601String(),
        'check_out': endTime.toIso8601String(),
      };
    }).toList();

    try {
      final response = await http.post(
        Uri.parse(_attendanceBulkUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(attendanceRecords),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إضافة الحضور لجميع العمال بنجاح')));
        await fetchPresence();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فشل في إضافة الحضور')));
      }
    } catch (e) {
      print('Error adding attendance: $e');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('حدث خطأ أثناء الإضافة')));
    }
  }

  void _showDatePickerForAllEmployees() async {
    DateTime? selectedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
      locale: const Locale('ar', 'AR'),
    );

    if (selectedDate != null) {
      await _addAttendanceForAllEmployees(selectedDate);
    }
  }

  Future<void> _fetchSalaryYears() async {
    try {
      final monthlyRes = await http.get(Uri.parse('${globalServerUri.toString()}/employees/attendance/years?type=monthly'));
      final pieceRes = await http.get(Uri.parse('${globalServerUri.toString()}/employees/attendance/years?type=piece'));
      
      Set<int> allYears = {};
      if (monthlyRes.statusCode == 200) allYears.addAll((jsonDecode(monthlyRes.body) as List).cast<int>());
      if (pieceRes.statusCode == 200) allYears.addAll((jsonDecode(pieceRes.body) as List).cast<int>());
      
      final sortedYears = allYears.toList()..sort((a, b) => b.compareTo(a));
      
      setState(() {
        _salaryYears = sortedYears;
        if (sortedYears.isNotEmpty) {
          selectedSalaryYear = sortedYears.contains(DateTime.now().year) ? DateTime.now().year : sortedYears.first;
          _fetchSalaryMonths();
        }
      });
    } catch (e) {
      print('Error fetching salary years: $e');
    }
  }

  Future<void> _fetchSalaryMonths() async {
    if (selectedSalaryYear == null) return;
    try {
      final type = selectedSalariesTab == 0 ? 'monthly' : 'piece';
      final res = await http.get(Uri.parse('${globalServerUri.toString()}/employees/attendance/months?year=$selectedSalaryYear&type=$type'));
      if (res.statusCode == 200) {
        final months = (jsonDecode(res.body) as List).cast<String>();
        setState(() {
          _salaryMonths = months;
          if (months.isNotEmpty) {
            final currentMonth = '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';
            selectedSalaryMonth = months.contains(currentMonth) ? currentMonth : months.first;
          }
        });
      }
    } catch (e) {
      print('Error fetching salary months: $e');
    }
  }

  String _monthLabel(String ym) {
    const months = ['جانفي', 'فيفري', 'مارس', 'أفريل', 'ماي', 'جوان', 'جويلية', 'أوت', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
    final parts = ym.split('-');
    final m = int.parse(parts[1]);
    return '${months[m - 1]} ${parts[0]}';
  }

  Future<void> fetchSalariesData() async {
  if (selectedSalaryMonth == null) return;
  setState(() => salaryLoading = true);

  final monthlyRes = await http.get(Uri.parse('${globalServerUri.toString()}/employees/attendance/monthly?month=$selectedSalaryMonth'));
  monthlyAttendance = monthlyRes.statusCode == 200 ? jsonDecode(monthlyRes.body) : [];

  final pieceRes = await http.get(Uri.parse('${globalServerUri.toString()}/employees/attendance/piece?month=$selectedSalaryMonth'));
  pieceAttendance = pieceRes.statusCode == 200 ? jsonDecode(pieceRes.body) : [];

  final debtRes = await http.get(Uri.parse('${globalServerUri.toString()}/employees/debts/monthly-summary?month=$selectedSalaryMonth'));
  Map<int, num> debtData = {};
  if (debtRes.statusCode == 200) {
    final decoded = jsonDecode(debtRes.body) as Map<String, dynamic>;
    decoded.forEach((key, value) {
      final id = int.tryParse(key) ?? 0;
      final debt = value is num ? value : num.tryParse(value.toString()) ?? 0;
      debtData[id] = debt;
    });
  }

  // Fetch loan data for the selected month
  // In fetchSalariesData
final loanRes = await http.get(Uri.parse(
    '${globalServerUri.toString()}/employees/loans/monthly-summary?month=$selectedSalaryMonth'));
loanData = {};
if (loanRes.statusCode == 200) {
  final decoded = jsonDecode(loanRes.body) as Map<String, dynamic>;
  decoded.forEach((key, value) {
    final id = int.tryParse(key) ?? 0;
    loanData[id] = {
      'monthly_due': value['monthly_due'] is num ? value['monthly_due'] : num.tryParse(value['monthly_due'].toString()) ?? 0,
      'total_loan': value['total_loan'] is num ? value['total_loan'] : num.tryParse(value['total_loan'].toString()) ?? 0,
      'remaining_loan': value['remaining_loan'] is num ? value['remaining_loan'] : num.tryParse(value['remaining_loan'].toString()) ?? 0,
    };
  });
}

  monthlyTableRows = _calculateMonthlySalaryRows(debtData);
  pieceTableRows = _calculatePieceSalaryRows(debtData);

  setState(() => salaryLoading = false);
}

  List<Map<String, dynamic>> _calculateMonthlySalaryRows(Map<int, num> debtData) {
    final List<Map<String, dynamic>> rows = [];

    // Parse selected month into year & month
    final parts = selectedSalaryMonth!.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);

    // Compute number of days in this month
    final daysInMonth = DateTime(year, month + 1, 0).day;

    // Count working days (exclude Fridays)
    int workingDays = 0;
    for (var d = 1; d <= daysInMonth; d++) {
      if (DateTime(year, month, d).weekday != DateTime.friday) {
        workingDays++;
      }
    }

    // Standard hours = workingDays × 8
    final standardHours = workingDays * 8.0;

    for (final emp in monthlyAttendance) {
      final empId = emp['employee_id'] as int;
      final fullName = '${emp['first_name'] ?? ''} ${emp['last_name'] ?? ''}';
      final salary = (emp['salary'] ?? 0).toDouble();
      final records = List.from(emp['attendance'] ?? []);

      // Sum up actual hours worked
      double totalHours = 0;
      for (final att in records) {
        final inTime = att['check_in'] != null
            ? DateTime.tryParse(att['check_in']!)
            : null;
        final outTime = att['check_out'] != null
            ? DateTime.tryParse(att['check_out']!)
            : null;
        if (inTime != null && outTime != null) {
          totalHours += outTime.difference(inTime).inMinutes / 60.0;
        }
      }

      // Pro-rated salary
      final calculatedSalary = standardHours > 0
          ? salary * (totalHours / standardHours)
          : 0.0;

      // Loan deduction
      final loan = loanData[empId] ??
          {'total_loan': 0, 'monthly_due': 0, 'remaining_loan': 0};
      final monthlyDue = loan['monthly_due']!;

      // Debt deduction
      final debt = debtData[empId] ?? 0;

      rows.add({
        'full_name': fullName,
        'salary': salary,
        'total_hours': totalHours,
        'standard_hours': standardHours,
        'calculated_salary': calculatedSalary,
        'total_loan': loan['total_loan']!,
        'monthly_due': monthlyDue,
        'debt': debt,
        'remaining_loan': loan['remaining_loan']!,
        'final_salary': calculatedSalary - monthlyDue - debt,
      });
    }

    return rows;
  }

  List<Map<String, dynamic>> _calculatePieceSalaryRows(Map<int, num> debtData) {
  final List<Map<String, dynamic>> rows = [];
  for (final emp in pieceAttendance) {
    final empId = emp['employee_id'] as int;
    final fullName = '${emp['first_name'] ?? ''} ${emp['last_name'] ?? ''}';
    final records = List.from(emp['piece_records'] ?? []);
    int totalQty = 0;
    double totalSalary = 0;
    for (final rec in records) {
      final int qty = (rec['quantity'] as num?)?.toInt() ?? 0;
      final price = (rec['piece_price'] ?? 0).toDouble();
      totalQty += qty;
      totalSalary += price * qty;
    }
    final loan = loanData[empId] ??
        {'total_loan': 0, 'monthly_due': 0, 'remaining_loan': 0};
    final monthlyDue = loan['monthly_due']!;
    final debt = debtData[empId] ?? 0;
    
    rows.add({
      'full_name': fullName,
      'total_qty': totalQty,
      'total_salary': totalSalary,
      'total_loan': loan['total_loan']!,
      'monthly_due': monthlyDue,
      'debt': debt,
      'remaining_loan': loan['remaining_loan']!,
      'final_salary': totalSalary - monthlyDue - debt,
    });
  }
  return rows;
}
  Future<void> _exportSalaryTableAsPdf({required bool isMonthly}) async {
    final pdf = pw.Document();
    final monthLabel = _monthLabel(selectedSalaryMonth!);
    final tableTitle = isMonthly
        ? 'رواتب العمال (شهرياً) - $monthLabel'
        : 'رواتب العمال (قطعة) - $monthLabel';
    final tableData = isMonthly ? monthlyTableRows : pieceTableRows;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (context) => [
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Header(
                  level: 0,
                  child: pw.Text(
                    tableTitle,
                    style: pw.TextStyle(
                      font: _arabicFont,
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.Table.fromTextArray(
                  headers: isMonthly
                      ? ['الاسم الكامل', 'الراتب', 'مجموع الساعات', 'الراتب الفعلي', 'السلف', 'الديون', 'الراتب النهائي']
                      : ['الاسم الكامل', 'مجموع القطع', 'مجموع الأجر', 'السلف', 'الديون', 'الراتب النهائي'],
                  data: tableData.map((row) {
                    return isMonthly
                        ? [
                            row['full_name'],
                            row['salary'].toStringAsFixed(2),
                            row['total_hours'].toStringAsFixed(2),
                            row['calculated_salary'].toStringAsFixed(2),
                            row['monthly_due'].toStringAsFixed(2),
                            row['debt'].toStringAsFixed(2),
                            row['final_salary'].toStringAsFixed(2),
                          ]
                        : [
                            row['full_name'],
                            row['total_qty'].toString(),
                            row['total_salary'].toStringAsFixed(2),
                            row['monthly_due'].toStringAsFixed(2),
                            row['debt'].toStringAsFixed(2),
                            row['final_salary'].toStringAsFixed(2),
                          ];
                  }).toList(),
                  headerStyle: pw.TextStyle(
                    font: _arabicFont,
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 14,
                  ),
                  cellStyle: pw.TextStyle(
                    font: _arabicFont,
                    fontSize: 12,
                  ),
                  cellAlignment: pw.Alignment.center,
                  headerDecoration: pw.BoxDecoration(color: PdfColors.grey300),
                  border: pw.TableBorder.all(width: 0.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final bytes = await pdf.save();
    
      // Desktop: let user choose install directory to save PDF
      final String? outputDir = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'اختر مجلد الحفظ',
      );
      if (outputDir != null) {
        final filePath = '$outputDir/رواتب_$monthLabel.pdf';
        final file = io.File(filePath);
        await file.writeAsBytes(bytes);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم حفظ الملف في $filePath')),
        );
      }
    
  }


  Future<void> fetchEmployees() async {
    setState(() => isLoading = true);
    final response = await http.get(Uri.parse(_employeesUrl));
    if (response.statusCode == 200) {
      employees = jsonDecode(response.body);
      _filteredEmployees = employees;
    } else {
      employees = [];
      _filteredEmployees = [];
    }
    setState(() => isLoading = false);
  }

  Future<void> addOrEditEmployee({Map? initial}) async {
    final result = await showDialog<Map>(
      context: context,
      builder: (context) => EmployeeDialog(initial: initial),
    );
    if (result != null) {
      try {
        if (initial == null) {
          await http.post(
            Uri.parse(_employeesUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(result),
          );
        } else {
          await http.put(
            Uri.parse('${globalServerUri.toString()}/employees/${initial['id']}'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(result),
          );
        }
        await fetchEmployees();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فشل في إضافة/تعديل العامل')));
      }
    }
  }

  Future<void> deleteEmployee(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف العامل'),
        content: const Text('هل أنت متأكد من حذف هذا العامل؟'),
        actions: [
          TextButton(child: const Text('إلغاء'), onPressed: () => Navigator.pop(context, false)),
          TextButton(child: const Text('حذف'), onPressed: () => Navigator.pop(context, true)),
        ],
      ),
    );
    if (ok == true) {
      await http.delete(Uri.parse('${globalServerUri.toString()}/employees/$id'));
      await fetchEmployees();
    }
  }

  Widget _buildInfoTable() {
    final sellerType = selectedInfoTab == 0 ? 'month' : 'piece';
    final filtered = _filteredEmployees.where((e) => e['seller_type'] == sellerType).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text('إضافة عامل جديد', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary),
                onPressed: () => addOrEditEmployee(),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _infoSearchController,
                  decoration: InputDecoration(
                    hintText: 'بحث بالاسم، الجوال، العنوان، الراتب أو المهنة',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                  ? const Center(child: Text('لا يوجد عمال هنا'))
                  : Center(
                      child: Align(
            alignment: Alignment.topCenter,
            child:Scrollbar(
                        controller: infoTableController,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: infoTableController,
                          scrollDirection: Axis.vertical,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              headingRowColor: MaterialStateProperty.all(Theme.of(context).colorScheme.primary),
                              columns: [
                                const DataColumn(label: Text('الاسم الكامل', style: TextStyle(color: Colors.white))),
                                const DataColumn(label: Text('الجوال', style: TextStyle(color: Colors.white))),
                                const DataColumn(label: Text('العنوان', style: TextStyle(color: Colors.white))),
                                if (selectedInfoTab == 0) const DataColumn(label: Text('الراتب', style: TextStyle(color: Colors.white))),
                                const DataColumn(label: Text('المهنه', style: TextStyle(color: Colors.white))),
                                const DataColumn(label: Text('إجراءات', style: TextStyle(color: Colors.white))),
                              ],
                              rows: filtered.map<DataRow>((emp) {
                                return DataRow(cells: [
                                  DataCell(Text('${emp['first_name']} ${emp['last_name']}')),
                                  DataCell(Text(emp['phone'] ?? '')),
                                  DataCell(Text(emp['address'] ?? '')),
                                  if (selectedInfoTab == 0) DataCell(Text(emp['salary']?.toString() ?? '')),
                                  DataCell(Text(emp['role'] ?? '')),
                                  DataCell(Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: Icon(Icons.edit, color: Theme.of(context).colorScheme.primary),
                                        onPressed: () => addOrEditEmployee(initial: emp),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete, color: Colors.red),
                                        onPressed: () => deleteEmployee(emp['id']),
                                      ),
                                    ],
                                  )),
                                ]);
                              }).toList(),
                            ),
                          ),
                        ),
                      ),),
                    ),
        ),
      ],
    );
  }

  Future<void> fetchAttendance() async {
  if (selectedYearMonth == null) return;
  setState(() {
    attLoading = true;
    attEmployees = [];
    _filteredAttEmployees = []; // Add this
    selectedEmployeeId = null;
  });

  final url = attType == 0
      ? '${globalServerUri.toString()}/employees/attendance/monthly?month=$selectedYearMonth'
      : '${globalServerUri.toString()}/employees/attendance/piece?month=$selectedYearMonth';

  final res = await http.get(Uri.parse(url));
  if (res.statusCode == 200) {
    attEmployees = jsonDecode(res.body);
    _filteredAttEmployees = attEmployees; // Add this
    selectedEmployeeId = attEmployees.isNotEmpty ? attEmployees.first['employee_id'] : null;
  } else {
    attEmployees = [];
    _filteredAttEmployees = []; // Add this
    selectedEmployeeId = null;
  }
  setState(() => attLoading = false);
}

void _filterAttendanceEmployees() {
  final query = _presenceSearchController.text.toLowerCase();
  setState(() {
    if (query.isEmpty) {
      _filteredAttEmployees = attEmployees;
    } else {
      _filteredAttEmployees = attEmployees.where((emp) {
        final fullName = '${emp['first_name']} ${emp['last_name']}'.toLowerCase();
        return fullName.contains(query);
      }).toList();
    }
  });
}

  Future<void> fetchPresence() async {
  setState(() {
    attLoading = true;
    attEmployees = [];
  });

  // build base URL
  var url = _attendanceUrl;

  // selectedPresenceMonth is already "YYYY-MM"
  if (selectedPresenceMonth != null) {
    url += '?month=$selectedPresenceMonth';
    if (selectedPresenceDay != null) {
      url += '&day=${selectedPresenceDay!.toString().padLeft(2, '0')}';
    }
  }

  final res = await http.get(Uri.parse(url));
  if (res.statusCode == 200) {
    attEmployees      = jsonDecode(res.body);
    _filteredPresence = attEmployees;
  } else {
    attEmployees      = [];
    _filteredPresence = [];
  }
  setState(() => attLoading = false);
}


  Future<void> fetchDataSection() async {
    setState(() => isDataLoading = true);

    final empRes = await http.get(Uri.parse(_employeesUrl));
    allEmployees = empRes.statusCode == 200 ? jsonDecode(empRes.body) : [];

final pieceEmpRes = await http.get(
  Uri.parse(_pieceEmployeesUrl)
);    pieceEmployees = pieceEmpRes.statusCode == 200 ? jsonDecode(pieceEmpRes.body) : [];

    final modelRes = await http.get(Uri.parse(_modelsUrl));
    allModels = modelRes.statusCode == 200 ? jsonDecode(modelRes.body) : [];

    final loanRes = await http.get(Uri.parse(_loansUrl));
    loans = loanRes.statusCode == 200 ? jsonDecode(loanRes.body) : [];
    _filteredLoans = loans;

    final pieceRes = await http.get(Uri.parse(_piecesUrl));
    pieces = pieceRes.statusCode == 200 ? jsonDecode(pieceRes.body) : [];
    _filteredPieces = pieces;

    final debtRes = await http.get(Uri.parse(_debtsUrl));
    debts = debtRes.statusCode == 200 ? jsonDecode(debtRes.body) : [];
    _filteredDebts = debts;

    setState(() => isDataLoading = false);
  }

  Future<void> addOrEditLoan({ Map? initial }) async {
  int? employeeId = initial?['employee_id'] as int?;
  final amountController = TextEditingController(text: initial?['amount']?.toString() ?? '');
  int duration = initial?['duration_months'] as int? ?? 1;
  DateTime selectedDate = initial != null && initial['loan_date'] != null
      ? DateTime.parse(initial['loan_date'])
      : DateTime.now();
  final _formKey = GlobalKey<FormState>();

  // State for "blocked until" logic:
  bool hasActiveLoan = false;
  DateTime? nextAvailable;

  String _norm(String s) {
    // lower + remove Arabic diacritics & tatweel + collapse spaces
    return s.toLowerCase()
        .replaceAll(RegExp(r'[\u064B-\u0652\u0640]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Iterable<Map<String, dynamic>> _searchEmployeesSync(String q) {
    final base = allEmployees.cast<Map<String, dynamic>>();
    if (q.isEmpty) return base.take(30);

    final nq = _norm(q);
    int score(Map<String, dynamic> e) {
      final name  = _norm('${e['first_name'] ?? ''} ${e['last_name'] ?? ''}');
      final phone = _norm('${e['phone'] ?? ''}');
      final role  = _norm('${e['role'] ?? ''}');

      if (name.startsWith(nq))  return 0;
      if (phone.startsWith(nq)) return 1;
      if (name.contains(nq))    return 2;
      if (phone.contains(nq))   return 3;
      if (role.contains(nq))    return 4;
      return 5;
    }

    final list = base
        .where((e) {
          final name  = _norm('${e['first_name'] ?? ''} ${e['last_name'] ?? ''}');
          final phone = _norm('${e['phone'] ?? ''}');
          final role  = _norm('${e['role'] ?? ''}');
          return name.contains(nq) || phone.contains(nq) || role.contains(nq);
        })
        .toList();

    list.sort((a, b) {
      final sa = score(a), sb = score(b);
      if (sa != sb) return sa.compareTo(sb);
      final an = _norm('${a['first_name'] ?? ''} ${a['last_name'] ?? ''}');
      final bn = _norm('${b['first_name'] ?? ''} ${b['last_name'] ?? ''}');
      return an.compareTo(bn);
    });

    return list.take(30);
  }

  await showDialog(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, setState) {
        // If dialog opened for NEW loan and an employeeId was pre-filled (rare), check block
        if (employeeId != null && initial == null && nextAvailable == null) {
          () async {
            final res = await http.get(
              Uri.parse('${globalServerUri.toString()}/employees/loans/check/$employeeId')
            );
            if (res.statusCode == 200) {
              final d = jsonDecode(res.body);
              setState(() {
                hasActiveLoan = d['has_active_loan'] as bool? ?? false;
                nextAvailable = d['next_available_date'] != null
                    ? DateTime.parse(d['next_available_date'])
                    : null;
              });
            }
          }();
        }

        return AlertDialog(
          title: Text(initial == null ? 'إضافة سلف' : 'تعديل سلف'),
          content: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Employee searchable selector (sync + ranked + Arabic-friendly)
                Autocomplete<Map<String, dynamic>>(
                  optionsBuilder: (TextEditingValue tev) {
                    return _searchEmployeesSync(tev.text);
                  },
                  displayStringForOption: (opt) => '${opt['first_name']} ${opt['last_name']}',
                  fieldViewBuilder: (
                    BuildContext context,
                    TextEditingController tc,
                    FocusNode fn,
                    VoidCallback onFieldSubmitted,
                  ) {
                    // Pre-fill when editing
                    if (initial != null && tc.text.isEmpty && employeeId != null) {
                      final initEmp = allEmployees
                          .cast<Map<String, dynamic>>()
                          .firstWhere((e) => e['id'] == employeeId, orElse: () => {});
                      if (initEmp.isNotEmpty) {
                        tc.text = '${initEmp['first_name']} ${initEmp['last_name']}';
                      }
                    }

                    return TextFormField(
                      controller: tc,
                      focusNode: fn,
                      decoration: InputDecoration(
                        labelText: 'العامل',
                        suffixIcon: tc.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  tc.clear();
                                  setState(() {
                                    employeeId = null;
                                    hasActiveLoan = false;
                                    nextAvailable = null;
                                  });
                                },
                              )
                            : null,
                      ),
                      onChanged: (_) {
                        // typing invalidates previous selection
                        if (employeeId != null) {
                          setState(() {
                            employeeId = null;
                            hasActiveLoan = false;
                            nextAvailable = null;
                          });
                        }
                      },
                      onEditingComplete: onFieldSubmitted, // keep default behavior
                      onFieldSubmitted: (_) {
                        // If user presses Enter with a unique match, pick it.
                        final matches = _searchEmployeesSync(tc.text).toList();
                        if (matches.length == 1) {
                          final only = matches.first;
                          setState(() {
                            employeeId = only['id'] as int;
                          });
                        }
                      },
                      validator: (_) => employeeId == null ? 'يرجى اختيار العامل' : null,
                    );
                  },
                  onSelected: (Map<String, dynamic> option) async {
                    setState(() {
                      employeeId = option['id'] as int;
                      hasActiveLoan = false;
                      nextAvailable = null;
                    });

                    // Check loan status for new loans
                    if (initial == null) {
                      final res = await http.get(
                        Uri.parse('${globalServerUri.toString()}/employees/loans/check/$employeeId')
                      );
                      if (res.statusCode == 200) {
                        final d = jsonDecode(res.body);
                        setState(() {
                          hasActiveLoan = d['has_active_loan'] as bool? ?? false;
                          nextAvailable = d['next_available_date'] != null
                              ? DateTime.parse(d['next_available_date'])
                              : null;
                        });
                        if (hasActiveLoan && nextAvailable != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('لا يمكن منح سلف جديدة حتى ${nextAvailable!.toLocal().toString().substring(0,10)}'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        }
                      }
                    }
                  },
                  optionsViewBuilder: (
                    BuildContext context,
                    AutocompleteOnSelected<Map<String, dynamic>> onSelected,
                    Iterable<Map<String, dynamic>> options,
                  ) {
                    return Align(
                      alignment: Alignment.topRight,
                      child: Material(
                        elevation: 4.0,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 240, maxWidth: 320),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: options.length,
                            itemBuilder: (BuildContext context, int index) {
                              final opt = options.elementAt(index);
                              return ListTile(
                                title: Text('${opt['first_name']} ${opt['last_name']}'),
                                subtitle: Text('${opt['phone'] ?? ''} - ${opt['role'] ?? ''}'),
                                onTap: () => onSelected(opt),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),

                if (hasActiveLoan && nextAvailable != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'لا يمكن منح سلف جديدة حتى ${nextAvailable!.toLocal().toString().substring(0,10)}',
                    style: const TextStyle(color: Colors.orange),
                  ),
                ],

                TextFormField(
                  controller: amountController,
                  decoration: const InputDecoration(labelText: 'المبلغ'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'مطلوب';
                    final numVal = num.tryParse(v);
                    if (numVal == null || numVal <= 0) return 'يجب أن يكون رقمًا إيجابيًا';
                    return null;
                  },
                ),

                DropdownButtonFormField<int>(
                  value: duration,
                  decoration: const InputDecoration(labelText: 'المدة (شهور)'),
                  items: List.generate(24, (i) => i + 1)
                      .map((m) => DropdownMenuItem<int>(value: m, child: Text('$m')))
                      .toList(),
                  onChanged: (v) => setState(() => duration = v!),
                  validator: (v) => v == null || v <= 0 ? 'يرجى اختيار مدة صالحة' : null,
                ),

                const SizedBox(height: 8),
                Text('تاريخ السلف: ${selectedDate.toLocal().toString().substring(0, 10)}'),
                ElevatedButton(
                  child: const Text('اختر التاريخ'),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                      locale: const Locale('ar', 'AR'),
                    );
                    if (picked != null && picked != selectedDate) {
                      setState(() => selectedDate = picked);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                if (!_formKey.currentState!.validate()) return;

                if (hasActiveLoan && initial == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('لا يمكن إضافة سلف جديدة - العامل لديه سلف نشطة'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                final data = {
                  'employee_id'     : employeeId,
                  'amount'          : num.tryParse(amountController.text) ?? 0,
                  'duration_months' : duration,
                  'loan_date'       : selectedDate.toIso8601String(),
                };

                try {
                  if (initial == null) {
                    await http.post(
                      Uri.parse(_loansUrl),
                      headers: {'Content-Type': 'application/json'},
                      body: jsonEncode(data),
                    );
                  } else {
                    await http.put(
                      Uri.parse('${globalServerUri.toString()}/employees/loans/${initial!['id']}'),
                      headers: {'Content-Type': 'application/json'},
                      body: jsonEncode(data),
                    );
                  }
                  Navigator.pop(context);
                  await fetchDataSection();
                } catch (_) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('فشل حفظ السلف')),
                  );
                }
              },
              child: const Text('حفظ'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
          ],
        );
      },
    ),
  );
}


  Future<void> addOrEditPiece({ Map? initial }) async {
  int? employeeId = initial?['employee_id'] as int?;
  int? modelId    = initial?['model_id']    as int?;
  final qtyController   = TextEditingController(text: initial?['quantity']?.toString()   ?? '');
  final priceController = TextEditingController(text: initial?['piece_price']?.toString() ?? '');
  DateTime selectedDate = initial != null && initial['record_date'] != null
      ? DateTime.parse(initial['record_date'])
      : DateTime.now();
  final _formKey = GlobalKey<FormState>();

  await showDialog(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, setState) {
        return AlertDialog(
          title: Text(initial == null ? 'إضافة قطعة' : 'تعديل قطعة'),
          content: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ◀️ LOCAL autocomplete over pieceEmployees, properly cast
                Autocomplete<Map<String, dynamic>>(
                  optionsBuilder: (TextEditingValue textEditingValue) {
                    final q = textEditingValue.text.toLowerCase();
                    return pieceEmployees
                        .cast<Map<String, dynamic>>()            // cast to the right type
                        .where((emp) {
                          final name = '${emp['first_name']} ${emp['last_name']}'.toLowerCase();
                          return name.contains(q);
                        });
                  },
                  displayStringForOption: (opt) => '${opt['first_name']} ${opt['last_name']}',
                  fieldViewBuilder: (context, tc, fn, onSubmitted) {
                    if (initial != null && tc.text.isEmpty) {
                      final initEmp = pieceEmployees
                          .cast<Map<String, dynamic>>()
                          .firstWhere((e) => e['id'] == employeeId, orElse: () => {});
                      if (initEmp.isNotEmpty) {
                        tc.text = '${initEmp['first_name']} ${initEmp['last_name']}';
                      }
                    }
                    return TextFormField(
                      controller: tc,
                      focusNode: fn,
                      decoration: InputDecoration(
                        labelText: 'العامل',
                        suffixIcon: tc.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  tc.clear();
                                  setState(() => employeeId = null);
                                },
                              )
                            : null,
                      ),
                      validator: (_) => employeeId == null ? 'يرجى اختيار العامل' : null,
                    );
                  },
                  onSelected: (opt) => setState(() => employeeId = opt['id'] as int),
                  optionsViewBuilder: (context, onSelected, options) {
                    return Align(
                      alignment: Alignment.topRight,
                      child: Material(
                        elevation: 4,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 200, maxWidth: 300),
                          child: ListView.builder(
                            itemCount: options.length,
                            itemBuilder: (ctx, i) {
                              final opt = options.elementAt(i);
                              return ListTile(
                                title: Text('${opt['first_name']} ${opt['last_name']}'),
                                subtitle: Text('${opt['phone'] ?? ''} - ${opt['role'] ?? ''}'),
                                onTap: () => onSelected(opt),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),

                // model dropdown
                DropdownButtonFormField<int>(
                  value: modelId,
                  decoration: const InputDecoration(labelText: 'الموديل'),
                  items: allModels.map((m) {
                    return DropdownMenuItem(
                      value: m['id'] as int,
                      child: Text(m['name']),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => modelId = v),
                  validator: (v) => v == null ? 'يرجى اختيار الموديل' : null,
                ),

                // quantity
                TextFormField(
                  controller: qtyController,
                  decoration: const InputDecoration(labelText: 'الكمية'),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    if (n == null || n <= 0) return 'يجب أن تكون كمية إيجابية';
                    return null;
                  },
                ),

                // price
                TextFormField(
                  controller: priceController,
                  decoration: const InputDecoration(labelText: 'سعر القطعة'),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    final n = num.tryParse(v ?? '');
                    if (n == null || n <= 0) return 'يجب أن يكون سعر إيجابي';
                    return null;
                  },
                ),

                // date picker
                Text('تاريخ القطعة: ${selectedDate.toLocal().toString().split(' ')[0]}'),
                ElevatedButton(
                  child: const Text('اختر التاريخ'),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                      locale: const Locale('ar', 'AR'),
                    );
                    if (picked != null) setState(() => selectedDate = picked);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: const Text('إلغاء'),
              onPressed: () => Navigator.pop(context),
            ),
            ElevatedButton(
              child: const Text('حفظ'),
              onPressed: () {
                if (!_formKey.currentState!.validate()) return;
                final data = {
                  'employee_id': employeeId,
                  'model_id'   : modelId,
                  'quantity'   : int.tryParse(qtyController.text)   ?? 0,
                  'piece_price': num.tryParse(priceController.text) ?? 0,
                  'record_date': selectedDate.toIso8601String(),
                };
                if (initial == null) {
                  http.post(
                    Uri.parse(_piecesUrl),
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode(data),
                  );
                } else {
                  http.put(
                    Uri.parse('${globalServerUri.toString()}/employees/pieces/${initial['id']}'),
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode(data),
                  );
                }
                Navigator.pop(context);
                fetchDataSection();
              },
            ),
          ],
        );
      },
    ),
  );
}

  Future<void> deleteLoan(int id) async {
    await http.delete(Uri.parse('${globalServerUri.toString()}/employees/loans/$id'));
    await fetchDataSection();
  }

  Future<void> deletePiece(int id) async {
    await http.delete(Uri.parse('${globalServerUri.toString()}/employees/pieces/$id'));
    await fetchDataSection();
  }

  Future<void> addOrEditDebt({Map? initial}) async {
  int? employeeId = initial?['employee_id'] as int?;
  final amountController = TextEditingController(text: initial?['amount']?.toString() ?? '');
  DateTime selectedDate = initial != null && initial['debt_date'] != null
      ? DateTime.parse(initial['debt_date'])
      : DateTime.now();
  final _formKey = GlobalKey<FormState>();

  String _norm(String s) {
    return s.toLowerCase()
        .replaceAll(RegExp(r'[\u064B-\u0652\u0640]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Iterable<Map<String, dynamic>> _searchEmployeesSync(String q) {
    final base = allEmployees.cast<Map<String, dynamic>>();
    if (q.isEmpty) return base.take(30);

    final nq = _norm(q);
    int score(Map<String, dynamic> e) {
      final name  = _norm('${e['first_name'] ?? ''} ${e['last_name'] ?? ''}');
      final phone = _norm('${e['phone'] ?? ''}');
      final role  = _norm('${e['role'] ?? ''}');
      if (name.startsWith(nq))  return 0;
      if (phone.startsWith(nq)) return 1;
      if (name.contains(nq))    return 2;
      if (phone.contains(nq))   return 3;
      if (role.contains(nq))    return 4;
      return 5;
    }

    final list = base
        .where((e) {
          final name  = _norm('${e['first_name'] ?? ''} ${e['last_name'] ?? ''}');
          final phone = _norm('${e['phone'] ?? ''}');
          final role  = _norm('${e['role'] ?? ''}');
          return name.contains(nq) || phone.contains(nq) || role.contains(nq);
        })
        .toList();

    list.sort((a, b) {
      final sa = score(a), sb = score(b);
      if (sa != sb) return sa.compareTo(sb);
      final an = _norm('${a['first_name'] ?? ''} ${a['last_name'] ?? ''}');
      final bn = _norm('${b['first_name'] ?? ''} ${b['last_name'] ?? ''}');
      return an.compareTo(bn);
    });

    return list.take(30);
  }

  await showDialog(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, setState) {
        return AlertDialog(
          title: Text(initial == null ? 'إضافة دين' : 'تعديل دين'),
          content: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Autocomplete<Map<String, dynamic>>(
                  optionsBuilder: (TextEditingValue tev) {
                    return _searchEmployeesSync(tev.text);
                  },
                  displayStringForOption: (opt) => '${opt['first_name']} ${opt['last_name']}',
                  fieldViewBuilder: (
                    BuildContext context,
                    TextEditingController tc,
                    FocusNode fn,
                    VoidCallback onFieldSubmitted,
                  ) {
                    if (initial != null && tc.text.isEmpty && employeeId != null) {
                      final initEmp = allEmployees
                          .cast<Map<String, dynamic>>()
                          .firstWhere((e) => e['id'] == employeeId, orElse: () => {});
                      if (initEmp.isNotEmpty) {
                        tc.text = '${initEmp['first_name']} ${initEmp['last_name']}';
                      }
                    }

                    return TextFormField(
                      controller: tc,
                      focusNode: fn,
                      decoration: InputDecoration(
                        labelText: 'العامل',
                        suffixIcon: tc.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  tc.clear();
                                  setState(() => employeeId = null);
                                },
                              )
                            : null,
                      ),
                      onChanged: (_) {
                        if (employeeId != null) setState(() => employeeId = null);
                      },
                      onEditingComplete: onFieldSubmitted,
                      onFieldSubmitted: (_) {
                        final matches = _searchEmployeesSync(tc.text).toList();
                        if (matches.length == 1) {
                          setState(() => employeeId = matches.first['id'] as int);
                        }
                      },
                      validator: (_) => employeeId == null ? 'يرجى اختيار العامل' : null,
                    );
                  },
                  onSelected: (Map<String, dynamic> option) {
                    setState(() => employeeId = option['id'] as int);
                  },
                  optionsViewBuilder: (
                    BuildContext context,
                    AutocompleteOnSelected<Map<String, dynamic>> onSelected,
                    Iterable<Map<String, dynamic>> options,
                  ) {
                    return Align(
                      alignment: Alignment.topRight,
                      child: Material(
                        elevation: 4.0,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 240, maxWidth: 320),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: options.length,
                            itemBuilder: (BuildContext context, int index) {
                              final opt = options.elementAt(index);
                              return ListTile(
                                title: Text('${opt['first_name']} ${opt['last_name']}'),
                                subtitle: Text('${opt['phone'] ?? ''} - ${opt['role'] ?? ''}'),
                                onTap: () => onSelected(opt),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),

                TextFormField(
                  controller: amountController,
                  decoration: const InputDecoration(labelText: 'المبلغ'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'مطلوب';
                    final numVal = num.tryParse(v);
                    if (numVal == null || numVal <= 0) return 'يجب أن يكون رقمًا إيجابيًا';
                    return null;
                  },
                ),

                Text('تاريخ الدين: ${selectedDate.toLocal().toString().substring(0, 10)}'),
                ElevatedButton(
                  child: const Text('اختر التاريخ'),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                      locale: const Locale('ar', 'AR'),
                    );
                    if (picked != null && picked != selectedDate) {
                      setState(() => selectedDate = picked);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                if (!_formKey.currentState!.validate()) return;
                final data = {
                  'employee_id': employeeId,
                  'amount'     : num.tryParse(amountController.text) ?? 0,
                  'debt_date'  : selectedDate.toIso8601String(),
                };

                try {
                  if (initial == null) {
                    await http.post(
                      Uri.parse(_debtsUrl),
                      headers: {'Content-Type': 'application/json'},
                      body: jsonEncode(data),
                    );
                  } else {
                    await http.put(
                      Uri.parse('${globalServerUri.toString()}/employees/debts/${initial['id']}'),
                      headers: {'Content-Type': 'application/json'},
                      body: jsonEncode(data),
                    );
                  }
                  Navigator.pop(context);
                  await fetchDataSection();
                } catch (_) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('فشل حفظ الدين')),
                  );
                }
              },
              child: const Text('حفظ'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
          ],
        );
      },
    ),
  );
}


  Future<void> deleteDebt(int id) async {
    await http.delete(Uri.parse('${globalServerUri.toString()}/employees/debts/$id'));
    await fetchDataSection();
  }

  Widget _buildDataSection() {
    final tabs = ['الديون', 'القطع', 'السلف', 'الحضور'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(tabs.length, (i) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: ChoiceChip(
                label: Text(tabs[i]),
                selected: selectedDataTab == i,
                selectedColor: Theme.of(context).colorScheme.primary,
                labelStyle: TextStyle(color: selectedDataTab == i ? Colors.white : Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold),
                onSelected: (_) {
                  setState(() => selectedDataTab = i);
                  if (i == 3) fetchPresence();
                },
              ),
            );
          }),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: selectedDataTab < 3
              ? (isDataLoading
                  ? const Center(child: CircularProgressIndicator())
                  : selectedDataTab == 0
                      ? _buildLoansTable()
                      : selectedDataTab == 1
                          ? _buildPiecesTable()
                          : _buildDebtsTable())
              : _buildPresenceDataSection(),
        ),
      ],
    );
  }

  Widget _buildLoansTable() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text('إضافة دين', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary),
                onPressed: () => addOrEditLoan(),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _loansSearchController,
                  decoration: InputDecoration(
                    hintText: 'بحث بالاسم، المبلغ أو التاريخ',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: Scrollbar(
              controller: loansTableController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: loansTableController,
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: MaterialStateProperty.all(Theme.of(context).colorScheme.primary),
                    columns: const [
                      DataColumn(label: Text('العامل', style: TextStyle(color: Colors.white))),
                      DataColumn(label: Text('المبلغ', style: TextStyle(color: Colors.white))),
                      DataColumn(label: Text('المدة (شهور)', style: TextStyle(color: Colors.white))),
                      DataColumn(label: Text('التاريخ', style: TextStyle(color: Colors.white))),
                      DataColumn(label: Text('خيارات', style: TextStyle(color: Colors.white))),
                    ],
                    rows: _filteredLoans.map((loan) {
                      return DataRow(cells: [
                        DataCell(Text(loan['employee_name'] ?? '')),
                        DataCell(Text(loan['amount'].toString())),
                        DataCell(Text('${loan['duration_months'] ?? 1}')),
                        DataCell(Text(loan['loan_date']?.substring(0, 10) ?? '')),
                        DataCell(Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(icon: Icon(Icons.edit, color: Theme.of(context).colorScheme.primary), onPressed: () => addOrEditLoan(initial: loan)),
                            IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => deleteLoan(loan['id'])),
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
      ],
    );
  }

  Widget _buildPiecesTable() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text('إضافة قطعة', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary),
                onPressed: () => addOrEditPiece(),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _piecesSearchController,
                  decoration: InputDecoration(
                    hintText: 'بحث بالعامل، الموديل، الكمية أو السعر',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: Scrollbar(
              controller: piecesTableController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: piecesTableController,
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: MaterialStateProperty.all(Theme.of(context).colorScheme.primary),
                    columns: const [
                      DataColumn(label: Text('العامل', style: TextStyle(color: Colors.white))),
                      DataColumn(label: Text('الموديل', style: TextStyle(color: Colors.white))),
                      DataColumn(label: Text('الكمية', style: TextStyle(color: Colors.white))),
                      DataColumn(label: Text('سعر القطعة', style: TextStyle(color: Colors.white))),
                      DataColumn(label: Text('التاريخ', style: TextStyle(color: Colors.white))),
                      DataColumn(label: Text('خيارات', style: TextStyle(color: Colors.white))),
                    ],
                    rows: _filteredPieces.map((piece) {
                      return DataRow(cells: [
                        DataCell(Text(piece['employee_name'] ?? '')),
                        DataCell(Text(piece['model_name'] ?? '')),
                        DataCell(Text(piece['quantity'].toString())),
                        DataCell(Text(piece['piece_price'].toString())),
                        DataCell(Text(piece['record_date']?.substring(0, 10) ?? '')),
                        DataCell(Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(icon: Icon(Icons.edit, color: Theme.of(context).colorScheme.primary), onPressed: () => addOrEditPiece(initial: piece)),
                            IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => deletePiece(piece['id'])),
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
      ],
    );
  }

  Widget _buildDebtsTable() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text('إضافة السلف', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary),
                onPressed: () => addOrEditDebt(),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _debtsSearchController,
                  decoration: InputDecoration(
                    hintText: 'بحث بالعامل، المبلغ أو التاريخ',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: Scrollbar(
              controller: debtsTableController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: debtsTableController,
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: MaterialStateProperty.all(Theme.of(context).colorScheme.primary),
                    columns: const [
                      DataColumn(label: Text('العامل', style: TextStyle(color: Colors.white))),
                      DataColumn(label: Text('المبلغ', style: TextStyle(color: Colors.white))),
                      DataColumn(label: Text('التاريخ', style: TextStyle(color: Colors.white))),
                      DataColumn(label: Text('خيارات', style: TextStyle(color: Colors.white))),
                    ],
                    rows: _filteredDebts.map((debt) {
                      return DataRow(cells: [
                        DataCell(Text(debt['employee_name'] ?? '')),
                        DataCell(Text((debt['amount'] as num).toStringAsFixed(2))),
                        DataCell(Text(debt['debt_date']?.substring(0, 10) ?? '')),
                        DataCell(Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(icon: Icon(Icons.edit, color: Theme.of(context).colorScheme.primary), onPressed: () => addOrEditDebt(initial: debt)),
                            IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => deleteDebt(debt['id'])),
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
      ],
    );
  }

  String _fmtTime(String? s) {
    if (s == null) return '';
    final t = s.indexOf('T');
    if (t >= 0 && s.length >= t + 6) return s.substring(t + 1, t + 6);
    if (s.length >= 5 && s.contains(':')) return s.substring(0, 5);
    return s;
  }

  Widget _buildPresenceDataSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            children: [
              Row(
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.group_add, color: Colors.white),
                    label: const Text('إضافة حضور للجميع', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary),
                    onPressed: _showDatePickerForAllEmployees,
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.person_add, color: Colors.white),
                    label: const Text('إضافة حضور فردي', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary),
                    onPressed: () async {
                      final result = await showDialog<Map<String, dynamic>>(
                        context: context,
                        builder: (_) => AttendanceDialog(
                          initialMonth: selectedPresenceMonth ?? DateTime.now().toIso8601String().substring(0, 7),
                          employees: allEmployees.where((e) => e['seller_type'] == 'month').toList(),
                        ),
                      );
                      if (result != null) {
                        await http.post(
                          Uri.parse(_attendanceUrl),
                          headers: {'Content-Type': 'application/json'},
                          body: jsonEncode(result),
                        );
                        await fetchPresence();
                      }
                    },
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _presenceSearchController,
                      decoration: InputDecoration(
                        hintText: 'بحث بالعامل أو التاريخ',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ),
              if (_presenceYears.isNotEmpty) const SizedBox(height: 16),
              if (_presenceYears.isNotEmpty)
                Row(
                  children: [
                    const Text('السنة:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    DropdownButton<int>(
                      value: selectedPresenceYear,
                      items: _presenceYears.map((y) => DropdownMenuItem(value: y, child: Text('$y'))).toList(),
                      onChanged: (val) async {
                        setState(() => selectedPresenceYear = val);
                        await _fetchPresenceMonths();
                      },
                    ),
                    const SizedBox(width: 24),
                    const Text('الشهر:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: selectedPresenceMonth,
                      items: _presenceMonths.map((m) => DropdownMenuItem(value: m, child: Text(_monthLabel(m).split(' ').first))).toList(),
                      onChanged: (val) async {
                        setState(() => selectedPresenceMonth = val);
                        await _fetchPresenceDays();
                      },
                    ),
                    const SizedBox(width: 24),
                    const Text('اليوم:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    DropdownButton<int?>(
  value: selectedPresenceDay,
  items: [
    const DropdownMenuItem<int?>(
      value: null,
      child: Text('الكل'),
    ),
    ..._presenceDays.map((d) => DropdownMenuItem<int?>(
      value: d,
      child: Text(d.toString()),
    )),
  ],
  onChanged: (val) {
    setState(() => selectedPresenceDay = val);
    fetchPresence();
  },
),


                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: attLoading
              ? const Center(child: CircularProgressIndicator())
              : _filteredPresence.isEmpty
                  ? const Center(child: Text('لا يوجد بيانات حضور'))
                  : Align(
                      alignment: Alignment.topCenter,
                      child: Scrollbar(
                        controller: presenceTableController,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: presenceTableController,
                          scrollDirection: Axis.vertical,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              headingRowColor: MaterialStateProperty.all(Theme.of(context).colorScheme.primary),
                              columns: const [
                                DataColumn(label: Text('العامل', style: TextStyle(color: Colors.white))),
                                DataColumn(label: Text('التاريخ', style: TextStyle(color: Colors.white))),
                                DataColumn(label: Text('دخول', style: TextStyle(color: Colors.white))),
                                DataColumn(label: Text('خروج', style: TextStyle(color: Colors.white))),
                                DataColumn(label: Text('إجراءات', style: TextStyle(color: Colors.white))),
                              ],
                              rows: _filteredPresence.map<DataRow>((rec) {
                                return DataRow(cells: [
                                  DataCell(Text(rec['employee_name'] ?? '')),
                                  DataCell(Text(rec['date'] ?? '')),
                                  DataCell(Text(_fmtTime(rec['check_in'] as String?))),
                                  DataCell(Text(_fmtTime(rec['check_out'] as String?))),
                                  DataCell(Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: Icon(Icons.edit, color: Theme.of(context).colorScheme.primary),
                                        onPressed: () async {
                                          final edited = await showDialog<Map<String, dynamic>>(
                                            context: context,
                                            builder: (_) => AttendanceDialog(
                                              initialMonth: selectedPresenceMonth ?? DateTime.now().toIso8601String().substring(0, 7),
                                              employees: allEmployees.where((e) => e['seller_type'] == 'month').toList(),
                                              initial: rec,
                                            ),
                                          );
                                          if (edited != null) {
                                            await http.put(
                                              Uri.parse('${globalServerUri.toString()}/employees/attendance/${rec['attendance_id']}'),
                                              headers: {'Content-Type': 'application/json'},
                                              body: jsonEncode(edited),
                                            );
                                            await fetchPresence();
                                          }
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete, color: Colors.red),
                                        onPressed: () async {
                                          await http.delete(Uri.parse('${globalServerUri.toString()}/employees/attendance/${rec['attendance_id']}'));
                                          await fetchPresence();
                                        },
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
      ],
    );
  }

  @override
Widget build(BuildContext context) {
  final mainTabs = ['معلومات', 'البيانات', 'ادارة البيانات', 'رواتب العمال'];
  final infoTabs = ['شهرياً', 'قطعة'];
  final salariesTabs = ['شهرياً', 'قطعة'];

  return Directionality(
    textDirection: TextDirection.rtl,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top-level tabs
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(mainTabs.length, (i) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: ChoiceChip(
                label: Text(mainTabs[i]),
                selected: selectedTab == i,
                selectedColor: Theme.of(context).colorScheme.primary,
                labelStyle: TextStyle(
                  color: selectedTab == i
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
                onSelected: (_) async {
                  setState(() => selectedTab = i);

                  if (i == 1) {
                    // البيانات (attendance)
                    if (_availableYears.isEmpty) {
                      await _fetchAttendanceYears();
                    }
                    if (_availableYears.isNotEmpty) {
                      await fetchAttendance();
                    }
                  } else if (i == 2) {
                    // ادارة البيانات (loans/pieces/debts)
                    await fetchDataSection();
                  } else if (i == 3) {
                    // رواتب العمال (salaries)
                    if (_salaryYears.isEmpty) {
                      await _fetchSalaryYears();
                    }
                    if (selectedSalaryMonth != null) {
                      await fetchSalariesData();
                    }
                  }
                },
              ),
            );
          }),
        ),
        const SizedBox(height: 16),

        // Content area
        Expanded(
          child: selectedTab == 0
              // معلومات
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Sub-tabs: شهرياً / قطعة
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(infoTabs.length, (i) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: ChoiceChip(
                            label: Text(infoTabs[i]),
                            selected: selectedInfoTab == i,
                            selectedColor:
                                Theme.of(context).colorScheme.primary,
                            labelStyle: TextStyle(
                              color: selectedInfoTab == i
                                  ? Colors.white
                                  : Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.bold,
                            ),
                            onSelected: (_) =>
                                setState(() => selectedInfoTab = i),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 16),
                    Expanded(child: _buildInfoTable()),
                  ],
                )

              // بيانات الحضور
              : selectedTab == 1
                  ? _buildAttendanceSection()

                  // ادارة البيانات
                  : selectedTab == 2
                      ? _buildDataSection()

                      // رواتب العمال
                      : _buildSalariesSection(salariesTabs),
        ),
      ],
    ),
  );
}


  Widget _buildSalariesSection(List<String> salariesTabs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(salariesTabs.length, (i) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: ChoiceChip(
              label: Text(salariesTabs[i]),
              selected: selectedSalariesTab == i,
              selectedColor: Theme.of(context).colorScheme.primary,
              labelStyle: TextStyle(color: selectedSalariesTab == i ? Colors.white : Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold),
              onSelected: (_) async {
                setState(() => selectedSalariesTab = i);
                await _fetchSalaryMonths();
                if (selectedSalaryMonth != null) await fetchSalariesData();
              },
            ),
          )),
        ),
        const SizedBox(height: 16),
        if (_salaryYears.isNotEmpty)
          Row(
            children: [
              const SizedBox(width: 8),
              const Text('السنة:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: selectedSalaryYear,
                items: _salaryYears.map((y) => DropdownMenuItem(value: y, child: Text('$y'))).toList(),
                onChanged: (val) async {
                  setState(() => selectedSalaryYear = val);
                  await _fetchSalaryMonths();
                  if (selectedSalaryMonth != null) await fetchSalariesData();
                },
              ),
              const SizedBox(width: 24),
              const Text('الشهر:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: selectedSalaryMonth,
                items: _salaryMonths.map((m) => DropdownMenuItem(value: m, child: Text(_monthLabel(m).split(' ').first))).toList(),
                onChanged: (val) {
                  setState(() => selectedSalaryMonth = val);
                  fetchSalariesData();
                },
              ),
              const Spacer(),
              ElevatedButton.icon(
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('تصدير PDF'),
                onPressed: salaryLoading ? null : () => _exportSalaryTableAsPdf(isMonthly: selectedSalariesTab == 0),
              ),
            ],
          ),
        const SizedBox(height: 16),
        Expanded(
          child: salaryLoading
              ? const Center(child: CircularProgressIndicator())
              : selectedSalariesTab == 0
                  ? _buildMonthlySalaryTable()
                  : _buildPieceSalaryTable(),
        ),
      ],
    );
  }

 Widget _buildMonthlySalaryTable() {
  if (monthlyTableRows.isEmpty) return const Center(child: Text('لا يوجد بيانات رواتب هنا'));
  return Align(
            alignment: Alignment.topCenter,
            child: Scrollbar(
      controller: monthlySalaryTableController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: monthlySalaryTableController,
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: MaterialStateProperty.all(Theme.of(context).colorScheme.primary),
            columns: const [
              DataColumn(label: Text('الاسم الكامل', style: TextStyle(color: Colors.white))),
              DataColumn(label: Text('الراتب', style: TextStyle(color: Colors.white))),
              DataColumn(label: Text('مجموع الساعات', style: TextStyle(color: Colors.white))),
              DataColumn(label: Text('الراتب الفعلي', style: TextStyle(color: Colors.white))),
              DataColumn(label: Text('الديون', style: TextStyle(color: Colors.white))),
              DataColumn(label: Text('السلف', style: TextStyle(color: Colors.white))),
              DataColumn(label: Text('الراتب النهائي', style: TextStyle(color: Colors.white))),
            ],
            rows: monthlyTableRows.map<DataRow>((row) {
              return DataRow(cells: [
                DataCell(Text(row['full_name'].toString())),
                DataCell(Text((row['salary'] as num?)?.toStringAsFixed(2) ?? '0.00')),
                DataCell(Text((row['total_hours'] as num?)?.toStringAsFixed(2) ?? '0.00')),
                DataCell(Text((row['calculated_salary'] as num?)?.toStringAsFixed(2) ?? '0.00')),
                DataCell(Text((row['monthly_due'] as num?)?.toStringAsFixed(2) ?? '0.00')), // Changed from row['loan']
                DataCell(Text((row['debt'] as num?)?.toStringAsFixed(2) ?? '0.00')),
                DataCell(Text((row['final_salary'] as num?)?.toStringAsFixed(2) ?? '0.00')),
              ]);
            }).toList(),
          ),
        ),
      ),
    ),
  );
}
  Widget _buildPieceSalaryTable() {
  if (pieceTableRows.isEmpty) return const Center(child: Text('لا يوجد بيانات رواتب هنا'));
  return Align(
            alignment: Alignment.topCenter,
            child: Scrollbar(
      controller: pieceSalaryTableController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: pieceSalaryTableController,
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: MaterialStateProperty.all(Theme.of(context).colorScheme.primary),
            columns: const [
              DataColumn(label: Text('الاسم الكامل', style: TextStyle(color: Colors.white))),
              DataColumn(label: Text('مجموع القطع', style: TextStyle(color: Colors.white))),
              DataColumn(label: Text('مجموع الأجر', style: TextStyle(color: Colors.white))),
              DataColumn(label: Text('الديون', style: TextStyle(color: Colors.white))),
              DataColumn(label: Text('السلف', style: TextStyle(color: Colors.white))),
              DataColumn(label: Text('الراتب النهائي', style: TextStyle(color: Colors.white))),
            ],
            rows: pieceTableRows.map<DataRow>((row) {
              return DataRow(cells: [
                DataCell(Text(row['full_name'].toString())),
                DataCell(Text((row['total_qty'] as num?)?.toString() ?? '0')),
                DataCell(Text((row['total_salary'] as num?)?.toStringAsFixed(2) ?? '0.00')),
                DataCell(Text((row['monthly_due'] as num?)?.toStringAsFixed(2) ?? '0.00')), // Changed from row['loan']
                DataCell(Text((row['debt'] as num?)?.toStringAsFixed(2) ?? '0.00')),
                DataCell(Text((row['final_salary'] as num?)?.toStringAsFixed(2) ?? '0.00')),
              ]);
            }).toList(),
          ),
        ),
      ),
    ),
  );
}
  Widget _buildAttendanceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ChoiceChip(
              label: const Text('شهرياً'),
              selected: attType == 0,
              selectedColor: Theme.of(context).colorScheme.primary,
              labelStyle: TextStyle(color: attType == 0 ? Colors.white : Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold),
              onSelected: (_) async {
                setState(() => attType = 0);
                await _fetchAttendanceYears();
                if (_availableYears.isNotEmpty) await fetchAttendance();
              },
            ),
            const SizedBox(width: 12),
            ChoiceChip(
              label: const Text('قطعة'),
              selected: attType == 1,
              selectedColor: Theme.of(context).colorScheme.primary,
              labelStyle: TextStyle(color: attType == 1 ? Colors.white : Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold),
              onSelected: (_) async {
                setState(() => attType = 1);
                await _fetchAttendanceYears();
                if (_availableYears.isNotEmpty) await fetchAttendance();
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_availableYears.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                const Text('السنة:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: selectedYear,
                  items: _availableYears.map((y) => DropdownMenuItem(value: y, child: Text('$y'))).toList(),
                  onChanged: (y) async {
                    if (y == null) return;
                    setState(() => selectedYear = y);
                    await _fetchAttendanceMonths();
                    if (selectedYearMonth != null) await fetchAttendance();
                  },
                ),
                const SizedBox(width: 24),
                const Text('الشهر:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: selectedYearMonth,
                  items: _availableMonths.map((ym) => DropdownMenuItem(value: ym, child: Text(_monthLabel(ym).split(' ').first))).toList(),
                  onChanged: (ym) {
                    if (ym == null) return;
                    setState(() => selectedYearMonth = ym);
                    fetchAttendance();
                  },
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: _availableYears.isEmpty
              ? const Center(child: Text('لا توجد بيانات حضور'))
              : Row(
                  children: [
                    Container(
                      width: 400,
                      decoration: BoxDecoration(color: Colors.grey[100]),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                Text('العمال', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[800])),
                                const SizedBox(height: 16),
                                TextField(
  controller: _presenceSearchController,
  onChanged: (_) => _filterAttendanceEmployees(),
  decoration: InputDecoration(
    hintText: 'بحث بالعامل',
    prefixIcon: const Icon(Icons.search),
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
  ),
),

                              ],
                            ),
                          ),
                          Expanded(
                            child: attLoading
                                ? const Center(child: CircularProgressIndicator())
                                : attEmployees.isEmpty
                                    ? const Center(child: Text('لا يوجد عمال'))
                                    : ListView.builder(
  padding: const EdgeInsets.symmetric(horizontal: 8),
  itemCount: _filteredAttEmployees.length,
  itemBuilder: (ctx, i) {
    final emp = _filteredAttEmployees[i];
    final isSel = selectedEmployeeId == emp['employee_id'];
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: isSel ? 4 : 1,
      color: isSel ? Colors.grey[100] : Colors.white,
      child: ListTile(
        selected: isSel,
        title: Text('${emp['first_name']} ${emp['last_name']}', 
          style: TextStyle(fontWeight: isSel ? FontWeight.bold : FontWeight.normal)),
        onTap: () => setState(() => selectedEmployeeId = emp['employee_id']),
      ),
    );
  },
),

                          ),
                        ],
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: () {
                          if (selectedEmployeeId == null) return const Center(child: Text('اختر عامل'));
                          final selectedEmp = attEmployees.firstWhere((e) => e['employee_id'] == selectedEmployeeId, orElse: () => null);
                          if (selectedEmp == null) return const Center(child: Text('اختر عامل'));
                          return attType == 0
                              ? _MonthlyAttendanceTable(selectedEmp, controller: monthlyAttTableController, month: selectedYearMonth!)
                              : _PieceAttendanceTable(selectedEmp, controller: pieceAttTableController);
                        }(),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _MonthlyAttendanceTable extends StatelessWidget {
  final Map emp;
  final ScrollController controller;
  final String month;

  const _MonthlyAttendanceTable(this.emp, {required this.controller, required this.month, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final parts = month.split('-');
    final year = int.parse(parts[0]);
    final m = int.parse(parts[1]);
    final daysInMonth = DateTime(year, m + 1, 0).day;

    int workingDays = 0;
    for (int d = 1; d <= daysInMonth; d++) {
      if (DateTime(year, m, d).weekday != DateTime.friday) workingDays++;
    }

    final salary = (emp['salary'] ?? 0).toDouble();
    final standardHours = workingDays * 8.0;
    final hourRate = standardHours > 0 ? salary / standardHours : 0.0;

    final records = List<Map<String, dynamic>>.from(emp['attendance'] ?? []);
    double totalHrs = 0;
    double totalPay = 0;
    final rows = records.map<DataRow>((att) {
      final inTime = att['check_in'] != null ? DateTime.tryParse(att['check_in'] as String) : null;
      final outTime = att['check_out'] != null ? DateTime.tryParse(att['check_out'] as String) : null;
      double hrs = 0;
      if (inTime != null && outTime != null) hrs = outTime.difference(inTime).inMinutes / 60.0;
      final dayPay = hourRate * hrs;
      totalHrs += hrs;
      totalPay += dayPay;

      return DataRow(cells: [
        DataCell(Text(att['date']?.substring(0, 10) ?? '')),
        DataCell(Text(inTime != null ? '${inTime.hour}:${inTime.minute.toString().padLeft(2, '0')}' : '')),
        DataCell(Text(outTime != null ? '${outTime.hour}:${outTime.minute.toString().padLeft(2, '0')}' : '')),
        DataCell(Text(hrs.toStringAsFixed(2))),
        DataCell(Text(hourRate.toStringAsFixed(2))),
        DataCell(Text(dayPay.toStringAsFixed(2))),
      ]);
    }).toList();

    return Column(
      children: [
        Text('${emp['first_name']} ${emp['last_name']}', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: Scrollbar(
              controller: controller,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: controller,
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: MaterialStateProperty.all(Theme.of(context).colorScheme.primary),
                    columns: const [
                      DataColumn(label: Text('اليوم', style: TextStyle(color: Colors.white))),
                      DataColumn(label: Text('دخول', style: TextStyle(color: Colors.white))),
                      DataColumn(label: Text('خروج', style: TextStyle(color: Colors.white))),
                      DataColumn(label: Text('ساعات', style: TextStyle(color: Colors.white))),
                      DataColumn(label: Text('سعر الساعة', style: TextStyle(color: Colors.white))),
                      DataColumn(label: Text('أجر اليوم', style: TextStyle(color: Colors.white))),
                    ],
                    rows: rows,
                  ),
                ),
              ),
            ),
          ),
        ),
        const Divider(),
        Card(
          margin: const EdgeInsets.all(8.0),
          color: Theme.of(context).colorScheme.primary,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'الإجمالي: مجموع الساعات: ${totalHrs.toStringAsFixed(2)}, مجموع الأجر: ${totalPay.toStringAsFixed(2)}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }
}

class _PieceAttendanceTable extends StatelessWidget {
  final Map emp;
  final ScrollController controller;
  const _PieceAttendanceTable(this.emp, {required this.controller});

  @override
  Widget build(BuildContext context) {
    final records = List.from(emp['piece_records'] ?? []);
    int totalQty = 0;
    double totalPrice = 0;

    final rows = records.map<DataRow>((rec) {
      final int qty = (rec['quantity'] as num?)?.toInt() ?? 0;
      final price = (rec['piece_price'] ?? 0).toDouble();
      final rowTotal = qty * price;
      totalQty += qty;
      totalPrice += rowTotal;
      return DataRow(cells: [
        DataCell(Text(rec['model_name'] ?? '')),
        DataCell(Text(qty.toString())),
        DataCell(Text(price.toStringAsFixed(2))),
        DataCell(Text(rowTotal.toStringAsFixed(2))),
      ]);
    }).toList();

    return Column(
      children: [
        Text('${emp['first_name']} ${emp['last_name']}', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: Scrollbar(
              controller: controller,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: controller,
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: MaterialStateProperty.all(Theme.of(context).colorScheme.primary),
                    columns: const [
                      DataColumn(label: Text('الموديل', style: TextStyle(color: Colors.white))),
                      DataColumn(label: Text('الكمية', style: TextStyle(color: Colors.white))),
                      DataColumn(label: Text('سعر القطعة', style: TextStyle(color: Colors.white))),
                      DataColumn(label: Text('الإجمالي', style: TextStyle(color: Colors.white))),
                    ],
                    rows: rows,
                  ),
                ),
              ),
            ),
          ),
        ),
        const Divider(),
        Card(
          margin: const EdgeInsets.all(8.0),
          color: Theme.of(context).colorScheme.primary,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'الإجمالي: مجموع القطع: $totalQty, مجموع السعر: ${totalPrice.toStringAsFixed(2)}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }
}

class AttendanceDialog extends StatefulWidget {
  final String initialMonth;
  final List<dynamic> employees;
  final Map<String, dynamic>? initial;

  const AttendanceDialog({Key? key, required this.initialMonth, required this.employees, this.initial}) : super(key: key);

  @override
  State<AttendanceDialog> createState() => _AttendanceDialogState();
}

TimeOfDay _parseTime(String? s) {
  if (s == null) return const TimeOfDay(hour: 8, minute: 0);
  if (s.contains('T')) {
    final dt = DateTime.tryParse(s);
    if (dt != null) return TimeOfDay(hour: dt.hour, minute: dt.minute);
  }
  if (RegExp(r'^\d{2}:\d{2}$').hasMatch(s)) {
    final parts = s.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }
  return const TimeOfDay(hour: 8, minute: 0);
}

class _AttendanceDialogState extends State<AttendanceDialog> {
  int? employeeId;
  DateTime date = DateTime.now();
  TimeOfDay checkIn = TimeOfDay.now();
  TimeOfDay checkOut = TimeOfDay.now();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      final init = widget.initial!;
      employeeId = init['employee_id'] as int?;
      date = DateTime.parse(init['date'] as String);
      checkIn = _parseTime(init['check_in']);
      checkOut = _parseTime(init['check_out']);
    } else {
      employeeId = widget.employees.isNotEmpty ? widget.employees.first['id'] as int : null;
      date = DateTime.now();
      checkIn = const TimeOfDay(hour: 8, minute: 0);
      checkOut = const TimeOfDay(hour: 16, minute: 0);
    }
  }

  // Helper method to fetch employees by search query
  Future<List<dynamic>> _fetchEmployeesByQuery(String searchQuery) async {
    if (searchQuery.isEmpty) return widget.employees;
    
    return widget.employees.where((emp) {
      final fullName = '${emp['first_name']} ${emp['last_name']}'.toLowerCase();
      return fullName.contains(searchQuery.toLowerCase());
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'إضافة حضور' : 'تعديل حضور'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Employee searchable selector
            Autocomplete<Map<String, dynamic>>(
              optionsBuilder: (TextEditingValue textEditingValue) async {
                final searchQuery = textEditingValue.text.toLowerCase();
                final employees = await _fetchEmployeesByQuery(searchQuery);
                return employees.cast<Map<String, dynamic>>();
              },
              displayStringForOption: (option) => '${option['first_name']} ${option['last_name']}',
              fieldViewBuilder: (
                BuildContext context,
                TextEditingController textEditingController,
                FocusNode focusNode,
                VoidCallback onFieldSubmitted,
              ) {
                // Set initial value if editing
                if (widget.initial != null && textEditingController.text.isEmpty) {
                  final initialEmp = widget.employees.firstWhere(
                    (e) => e['id'] == employeeId,
                    orElse: () => {},
                  );
                  if (initialEmp.isNotEmpty) {
                    textEditingController.text = '${initialEmp['first_name']} ${initialEmp['last_name']}';
                  }
                }
                
                return TextFormField(
                  controller: textEditingController,
                  focusNode: focusNode,
                  decoration: InputDecoration(
                    labelText: 'العامل',
                    suffixIcon: textEditingController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              textEditingController.clear();
                              setState(() => employeeId = null);
                            },
                          )
                        : null,
                  ),
                  validator: (v) => employeeId == null ? 'يرجى اختيار العامل' : null,
                );
              },
              onSelected: (Map<String, dynamic> option) {
                setState(() => employeeId = option['id'] as int);
              },
              optionsViewBuilder: (
                BuildContext context,
                AutocompleteOnSelected<Map<String, dynamic>> onSelected,
                Iterable<Map<String, dynamic>> options,
              ) {
                return Align(
                  alignment: Alignment.topRight,
                  child: Material(
                    elevation: 4.0,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 200, maxWidth: 300),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: options.length,
                        itemBuilder: (BuildContext context, int index) {
                          final option = options.elementAt(index);
                          return GestureDetector(
                            onTap: () => onSelected(option),
                            child: ListTile(
                              title: Text('${option['first_name']} ${option['last_name']}'),
                              subtitle: Text('${option['phone'] ?? ''} - ${option['role'] ?? ''}'),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
            
            ListTile(
              title: Text('التاريخ: ${date.toLocal().toIso8601String().substring(0, 10)}'),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                  locale: const Locale('ar', 'AR'),
                );
                if (picked != null) setState(() => date = picked);
              },
            ),
            ListTile(
              title: Text('دخول: ${checkIn.format(context)}'),
              trailing: const Icon(Icons.access_time),
              onTap: () async {
                final t = await showTimePicker(context: context, initialTime: checkIn);
                if (t != null) setState(() => checkIn = t);
              },
            ),
            ListTile(
              title: Text('خروج: ${checkOut.format(context)}'),
              trailing: const Icon(Icons.access_time),
              onTap: () async {
                final t = await showTimePicker(context: context, initialTime: checkOut);
                if (t != null) setState(() => checkOut = t);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              if (date.isAfter(DateTime.now())) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يمكن اختيار تاريخ في المستقبل')));
                return;
              }
              final checkInDt = DateTime(date.year, date.month, date.day, checkIn.hour, checkIn.minute);
              final checkOutDt = DateTime(date.year, date.month, date.day, checkOut.hour, checkOut.minute);
              if (checkOutDt.isBefore(checkInDt)) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('وقت الخروج يجب أن يكون بعد وقت الدخول')));
                return;
              }
              final payload = <String, dynamic>{
                'employee_id': employeeId,
                'date': date.toIso8601String().substring(0, 10),
                'check_in': checkInDt.toIso8601String(),
                'check_out': checkOutDt.toIso8601String(),
              };
              if (widget.initial != null && widget.initial!['attendance_id'] != null) payload['attendance_id'] = widget.initial!['attendance_id'];
              Navigator.pop<Map<String, dynamic>>(context, payload);
            }
          },
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}

class EmployeeDialog extends StatefulWidget {
  final Map? initial;
  const EmployeeDialog({this.initial, super.key});
  @override
  State<EmployeeDialog> createState() => _EmployeeDialogState();
}

class _EmployeeDialogState extends State<EmployeeDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController firstName, lastName, phone, address, salary, photoUrl;
  String sellerType = 'month';
  String? role;

  static const monthlyRoles = ['خياطة', 'فينيسيون'];
  static const pieceRoles = ['كوي', 'خياطة', 'قص'];

  @override
  void initState() {
    super.initState();
    final init = widget.initial ?? {};
    firstName = TextEditingController(text: init['first_name'] ?? '');
    lastName = TextEditingController(text: init['last_name'] ?? '');
    phone = TextEditingController(text: init['phone'] ?? '');
    address = TextEditingController(text: init['address'] ?? '');
    salary = TextEditingController(text: init['salary']?.toString() ?? '');
    photoUrl = TextEditingController(text: init['photo_url'] ?? '');
    sellerType = init['seller_type'] ?? 'month';
    role = init['role'] ?? (sellerType == 'month' ? monthlyRoles.first : pieceRoles.first);
  }

  @override
  Widget build(BuildContext context) {
    final isMonthly = sellerType == 'month';
    final allowedRoles = isMonthly ? monthlyRoles : pieceRoles;

    return AlertDialog(
      title: Text(widget.initial == null ? 'إضافة عامل' : 'تعديل بيانات العامل'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text('شهرياً'),
                      value: 'month',
                      groupValue: sellerType,
                      onChanged: (v) => setState(() {
                        sellerType = v!;
                        role = monthlyRoles.first;
                      }),
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text('قطعة'),
                      value: 'piece',
                      groupValue: sellerType,
                      onChanged: (v) => setState(() {
                        sellerType = v!;
                        role = pieceRoles.first;
                      }),
                    ),
                  ),
                ],
              ),
              TextFormField(
                controller: firstName,
                decoration: const InputDecoration(labelText: 'الاسم الأول'),
                validator: (v) => v == null || v.isEmpty ? 'مطلوب' : null,
              ),
              TextFormField(
                controller: lastName,
                decoration: const InputDecoration(labelText: 'الاسم الأخير'),
                validator: (v) => v == null || v.isEmpty ? 'مطلوب' : null,
              ),
              TextFormField(
                controller: phone,
                decoration: const InputDecoration(labelText: 'رقم الجوال'),
                keyboardType: TextInputType.phone,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'مطلوب';
                  if (!RegExp(r'^0[0-9]{9}$').hasMatch(v)) return 'يجب أن يبدأ بـ 0 ويكون 10 أرقام';
                  return null;
                },
              ),
              TextFormField(
                controller: address,
                decoration: const InputDecoration(labelText: 'العنوان'),
                validator: (v) => v == null || v.isEmpty ? 'مطلوب' : null,
              ),
              if (isMonthly)
                TextFormField(
                  controller: salary,
                  decoration: const InputDecoration(labelText: 'الراتب الشهري'),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'مطلوب';
                    final numVal = num.tryParse(v);
                    if (numVal == null || numVal <= 0) return 'يجب أن يكون رقم إيجابي';
                    return null;
                  },
                ),
              DropdownButtonFormField<String>(
                value: role,
                decoration: const InputDecoration(labelText: 'المهنه'),
                items: allowedRoles.map((r) => DropdownMenuItem<String>(value: r, child: Text(r))).toList(),
                onChanged: (v) => setState(() => role = v),
                validator: (v) => v == null ? 'مطلوب' : null,
              ),
              // TextFormField(
              //   controller: photoUrl,
              //   decoration: const InputDecoration(labelText: 'رابط الصورة (اختياري)'),
              // ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        ElevatedButton(
          child: const Text('حفظ'),
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop<Map>(context, {
                'first_name': firstName.text.trim(),
                'last_name': lastName.text.trim(),
                'phone': phone.text.trim(),
                'address': address.text.trim(),
                'seller_type': sellerType,
                'salary': isMonthly ? double.tryParse(salary.text) ?? 0 : null,
                'role': role,
                'photo_url': photoUrl.text.trim().isEmpty ? null : photoUrl.text.trim(),
              });
            }
          },
        ),
      ],
    );
  }
}