import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class SewingEmployeesSection extends StatefulWidget {
  const SewingEmployeesSection({super.key});
  @override
  State<SewingEmployeesSection> createState() => _SewingEmployeesSectionState();
}

class _SewingEmployeesSectionState extends State<SewingEmployeesSection> {
  int selectedTab = 0; // 0: معلومات, 1: الحضور, 2: اداره سلف و قطع العمال, 3: رواتب العمال
  int selectedInfoTab = 0; // 0: شهرياً, 1: قطعة

  // Attendance state
  int attType = 0; // 0: monthly, 1: piece
  String selectedMonth = _initialMonth();
  int? selectedEmployeeId;
  List<dynamic> attEmployees = [];
  bool attLoading = false;

  // Info state
  List<dynamic> employees = [];
  bool isLoading = false;

  // Loans & Pieces state
  int selectedDataTab = 0; // 0: سلف, 1: قطع
  List<dynamic> loans = [];
  List<dynamic> pieces = [];
  List<dynamic> allEmployees = [];
  List<dynamic> pieceEmployees = [];
  List<dynamic> allModels = [];
  bool isDataLoading = false;

  // Salaries tab state
  int selectedSalariesTab = 0; // 0: شهرياً, 1: قطعة
  String selectedSalaryMonth = _initialMonth();
  bool salaryLoading = false;
  List<dynamic> monthlyAttendance = [];
  List<dynamic> pieceAttendance = [];
  Map<int, Map<String, num>> loanData = {};
  List<Map<String, dynamic>> monthlyTableRows = [];
  List<Map<String, dynamic>> pieceTableRows = [];

  // SCROLL CONTROLLERS FOR TABLES
  final ScrollController infoTableController = ScrollController();
  final ScrollController loansTableController = ScrollController();
  final ScrollController piecesTableController = ScrollController();
  final ScrollController monthlySalaryTableController = ScrollController();
  final ScrollController pieceSalaryTableController = ScrollController();
  final ScrollController monthlyAttTableController = ScrollController();
  final ScrollController pieceAttTableController = ScrollController();

  @override
  void dispose() {
    infoTableController.dispose();
    loansTableController.dispose();
    piecesTableController.dispose();
    monthlySalaryTableController.dispose();
    pieceSalaryTableController.dispose();
    monthlyAttTableController.dispose();
    pieceAttTableController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    fetchEmployees();
    fetchAttendance();
    fetchDataSection();
    fetchSalariesData();
  }

  static String _initialMonth() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  // ... [CUT: unchanged functions for brevity, unchanged from your code] ...

  // ========== TABLES: SCROLLBAR ADDED ==========

  Widget _buildInfoTable() {
    final sellerType = selectedInfoTab == 0 ? 'month' : 'piece';
    final filtered = employees.where((e) => e['seller_type'] == sellerType).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('إضافة عامل جديد'),
            onPressed: () =>
                addOrEditEmployee(initial: {'seller_type': sellerType}),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                  ? const Center(child: Text('لا يوجد عمال هنا'))
                  : Center(
                      child: Scrollbar(
                        controller: infoTableController,
                        thumbVisibility: true,
                        trackVisibility: true,
                        child: SingleChildScrollView(
                          controller: infoTableController,
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            headingRowColor:
                                MaterialStateProperty.all(
                                    Theme.of(context).colorScheme.primary),
                            columns: [
                              const DataColumn(
                                  label: Text('الاسم الكامل',
                                      style: TextStyle(color: Colors.white))),
                              const DataColumn(
                                  label: Text('الجوال',
                                      style: TextStyle(color: Colors.white))),
                              const DataColumn(
                                  label: Text('العنوان',
                                      style: TextStyle(color: Colors.white))),
                              if (selectedInfoTab == 0)
                                const DataColumn(
                                    label: Text('الراتب',
                                        style: TextStyle(color: Colors.white))),
                              const DataColumn(
                                  label: Text('المهنه',
                                      style: TextStyle(color: Colors.white))),
                              const DataColumn(
                                  label: Text('إجراءات',
                                      style: TextStyle(color: Colors.white))),
                            ],
                            rows: filtered.map<DataRow>((emp) {
                              return DataRow(cells: [
                                DataCell(Text(
                                    '${emp['first_name']} ${emp['last_name']}')),
                                DataCell(Text(emp['phone'] ?? '')),
                                DataCell(Text(emp['address'] ?? '')),
                                if (selectedInfoTab == 0)
                                  DataCell(Text(emp['salary']?.toString() ?? '')),
                                DataCell(Text(emp['role'] ?? '')),
                                DataCell(Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit, color: Colors.green),
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
      ],
    );
  }

  Widget _buildLoansTable() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('إضافة سلفة'),
            onPressed: () => addOrEditLoan(),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Center(
            child: Scrollbar(
              controller: loansTableController,
              thumbVisibility: true,
              trackVisibility: true,
              child: SingleChildScrollView(
                controller: loansTableController,
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: MaterialStateProperty.all(
                      Theme.of(context).colorScheme.primary),
                  columns: const [
                    DataColumn(
                        label: Text('العامل',
                            style: TextStyle(color: Colors.white))),
                    DataColumn(
                        label: Text('المبلغ',
                            style: TextStyle(color: Colors.white))),
                    DataColumn(
                        label: Text('المدة (شهور)',
                            style: TextStyle(color: Colors.white))),
                    DataColumn(
                        label: Text('التاريخ',
                            style: TextStyle(color: Colors.white))),
                    DataColumn(
                        label: Text('خيارات',
                            style: TextStyle(color: Colors.white))),
                  ],
                  rows: loans.map((loan) {
                    return DataRow(cells: [
                      DataCell(Text(loan['employee_name'] ?? '')),
                      DataCell(Text(loan['amount'].toString())),
                      DataCell(Text('${loan['duration_months'] ?? 1}')),
                      DataCell(Text(loan['loan_date']?.substring(0, 10) ?? '')),
                      DataCell(Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.green),
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
      ],
    );
  }

  Widget _buildPiecesTable() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('إضافة قطعة'),
              onPressed: () => addOrEditPiece(),
            )),
        const SizedBox(height: 16),
        Expanded(
          child: Center(
            child: Scrollbar(
              controller: piecesTableController,
              thumbVisibility: true,
              trackVisibility: true,
              child: SingleChildScrollView(
                controller: piecesTableController,
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: MaterialStateProperty.all(
                      Theme.of(context).colorScheme.primary),
                  columns: const [
                    DataColumn(
                        label: Text('العامل',
                            style: TextStyle(color: Colors.white))),
                    DataColumn(
                        label: Text('الموديل',
                            style: TextStyle(color: Colors.white))),
                    DataColumn(
                        label: Text('الكمية',
                            style: TextStyle(color: Colors.white))),
                    DataColumn(
                        label: Text('سعر القطعة',
                            style: TextStyle(color: Colors.white))),
                    DataColumn(
                        label: Text('التاريخ',
                            style: TextStyle(color: Colors.white))),
                    DataColumn(
                        label: Text('خيارات',
                            style: TextStyle(color: Colors.white))),
                  ],
                  rows: pieces.map((piece) {
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
                            icon: const Icon(Icons.edit, color: Colors.green),
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
      ],
    );
  }

  Widget _buildMonthlySalaryTable() {
    if (monthlyTableRows.isEmpty) {
      return const Center(child: Text('لا يوجد بيانات رواتب هنا'));
    }
    return Center(
      child: Scrollbar(
        controller: monthlySalaryTableController,
        thumbVisibility: true,
        trackVisibility: true,
        child: SingleChildScrollView(
          controller: monthlySalaryTableController,
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor:
                MaterialStateProperty.all(Theme.of(context).colorScheme.primary),
            columns: const [
              DataColumn(
                  label: Text('الاسم الكامل',
                      style: TextStyle(color: Colors.white))),
              DataColumn(
                  label: Text('الراتب',
                      style: TextStyle(color: Colors.white))),
              DataColumn(
                  label: Text('مجموع الساعات',
                      style: TextStyle(color: Colors.white))),
              DataColumn(
                  label: Text('الراتب الفعلي',
                      style: TextStyle(color: Colors.white))),
              DataColumn(
                  label: Text('إجمالي السلف',
                      style: TextStyle(color: Colors.white))),
              DataColumn(
                  label: Text('سلفة هذا الشهر',
                      style: TextStyle(color: Colors.white))),
              DataColumn(
                  label: Text('باقي السلف',
                      style: TextStyle(color: Colors.white))),
              DataColumn(
                  label: Text('الراتب النهائي',
                      style: TextStyle(color: Colors.white))),
            ],
            rows: monthlyTableRows.map<DataRow>((row) {
              return DataRow(cells: [
                DataCell(Text(row['full_name'])),
                DataCell(Text(row['salary'].toStringAsFixed(2))),
                DataCell(Text(row['total_hours'].toStringAsFixed(2))),
                DataCell(Text(row['calculated_salary'].toStringAsFixed(2))),
                DataCell(Text(row['total_loan'].toStringAsFixed(2))),
                DataCell(Text(row['monthly_due'].toStringAsFixed(2))),
                DataCell(Text(row['remaining_loan'].toStringAsFixed(2))),
                DataCell(Text(row['final_salary'].toStringAsFixed(2))),
              ]);
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildPieceSalaryTable() {
    if (pieceTableRows.isEmpty) {
      return const Center(child: Text('لا يوجد بيانات رواتب هنا'));
    }
    return Center(
      child: Scrollbar(
        controller: pieceSalaryTableController,
        thumbVisibility: true,
        trackVisibility: true,
        child: SingleChildScrollView(
          controller: pieceSalaryTableController,
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor:
                MaterialStateProperty.all(Theme.of(context).colorScheme.primary),
            columns: const [
              DataColumn(
                  label: Text('الاسم الكامل',
                      style: TextStyle(color: Colors.white))),
              DataColumn(
                  label: Text('مجموع القطع',
                      style: TextStyle(color: Colors.white))),
              DataColumn(
                  label: Text('مجموع الأجر',
                      style: TextStyle(color: Colors.white))),
              DataColumn(
                  label: Text('إجمالي السلف',
                      style: TextStyle(color: Colors.white))),
              DataColumn(
                  label: Text('سلفة هذا الشهر',
                      style: TextStyle(color: Colors.white))),
              DataColumn(
                  label: Text('باقي السلف',
                      style: TextStyle(color: Colors.white))),
              DataColumn(
                  label: Text('الراتب النهائي',
                      style: TextStyle(color: Colors.white))),
            ],
            rows: pieceTableRows.map<DataRow>((row) {
              return DataRow(cells: [
                DataCell(Text(row['full_name'])),
                DataCell(Text(row['total_qty'].toString())),
                DataCell(Text(row['total_salary'].toStringAsFixed(2))),
                DataCell(Text(row['total_loan'].toStringAsFixed(2))),
                DataCell(Text(row['monthly_due'].toStringAsFixed(2))),
                DataCell(Text(row['remaining_loan'].toStringAsFixed(2))),
                DataCell(Text(row['final_salary'].toStringAsFixed(2))),
              ]);
            }).toList(),
          ),
        ),
      ),
    );
  }

  // ... [CUT: unchanged build(), _buildSalariesSection(), etc.] ...

  Widget _buildAttendanceSection() {
    final months = _generateMonths();
    return Column(
      children: [
        Row(
          children: [
            const Text('الشهر:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: selectedMonth,
              items: months
                  .map((m) => DropdownMenuItem(
                        value: m,
                        child: Text(_monthLabel(m)),
                      ))
                  .toList(),
              onChanged: (val) {
                setState(() {
                  selectedMonth = val!;
                  fetchAttendance();
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Row(
            children: [
              Container(
                width: 180,
                color: Colors.grey[200],
                child: Column(
                  children: [
                    for (int i = 0; i < 2; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8.0, vertical: 4.0),
                        child: TextButton(
                          style: TextButton.styleFrom(
                            backgroundColor: attType == i
                                ? Theme.of(context).colorScheme.primary
                                : null,
                            foregroundColor: attType == i
                                ? Colors.white
                                : Theme.of(context).colorScheme.onSurface,
                          ),
                          child: Text(i == 0 ? 'شهرياً' : 'قطعة'),
                          onPressed: () {
                            setState(() {
                              attType = i;
                              fetchAttendance();
                            });
                          },
                        ),
                      ),
                    const Divider(),
                    Expanded(
                      child: attLoading
                          ? const Center(child: CircularProgressIndicator())
                          : attEmployees.isEmpty
                              ? const Center(child: Text('لا يوجد عمال'))
                              : ListView.builder(
                                  itemCount: attEmployees.length,
                                  itemBuilder: (context, i) {
                                    final emp = attEmployees[i];
                                    return ListTile(
                                      title: Text(
                                          '${emp['first_name']} ${emp['last_name']}'),
                                      selected: selectedEmployeeId ==
                                          emp['employee_id'],
                                      onTap: () => setState(() =>
                                          selectedEmployeeId =
                                              emp['employee_id']),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: selectedEmployeeId == null
                    ? const Center(child: Text('اختر عامل'))
                    : attType == 0
                        ? _MonthlyAttendanceTable(
                            attEmployees.firstWhere(
                                (e) => e['employee_id'] == selectedEmployeeId),
                            controller: monthlyAttTableController,
                          )
                        : _PieceAttendanceTable(
                            attEmployees.firstWhere(
                                (e) => e['employee_id'] == selectedEmployeeId),
                            controller: pieceAttTableController,
                          ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ... [CUT: rest of unchanged code, dialogs, etc.] ...
}

// ========== Modified Attendance Table Widgets ==========

class _MonthlyAttendanceTable extends StatelessWidget {
  final Map emp;
  final ScrollController controller;
  const _MonthlyAttendanceTable(this.emp, {required this.controller});

  @override
  Widget build(BuildContext context) {
    final records = List.from(emp['attendance'] ?? []);
    final salary = (emp['salary'] ?? 0).toDouble();
    final hourRate = salary / (26 * 8);
    double totalHours = 0;
    double totalSalary = 0;

    final rows = records.map<DataRow>((att) {
      final inTime = att['check_in'] != null
          ? DateTime.tryParse(att['check_in'])
          : null;
      final outTime = att['check_out'] != null
          ? DateTime.tryParse(att['check_out'])
          : null;
      double hoursWorked = 0;
      if (inTime != null && outTime != null) {
        hoursWorked = outTime.difference(inTime).inMinutes / 60.0;
      }
      final daySalary = hourRate * hoursWorked;
      totalHours += hoursWorked;
      totalSalary += daySalary;
      return DataRow(cells: [
        DataCell(Text(att['date']?.substring(0, 10) ?? '')),
        DataCell(Text(inTime != null
            ? "${inTime.hour}:${inTime.minute.toString().padLeft(2, '0')}"
            : '')),
        DataCell(Text(outTime != null
            ? "${outTime.hour}:${outTime.minute.toString().padLeft(2, '0')}"
            : '')),
        DataCell(Text(hoursWorked.toStringAsFixed(2))),
        DataCell(Text(hourRate.toStringAsFixed(2))),
        DataCell(Text(daySalary.toStringAsFixed(2))),
      ]);
    }).toList();

    return Column(
      children: [
        Text('${emp['first_name']} ${emp['last_name']}',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        Expanded(
          child: Center(
            child: Scrollbar(
              controller: controller,
              thumbVisibility: true,
              trackVisibility: true,
              child: SingleChildScrollView(
                controller: controller,
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor:
                      MaterialStateProperty.all(Theme.of(context).colorScheme.primary),
                  columns: const [
                    DataColumn(
                        label: Text('اليوم', style: TextStyle(color: Colors.white))),
                    DataColumn(
                        label: Text('دخول', style: TextStyle(color: Colors.white))),
                    DataColumn(
                        label: Text('خروج', style: TextStyle(color: Colors.white))),
                    DataColumn(
                        label: Text('عدد الساعات', style: TextStyle(color: Colors.white))),
                    DataColumn(
                        label: Text('سعر الساعة', style: TextStyle(color: Colors.white))),
                    DataColumn(
                        label: Text('أجر اليوم', style: TextStyle(color: Colors.white))),
                  ],
                  rows: rows,
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
              'الإجمالي: مجموع الساعات: ${totalHours.toStringAsFixed(2)}, مجموع الأجر: ${totalSalary.toStringAsFixed(2)}',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
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
        Text('${emp['first_name']} ${emp['last_name']}',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        Expanded(
          child: Center(
            child: Scrollbar(
              controller: controller,
              thumbVisibility: true,
              trackVisibility: true,
              child: SingleChildScrollView(
                controller: controller,
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor:
                      MaterialStateProperty.all(Theme.of(context).colorScheme.primary),
                  columns: const [
                    DataColumn(
                        label: Text('الموديل', style: TextStyle(color: Colors.white))),
                    DataColumn(
                        label: Text('الكمية', style: TextStyle(color: Colors.white))),
                    DataColumn(
                        label: Text('سعر القطعة', style: TextStyle(color: Colors.white))),
                    DataColumn(
                        label: Text('الإجمالي', style: TextStyle(color: Colors.white))),
                  ],
                  rows: rows,
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
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
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
  late TextEditingController firstName,
      lastName,
      phone,
      address,
      salary,
      photoUrl;
  String sellerType = 'month';
  String? role;

  static const monthlyRoles = ['خياطة', 'فينيسيون'];
  static const pieceRoles = ['كوي', 'خياطة', 'قص'];

  @override
  void initState() {
    super.initState();
    final init = widget.initial ?? {};
    firstName =
        TextEditingController(text: init['first_name'] ?? '');
    lastName =
        TextEditingController(text: init['last_name'] ?? '');
    phone = TextEditingController(text: init['phone'] ?? '');
    address =
        TextEditingController(text: init['address'] ?? '');
    salary =
        TextEditingController(text: init['salary']?.toString() ?? '');
    photoUrl =
        TextEditingController(text: init['photo_url'] ?? '');
    sellerType = init['seller_type'] ?? 'month';
    role = init['role'] ??
        (sellerType == 'month'
            ? monthlyRoles.first
            : pieceRoles.first);
  }

  @override
  Widget build(BuildContext context) {
    final isMonthly = sellerType == 'month';
    final allowedRoles =
        isMonthly ? monthlyRoles : pieceRoles;

    return AlertDialog(
      title: Text(widget.initial == null
          ? 'إضافة عامل'
          : 'تعديل بيانات العامل'),
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
                decoration:
                    const InputDecoration(labelText: 'الاسم الأول'),
                validator: (v) => v == null || v.isEmpty
                    ? 'مطلوب'
                    : null,
              ),
              TextFormField(
                controller: lastName,
                decoration:
                    const InputDecoration(labelText: 'الاسم الأخير'),
                validator: (v) => v == null || v.isEmpty
                    ? 'مطلوب'
                    : null,
              ),
              TextFormField(
                controller: phone,
                decoration:
                    const InputDecoration(labelText: 'رقم الجوال'),
                validator: (v) => v == null || v.isEmpty
                    ? 'مطلوب'
                    : null,
              ),
              TextFormField(
                controller: address,
                decoration:
                    const InputDecoration(labelText: 'العنوان'),
                validator: (v) => v == null || v.isEmpty
                    ? 'مطلوب'
                    : null,
              ),
              if (isMonthly)
                TextFormField(
                  controller: salary,
                  decoration:
                      const InputDecoration(labelText: 'الراتب الشهري'),
                  keyboardType: TextInputType.number,
                  validator: (v) => v == null || v.isEmpty
                      ? 'مطلوب'
                      : null,
                ),
              DropdownButtonFormField<String>(
                value: role,
                decoration:
                    const InputDecoration(labelText: 'المهنه'),
                items: allowedRoles
                    .map((r) => DropdownMenuItem<String>(
                          value: r,
                          child: Text(r),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => role = v),
                validator: (v) => v == null ? 'مطلوب' : null,
              ),
              TextFormField(
                controller: photoUrl,
                decoration:
                    const InputDecoration(labelText: 'رابط الصورة (اختياري)'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء')),
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
                'salary': isMonthly
                    ? double.tryParse(salary.text) ?? 0
                    : null,
                'role': role,
                'photo_url': photoUrl.text.trim().isEmpty
                    ? null
                    : photoUrl.text.trim(),
              });
            }
          },
        ),
      ],
    );
  }
}
// ... [CUT: rest of unchanged code, EmployeeDialog, etc.] ...
