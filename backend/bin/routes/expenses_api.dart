// lib/routes/expenses_api.dart

import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:postgres/postgres.dart';

Router getExpensesRoutes(PostgreSQLConnection db) {
  final router = Router();

  // Helper to parse amount field which may come as String or num
  double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  // GET /expenses/ — list all, with optional filtering
  router.get('/', (Request request) async {
    final qp = request.requestedUri.queryParameters;
    final conditions = <String>[];
    final subs = <String, dynamic>{};

    if (qp['type'] != null) {
      conditions.add('expense_type = @type');
      subs['type'] = qp['type'];
    }
    if (qp['year'] != null && qp['month'] != null) {
      conditions.add('EXTRACT(YEAR FROM expense_date) = @year');
      conditions.add('EXTRACT(MONTH FROM expense_date) = @month');
      subs['year'] = int.parse(qp['year']!);
      subs['month'] = int.parse(qp['month']!);
    }

    final where = conditions.isNotEmpty ? 'WHERE ' + conditions.join(' AND ') : '';
    final rows = await db.query(
      '''
      SELECT id, expense_type, description, amount, expense_date, created_at
      FROM sewing.expenses
      $where
      ORDER BY expense_date DESC
      ''',
      substitutionValues: subs,
    );

    final list = rows.map((r) {
      return {
        'id': r[0],
        'expense_type': r[1],
        'description': r[2],
        'amount': _toDouble(r[3]),
        'expense_date': r[4].toString(),
        'created_at': r[5].toString(),
      };
    }).toList();

    return Response.ok(jsonEncode(list),
        headers: {'Content-Type': 'application/json'});
  });

  // GET /expenses/{id}
  router.get('/<id>', (Request request, String id) async {
    final rows = await db.query(
      '''
      SELECT id, expense_type, description, amount, expense_date, created_at
      FROM sewing.expenses
      WHERE id = @id
      ''',
      substitutionValues: {'id': int.parse(id)},
    );

    if (rows.isEmpty) {
      return Response.notFound(jsonEncode({'error': 'Expense not found'}));
    }

    final r = rows.first;
    final exp = {
      'id': r[0],
      'expense_type': r[1],
      'description': r[2],
      'amount': _toDouble(r[3]),
      'expense_date': r[4].toString(),
      'created_at': r[5].toString(),
    };
    return Response.ok(jsonEncode(exp),
        headers: {'Content-Type': 'application/json'});
  });

  // POST /expenses/ — create
  router.post('/', (Request request) async {
    final body = jsonDecode(await request.readAsString()) as Map;
    final type = body['expense_type'] as String?;
    final amt = (body['amount'] as num?)?.toDouble();
    final desc = body['description'] as String? ?? '';
    final date = body['expense_date'] as String?;

    if (type == null || amt == null) {
      return Response(400,
          body: jsonEncode({'error': 'Type and amount are required'}));
    }

    final result = await db.query(
      '''
      INSERT INTO sewing.expenses (expense_type, description, amount, expense_date)
      VALUES (@type, @desc, @amount, @date)
      RETURNING id
      ''',
      substitutionValues: {
        'type': type,
        'desc': desc,
        'amount': amt,
        'date': date != null ? DateTime.parse(date) : DateTime.now(),
      },
    );

    return Response(201,
        body: jsonEncode({'id': result.first[0]}),
        headers: {'Content-Type': 'application/json'});
  });

  // PUT /expenses/{id} — update
  router.put('/<id>', (Request request, String id) async {
    final body = jsonDecode(await request.readAsString()) as Map;
    final type = body['expense_type'] as String?;
    final amt = (body['amount'] as num?)?.toDouble();
    final desc = body['description'] as String? ?? '';
    final date = body['expense_date'] as String?;

    if (type == null || amt == null) {
      return Response(400,
          body: jsonEncode({'error': 'Type and amount are required'}));
    }

    final count = await db.execute(
      '''
      UPDATE sewing.expenses
      SET expense_type=@type, description=@desc, amount=@amount, expense_date=@date
      WHERE id=@id
      ''',
      substitutionValues: {
        'type': type,
        'desc': desc,
        'amount': amt,
        'date': date != null ? DateTime.parse(date) : DateTime.now(),
        'id': int.parse(id),
      },
    );

    if (count == 0) {
      return Response.notFound(jsonEncode({'error': 'Expense not found'}));
    }
    return Response.ok(jsonEncode({'message': 'Updated'}));
  });

  // DELETE /expenses/{id}
  router.delete('/<id>', (Request request, String id) async {
    final count = await db.execute(
      'DELETE FROM sewing.expenses WHERE id=@id',
      substitutionValues: {'id': int.parse(id)},
    );
    if (count == 0) {
      return Response.notFound(jsonEncode({'error': 'Expense not found'}));
    }
    return Response.ok(jsonEncode({'message': 'Deleted'}));
  });

  return router;
}
