import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:postgres/postgres.dart';

Router getSeasonRoutes(PostgreSQLConnection db) {
  final router = Router();
num _num(dynamic v) => v == null
    ? 0.0
    : (v is num ? v : (num.tryParse(v.toString()) ?? 0.0));
int _int(dynamic v) => v == null
    ? 0
    : (v is int ? v : (int.tryParse(v.toString()) ?? 0));

  double parseNum(dynamic v) =>
      v == null ? 0.0 : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0);
  int parseInt(dynamic v) =>
      v == null ? 0 : (v is num ? v.toInt() : int.tryParse(v.toString()) ?? 0);

  // Create
  router.post('/', (Request req) async {
    try {
      final data = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final name = data['name'] as String;
      final startDate = DateTime.parse(data['start_date']);
      final endDate   = DateTime.parse(data['end_date']);

      final result = await db.query('''
        INSERT INTO sewing.seasons (name, start_date, end_date)
        VALUES (@name, @start_date, @end_date)
        RETURNING id, name, start_date, end_date
      ''', substitutionValues: {
        'name':       name,
        'start_date': startDate,
        'end_date':   endDate,
      });

      final row = result.first;
      return Response(201,
        body: jsonEncode({
          'id':         parseInt(row[0]),
          'name':       row[1],
          'start_date': (row[2] as DateTime).toIso8601String(),
          'end_date':   (row[3] as DateTime).toIso8601String(),
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to create season: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // Read all
  router.get('/', (Request _) async {
    try {
      final results = await db.query('''
        SELECT id, name, start_date, end_date
        FROM sewing.seasons
        ORDER BY start_date DESC
      ''');

      final seasons = results.map((r) => {
        'id':         parseInt(r[0]),
        'name':       r[1],
        'start_date': (r[2] as DateTime).toIso8601String(),
        'end_date':   (r[3] as DateTime).toIso8601String(),
      }).toList();

      return Response.ok(jsonEncode(seasons), headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch seasons: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // Read one
  router.get('/<id>', (Request _, String id) async {
    final sid = parseInt(id);
    try {
      final res = await db.query('''
        SELECT id, name, start_date, end_date
        FROM sewing.seasons
        WHERE id = @id
      ''', substitutionValues: {'id': sid});

      if (res.isEmpty) {
        return Response.notFound(
          jsonEncode({'error': 'Season not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final r = res.first;
      return Response.ok(jsonEncode({
        'id':         parseInt(r[0]),
        'name':       r[1],
        'start_date': (r[2] as DateTime).toIso8601String(),
        'end_date':   (r[3] as DateTime).toIso8601String(),
      }), headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch season: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // Update
  router.put('/<id>', (Request req, String id) async {
    final sid = parseInt(id);
    try {
      final data = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final name      = data['name'] as String;
      final startDate = DateTime.parse(data['start_date']);
      final endDate   = DateTime.parse(data['end_date']);

      await db.query('''
        UPDATE sewing.seasons
        SET name = @name, start_date = @start_date, end_date = @end_date
        WHERE id = @id
      ''', substitutionValues: {
        'id':         sid,
        'name':       name,
        'start_date': startDate,
        'end_date':   endDate,
      });

      return Response.ok(
        jsonEncode({'message': 'Season updated successfully'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to update season: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // Delete (also remove related season_reports)
  router.delete('/<id>', (Request _, String id) async {
    final sid = parseInt(id);
    try {
      await db.transaction((txn) async {
        await txn.query(
          'DELETE FROM sewing.season_reports WHERE season_id = @id',
          substitutionValues: {'id': sid},
        );
        await txn.query(
          'DELETE FROM sewing.seasons WHERE id = @id',
          substitutionValues: {'id': sid},
        );
      });

      return Response.ok(
        jsonEncode({'message': 'Season deleted successfully'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to delete season: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

   router.get('/<id>/profit', (Request request, String id) async {
    try {
      final sid = _int(id);
      // fetch season dates
      final seasonRes = await db.query(r'''
        SELECT start_date, end_date
        FROM sewing.seasons
        WHERE id = @id
      ''', substitutionValues: {'id': sid});
      if (seasonRes.isEmpty) {
        return Response.notFound(
          jsonEncode({'error': 'Season not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      final startDate = seasonRes.first[0] as DateTime;
      final endDate   = seasonRes.first[1] as DateTime;

      // compute revenue & COGS based on global_price only
      final profitRes = await db.query(r'''
        SELECT
          COALESCE(SUM(fi.quantity * fi.unit_price), 0)           AS total_revenue,
          COALESCE(SUM(fi.quantity * COALESCE(m.global_price,0)),0) AS total_cost_of_goods_sold
        FROM sewing.facture_items fi
        JOIN sewing.factures f   ON fi.facture_id = f.id
        JOIN sewing.models   m   ON fi.model_id     = m.id
        WHERE f.facture_date >= @start_date
          AND f.facture_date <= @end_date;
      ''', substitutionValues: {
        'start_date': startDate,
        'end_date':   endDate,
      });

      final totalRevenue         = _num(profitRes.first[0]);
      final totalCostOfGoodsSold = _num(profitRes.first[1]);
      final profitBeforeOthers   = totalRevenue - totalCostOfGoodsSold;

      // other expenses
      final otherRes = await db.query(r'''
        SELECT COALESCE(SUM(amount),0)
        FROM sewing.expenses
        WHERE expense_date >= @start_date
          AND expense_date <= @end_date
          AND expense_type = @type_other
      ''', substitutionValues: {
        'start_date': startDate,
        'end_date':   endDate,
        'type_other': 'custom'
      });
      final otherExpenses = _num(otherRes.first[0]);
      final netProfit     = profitBeforeOthers - otherExpenses;

      return Response.ok(
        jsonEncode({
          'total_revenue':             totalRevenue,
          'total_cost_of_goods_sold':  totalCostOfGoodsSold,
          'total_profit':              profitBeforeOthers,
          'other_expenses':            otherExpenses,
          'net_profit':                netProfit,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to calculate season profit: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });
  return router;
}
