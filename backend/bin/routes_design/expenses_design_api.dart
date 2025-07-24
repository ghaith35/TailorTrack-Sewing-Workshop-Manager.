// lib/routes/design_expenses_api.dart
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:postgres/postgres.dart';

Router getDesignExpensesRoutes(PostgreSQLConnection db) {
  final router = Router();

  double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  Future<double?> _latestUnitPrice(int materialId) async {
    final q = await db.query('''
      SELECT pi.unit_price
      FROM design.purchase_items pi
      WHERE pi.material_id = @mid
      ORDER BY pi.id DESC
      LIMIT 1
    ''', substitutionValues: {'mid': materialId});
    if (q.isEmpty) return null;
    return _toDouble(q.first[0]);
  }

  // -------- GET /design/expenses/ --------
  router.get('/', (Request request) async {
    final qp = request.requestedUri.queryParameters;

    final cond = <String>[];
    final subs = <String, dynamic>{};
    // hide 'transport'
    cond.add("expense_type <> 'transport'");

    if (qp['type'] != null) {
      cond.add('expense_type = @type');
      subs['type'] = qp['type'];
    }
    if (qp['year'] != null && qp['month'] != null) {
      cond.add('EXTRACT(YEAR FROM expense_date) = @y');
      cond.add('EXTRACT(MONTH FROM expense_date) = @m');
      subs['y'] = int.parse(qp['year']!);
      subs['m'] = int.parse(qp['month']!);
    }

    final where = cond.isNotEmpty ? 'WHERE ${cond.join(" AND ")}' : '';

    final rows = await db.query('''
      SELECT e.id,
             e.expense_type,
             e.description,
             e.amount,
             e.expense_date,
             e.created_at,
             e.material_type_id,
             e.material_id,
             e.quantity,
             e.unit_price,
             mt.name  AS material_type_name,
             m.code   AS material_code
      FROM design.expenses e
      LEFT JOIN design.material_types mt ON mt.id = e.material_type_id
      LEFT JOIN design.materials      m  ON m.id  = e.material_id
      $where
      ORDER BY e.expense_date DESC, e.id DESC
    ''', substitutionValues: subs);

    final list = rows.map((r) => {
          'id'                 : r[0],
          'expense_type'       : r[1],
          'description'        : r[2],
          'amount'             : _toDouble(r[3]),
          'expense_date'       : r[4].toString(),
          'created_at'         : r[5].toString(),
          'material_type_id'   : r[6],
          'material_id'        : r[7],
          'quantity'           : _toDouble(r[8]),
          'unit_price'         : _toDouble(r[9]),
          'material_type_name' : r[10],
          'material_code'      : r[11],
        }).toList();

    return Response.ok(jsonEncode(list), headers: {'Content-Type': 'application/json'});
  });

  // -------- GET one --------
  router.get('/<id>', (Request request, String id) async {
    final rows = await db.query('''
      SELECT id, expense_type, description, amount, expense_date, created_at,
             material_type_id, material_id, quantity, unit_price
      FROM design.expenses
      WHERE id=@id
    ''', substitutionValues: {'id': int.parse(id)});

    if (rows.isEmpty) {
      return Response.notFound(jsonEncode({'error': 'Expense not found'}));
    }
    final r = rows.first;
    return Response.ok(jsonEncode({
      'id'              : r[0],
      'expense_type'    : r[1],
      'description'     : r[2],
      'amount'          : _toDouble(r[3]),
      'expense_date'    : r[4].toString(),
      'created_at'      : r[5].toString(),
      'material_type_id': r[6],
      'material_id'     : r[7],
      'quantity'        : _toDouble(r[8]),
      'unit_price'      : _toDouble(r[9]),
    }), headers: {'Content-Type': 'application/json'});
  });

  // -------- POST --------
  router.post('/', (Request request) async {
    try {
      final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final type = body['expense_type'] as String?;
      if (type == null) {
        return Response(400, body: jsonEncode({'error': 'expense_type required'}));
      }
      if (type == 'transport') {
        return Response(400, body: jsonEncode({'error': 'transport is hidden'}));
      }

      final desc = body['description'] as String? ?? '';
      final date = (body['expense_date'] as String?) != null
          ? DateTime.parse(body['expense_date'] as String)
          : DateTime.now();

      num amount;
      int? mTypeId;
      int? mId;
      double? q;
      double? up;

      if (type == 'raw_materials') {
        mTypeId = body['material_type_id'] as int?;
        mId     = body['material_id']     as int?;
        q       = _toDouble(body['quantity']);
        if (mId == null || q <= 0) {
          return Response(400, body: jsonEncode({'error': 'material_id & quantity required'}));
        }
        final price = await _latestUnitPrice(mId);
        if (price == null) {
          return Response(400, body: jsonEncode({'error': 'no purchases for this material'}));
        }
        up     = price;
        amount = up * q;
      } else {
        amount = _toDouble(body['amount']);
        if (amount <= 0) {
          return Response(400, body: jsonEncode({'error': 'amount must be > 0'}));
        }
      }

      final res = await db.query('''
        INSERT INTO design.expenses
          (expense_type, description, amount, expense_date,
           material_type_id, material_id, quantity, unit_price)
        VALUES (@t,@d,@a,@dt,@mt,@m,@q,@up)
        RETURNING id
      ''', substitutionValues: {
        't' : type,
        'd' : desc,
        'a' : amount,
        'dt': date,
        'mt': mTypeId,
        'm' : mId,
        'q' : q,
        'up': up,
      });

      return Response(201,
          body: jsonEncode({'id': res.first[0]}),
          headers: {'Content-Type': 'application/json'});
    } catch (e, st) {
      print('POST /design/expenses error: $e\n$st');
      return Response.internalServerError(
        body: jsonEncode({'error': 'server error', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // -------- PUT --------
  router.put('/<id>', (Request request, String id) async {
    try {
      final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final type = body['expense_type'] as String?;
      if (type == null) {
        return Response(400, body: jsonEncode({'error': 'expense_type required'}));
      }
      if (type == 'transport') {
        return Response(400, body: jsonEncode({'error': 'transport is hidden'}));
      }

      final desc = body['description'] as String? ?? '';
      final date = (body['expense_date'] as String?) != null
          ? DateTime.parse(body['expense_date'] as String)
          : DateTime.now();

      num amount;
      int? mTypeId;
      int? mId;
      double? q;
      double? up;

      if (type == 'raw_materials') {
        mTypeId = body['material_type_id'] as int?;
        mId     = body['material_id']     as int?;
        q       = _toDouble(body['quantity']);
        if (mId == null || q <= 0) {
          return Response(400, body: jsonEncode({'error': 'material_id & quantity required'}));
        }
        final price = await _latestUnitPrice(mId);
        if (price == null) {
          return Response(400, body: jsonEncode({'error': 'no purchases for this material'}));
        }
        up     = price;
        amount = up * q;
      } else {
        amount = _toDouble(body['amount']);
        if (amount <= 0) {
          return Response(400, body: jsonEncode({'error': 'amount must be > 0'}));
        }
      }

      final count = await db.execute('''
        UPDATE design.expenses
        SET expense_type=@t,
            description=@d,
            amount=@a,
            expense_date=@dt,
            material_type_id=@mt,
            material_id=@m,
            quantity=@q,
            unit_price=@up
        WHERE id=@id
      ''', substitutionValues: {
        't' : type,
        'd' : desc,
        'a' : amount,
        'dt': date,
        'mt': mTypeId,
        'm' : mId,
        'q' : q,
        'up': up,
        'id': int.parse(id),
      });

      if (count == 0) {
        return Response.notFound(jsonEncode({'error': 'Expense not found'}));
      }
      return Response.ok(jsonEncode({'message': 'Updated'}),
          headers: {'Content-Type': 'application/json'});
    } catch (e, st) {
      print('PUT /design/expenses error: $e\n$st');
      return Response.internalServerError(
        body: jsonEncode({'error': 'server error', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // -------- DELETE --------
  router.delete('/<id>', (Request request, String id) async {
    final cnt = await db.execute(
      'DELETE FROM design.expenses WHERE id=@id',
      substitutionValues: {'id': int.parse(id)},
    );
    if (cnt == 0) {
      return Response.notFound(jsonEncode({'error': 'Expense not found'}));
    }
    return Response.ok(jsonEncode({'message': 'Deleted'}),
        headers: {'Content-Type': 'application/json'});
  });

  return router;
}
