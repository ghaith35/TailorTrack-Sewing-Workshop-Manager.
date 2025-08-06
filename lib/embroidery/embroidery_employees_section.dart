import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../main.dart';

class EmbroideryEmployeesSection extends StatefulWidget {
  const EmbroideryEmployeesSection({super.key});
  @override
  State<EmbroideryEmployeesSection> createState() => _EmbroideryEmployeesSectionState();
}

class _EmbroideryEmployeesSectionState extends State<EmbroideryEmployeesSection> {
  int selectedTab = 0;
  int selectedInfoTab = 0;
  int attType = 0;
  int selectedDataTab = 0;
  int selectedSalariesTab = 0;
  String get _apiUrl => '${globalServerUri.toString()}/embroidery-employees';

  // Attendance year/month selection
  List<int> _availableYears = [];
  List<String> _availableMonths = [];
  int? selectedYear;
  String? selectedYearMonth;
  List<int> _presenceDays = [];
  int? selectedDay;

  // Salary year/month selection
  List<int> _salaryYears = [];
  List<String> _salaryMonths = [];
  int? selectedSalaryYear;
  String? selectedSalaryMonth;

  int? selectedEmployeeId;
  List<dynamic> attEmployees = [];
  bool attLoading = false;
  List<dynamic> employees = [];
  bool isLoading = false;
  List<dynamic> loans = [];
  List<dynamic> pieces = [];
  List<dynamic> debts = [];
  List<dynamic> allEmployees = [];
  List<dynamic> pieceEmployees = [];
  List<dynamic> allModels = [];
  bool isDataLoading = false;
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

  @override
  void initState() {
    super.initState();
    _infoSearchController.addListener(_filterEmployees);
    _loansSearchController.addListener(_filterLoans);
    _piecesSearchController.addListener(_filterPieces);
    _debtsSearchController.addListener(_filterDebts);
    _presenceSearchController.addListener(_filterPresence);
    _initializeData();
  }

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

  Future<void> _initializeData() async {
    await fetchEmployees();
    await _fetchAttendanceYears();
    await _fetchSalaryYears();
    await fetchDataSection();
    if (_availableYears.isNotEmpty) {
      await _fetchAttendanceMonths();
      await _fetchPresenceDays();
      await fetchAttendance();
    }
    if (_salaryYears.isNotEmpty) await fetchSalariesData();
  }

  // Filter methods
  void _filterEmployees() {
    final query = _infoSearchController.text.toLowerCase();
    setState(() {
      _filteredEmployees = query.isEmpty
          ? employees
          : employees.where((emp) {
              final fullName = '${emp['first_name']} ${emp['last_name']}'.toLowerCase();
              final phone = (emp['phone'] ?? '').toLowerCase();
              final address = (emp['address'] ?? '').toLowerCase();
              final salary = emp['salary']?.toString() ?? '';
              final shiftHours = emp['shift_hours']?.shiftHours.contains(query);
              return fullName.contains(query) ||
                  phone.contains(query) ||
                  address.contains(query) ||
                  salary.contains(query) ||
                  shiftHours.contains(query);
            }).toList();
    });
  }

  void _filterLoans() {
    final query = _loansSearchController.text.toLowerCase();
    setState(() {
      _filteredLoans = query.isEmpty
          ? loans
          : loans.where((loan) {
              final empName = (loan['employee_name'] ?? '').toLowerCase();
              final amount = loan['amount'].toString();
              final date = (loan['loan_date'] ?? '').toLowerCase();
              return empName.contains(query) || amount.contains(query) || date.contains(query);
            }).toList();
    });
  }

  void _filterPieces() {
    final query = _piecesSearchController.text.toLowerCase();
    setState(() {
      _filteredPieces = query.isEmpty
          ? pieces
          : pieces.where((piece) {
              final empName = (piece['employee_name'] ?? '').toLowerCase();
              final modelName = (piece['model_name'] ?? '').toLowerCase();
              final qty = piece['quantity'].toString();
              final price = piece['piece_price'].toString();
              return empName.contains(query) ||
                  modelName.contains(query) ||
                  qty.contains(query) ||
                  price.contains(query);
            }).toList();
    });
  }

  void _filterDebts() {
    final query = _debtsSearchController.text.toLowerCase();
    setState(() {
      _filteredDebts = query.isEmpty
          ? debts
          : debts.where((debt) {
              final empName = (debt['employee_name'] ?? '').toLowerCase();
              final amount = debt['amount'].toString();
              final date = (debt['debt_date'] ?? '').toLowerCase();
              return empName.contains(query) || amount.contains(query) || date.contains(query);
            }).toList();
    });
  }

  void _filterPresence() {
    final query = _presenceSearchController.text.toLowerCase();
    setState(() {
      _filteredPresence = query.isEmpty
          ? attEmployees
          : attEmployees.where((att) {
              final empName = (att['employee_name'] ?? '').toLowerCase();
              final date = (att['date'] ?? '').toLowerCase();
              return empName.contains(query) || date.contains(query);
            }).toList();
    });
  }

  // Fetch methods
  Future<void> fetchEmployees() async {
    setState(() => isLoading = true);
    try {
      final response = await http.get(Uri.parse('$_apiUrl'));
      if (response.statusCode == 200) {
        setState(() {
          employees = jsonDecode(response.body);
          _filteredEmployees = employees;
        });
      }
    } catch (e) {
      print('Error fetching employees: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _fetchAttendanceYears() async {
    try {
      final res = await http.get(Uri.parse(
          '${_apiUrl}/attendance/years?type=${attType == 0 ? "monthly" : "piece"}'));
      if (res.statusCode == 200) {
        setState(() {
          _availableYears = (jsonDecode(res.body) as List).cast<int>();
          if (_availableYears.isNotEmpty) {
            selectedYear = _availableYears.contains(DateTime.now().year)
                ? DateTime.now().year
                : _availableYears.first;
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
      final res = await http.get(Uri.parse(
          '${_apiUrl}/attendance/months?year=$selectedYear&type=${attType == 0 ? "monthly" : "piece"}'));
      if (res.statusCode == 200) {
        setState(() {
          _availableMonths = (jsonDecode(res.body) as List).cast<String>();
          if (_availableMonths.isNotEmpty) {
            final currentMonth = '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';
            selectedYearMonth = _availableMonths.contains(currentMonth) ? currentMonth : _availableMonths.first;
          }
        });
      }
    } catch (e) {
      print('Error fetching attendance months: $e');
    }
  }

  Future<void> fetchAttendance() async {
    if (selectedYearMonth == null) return;
    setState(() {
      attLoading = true;
      attEmployees = [];
      selectedEmployeeId = null;
    });

    final url = attType == 0
        ? '${_apiUrl}/attendance/monthly?month=$selectedYearMonth'
        : '${_apiUrl}/attendance/piece?month=$selectedYearMonth';

    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200) {
        setState(() {
          attEmployees = jsonDecode(res.body);
          selectedEmployeeId = attEmployees.isNotEmpty ? attEmployees.first['employee_id'] : null;
        });
      }
    } catch (e) {
      print('Error fetching attendance: $e');
    } finally {
      setState(() => attLoading = false);
    }
  }

  Future<void> _fetchPresenceDays() async {
    if (selectedYearMonth == null) {
      setState(() {
        _presenceDays = [];
        selectedDay = null;
      });
      return;
    }
    try {
      final parts = selectedYearMonth!.split('-');
      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final daysInMonth = DateTime(year, month + 1, 0).day;
      setState(() {
        _presenceDays = List.generate(daysInMonth, (i) => i + 1);
        final now = DateTime.now();
if (year == now.year && month == now.month) {
  selectedDay = now.day;
} else {
  selectedDay = null;
}
      });
    } catch (e) {
      print('Error calculating days: $e');
    }
  }

  Future<void> fetchPresence() async {
    setState(() {
      attLoading = true;
      attEmployees = [];
    });

    var url = '$_apiUrl/attendance';
    if (selectedYearMonth != null) {
      final parts = selectedYearMonth!.split('-');
      final year = parts[0];
      final month = parts[1].padLeft(2, '0');
      url += '?year=$year&month=$month';
      if (selectedDay != null) {
        final day = selectedDay!.toString().padLeft(2, '0');
        url += '&day=$day';
      }
    }

    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200) {
        setState(() {
          attEmployees = jsonDecode(res.body);
          _filteredPresence = attEmployees;
        });
      }
    } catch (e) {
      print('Error fetching presence: $e');
    } finally {
      setState(() => attLoading = false);
    }
  }

  Future<void> fetchDataSection() async {
    setState(() => isDataLoading = true);
    try {
      final empRes = await http.get(Uri.parse('$_apiUrl'));
      allEmployees = empRes.statusCode == 200 ? jsonDecode(empRes.body) : [];
      pieceEmployees = allEmployees.where((e) => e['payment_type'] == 'stitchly').toList();

      final modelRes = await http.get(Uri.parse('$_apiUrl/models'));
      allModels = modelRes.statusCode == 200 ? jsonDecode(modelRes.body) : [];

      final loanRes = await http.get(Uri.parse('$_apiUrl/loans'));
      loans = loanRes.statusCode == 200 ? jsonDecode(loanRes.body) : [];
      _filteredLoans = loans;

      final pieceRes = await http.get(Uri.parse('$_apiUrl/pieces'));
      pieces = pieceRes.statusCode == 200 ? jsonDecode(pieceRes.body) : [];
      _filteredPieces = pieces;

      final debtRes = await http.get(Uri.parse('$_apiUrl/debts'));
      debts = debtRes.statusCode == 200 ? jsonDecode(debtRes.body) : [];
      _filteredDebts = debts;
    } catch (e) {
      print('Error fetching data section:DataSection(): $e');
    } finally {
      setState(() => isDataLoading = false);
    }
  }

  Future<void> _fetchSalaryYears() async {
    try {
      final monthlyRes = await http.get(Uri.parse('${_apiUrl}/attendance/years?type=monthly'));
      final pieceRes = await http.get(Uri.parse('${_apiUrl}/attendance/years?type=piece'));
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
      final res = await http.get(Uri.parse(
          '${_apiUrl}/attendance/months?year=$selectedSalaryYear&type=$type'));
      if (res.statusCode == 200) {
        setState(() {
          _salaryMonths = (jsonDecode(res.body) as List).cast<String>();
          if (_salaryMonths.isNotEmpty) {
            final currentMonth = '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';
            selectedSalaryMonth = _salaryMonths.contains(currentMonth) ? currentMonth : _salaryMonths.first;
          }
        });
      }
    } catch (e) {
      print('Error fetching salary months: $e');
    }
  }

  Future<void> fetchSalariesData() async {
    if (selectedSalaryMonth == null) return;
    setState(() => salaryLoading = true);
    try {
      final monthlyRes = await http.get(Uri.parse(
          '${_apiUrl}/attendance/monthly?month=$selectedSalaryMonth'));
      monthlyAttendance = monthlyRes.statusCode == 200 ? jsonDecode(monthlyRes.body) : [];

      final pieceRes = await http.get(Uri.parse(
          '$_apiUrl/attendance/piece?month=$selectedSalaryMonth'));
      pieceAttendance = pieceRes.statusCode == 200 ? jsonDecode(pieceRes.body) : [];

      final loanRes = await http.get(Uri.parse(
          '$_apiUrl/loans/monthly-summary?month=$selectedSalaryMonth'));
      loanData = {};
      if (loanRes.statusCode == 200) {
        final decoded = jsonDecode(loanRes.body) as Map<String, dynamic>;
        decoded.forEach((key, value) {
          final id = int.tryParse(key) ?? 0;
          loanData[id] = {
            'monthly_due': num.tryParse(value['monthly_due'].toString()) ?? 0,
            'total_loan': num.tryParse(value['total_loan'].toString()) ?? 0,
            'remaining_loan': num.tryParse(value['remaining_loan'].toString()) ?? 0,
          };
        });
      }

      final debtRes = await http.get(Uri.parse(
          '$_apiUrl/debts/monthly-summary?month=$selectedSalaryMonth'));
      Map<int, num> debtData = {};
      if (debtRes.statusCode == 200) {
        final decoded = jsonDecode(debtRes.body) as Map<String, dynamic>;
        decoded.forEach((key, value) {
          final id = int.tryParse(key) ?? 0;
          debtData[id] = num.tryParse(value.toString()) ?? 0;
        });
      }

      monthlyTableRows = _calculateMonthlySalaryRows(debtData);
      pieceTableRows = _calculatePieceSalaryRows(debtData);
    } catch (e) {
      print('Error fetching salaries data: $e');
    } finally {
      setState(() => salaryLoading = false);
    }
  }

  List<Map<String, dynamic>> _calculateMonthlySalaryRows(Map<int, num> debtData) {
    final List<Map<String, dynamic>> rows = [];
    final parts = selectedSalaryMonth!.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    int workingDays = 0;
    for (var d = 1; d <= daysInMonth; d++) {
      if (DateTime(year, month, d).weekday != DateTime.friday) workingDays++;
    }
    for (final emp in monthlyAttendance) {
      final empId = emp['employee_id'] as int;
      final fullName = '${emp['first_name'] ?? ''} ${emp['last_name'] ?? ''}';
      final salary = (emp['salary'] ?? 0).toDouble();
      final shiftHours = (emp['shift_hours'] ?? 8).toDouble();
      final records = List.from(emp['attendance'] ?? []);
      double totalHours = 0;
      for (final att in records) {
        final inTime = DateTime.tryParse(att['check_in'] ?? '');
        final outTime = DateTime.tryParse(att['check_out'] ?? '');
        if (inTime != null && outTime != null) {
          totalHours += outTime.difference(inTime).inMinutes / 60.0;
        }
      }
      final standardHours = workingDays * shiftHours;
      final calculatedSalary = standardHours > 0 ? salary * (totalHours / standardHours) : 0.0;
      final loan = loanData[empId] ?? {'monthly_due': 0, 'total_loan': 0, 'remaining_loan': 0};
      final monthlyDue = loan['monthly_due']!.toDouble();
      final debt = debtData[empId] ?? 0;
      rows.add({
        'full_name': fullName,
        'salary': salary,
        'total_hours': totalHours,
        'standard_hours': standardHours,
        'calculated_salary': calculatedSalary,
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
        final qty = (rec['quantity'] ?? 0) as int;
        final price = (rec['piece_price'] ?? 0).toDouble();
        totalQty += qty;
        totalSalary += price * qty;
      }
      final loan = loanData[empId] ?? {'monthly_due': 0, 'total_loan': 0, 'remaining_loan': 0};
      final monthlyDue = loan['monthly_due']!.toDouble();
      final debt = debtData[empId] ?? 0;
      rows.add({
        'full_name': fullName,
        'total_qty': totalQty,
        'total_salary': totalSalary,
        'monthly_due': monthlyDue,
        'debt': debt,
        'remaining_loan': loan['remaining_loan']!,
        'final_salary': totalSalary - monthlyDue - debt,
      });
    }
    return rows;
  }

  String _monthLabel(String ym) {
    const months = [
      'جانفي', 'فيفري', 'مارس', 'أفريل', 'ماي', 'جوان', 'جويلية', 'أوت', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
    ];
    final parts = ym.split('-');
    return '${months[int.parse(parts[1]) - 1]} ${parts[0]}';
  }

  Future<void> _exportSalaryTableAsPdf({required bool isMonthly}) async {
    final pdf = pw.Document();
    final monthLabel = _monthLabel(selectedSalaryMonth!);
    final tableTitle = isMonthly ? 'رواتب العمال (شهرياً) - $monthLabel' : 'رواتب العمال (غرزة) - $monthLabel';
    final tableData = isMonthly ? monthlyTableRows : pieceTableRows;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Text(tableTitle, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 20)),
          ),
          pw.Table.fromTextArray(
            headers: isMonthly
                ? ['الاسم الكامل', 'الراتب', 'مجموع الساعات', 'الراتب الفعلي', 'دين هذا الشهر', 'السلف', 'الراتب النهائي']
                : ['الاسم الكامل', 'مجموع الغرز', 'مجموع الأجر', 'دين هذا الشهر', 'السلف', 'باقي الديون', 'الراتب النهائي'],
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
                      row['remaining_loan'].toStringAsFixed(2),
                      row['final_salary'].toStringAsFixed(2),
                    ];
            }).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
            cellStyle: const pw.TextStyle(fontSize: 12),
            cellAlignment: pw.Alignment.center,
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            border: pw.TableBorder.all(width: 0.5),
          ),
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  Future<void> _addAttendanceForAllEmployees(DateTime selectedDate) async {
    final attendanceRecords = allEmployees.where((e) => e['payment_type'] == 'monthly').map((employee) {
      final shiftHours = employee['shift_hours'] as int? ?? 8;
      final startTime = DateTime(selectedDate.year, selectedDate.month, selectedDate.day, 8, 0);
      final endTime = DateTime(selectedDate.year, selectedDate.month, selectedDate.day, 8 + shiftHours, 0);
      return {
        'employee_id': employee['id'],
        'date': selectedDate.toIso8601String().substring(0, 10),
        'check_in': startTime.toIso8601String(),
        'check_out': endTime.toIso8601String(),
      };
    }).toList();

    try {
      final response = await http.post(
        Uri.parse('$_apiUrl/attendance/bulk'),
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
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
      locale: const Locale('ar', 'AR'),
    );
    if (selectedDate != null) await _addAttendanceForAllEmployees(selectedDate);
  }

  // CRUD methods
  Future<void> addOrEditEmployee({Map? initial}) async {
    final result = await showDialog<Map>(
      context: context,
      builder: (context) => EmployeeDialog(initial: initial),
    );
    if (result != null) {
      try {
        if (initial == null) {
          await http.post(
            Uri.parse('$_apiUrl'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(result),
          );
        } else {
          await http.put(
            Uri.parse('$_apiUrl/${initial['id']}'),
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
          TextButton(
            child: const Text('إلغاء'),
            onPressed: () => Navigator.pop(context, false),
          ),
          TextButton(
            child: const Text('حذف'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (ok == true) {
      await http.delete(Uri.parse('$_apiUrl/$id'));
      await fetchEmployees();
    }
  }

  Future<void> addOrEditLoan({ Map? initial }) async {
    final _formKey = GlobalKey<FormState>();
    int? employeeId = initial?['employee_id'] as int?;
    final amountController = TextEditingController(text: initial?['amount']?.toString() ?? '');
    int duration = initial?['duration_months'] as int? ?? 1;
    DateTime selectedDate = initial != null && initial['loan_date'] != null
        ? DateTime.parse(initial['loan_date'])
        : DateTime.now();

    bool hasActiveLoan = false;
    if (employeeId != null && initial == null) {
      final checkRes = await http.get(Uri.parse('$_apiUrl/loans/check/$employeeId'));
      if (checkRes.statusCode == 200) {
        final data = jsonDecode(checkRes.body);
        hasActiveLoan = data['has_active_loan'] ?? false;
      }
    }

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(initial == null ? 'إضافة دين' : 'تعديل دين'),
          content: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  value: employeeId,
                  decoration: const InputDecoration(labelText: 'العامل'),
                  items: allEmployees.map((e) {
                    return DropdownMenuItem<int>(
                      value: e['id'] as int,
                      child: Text('${e['first_name']} ${e['last_name']}'),
                    );
                  }).toList(),
                  onChanged: (v) async {
                    setState(() => employeeId = v);
                    if (v != null && initial == null) {
                      final resp = await http.get(Uri.parse('$_apiUrl/loans/check/$v'));
                      if (resp.statusCode == 200) {
                        final d = jsonDecode(resp.body);
                        setState(() => hasActiveLoan = d['has_active_loan'] ?? false);
                        if (hasActiveLoan) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('هذا العامل لديه دين نشطة بالفعل'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        }
                      }
                    }
                  },
                  validator: (v) => v == null ? 'مطلوب' : null,
                ),
                if (hasActiveLoan)
                  const Padding(
                    padding: EdgeInsets.only(top: 8.0),
                    child: Text(
                      'تحذير: هذا العامل لديه دين نشطة',
                      style: TextStyle(color: Colors.orange),
                    ),
                  ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: amountController,
                  decoration: const InputDecoration(labelText: 'المبلغ'),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'مطلوب';
                    final num? val = num.tryParse(v);
                    if (val == null || val <= 0) return 'أدخل مبلغاً صالحاً أكبر من صفر';
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  value: duration,
                  decoration: const InputDecoration(labelText: 'المدة (شهور)'),
                  items: List.generate(12, (i) => i + 1)
                      .map((m) => DropdownMenuItem(value: m, child: Text('$m')))
                      .toList(),
                  onChanged: (v) => setState(() => duration = v!),
                  validator: (v) => (v == null || v <= 0) ? 'مطلوب' : null,
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('تاريخ الدين: ${selectedDate.toIso8601String().split('T').first}'),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
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
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!_formKey.currentState!.validate()) return;
                if (hasActiveLoan && initial == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('لا يمكن إضافة دين جديدة - العامل لديه دين نشطة'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                final data = {
                  'employee_id': employeeId,
                  'amount': num.parse(amountController.text.trim()),
                  'duration_months': duration,
                  'loan_date': selectedDate.toIso8601String(),
                };

                if (initial == null) {
                  await http.post(
                    Uri.parse('$_apiUrl/loans'),
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode(data),
                  );
                } else {
                  await http.put(
                    Uri.parse('$_apiUrl/loans/${initial!['id']}'),
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode(data),
                  );
                }

                Navigator.pop(context);
                await fetchDataSection();
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> deleteLoan(int id) async {
    await http.delete(Uri.parse('$_apiUrl/loans/$id'));
    await fetchDataSection();
  }

  Future<void> addOrEditPiece({ Map? initial }) async {
    final _formKey = GlobalKey<FormState>();
    int? employeeId = initial?['employee_id'] as int?;
    int? modelId    = initial?['model_id']    as int?;
    final qtyController   = TextEditingController(text: initial?['quantity']?.toString() ?? '');
    final priceController = TextEditingController(text: initial?['piece_price']?.toString() ?? '');
    DateTime selectedDate = initial != null && initial['record_date'] != null
        ? DateTime.parse(initial['record_date'])
        : DateTime.now();

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(initial == null ? 'إضافة غرزة' : 'تعديل غرزة'),
          content: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  value: employeeId,
                  decoration: const InputDecoration(labelText: 'العامل'),
                  items: pieceEmployees.map((e) {
                    return DropdownMenuItem<int>(
                      value: e['id'] as int,
                      child: Text('${e['first_name']} ${e['last_name']}'),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => employeeId = v),
                  validator: (v) => v == null ? 'مطلوب' : null,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  value: modelId,
                  decoration: const InputDecoration(labelText: 'الموديل'),
                  items: allModels.map((m) {
                    return DropdownMenuItem<int>(
                      value: m['id'] as int,
                      child: Text(m['name']),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => modelId = v),
                  validator: (v) => v == null ? 'مطلوب' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: qtyController,
                  decoration: const InputDecoration(labelText: 'الكمية'),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'مطلوب';
                    final int? q = int.tryParse(v);
                    if (q == null || q <= 0) return 'أدخل كمية صحيحة أكبر من صفر';
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: priceController,
                  decoration: const InputDecoration(labelText: 'سعر الغرزة'),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'مطلوب';
                    final num? p = num.tryParse(v);
                    if (p == null || p <= 0) return 'أدخل سعراً صالحاً أكبر من صفر';
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('تاريخ الغرزة: ${selectedDate.toIso8601String().split("T").first}'),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
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
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!_formKey.currentState!.validate()) return;
                final data = {
                  'employee_id': employeeId,
                  'model_id':    modelId,
                  'quantity':    int.parse(qtyController.text.trim()),
                  'piece_price': num.parse(priceController.text.trim()),
                  'record_date': selectedDate.toIso8601String(),
                };
                if (initial == null) {
                  await http.post(
                    Uri.parse('$_apiUrl/pieces'),
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode(data),
                  );
                } else {
                  await http.put(
                    Uri.parse('$_apiUrl/pieces/${initial!['id']}'),
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode(data),
                  );
                }
                Navigator.pop(context);
                await fetchDataSection();
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> deletePiece(int id) async {
    await http.delete(Uri.parse('$_apiUrl/pieces/$id'));
    await fetchDataSection();
  }

  Future<void> addOrEditDebt({ Map? initial }) async {
    final _formKey = GlobalKey<FormState>();
    int? employeeId = initial?['employee_id'] as int?;
    final amountController = TextEditingController(text: initial?['amount']?.toString() ?? '');
    DateTime selectedDate = initial != null && initial['debt_date'] != null
        ? DateTime.parse(initial['debt_date'])
        : DateTime.now();

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(initial == null ? 'إضافة دين' : 'تعديل دين'),
          content: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  value: employeeId,
                  decoration: const InputDecoration(labelText: 'العامل'),
                  items: allEmployees.map((e) {
                    return DropdownMenuItem<int>(
                      value: e['id'] as int,
                      child: Text('${e['first_name']} ${e['last_name']}'),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => employeeId = v),
                  validator: (v) => v == null ? 'مطلوب' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: amountController,
                  decoration: const InputDecoration(labelText: 'المبلغ'),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'مطلوب';
                    final num? val = num.tryParse(v);
                    if (val == null || val <= 0) return 'أدخل مبلغاً صالحاً أكبر من صفر';
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('تاريخ الدين: ${selectedDate.toIso8601String().split('T').first}'),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
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
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!_formKey.currentState!.validate()) return;
                final data = {
                  'employee_id': employeeId,
                  'amount': num.parse(amountController.text.trim()),
                  'debt_date': selectedDate.toIso8601String(),
                };
                if (initial == null) {
                  await http.post(
                    Uri.parse('$_apiUrl/debts'),
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode(data),
                  );
                } else {
                  await http.put(
                    Uri.parse('$_apiUrl/debts/${initial!['id']}'),
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode(data),
                  );
                }
                Navigator.pop(context);
                await fetchDataSection();
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> deleteDebt(int id) async {
    await http.delete(Uri.parse('$_apiUrl/debts/$id'));
    await fetchDataSection();
  }

  // UI builders
  Widget _buildInfoTable() {
    final paymentType = selectedInfoTab == 0 ? 'monthly' : 'stitchly';
    final filtered = _filteredEmployees.where((e) => e['payment_type'] == paymentType).toList();

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
                    hintText: 'بحث بالاسم، الجوال، العنوان، الراتب أو ساعات العمل',
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
                        child: Scrollbar(
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
                                  if (selectedInfoTab == 0)
                                    const DataColumn(label: Text('الراتب', style: TextStyle(color: Colors.white))),
                                  const DataColumn(label: Text('ساعات العمل', style: TextStyle(color: Colors.white))),
                                  const DataColumn(label: Text('إجراءات', style: TextStyle(color: Colors.white))),
                                ],
                                rows: filtered.map<DataRow>((emp) {
                                  return DataRow(cells: [
                                    DataCell(Text('${emp['first_name']} ${emp['last_name']}')),
                                    DataCell(Text(emp['phone'] ?? '')),
                                    DataCell(Text(emp['address'] ?? '')),
                                    if (selectedInfoTab == 0) DataCell(Text(emp['salary']?.toString() ?? '')),
                                    DataCell(Text(emp['shift_hours']?.toString() ?? '')),
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
                        ),
                      ),
                    ),
        ),
      ],
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
              labelStyle: TextStyle(
                color: attType == 0 ? Colors.white : Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
              onSelected: (_) async {
                setState(() => attType = 0);
                await _fetchAttendanceYears();
                if (_availableYears.isNotEmpty) await fetchAttendance();
              },
            ),
            const SizedBox(width: 12),
            ChoiceChip(
              label: const Text('بالغرزة'),
              selected: attType == 1,
              selectedColor: Theme.of(context).colorScheme.primary,
              labelStyle: TextStyle(
                color: attType == 1 ? Colors.white : Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
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
                  items: _availableMonths
                      .map((ym) => DropdownMenuItem(value: ym, child: Text(_monthLabel(ym).split(' ').first)))
                      .toList(),
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
                                Text(
                                  'العمال',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[800]),
                                ),
                                const SizedBox(height: 16),
                                TextField(
                                  controller: _presenceSearchController,
                                  decoration: InputDecoration(
                                    hintText: 'بحث بالعامل أو التاريخ',
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
                                        itemCount: attEmployees.length,
                                        itemBuilder: (ctx, i) {
                                          final emp = attEmployees[i];
                                          final isSel = selectedEmployeeId == emp['employee_id'];
                                          return Card(
                                            margin: const EdgeInsets.symmetric(vertical: 4),
                                            elevation: isSel ? 4 : 1,
                                            color: isSel ? Colors.grey[100] : Colors.white,
                                            child: ListTile(
                                              selected: isSel,
                                              title: Text(
                                                '${emp['first_name']} ${emp['last_name']}',
                                                style: TextStyle(fontWeight: isSel ? FontWeight.bold : FontWeight.normal),
                                              ),
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
                        child: selectedEmployeeId == null
                            ? const Center(child: Text('اختر عامل'))
                            : attEmployees.firstWhere((e) => e['employee_id'] == selectedEmployeeId, orElse: () => null) == null
                                ? const Center(child: Text('اختر عامل'))
                                : attType == 0
                                    ? _MonthlyAttendanceTable(
                                        attEmployees.firstWhere((e) => e['employee_id'] == selectedEmployeeId),
                                        controller: monthlyAttTableController,
                                        month: selectedYearMonth!,
                                      )
                                    : _PieceAttendanceTable(
                                        attEmployees.firstWhere((e) => e['employee_id'] == selectedEmployeeId),
                                        controller: pieceAttTableController,
                                      ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildDataSection() {
    final tabs = ['الديون', 'الغرز', 'السلف', 'الحضور'];
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
                labelStyle: TextStyle(
                  color: selectedDataTab == i ? Colors.white : Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
                onSelected: (_) async {
                  setState(() => selectedDataTab = i);
                  if (i == 3) {
                    await _fetchPresenceDays();
                    await fetchPresence();
                  }
                },
              ),
            );
          }),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: selectedDataTab < 3
              ? isDataLoading
                  ? const Center(child: CircularProgressIndicator())
                  : selectedDataTab == 0
                      ? _buildLoansTable()
                      : selectedDataTab == 1
                          ? _buildPiecesTable()
                          : _buildDebtsTable()
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
            child: Center(
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
                                IconButton(
                                  icon: Icon(Icons.edit, color: Theme.of(context).colorScheme.primary),
                                  onPressed: () => addOrEditLoan(initial: loan),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () => deleteLoan(loan['id']),
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
                label: const Text('إضافة غرزة', style: TextStyle(color: Colors.white)),
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
            child: Center(
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
                          DataColumn(label: Text('سعر الغرزة', style: TextStyle(color: Colors.white))),
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
                                IconButton(
                                  icon: Icon(Icons.edit, color: Theme.of(context).colorScheme.primary),
                                  onPressed: () => addOrEditPiece(initial: piece),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () => deletePiece(piece['id']),
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
                label: const Text('إضافة سلفة', style: TextStyle(color: Colors.white)),
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
                            IconButton(
                              icon: Icon(Icons.edit, color: Theme.of(context).colorScheme.primary),
                              onPressed: () => addOrEditDebt(initial: debt),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => deleteDebt(debt['id']),
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
          child: Row(
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
                      initialMonth: selectedYearMonth ?? DateTime.now().toIso8601String().substring(0, 7),
                      employees: allEmployees.where((e) => e['payment_type'] == 'monthly').toList(),
                    ),
                  );
                  if (result != null) {
                    await http.post(
                      Uri.parse('${_apiUrl}/attendance'),
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
        ),
        const SizedBox(height: 16),
        if (_availableYears.isNotEmpty)
          Row(
            children: [
              const Text('السنة:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: selectedYear,
                items: _availableYears.map((y) => DropdownMenuItem(value: y, child: Text('$y'))).toList(),
                onChanged: (y) async {
                  setState(() {
                    selectedYear = y;
                    selectedDay = null;
                  });
                  await _fetchAttendanceMonths();
                  await _fetchPresenceDays();
                  await fetchPresence();
                },
              ),
              const SizedBox(width: 24),
              const Text('الشهر:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: selectedYearMonth,
                items: _availableMonths
                    .map((m) => DropdownMenuItem(value: m, child: Text(_monthLabel(m).split(' ').first)))
                    .toList(),
                onChanged: (val) async {
                  setState(() {
                    selectedYearMonth = val;
                    selectedDay = null;
                  });
                  await _fetchPresenceDays();
                  await fetchPresence();
                },
              ),
              const SizedBox(width: 24),
              const Text('اليوم:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              DropdownButton<int?>(
                value: selectedDay,
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
                  setState(() => selectedDay = val);
                  fetchPresence();
                },
              ),
            ],
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
                                              initialMonth: selectedYearMonth ?? DateTime.now().toIso8601String().substring(0, 7),
                                              employees: allEmployees.where((e) => e['payment_type'] == 'monthly').toList(),
                                              initial: rec,
                                            ),
                                          );
                                          if (edited != null) {
                                            await http.put(
                                              Uri.parse('$_apiUrl/attendance/${rec['attendance_id']}'),
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
                                          await http.delete(Uri.parse('$_apiUrl/attendance/${rec['attendance_id']}'));
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

  Widget _buildSalariesSection(List<String> salariesTabs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            salariesTabs.length,
            (i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: ChoiceChip(
                label: Text(salariesTabs[i]),
                selected: selectedSalariesTab == i,
                selectedColor: Theme.of(context).colorScheme.primary,
                labelStyle: TextStyle(
                  color: selectedSalariesTab == i ? Colors.white : Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
                onSelected: (_) async {
                  setState(() => selectedSalariesTab = i);
                  await _fetchSalaryMonths();
                  if (selectedSalaryMonth != null) await fetchSalariesData();
                },
              ),
            ),
          ),
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
                items: _salaryMonths
                    .map((m) => DropdownMenuItem(value: m, child: Text(_monthLabel(m).split(' ').first)))
                    .toList(),
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
    return Center(
      child: Align(
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
                  DataColumn(label: Text('دين هذا الشهر', style: TextStyle(color: Colors.white))),
                  DataColumn(label: Text('السلف', style: TextStyle(color: Colors.white))),
                  DataColumn(label: Text('الراتب النهائي', style: TextStyle(color: Colors.white))),
                ],
                rows: monthlyTableRows.map<DataRow>((row) {
                  return DataRow(cells: [
                    DataCell(Text(row['full_name'].toString())),
                    DataCell(Text(row['salary'].toStringAsFixed(2))),
                    DataCell(Text(row['total_hours'].toStringAsFixed(2))),
                    DataCell(Text(row['calculated_salary'].toStringAsFixed(2))),
                    DataCell(Text(row['monthly_due'].toStringAsFixed(2))),
                    DataCell(Text(row['debt'].toStringAsFixed(2))),
                    DataCell(Text(row['final_salary'].toStringAsFixed(2))),
                  ]);
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPieceSalaryTable() {
    if (pieceTableRows.isEmpty) return const Center(child: Text('لا يوجد بيانات رواتب هنا'));
    return Center(
      child: Align(
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
                  DataColumn(label: Text('مجموع الغرز', style: TextStyle(color: Colors.white))),
                  DataColumn(label: Text('مجموع الأجر', style: TextStyle(color: Colors.white))),
                  DataColumn(label: Text('دين هذا الشهر', style: TextStyle(color: Colors.white))),
                  DataColumn(label: Text('السلف', style: TextStyle(color: Colors.white))),
                  DataColumn(label: Text('باقي الديون', style: TextStyle(color: Colors.white))),
                  DataColumn(label: Text('الراتب النهائي', style: TextStyle(color: Colors.white))),
                ],
                rows: pieceTableRows.map<DataRow>((row) {
                  return DataRow(cells: [
                    DataCell(Text(row['full_name'])),
                    DataCell(Text(row['total_qty'].toString())),
                    DataCell(Text(row['total_salary'].toStringAsFixed(2))),
                    DataCell(Text(row['monthly_due'].toStringAsFixed(2))),
                    DataCell(Text(row['debt'].toStringAsFixed(2))),
                    DataCell(Text(row['remaining_loan'].toStringAsFixed(2))),
                    DataCell(Text(row['final_salary'].toStringAsFixed(2))),
                  ]);
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mainTabs = ['معلومات', 'البيانات', 'ادارة البيانات', 'رواتب العمال'];
    final infoTabs = ['شهرياً', 'بالغرزة'];
    final salariesTabs = ['شهرياً', 'بالغرزة'];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                    if (i == 1 && _availableYears.isEmpty) {
                      await _fetchAttendanceYears();
                      if (_availableYears.isNotEmpty) {
                        await fetchAttendance();
                      }
                    }
                    if (i == 2) {
                      await fetchDataSection();
                    }
                  },
                ),
              );
            }),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: selectedTab == 0
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(infoTabs.length, (i) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0),
                            child: ChoiceChip(
                              label: Text(infoTabs[i]),
                              selected: selectedInfoTab == i,
                              selectedColor: Theme.of(context).colorScheme.primary,
                              labelStyle: TextStyle(
                                color: selectedInfoTab == i
                                    ? Colors.white
                                    : Theme.of(context).colorScheme.onSurface,
                                fontWeight: FontWeight.bold,
                              ),
                              onSelected: (_) => setState(() => selectedInfoTab = i),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 16),
                      Expanded(child: _buildInfoTable()),
                    ],
                  )
                : selectedTab == 1
                    ? _buildAttendanceSection()
                    : selectedTab == 2
                        ? _buildDataSection()
                        : _buildSalariesSection(salariesTabs),
          ),
        ],
      ),
    );
  }
}

class _MonthlyAttendanceTable extends StatelessWidget {
  final Map emp;
  final ScrollController controller;
  final String month;

  const _MonthlyAttendanceTable(this.emp, {required this.controller, required this.month});

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
    final shiftHours = (emp['shift_hours'] ?? 8).toDouble();
    final standardHours = workingDays * shiftHours;
    final hourRate = standardHours > 0 ? salary / standardHours : 0.0;

    final records = List<Map<String, dynamic>>.from(emp['attendance'] ?? []);
    double totalHrs = 0;
    double totalPay = 0;
    final rows = records.map<DataRow>((att) {
      final inTime = DateTime.tryParse(att['check_in'] ?? '');
      final outTime = DateTime.tryParse(att['check_out'] ?? '');
      double hrs = 0;
      if (inTime != null && outTime != null) {
        hrs = outTime.difference(inTime).inMinutes / 60.0;
      }
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
      final qty = (rec['quantity'] ?? 0) as int;
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
                      DataColumn(label: Text('سعر الغرزة', style: TextStyle(color: Colors.white))),
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
              'الإجمالي: مجموع الغرز: $totalQty, مجموع السعر: ${totalPrice.toStringAsFixed(2)}',
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
  final _formKey = GlobalKey<FormState>();
  int? employeeId;
  DateTime date = DateTime.now();
  TimeOfDay checkIn = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay checkOut = const TimeOfDay(hour: 16, minute: 0);

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
    }
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
            DropdownButtonFormField<int>(
              value: employeeId,
              decoration: const InputDecoration(labelText: 'العامل'),
              items: widget.employees.map((e) {
                return DropdownMenuItem<int>(
                  value: e['id'] as int,
                  child: Text('${e['first_name']} ${e['last_name']}'),
                );
              }).toList(),
              onChanged: (v) => setState(() => employeeId = v),
              validator: (v) => v == null ? 'مطلوب' : null,
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('التاريخ: ${date.toIso8601String().split('T').first}'),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                  locale: const Locale('ar', 'AR'),
                );
                if (picked != null) setState(() => date = picked);
              },
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('دخول: ${checkIn.format(context)}'),
              trailing: const Icon(Icons.access_time),
              onTap: () async {
                final t = await showTimePicker(context: context, initialTime: checkIn);
                if (t != null) setState(() => checkIn = t);
              },
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('خروج: ${checkOut.format(context)}'),
              trailing: const Icon(Icons.access_time),
              onTap: () async {
                final t = await showTimePicker(context: context, initialTime: checkOut);
                if (t != null) setState(() => checkOut = t);
              },
            ),
            const SizedBox(height: 8),
            Builder(
              builder: (context) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!_formKey.currentState!.validate() && mounted) {
                    setState(() {});
                  }
                });
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        ElevatedButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            final inDT = DateTime(date.year, date.month, date.day, checkIn.hour, checkIn.minute);
            final outDT = DateTime(date.year, date.month, date.day, checkOut.hour, checkOut.minute);
            if (!outDT.isAfter(inDT)) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('وقت الخروج يجب أن يكون بعد وقت الدخول'),
                  backgroundColor: Colors.red,
                ),
              );
              return;
            }
            final payload = <String, dynamic>{
              'employee_id': employeeId,
              'date': date.toIso8601String().split('T').first,
              'check_in': inDT.toIso8601String(),
              'check_out': outDT.toIso8601String(),
            };
            if (widget.initial != null && widget.initial!['attendance_id'] != null) {
              payload['attendance_id'] = widget.initial!['attendance_id'];
            }
            Navigator.pop<Map<String, dynamic>>(context, payload);
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
  String paymentType = 'monthly';
  int shiftHours = 8;

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
    paymentType = init['payment_type'] ?? 'monthly';
    shiftHours = init['shift_hours'] ?? 8;
  }

  @override
  Widget build(BuildContext context) {
    final isMonthly = paymentType == 'monthly';
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
                      value: 'monthly',
                      groupValue: paymentType,
                      onChanged: (v) => setState(() => paymentType = v!),
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text('بالغرزة'),
                      value: 'stitchly',
                      groupValue: paymentType,
                      onChanged: (v) => setState(() => paymentType = v!),
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
                  if (v.length != 10) return 'يجب أن يكون 10 أرقام';
                  if (!RegExp(r'^\d{10}$').hasMatch(v)) return 'يجب أن يحتوي على أرقام فقط';
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
                  validator: (v) => v == null || v.isEmpty ? 'مطلوب' : null,
                ),
              if (paymentType == 'monthly' || paymentType == 'stitchly')
                DropdownButtonFormField<int>(
                  value: shiftHours,
                  decoration: const InputDecoration(labelText: 'ساعات العمل'),
                  items: [8, 12].map((h) => DropdownMenuItem(value: h, child: Text('$h ساعات'))).toList(),
                  onChanged: (v) => setState(() => shiftHours = v!),
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
                'payment_type': paymentType,
                'salary': isMonthly ? double.tryParse(salary.text) ?? 0 : null,
                'shift_hours': shiftHours,
                'photo_url': photoUrl.text.trim().isEmpty ? null : photoUrl.text.trim(),
              });
            }
          },
        ),
      ],
    );
  }
}