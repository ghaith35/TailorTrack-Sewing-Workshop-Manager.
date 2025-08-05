import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:postgres/postgres.dart';
import 'dart:convert';

Router getEmbrodryEmployeesRoutes(PostgreSQLConnection db) {
  // print('Embroidery Employees API: Initializing routes');
  final router = Router();

  // Get all active employees
  router.get('/', (Request request) async {
  try {
    final result = await db.mappedResultsQuery(
      '''
      SELECT id, first_name, last_name, phone, address, payment_type,
             role, salary, photo_url, shift_hours
        FROM embroidery.employees
       WHERE status = @status
       ORDER BY id DESC
      ''',
      substitutionValues: {'status': 'active'},
    );

    final employees = result.map((row) {
      final emp = row.values.first;
      return {
        'id'          : emp['id'],
        'first_name'  : emp['first_name'],
        'last_name'   : emp['last_name'],
        'phone'       : emp['phone'],
        'address'     : emp['address'],
        'payment_type': emp['payment_type'],  // Added payment_type
        'role'        : emp['role'],
        'salary'      : emp['salary'] == null
                          ? null
                          : num.tryParse(emp['salary'].toString()),
        'photo_url'   : emp['photo_url'],
        'shift_hours' : emp['shift_hours'],
      };
    }).toList();

    return Response.ok(
      jsonEncode(employees),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e, stack) {
    print("ERROR: $e\n$stack");
    return Response.internalServerError(body: 'Internal Server Error: $e');
  }
});

  // Add new employee
  router.post('/', (Request request) async {
  final body = await request.readAsString();
  final data = jsonDecode(body);

  try {
    final res = await db.query(
      '''
      INSERT INTO embroidery.employees
        (first_name, last_name, phone, address, payment_type, role, salary, photo_url, shift_hours)
      VALUES
        (@first_name, @last_name, @phone, @address, @payment_type, @role, @salary, @photo_url, @shift_hours)
      RETURNING id
      ''',
      substitutionValues: {
        'first_name'  : data['first_name'],
        'last_name'   : data['last_name'],
        'phone'       : data['phone'],
        'address'     : data['address'],
        'payment_type': data['payment_type'],  // Added payment_type
        'role'        : data['role'],
        'salary'      : data['salary'],
        'photo_url'   : data['photo_url'],
        'shift_hours' : data['shift_hours'],
      },
    );

    return Response.ok(
      jsonEncode({'id': res.first[0]}),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e, stack) {
    print("ERROR: $e\n$stack");
    return Response.internalServerError(body: 'Internal Server Error: $e');
  }
});
  // Edit employee
  router.put('/<id|[0-9]+>', (Request request, String id) async {
    final body = await request.readAsString();
    final data = jsonDecode(body);

    try {
      await db.query(
        '''
        UPDATE embroidery.employees
           SET first_name  = @first_name,
               last_name   = @last_name,
               phone       = @phone,
               address     = @address,
               role = @role,
               salary      = @salary,
               photo_url   = @photo_url,
               shift_hours = @shift_hours
         WHERE id = @id
        ''',
        substitutionValues: {
          'first_name'  : data['first_name'],
          'last_name'   : data['last_name'],
          'phone'       : data['phone'],
          'address'     : data['address'],
          'role'        : data['role'],
          'salary'      : data['salary'],
          'photo_url'   : data['photo_url'],
          'shift_hours' : data['shift_hours'],
          'id'          : int.parse(id),
        },
      );

      return Response.ok('{"ok":true}');
    } catch (e, stack) {
      print("ERROR: $e\n$stack");
      return Response.internalServerError(body: 'Internal Server Error: $e');
    }
  });

  // Delete (soft) employee
  // ========== DELETE EMPLOYEE (hard delete if no dependencies) ==========
router.delete('/<id|[0-9]+>', (Request req, String id) async {
  try {
    final empId = int.parse(id);

    return await db.transaction((txn) async {
      // 1) Check for attendance records
      final attCountRow = await txn.query(
        '''SELECT COUNT(*) FROM embroidery.employee_attendance
           WHERE employee_id = @eid''',
        substitutionValues: {'eid': empId},
      );
      final attCount = attCountRow.first[0] as int;
      if (attCount > 0) {
        return Response(
          400,
          body: jsonEncode({
            'error':
              'Cannot delete employee $empId: has $attCount attendance record(s).'
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // 2) Check for piece records
      final pieceCountRow = await txn.query(
        '''SELECT COUNT(*) FROM embroidery.piece_records
           WHERE employee_id = @eid''',
        substitutionValues: {'eid': empId},
      );
      final pieceCount = pieceCountRow.first[0] as int;
      if (pieceCount > 0) {
        return Response(
          400,
          body: jsonEncode({
            'error':
              'Cannot delete employee $empId: has $pieceCount piece record(s).'
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // 3) Check for loans
      final loanCountRow = await txn.query(
        '''SELECT COUNT(*) FROM embroidery.employee_loans
           WHERE employee_id = @eid''',
        substitutionValues: {'eid': empId},
      );
      final loanCount = loanCountRow.first[0] as int;
      if (loanCount > 0) {
        return Response(
          400,
          body: jsonEncode({
            'error':
              'Cannot delete employee $empId: has $loanCount loan(s).'
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // 4) Check for debts
      final debtCountRow = await txn.query(
        '''SELECT COUNT(*) FROM embroidery.employee_debts
           WHERE employee_id = @eid''',
        substitutionValues: {'eid': empId},
      );
      final debtCount = debtCountRow.first[0] as int;
      if (debtCount > 0) {
        return Response(
          400,
          body: jsonEncode({
            'error':
              'Cannot delete employee $empId: has $debtCount debt record(s).'
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // 5) Finally, delete the employee
      final del = await txn.query(
        '''DELETE FROM embroidery.employees
           WHERE id = @eid
         RETURNING id''',
        substitutionValues: {'eid': empId},
      );
      if (del.isEmpty) {
        return Response.notFound(
          jsonEncode({'error': 'Employee not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      return Response.ok(
        jsonEncode({'deleted': empId}),
        headers: {'Content-Type': 'application/json'},
      );
    });
  } catch (e, st) {
    print('❌ DELETE /employees/$id ERROR: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Delete failed', 'details': e.toString()}),
      headers: {'Content-Type': 'application/json'},
    );
  }
});

  // Utility: format DateTime as YYYY-MM-DD
  String formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ==== Monthly Attendance ====
  // Utility: format DateTime as YYYY-MM-DD

// ==== Monthly Attendance ====
router.get('/attendance/monthly', (Request request) async {
  final month = request.url.queryParameters['month']; // format: YYYY-MM
  if (month == null) {
    return Response(400, body: 'month is required');
  }
  final firstDay = DateTime.parse('$month-01');
  final nextMonth = DateTime(firstDay.year, firstDay.month + 1, 1);
  final lastDay = nextMonth.subtract(const Duration(days: 1));
  final startDate = formatDate(firstDay);
  final endDate   = formatDate(lastDay);

  // print('Attendance Query: $startDate to $endDate');

  final result = await db.mappedResultsQuery(r'''
    SELECT employees.*, employee_attendance.*
      FROM embroidery.employees
      LEFT JOIN embroidery.employee_attendance
        ON employee_attendance.employee_id = employees.id
       AND employee_attendance.date >= @start
       AND employee_attendance.date <= @end
     WHERE employees.status = 'active'
       AND employees.payment_type = 'monthly'
     ORDER BY employees.id, employee_attendance.date
  ''', substitutionValues: {
    'start': startDate,
    'end'  : endDate,
  });

  // print('RAW RESULT: $result');

  // Group by employee
  final Map<int, dynamic> grouped = {};
  for (final row in result) {
    final emp = row['employees'] as Map<String, dynamic>?;
    final att = row['employee_attendance'] as Map<String, dynamic>?;
    if (emp == null) continue;
    final empId = emp['id'] as int?;
    if (empId == null) continue;

    if (!grouped.containsKey(empId)) {
      grouped[empId] = {
        'employee_id': empId,
        'first_name' : emp['first_name'] as String?,
        'last_name'  : emp['last_name'] as String?,
        'salary'     : emp['salary'] == null
                          ? null
                          : num.tryParse(emp['salary'].toString()),
        'shift_hours': emp['shift_hours'] as int?,
        'attendance' : <Map<String, dynamic>>[],
      };
    }

    if (att != null && att['id'] != null) {
      grouped[empId]['attendance'].add({
        'attendance_id': att['id'],
        'date'         : att['date']?.toString(),
        'check_in'     : att['check_in']?.toString(),
        'check_out'    : att['check_out']?.toString(),
      });
    }
  }

  return Response.ok(
    jsonEncode(grouped.values.toList()),
    headers: {'Content-Type': 'application/json'},
  );
});

// ==== Piece Attendance ====
router.get('/attendance/piece', (Request request) async {
  final month = request.url.queryParameters['month']; // format: YYYY‑MM
  if (month == null) {
    return Response(400, body: 'month is required');
  }
  final firstDay = DateTime.parse('$month-01');
  final nextMonth = DateTime(firstDay.year, firstDay.month + 1, 1);
  final lastDay = nextMonth.subtract(const Duration(days: 1));
  final startDate = formatDate(firstDay);
  final endDate   = formatDate(lastDay);

  // print('Piece Attendance Query: $startDate to $endDate');

  final result = await db.mappedResultsQuery(r'''
    SELECT employees.*, piece_records.*, models.model_name
      FROM embroidery.employees
      LEFT JOIN embroidery.piece_records
        ON piece_records.employee_id = employees.id
       AND piece_records.record_date >= @start
       AND piece_records.record_date <= @end
      LEFT JOIN embroidery.models
        ON piece_records.model_id = models.id
     WHERE employees.status = 'active'
       AND employees.payment_type = 'stitchly'
     ORDER BY employees.id, piece_records.record_date
  ''', substitutionValues: {
    'start': startDate,
    'end'  : endDate,
  });

  // print('RAW PIECE RESULT: $result');

  // Group by employee
  final Map<int, dynamic> grouped = {};
  for (final row in result) {
    final emp       = row['employees'] as Map<String, dynamic>?;
    final pr        = row['piece_records'] as Map<String, dynamic>?;
    final modelName = (row['models'] as Map<String, dynamic>?)?['model_name'] as String?;
    if (emp == null) continue;
    final empId = emp['id'] as int?;
    if (empId == null) continue;

    if (!grouped.containsKey(empId)) {
      grouped[empId] = {
        'employee_id'  : empId,
        'first_name'   : emp['first_name'] as String?,
        'last_name'    : emp['last_name'] as String?,
        'shift_hours'  : emp['shift_hours'] as int?,
        'piece_records': <Map<String, dynamic>>[],
      };
    }

    if (pr != null && pr['id'] != null) {
      grouped[empId]['piece_records'].add({
        'piece_id'   : pr['id'],
        'model_name' : modelName,
        'quantity'   : pr['quantity'] as int?,
        'piece_price': pr['piece_price'] == null
                          ? null
                          : num.tryParse(pr['piece_price'].toString()),
        'record_date': pr['record_date']?.toString(),
      });
    }
  }

  return Response.ok(
    jsonEncode(grouped.values.toList()),
    headers: {'Content-Type': 'application/json'},
  );
});

  // ========== LOANS CRUD ==========

  // GET /loans
  router.get('/loans', (Request request) async {
    final res = await db.mappedResultsQuery(r'''
      SELECT el.*,
            e.first_name,
            e.last_name
        FROM embroidery.employee_loans AS el
        JOIN embroidery.employees    AS e  ON e.id = el.employee_id
      ORDER BY el.loan_date DESC, el.id DESC
    ''');

    final loans = res.map((row) {
      final loan = row['employee_loans']!;
      final emp  = row['employees']!;
      return {
        'id'              : loan['id'],
        'employee_id'     : loan['employee_id'],
        'employee_name'   : '${emp['first_name']} ${emp['last_name']}',
        'amount'          : num.tryParse(loan['amount'].toString()) ?? 0,
        'duration_months' : loan['duration_months'],
        'loan_date'       : loan['loan_date']?.toString().substring(0,10),
      };
    }).toList();

    return Response.ok(
      jsonEncode(loans),
      headers: {'Content-Type': 'application/json'},
    );
  });

  // Add loan (with duration and automatic installments)
  router.post('/loans', (Request req) async {
    final data = jsonDecode(await req.readAsString());
    final empId   = data['employee_id'] as int;
    final amount  = (data['amount'] as num).toDouble();
    final dateStr = data['loan_date'] as String? ?? DateTime.now().toIso8601String().substring(0,10);
    final duration = data['duration_months'] as int? ?? 1;

    // 1) Insert base loan
    final res = await db.query('''
      INSERT INTO embroidery.employee_loans (employee_id, amount, loan_date, duration_months)
      VALUES (@eid, @amt, @ldate, @dur)
      RETURNING id
    ''', substitutionValues: {
      'eid': empId, 'amt': amount, 'ldate': dateStr, 'dur': duration,
    });
    final loanId = res.first[0] as int;

    // 2) Create equal installments
    final perInstallment = (amount / duration);
    DateTime baseDate = DateTime.parse(dateStr);
    for (var i = 0; i < duration; i++) {
      final due = DateTime(baseDate.year, baseDate.month + i, baseDate.day);
      await db.query('''
        INSERT INTO embroidery.employee_loan_installments
          (loan_id, installment_no, due_date, amount)
        VALUES (@lid, @no, @due, @amt)
      ''', substitutionValues: {
        'lid': loanId, 'no': i + 1, 'due': '${due.toIso8601String().substring(0,10)}', 'amt': perInstallment,
      });
    }

    return Response.ok(jsonEncode({'id': loanId}), headers: {'Content-Type':'application/json'});
  });

  // Edit loan: update duration, amount, loan_date and rebuild installments
  router.put('/loans/<id|[0-9]+>', (Request req, String id) async {
    final data = jsonDecode(await req.readAsString());
    final loanId  = int.parse(id);
    final empId   = data['employee_id'] as int;
    final amount  = (data['amount'] as num).toDouble();
    final dateStr = data['loan_date'] as String;
    final duration= data['duration_months'] as int? ?? 1;

    // 1) Update loan
    await db.query('''
      UPDATE embroidery.employee_loans
      SET employee_id=@eid, amount=@amt, loan_date=@ldate, duration_months=@dur
      WHERE id=@id
    ''', substitutionValues: {
      'eid': empId, 'amt': amount, 'ldate': dateStr, 'dur': duration, 'id': loanId,
    });

    // 2) Delete old installments
    await db.query(
      'DELETE FROM embroidery.employee_loan_installments WHERE loan_id=@lid',
      substitutionValues: {'lid': loanId},
    );

    // 3) Recreate installments (same logic as above)
    final perInst = amount / duration;
    DateTime baseDate = DateTime.parse(dateStr);
    for (var i = 0; i < duration; i++) {
      final due = DateTime(baseDate.year, baseDate.month + i, baseDate.day);
      await db.query('''
        INSERT INTO embroidery.employee_loan_installments
          (loan_id, installment_no, due_date, amount)
        VALUES (@lid, @no, @due, @amt)
      ''', substitutionValues: {
        'lid': loanId, 'no': i + 1, 'due': '${due.toIso8601String().substring(0,10)}', 'amt': perInst,
      });
    }

    return Response.ok(jsonEncode({'ok': true}), headers: {'Content-Type':'application/json'});
  });

  // Delete loan
  router.delete('/loans/<id|[0-9]+>', (Request req, String id) async {
    final loanId = int.parse(id);
    
    // Delete installments first
    await db.query(
      'DELETE FROM embroidery.employee_loan_installments WHERE loan_id=@lid',
      substitutionValues: {'lid': loanId},
    );
    
    // Delete loan
    await db.query(
      'DELETE FROM embroidery.employee_loans WHERE id=@id',
      substitutionValues: {'id': loanId},
    );
    
    return Response.ok(jsonEncode({'ok': true}), headers: {'Content-Type':'application/json'});
  });

  // ========== PIECE RECORDS CRUD ==========
  router.get('/pieces', (Request request) async {
    final res = await db.mappedResultsQuery('''
      SELECT piece_records.*, employees.first_name, employees.last_name, models.model_name
      FROM embroidery.piece_records
      JOIN embroidery.employees ON employees.id = piece_records.employee_id
      JOIN embroidery.models ON models.id = piece_records.model_id
      ORDER BY piece_records.record_date DESC, piece_records.id DESC
    ''');
    final pieces = res.map((row) {
      final pr = row['piece_records'] as Map<String, dynamic>?;
      final emp = row['employees'] as Map<String, dynamic>?;
      final model = row['models'] as Map<String, dynamic>?;
      return {
        'id': pr?['id'],
        'employee_id': pr?['employee_id'],
        'employee_name': '${emp?['first_name'] ?? ''} ${emp?['last_name'] ?? ''}',
        'model_id': pr?['model_id'],
        'model_name': model?['model_name'] ?? '',
        'quantity': pr?['quantity'],
        'piece_price': pr?['piece_price'] == null ? null : num.tryParse(pr?['piece_price']?.toString() ?? ''),
        'record_date': pr?['record_date']?.toString(),
      };
    }).toList();
    return Response.ok(jsonEncode(pieces), headers: {'Content-Type': 'application/json'});
  });

  // Add piece record
  router.post('/pieces', (Request request) async {
    final body = await request.readAsString();
    final data = jsonDecode(body);
    final res = await db.query('''
      INSERT INTO embroidery.piece_records (employee_id, model_id, quantity, piece_price, record_date)
      VALUES (@employee_id, @model_id, @quantity, @piece_price, @record_date)
      RETURNING id
    ''', substitutionValues: {
      'employee_id': data['employee_id'],
      'model_id': data['model_id'],
      'quantity': data['quantity'],
      'piece_price': data['piece_price'],
      'record_date': data['record_date'] ?? DateTime.now().toIso8601String().substring(0,10),
    });
    return Response.ok(jsonEncode({'id': res.first[0]}));
  });

  // Edit piece record
  router.put('/pieces/<id|[0-9]+>', (Request request, String id) async {
    final body = await request.readAsString();
    final data = jsonDecode(body);
    await db.query('''
      UPDATE embroidery.piece_records 
        SET employee_id=@employee_id, model_id=@model_id, quantity=@quantity, piece_price=@piece_price, record_date=@record_date
      WHERE id=@id
    ''', substitutionValues: {
      'employee_id': data['employee_id'],
      'model_id': data['model_id'],
      'quantity': data['quantity'],
      'piece_price': data['piece_price'],
      'record_date': data['record_date'],
      'id': int.parse(id),
    });
    return Response.ok('{"ok":true}');
  });

  // Delete piece record
  router.delete('/pieces/<id|[0-9]+>', (Request request, String id) async {
    await db.query('DELETE FROM embroidery.piece_records WHERE id=@id', substitutionValues: {'id': int.parse(id)});
    return Response.ok('{"ok":true}');
  });

  // ========== Supporting Endpoints ==========

  // List all employees (can filter by payment_type)
  router.get('/list', (Request request) async {
    final paymentType = request.url.queryParameters['payment_type'];
    var sql = '''
      SELECT id, first_name, last_name, phone, address,
             role, salary, photo_url, shift_hours
        FROM embroidery.employees
       WHERE status = @status
    ''';
    var values = {'status': 'active'};

    if (paymentType != null) {
      sql += ' AND payment_type = @payment_type';
      values['payment_type'] = paymentType;
    }

    sql += ' ORDER BY first_name, last_name';

    final result = await db.query(sql, substitutionValues: values);

    final employees = result.map((row) {
      return {
        'id'          : row[0],
        'first_name'  : row[1],
        'last_name'   : row[2],
        'phone'       : row[3],
        'address'     : row[4],
        'payment_type': row[5],
        'salary'      : row[6],
        'photo_url'   : row[7],
        'shift_hours' : row[8],
      };
    }).toList();

    return Response.ok(
      jsonEncode(employees),
      headers: {'Content-Type': 'application/json'},
    );
  });

  // Bulk attendance creation
  router.post('/attendance/bulk', (Request req) async {
    final List<dynamic> attendanceRecords = jsonDecode(await req.readAsString());

    try {
      for (var record in attendanceRecords) {
        final empId = record['employee_id'];
        final date = record['date'];
        final checkIn = record['check_in'];
        final checkOut = record['check_out'];

        await db.query('''
          INSERT INTO embroidery.employee_attendance (employee_id, date, check_in, check_out)
          VALUES (@eid, @date, @in, @out)
          ON CONFLICT (employee_id, date) DO UPDATE SET check_in = @in, check_out = @out
        ''', substitutionValues: {
          'eid': empId,
          'date': date,
          'in': checkIn,
          'out': checkOut,
        });
      }
      return Response.ok('{"status": "success"}', headers: {'Content-Type': 'application/json'});
    } catch (e) {
      print("ERROR: $e");
      return Response.internalServerError(body: 'Internal Server Error: $e');
    }
  });

  // =============================
  // Monthly loan summary
  // =============================
  router.get('/loans/monthly-summary', (Request request) async {
    final month = request.url.queryParameters['month'];
    if (month == null) return Response(400, body: 'month is required');

    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    final firstDay  = DateTime.parse('$month-01');
    final nextMonth = DateTime(firstDay.year, firstDay.month + 1, 1);
    final lastDay   = nextMonth.subtract(const Duration(days: 1));
    final startDate = fmt(firstDay);
    final endDate   = fmt(lastDay);
    final today     = fmt(DateTime.now());

    // await db.transaction((ctx) async {
    //   // Aggregate unpaid installments first, then update
    //   await ctx.query(r'''
    //     WITH due AS (
    //       SELECT inst.loan_id,
    //              SUM(inst.amount) AS amt_sum,
    //              COUNT(*)         AS cnt
    //       FROM   embroidery.employee_loan_installments inst
    //       WHERE  inst.due_date BETWEEN @start AND @end
    //         AND  inst.is_paid = FALSE
    //       GROUP  BY inst.loan_id
    //     ),
    //     mark AS (
    //       UPDATE embroidery.employee_loan_installments inst
    //          SET is_paid = TRUE,
    //              paid_date = @today
    //        WHERE inst.due_date BETWEEN @start AND @end
    //          AND inst.is_paid = FALSE
    //       RETURNING loan_id
    //     )
    //     UPDATE embroidery.employee_loans el
    //        SET amount          = GREATEST(el.amount - d.amt_sum, 0),
    //            duration_months = GREATEST(el.duration_months - d.cnt, 0)
    //     FROM due d
    //     WHERE d.loan_id = el.id;
    //   ''', substitutionValues: {
    //     'today': today,
    //     'start': startDate,
    //     'end'  : endDate,
    //   });
    // });

    // Helper to coerce any DB value to num
    num _toNum(dynamic v) {
      if (v is num) return v;
      if (v == null) return 0;
      return num.tryParse(v.toString()) ?? 0;
    }

    final rows = await db.query(r'''
      WITH monthly AS (
        SELECT e.employee_id,
               SUM(i.amount) AS monthly_due
          FROM embroidery.employee_loans AS e
          JOIN embroidery.employee_loan_installments AS i
            ON i.loan_id = e.id
         WHERE i.due_date BETWEEN @startDate AND @endDate
         GROUP BY e.employee_id
      ),
      totals AS (
        SELECT e.employee_id,
               SUM(e.amount) AS total_loan,
               SUM(CASE WHEN i.is_paid = false THEN i.amount ELSE 0 END) AS remaining_loan
          FROM embroidery.employee_loans AS e
          JOIN embroidery.employee_loan_installments AS i
            ON i.loan_id = e.id
         GROUP BY e.employee_id
      )
      SELECT e.id AS employee_id,
             COALESCE(m.monthly_due, 0)    AS monthly_due,
             COALESCE(t.total_loan, 0)     AS total_loan,
             COALESCE(t.remaining_loan, 0) AS remaining_loan
        FROM embroidery.employees AS e
        LEFT JOIN monthly AS m ON m.employee_id = e.id
        LEFT JOIN totals  AS t ON t.employee_id = e.id
       WHERE e.status = 'active'
    ''', substitutionValues: {
      'startDate': startDate,
      'endDate'  : endDate,
    });

    final Map<String, Map<String, num>> flatMap = {};
    for (final r in rows) {
      final empId = r[0].toString();
      flatMap[empId] = {
        'monthly_due'   : _toNum(r[1]),
        'total_loan'    : _toNum(r[2]),
        'remaining_loan': _toNum(r[3]),
      };
    }

    return Response.ok(
      jsonEncode(flatMap),
      headers: {'Content-Type': 'application/json'},
    );
  });

  // Search employees route
  router.get('/search', (Request request) async {
    final query = request.url.queryParameters['q']?.toLowerCase() ?? '';
    final paymentType = request.url.queryParameters['payment_type'];
    
    try {
      var sql = '''
        SELECT id, first_name, last_name, phone, address,
               role, salary, photo_url, shift_hours
          FROM embroidery.employees
         WHERE status = 'active'
           AND (LOWER(first_name) LIKE @query
                OR LOWER(last_name) LIKE @query
                OR LOWER(phone) LIKE @query
                OR LOWER(address) LIKE @query
                OR (salary IS NOT NULL AND salary::text LIKE @query)
                OR shift_hours::text LIKE @query)
      ''';
      
      var values = {'query': '%$query%'};
      
      if (paymentType != null) {
        sql += ' AND payment_type = @payment_type';
        values['payment_type'] = paymentType;
      }
      
      sql += ' ORDER BY first_name, last_name';
      
      final result = await db.mappedResultsQuery(sql, substitutionValues: values);
      
      final employees = result.map((row) {
        final emp = row.values.first;
        return {
          'id': emp['id'],
          'first_name': emp['first_name'],
          'last_name': emp['last_name'],
          'phone': emp['phone'],
          'address': emp['address'],
          'role'        : emp['role'],
          'salary': emp['salary'] == null ? null : num.tryParse(emp['salary'].toString()),
          'photo_url': emp['photo_url'],
          'shift_hours': emp['shift_hours'],
        };
      }).toList();
      
      return Response.ok(
        jsonEncode(employees),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stack) {
      print("ERROR: $e\n$stack");
      return Response.internalServerError(body: 'Internal Server Error: $e');
    }
  });

  // Get attendance years with data
  router.get('/attendance/years', (Request request) async {
    final attType = request.url.queryParameters['type'] ?? 'monthly';
    
    try {
      List<int> years = [];
      
      if (attType == 'monthly') {
        final result = await db.query('''
          SELECT DISTINCT EXTRACT(YEAR FROM date)::int as year
          FROM embroidery.employee_attendance
          ORDER BY year DESC
        ''');
        years = result.map((row) => row[0] as int).toList();
      } else {
        final result = await db.query('''
          SELECT DISTINCT EXTRACT(YEAR FROM record_date)::int as year
          FROM embroidery.piece_records
          ORDER BY year DESC
        ''');
        years = result.map((row) => row[0] as int).toList();
      }
      
      return Response.ok(
        jsonEncode(years),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      print("ERROR: $e");
      return Response.internalServerError(body: 'Internal Server Error: $e');
    }
  });

  // Get months with data for a specific year
  router.get('/attendance/months', (Request request) async {
    final year = request.url.queryParameters['year'];
    final attType = request.url.queryParameters['type'] ?? 'monthly';
    
    if (year == null) {
      return Response(400, body: 'year is required');
    }
    
    try {
      List<String> months = [];
      
      if (attType == 'monthly') {
        final result = await db.query('''
          SELECT DISTINCT TO_CHAR(date, 'YYYY-MM') as month
          FROM embroidery.employee_attendance
          WHERE EXTRACT(YEAR FROM date) = @year
          ORDER BY month DESC
        ''', substitutionValues: {'year': int.parse(year)});
        months = result.map((row) => row[0] as String).toList();
      } else {
        final result = await db.query('''
          SELECT DISTINCT TO_CHAR(record_date, 'YYYY-MM') as month
          FROM embroidery.piece_records
          WHERE EXTRACT(YEAR FROM record_date) = @year
          ORDER BY month DESC
        ''', substitutionValues: {'year': int.parse(year)});
        months = result.map((row) => row[0] as String).toList();
      }
      
      return Response.ok(
        jsonEncode(months),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      print("ERROR: $e");
      return Response.internalServerError(body: 'Internal Server Error: $e');
    }
  });
  // ─── Hard-delete an embroidery employee and all their data ───────────────────
  router.delete('/hard/<id|[0-9]+>', (Request req, String id) async {
    final empId = int.parse(id);

    await db.transaction((txn) async {
      // 1) Attendance
      await txn.query(
        'DELETE FROM embroidery.employee_attendance WHERE employee_id = @eid',
        substitutionValues: {'eid': empId},
      );
      // 2) Piece records
      await txn.query(
        'DELETE FROM embroidery.piece_records WHERE employee_id = @eid',
        substitutionValues: {'eid': empId},
      );
      // 3) Loan installments → loans
      await txn.query(
        '''DELETE FROM embroidery.employee_loan_installments
           WHERE loan_id IN (
             SELECT id FROM embroidery.employee_loans WHERE employee_id = @eid
           )''',
        substitutionValues: {'eid': empId},
      );
      await txn.query(
        'DELETE FROM embroidery.employee_loans WHERE employee_id = @eid',
        substitutionValues: {'eid': empId},
      );
      // 4) Debts
      await txn.query(
        'DELETE FROM embroidery.employee_debts WHERE employee_id = @eid',
        substitutionValues: {'eid': empId},
      );
      // 5) Finally, the employee record
      await txn.query(
        'DELETE FROM embroidery.employees WHERE id = @eid',
        substitutionValues: {'eid': empId},
      );
    });

    return Response.ok(
      jsonEncode({'ok': true}),
      headers: {'Content-Type': 'application/json'},
    );
  });

  // // Check if employee has active loan
  // router.get('/loans/check/<id|[0-9]+>', (Request request, String id) async {
  //   final empId = int.parse(id);
    
  //   try {
  //     final result = await db.query('''
  //       SELECT COUNT(*) > 0 as has_active_loan
  //       FROM embroidery.employee_loans el
  //       JOIN embroidery.employee_loan_installments eli ON eli.loan_id = el.id
  //       WHERE el.employee_id = @empId
  //         AND eli.is_paid = false
  //     ''', substitutionValues: {'empId': empId});
      
  //     final hasActiveLoan = result.first[0] as bool;
      
  //     return Response.ok(
  //       jsonEncode({'has_active_loan': hasActiveLoan}),
  //       headers: {'Content-Type': 'application/json'},
  //     );
  //   } catch (e) {
  //     print("ERROR: $e");
  //     return Response.internalServerError(body: 'Internal Server Error: $e');
  //   }
  // });
router.get('/loans/check/<id|[0-9]+>', (Request request, String id) async {
  final empId = int.parse(id);

  // 1) Find the latest "block end" among all loans: loan_date + duration_months
  final res = await db.query(r'''
    SELECT MAX(
      (loan_date::date + (duration_months || ' months')::interval)
    )::date AS next_available
    FROM embroidery.employee_loans
    WHERE employee_id = @empId
  ''', substitutionValues: {'empId': empId});

  // 2) Parse result
  final nextAvailable = res.first[0] as DateTime?;
  final today         = DateTime.now();
  final hasActiveLoan =
    nextAvailable != null && today.isBefore(nextAvailable);

  // 3) Return both a boolean and the unblock date
  return Response.ok(
    jsonEncode({
      'has_active_loan'    : hasActiveLoan,
      'next_available_date': nextAvailable?.toIso8601String().substring(0,10),
    }),
    headers: {'Content-Type': 'application/json'},
  );
});
  // Get models for piece records
  router.get('/models', (Request req) async {
    final res = await db.query('''
      SELECT id, model_name
      FROM embroidery.models
      ORDER BY model_name
    ''');
    final models = res.map((row) => {
      'id': row[0],
      'name': row[1],
    }).toList();
    return Response.ok(jsonEncode(models), headers: {'Content-Type': 'application/json'});
  });

  // List debts
  router.get('/debts', (Request req) async {
    final res = await db.mappedResultsQuery(r'''
      SELECT d.*, e.first_name, e.last_name
        FROM embroidery.employee_debts AS d
        JOIN embroidery.employees AS e ON e.id = d.employee_id
       ORDER BY d.debt_date DESC, d.id DESC
    ''');
    final out = res.map((row) {
      final d = row['employee_debts']!;
      final e = row['employees']!;
      return {
        'id': d['id'],
        'employee_id': d['employee_id'],
        'employee_name': '${e['first_name']} ${e['last_name']}',
        'amount': num.tryParse(d['amount'].toString()) ?? 0,
        'debt_date': d['debt_date']?.toString().substring(0, 10),
      };
    }).toList();
    return Response.ok(jsonEncode(out), headers: {'Content-Type':'application/json'});
  });

  // Create debt
  router.post('/debts', (Request req) async {
    final data = jsonDecode(await req.readAsString());
    final res = await db.query(r'''
      INSERT INTO embroidery.employee_debts (employee_id, amount, debt_date)
      VALUES (@eid, @amt, @ddate)
      RETURNING id
    ''', substitutionValues: {
      'eid': data['employee_id'],
      'amt': data['amount'],
      'ddate': data['debt_date'] ?? DateTime.now().toIso8601String().substring(0,10),
    });
    return Response.ok(jsonEncode({'id': res.first[0]}), headers: {'Content-Type':'application/json'});
  });

  // Update debt
  router.put('/debts/<id|[0-9]+>', (Request req, String id) async {
    final data = jsonDecode(await req.readAsString());
    await db.query(r'''
      UPDATE embroidery.employee_debts
         SET employee_id=@eid, amount=@amt, debt_date=@ddate
       WHERE id=@id
    ''', substitutionValues: {
      'eid': data['employee_id'],
      'amt': data['amount'],
      'ddate': data['debt_date'],
      'id': int.parse(id),
    });
    return Response.ok('{"ok":true}');
  });

  // Delete debt
  router.delete('/debts/<id|[0-9]+>', (Request req, String id) async {
    await db.query('DELETE FROM embroidery.employee_debts WHERE id=@id',
      substitutionValues: {'id': int.parse(id)});
    return Response.ok('{"ok":true}');
  });

  // Monthly summary of debts
  router.get('/debts/monthly-summary', (Request req) async {
    final month = req.url.queryParameters['month'];
    if (month == null) return Response(400, body: 'month is required');
    final firstDay = DateTime.parse('$month-01');
    final nextMonth = DateTime(firstDay.year, firstDay.month+1, 1);
    final lastDay = nextMonth.subtract(Duration(days:1));
    final start = '${firstDay.year}-${firstDay.month.toString().padLeft(2,'0')}-01';
    final end   = '${lastDay.year}-${lastDay.month.toString().padLeft(2,'0')}-${lastDay.day.toString().padLeft(2,'0')}';

    try {
      final rows = await db.query(r'''
        SELECT employee_id, COALESCE(SUM(amount), 0) AS total_debt
        FROM embroidery.employee_debts
        WHERE debt_date BETWEEN @start AND @end
        GROUP BY employee_id
      ''', substitutionValues:{'start':start,'end':end});

      final Map<String,num> map = {};
      for (var r in rows) {
        final empId = r[0].toString();
        final val = r[1];
        num totalDebt;
        if (val == null) {
          totalDebt = 0;
        } else if (val is num) {
          totalDebt = val;
        } else if (val is String) {
          totalDebt = num.tryParse(val) ?? 0;
        } else {
          totalDebt = 0;
        }
        map[empId] = totalDebt;
      }
      return Response.ok(jsonEncode(map), headers: {'Content-Type':'application/json'});
    } catch (e, st) {
      print('⚠️ Error in /debts/monthly-summary: $e\n$st');
      return Response.internalServerError(body: 'Server error: $e');
    }
  });

  // ─── Create attendance ──────────────────────────────────
  router.post('/attendance', (Request req) async {
    final data = jsonDecode(await req.readAsString());
    final empId   = data['employee_id'] as int;
    final date    = data['date']       as String; // "YYYY-MM-DD"
    final inTs    = data['check_in']  as String?;
    final outTs   = data['check_out'] as String?;
    final res = await db.query(r'''
      INSERT INTO embroidery.employee_attendance
        (employee_id, date, check_in, check_out)
      VALUES (@eid, @date, @in, @out)
      RETURNING id
    ''', substitutionValues:{
      'eid' : empId,
      'date': date,
      'in'  : inTs,
      'out' : outTs,
    });
    return Response.ok(jsonEncode({'id': res.first[0]}),
        headers: {'Content-Type':'application/json'});
  });

  // ─── Update attendance ──────────────────────────────────
  router.put('/attendance/<id|[0-9]+>', (Request req, String id) async {
    final data = jsonDecode(await req.readAsString());
    await db.query(r'''
      UPDATE embroidery.employee_attendance
         SET date     = @date,
             check_in = @in,
             check_out= @out
       WHERE id = @aid
    ''', substitutionValues:{
      'aid' : int.parse(id),
      'date': data['date'],
      'in'  : data['check_in'],
      'out' : data['check_out'],
    });
    return Response.ok('{"ok":true}', headers: {'Content-Type':'application/json'});
  });

  // ─── Delete attendance ──────────────────────────────────
  router.delete('/attendance/<id|[0-9]+>', (Request req, String id) async {
    await db.query('DELETE FROM embroidery.employee_attendance WHERE id = @aid',
        substitutionValues:{'aid': int.parse(id)});
    return Response.ok('{"ok":true}');
  });

  // ─── Fetch all attendance ──────────────────────────────────
  // ─── Fetch (and filter) attendance ──────────────────────────────────
router.get('/attendance', (Request req) async {
    final yearStr  = req.url.queryParameters['year'];
    final monthStr = req.url.queryParameters['month'];
    final dayStr   = req.url.queryParameters['day'];

    // Build the WHERE clause
    final whereClauses = <String>[];
    final subs = <String, dynamic>{};

    if (yearStr != null) {
        whereClauses.add("EXTRACT(YEAR FROM a.date) = @year");
        subs['year'] = int.parse(yearStr);
    }
    
    if (monthStr != null) {
        // Extract the month from the YYYY-MM format
        final monthParts = monthStr.split('-');
        if (monthParts.length == 2) {
            whereClauses.add("EXTRACT(MONTH FROM a.date) = @month");
            subs['month'] = int.parse(monthParts[1]); // Get the month part
        }
    }
    
    if (dayStr != null) {
        whereClauses.add("EXTRACT(DAY FROM a.date) = @day");
        subs['day'] = int.parse(dayStr);
    }

    // Build the SQL query
    var sql = r'''
        SELECT 
            a.id,
            a.employee_id,
            e.first_name || ' ' || e.last_name AS employee_name,
            to_char(a.date, 'YYYY-MM-DD')    AS date,
            to_char(a.check_in, 'HH24:MI')   AS check_in,
            to_char(a.check_out,'HH24:MI')   AS check_out
        FROM embroidery.employee_attendance a
        JOIN embroidery.employees e
          ON e.id = a.employee_id
    ''';

    if (whereClauses.isNotEmpty) {
        sql += '\n WHERE ' + whereClauses.join(' AND ');
    }

    sql += '\n ORDER BY a.date DESC, a.employee_id';

    // Execute the query
    final rows = await db.query(sql, substitutionValues: subs);

    final data = rows.map((r) => {
        'attendance_id' : r[0],
        'employee_id'   : r[1],
        'employee_name' : r[2],
        'date'          : r[3],
        'check_in'      : r[4],
        'check_out'     : r[5],
    }).toList();

    return Response.ok(jsonEncode(data), headers: {'Content-Type':'application/json'});
});


  return router;
}

