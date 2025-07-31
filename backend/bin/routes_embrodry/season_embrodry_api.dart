// bin/routes_embrodry/seasons_embrodry_api.dart
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:postgres/postgres.dart';

Router getEmbrodrySeasonRoutes(PostgreSQLConnection db) {
  final router = Router();

  double _toD(dynamic v) =>
      v == null ? 0.0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0);
  int _toI(dynamic v) =>
      v == null ? 0 : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);

  // ---------------- SEASONS CRUD ----------------
  router.post('/', (Request req) async {
    try {
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final name = body['name'] as String?;
      final sd   = DateTime.parse(body['start_date']);
      final ed   = DateTime.parse(body['end_date']);

      if (name == null || name.isEmpty) {
        return Response(400,
            body: jsonEncode({'error': 'name required'}),
            headers: {'Content-Type': 'application/json'});
      }

      final res = await db.query('''
        INSERT INTO embroidery.seasons (name, start_date, end_date)
        VALUES (@n, @sd, @ed)
        RETURNING id, name, start_date, end_date
      ''', substitutionValues: {'n': name, 'sd': sd, 'ed': ed});

      final row = res.first;
      return Response(201,
          body: jsonEncode({
            'id': _toI(row[0]),
            'name': row[1],
            'start_date': row[2].toString(),
            'end_date': row[3].toString(),
          }),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': 'create season failed', 'details': e.toString()}),
          headers: {'Content-Type': 'application/json'});
    }
  });

  router.get('/', (Request req) async {
    try {
      final rows = await db.query('''
        SELECT id, name, start_date, end_date
        FROM embroidery.seasons
        ORDER BY start_date DESC
      ''');

      final list = rows
          .map((r) => {
                'id': _toI(r[0]),
                'name': r[1],
                'start_date': r[2].toString(),
                'end_date': r[3].toString(),
              })
          .toList();

      return Response.ok(jsonEncode(list),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': 'fetch seasons failed', 'details': e.toString()}),
          headers: {'Content-Type': 'application/json'});
    }
  });

  router.get('/<id>', (Request req, String id) async {
    try {
      final rows = await db.query('''
        SELECT id, name, start_date, end_date
        FROM embroidery.seasons
        WHERE id=@id
      ''', substitutionValues: {'id': _toI(id)});

      if (rows.isEmpty) {
        return Response.notFound(jsonEncode({'error': 'season not found'}),
            headers: {'Content-Type': 'application/json'});
      }

      final r = rows.first;
      return Response.ok(
          jsonEncode({
            'id': _toI(r[0]),
            'name': r[1],
            'start_date': r[2].toString(),
            'end_date': r[3].toString(),
          }),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': 'fetch season failed', 'details': e.toString()}),
          headers: {'Content-Type': 'application/json'});
    }
  });

  router.put('/<id>', (Request req, String id) async {
    try {
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final name = body['name'] as String?;
      final sd   = DateTime.parse(body['start_date']);
      final ed   = DateTime.parse(body['end_date']);

      if (name == null || name.isEmpty) {
        return Response(400,
            body: jsonEncode({'error': 'name required'}),
            headers: {'Content-Type': 'application/json'});
      }

      final count = await db.execute('''
        UPDATE embroidery.seasons
        SET name=@n, start_date=@sd, end_date=@ed
        WHERE id=@id
      ''', substitutionValues: {'n': name, 'sd': sd, 'ed': ed, 'id': _toI(id)});

      if (count == 0) {
        return Response.notFound(jsonEncode({'error': 'not found'}),
            headers: {'Content-Type': 'application/json'});
      }
      return Response.ok(jsonEncode({'message': 'updated'}),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': 'update failed', 'details': e.toString()}),
          headers: {'Content-Type': 'application/json'});
    }
  });

  router.delete('/<id>', (Request req, String id) async {
    try {
      final count = await db.execute(
          'DELETE FROM embroidery.seasons WHERE id=@id',
          substitutionValues: {'id': _toI(id)});
      if (count == 0) {
        return Response.notFound(jsonEncode({'error': 'not found'}),
            headers: {'Content-Type': 'application/json'});
      }
      return Response.ok(jsonEncode({'message': 'deleted'}),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': 'delete failed', 'details': e.toString()}),
          headers: {'Content-Type': 'application/json'});
    }
  });

  // ---------------- SEASON REPORT ----------------
  router.get('/<id>/report', (Request req, String id) async {
    try {
        final seasonQ = await db.query('''
            SELECT start_date, end_date
            FROM embroidery.seasons
            WHERE id=@id
        ''', substitutionValues: {'id': _toI(id)});

        if (seasonQ.isEmpty) {
            return Response.notFound(jsonEncode({'error': 'Season not found'}),
                headers: {'Content-Type': 'application/json'});
        }

        final startDate = seasonQ.first[0] as DateTime;
        final endDate = seasonQ.first[1] as DateTime;

        // ---------- TOTAL REVENUE ----------
        final revQ = await db.query('''
            SELECT COALESCE(SUM(fi.quantity * fi.unit_price), 0)
            FROM embroidery.facture_items fi
            JOIN embroidery.factures f ON fi.facture_id = f.id
            WHERE f.facture_date >= @sd AND f.facture_date <= @ed
        ''', substitutionValues: {'sd': startDate, 'ed': endDate});
        final totalRevenue = _toD(revQ.first[0]);

        // ---------- RETURNS VALUE ----------
        final retQ = await db.query('''
            SELECT COALESCE(SUM(r.quantity * fi.unit_price), 0)
            FROM embroidery.returns r
            JOIN embroidery.facture_items fi ON fi.facture_id = r.facture_id AND fi.model_id = r.model_id
            JOIN embroidery.factures f ON f.id = r.facture_id
            WHERE r.return_date >= @sd AND r.return_date <= @ed
        ''', substitutionValues: {'sd': startDate, 'ed': endDate});
        final totalReturnsValue = _toD(retQ.first[0]);

        // ---------- RAW MATERIALS USAGE ----------
        final rawQ = await db.query('''
            SELECT COALESCE(SUM(amount), 0)
            FROM embroidery.expenses
            WHERE expense_date >= @sd AND expense_date <= @ed AND expense_type = 'raw_materials'
        ''', substitutionValues: {'sd': startDate, 'ed': endDate});
        final rawUsage = _toD(rawQ.first[0]);

        // ---------- OTHER EXPENSES ----------
        final othQ = await db.query('''
            SELECT COALESCE(SUM(amount), 0)
            FROM embroidery.expenses
            WHERE expense_date >= @sd AND expense_date <= @ed AND expense_type <> 'raw_materials'
        ''', substitutionValues: {'sd': startDate, 'ed': endDate});
        final otherExpenses = _toD(othQ.first[0]);

        // ---------- TOTAL EMPLOYEE SALARIES ----------
        final empSalaryQ = await db.query('''
            SELECT COALESCE(SUM(salary), 0)
            FROM embroidery.employees
        ''');
        final totalSalaries = _toD(empSalaryQ.first[0]);

        // ---------- TOTAL PIECES AND QUANTITY ----------
        final piecesQ = await db.query('''
            SELECT COALESCE(SUM(quantity * piece_price), 0)
            FROM embroidery.piece_records
        ''');
        final totalPiecesValue = _toD(piecesQ.first[0]);

        // Update netProfit calculation to exclude totalSalaries and totalPiecesValue
        final netProfit = totalRevenue - totalReturnsValue - rawUsage - otherExpenses - totalSalaries - totalPiecesValue;

        // ---------- BY MODEL ----------
        final byModelQ = await db.query('''
            WITH sales AS (
                SELECT fi.model_id,
                       SUM(fi.quantity * fi.unit_price) AS revenue
                FROM embroidery.facture_items fi
                JOIN embroidery.factures f ON fi.facture_id = f.id
                WHERE f.facture_date >= @sd AND f.facture_date <= @ed
                GROUP BY fi.model_id
            ),
            returns AS (
                SELECT r.model_id,
                       SUM(r.quantity * fi.unit_price) AS returns_value
                FROM embroidery.returns r
                JOIN embroidery.facture_items fi ON fi.facture_id=r.facture_id AND fi.model_id=r.model_id
                JOIN embroidery.factures f ON f.id = r.facture_id
                WHERE r.return_date >= @sd AND r.return_date <= @ed
                GROUP BY r.model_id
            )
            SELECT m.id, m.model_name,
                   COALESCE(sales.revenue, 0) AS revenue,
                   COALESCE(returns.returns_value, 0) AS returns_value,
                   (COALESCE(sales.revenue, 0) - COALESCE(returns.returns_value, 0)) AS profit
            FROM embroidery.models m
            LEFT JOIN sales ON sales.model_id = m.id
            LEFT JOIN returns ON returns.model_id = m.id
            WHERE (sales.revenue IS NOT NULL OR returns.returns_value IS NOT NULL)
            ORDER BY profit DESC;
        ''', substitutionValues: {'sd': startDate, 'ed': endDate});

        final profitByModel = byModelQ.map((r) => {
            'model_id': _toI(r[0]),
            'model_name': r[1],
            'revenue': _toD(r[2]),
            'returns_value': _toD(r[3]),
            'profit': _toD(r[4]),
        }).toList();

        // ---------- BY CLIENT ----------
        final byClientQ = await db.query('''
            WITH sales AS (
                SELECT f.client_id,
                       SUM(fi.quantity * fi.unit_price) AS revenue
                FROM embroidery.facture_items fi
                JOIN embroidery.factures f ON fi.facture_id = f.id
                WHERE f.facture_date >= @sd AND f.facture_date <= @ed
                GROUP BY f.client_id
            ),
            returns AS (
                SELECT f.client_id,
                       SUM(r.quantity * fi.unit_price) AS returns_value
                FROM embroidery.returns r
                JOIN embroidery.facture_items fi ON fi.facture_id=r.facture_id AND fi.model_id=r.model_id
                JOIN embroidery.factures f ON f.id = r.facture_id
                WHERE r.return_date >= @sd AND r.return_date <= @ed
                GROUP BY f.client_id
            )
            SELECT c.id, c.full_name,
                   COALESCE(sales.revenue, 0) AS revenue,
                   COALESCE(returns.returns_value, 0) AS returns_value,
                   (COALESCE(sales.revenue, 0) - COALESCE(returns.returns_value, 0)) AS profit
            FROM embroidery.clients c
            LEFT JOIN sales ON sales.client_id = c.id
            LEFT JOIN returns ON returns.client_id = c.id
            WHERE (sales.revenue IS NOT NULL OR returns.returns_value IS NOT NULL)
            ORDER BY profit DESC;
        ''', substitutionValues: {'sd': startDate, 'ed': endDate});

        final profitByClient = byClientQ.map((r) => {
            'client_id': _toI(r[0]),
            'client_name': r[1],
            'revenue': _toD(r[2]),
            'returns_value': _toD(r[3]),
            'profit': _toD(r[4]),
        }).toList();

        return Response.ok(
            jsonEncode({
                'total_revenue': totalRevenue,
                'total_returns_value': totalReturnsValue,
                'raw_materials_usage': rawUsage,
                'other_expenses': otherExpenses,
                'total_salaries': totalSalaries,
                'total_pieces_value': totalPiecesValue,
                'net_profit': netProfit,
                'profit_by_model': profitByModel,
                'profit_by_client': profitByClient,
            }),
            headers: {'Content-Type': 'application/json'});
    } catch (e) {
        return Response.internalServerError(
            body: jsonEncode({'error': 'season report failed', 'details': e.toString()}),
            headers: {'Content-Type': 'application/json'});
    }
});


  return router;
}
