import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:postgres/postgres.dart';

Router getSeasonRoutes(PostgreSQLConnection db) {
  final router = Router();

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
      final seasonResult = await db.query("""
        SELECT start_date, end_date
        FROM sewing.seasons
        WHERE id = @id
      """, substitutionValues: {'id': parseInt(id)});

      if (seasonResult.isEmpty) {
        return Response.notFound(jsonEncode({'error': 'Season not found'}),
            headers: {'Content-Type': 'application/json'});
      }

      final startDate = seasonResult.first[0] as DateTime;
      final endDate   = seasonResult.first[1] as DateTime;

      // ========= الربح من المبيعات =========
      final profitResults = await db.query("""
        SELECT
            SUM(fi.quantity * fi.unit_price) AS total_revenue,
            SUM(fi.quantity * (
                COALESCE(m.cut_price, 0) +
                COALESCE(m.sewing_price, 0) +
                COALESCE(m.press_price, 0) +
                COALESCE(m.assembly_price, 0) +
                COALESCE(m.electricity, 0) +
                COALESCE(m.rent, 0) +
                COALESCE(m.maintenance, 0) +
                COALESCE(m.water, 0) +
                COALESCE(m.washing, 0) +
                COALESCE(m.embroidery, 0) +
                COALESCE(m.laser, 0) +
                COALESCE(m.printing, 0) +
                COALESCE(m.crochet, 0) +
                COALESCE(material_costs.total_material_cost_per_unit, 0)
            )) AS total_cost_of_goods_sold
        FROM sewing.facture_items fi
        JOIN sewing.factures f ON fi.facture_id = f.id
        JOIN sewing.models m ON fi.model_id = m.id
        LEFT JOIN (
            SELECT
                mc.model_id,
                SUM(mc.quantity_needed * COALESCE(avg_prices.avg_price, 0)) AS total_material_cost_per_unit
            FROM sewing.model_components mc
            LEFT JOIN (
                SELECT material_id, AVG(unit_price) AS avg_price
                FROM sewing.purchase_items
                GROUP BY material_id
            ) avg_prices ON mc.material_id = avg_prices.material_id
            GROUP BY mc.model_id
        ) AS material_costs ON m.id = material_costs.model_id
        WHERE f.facture_date >= @start_date AND f.facture_date <= @end_date
      """, substitutionValues: {
        'start_date': startDate,
        'end_date'  : endDate,
      });

      final totalRevenue            = parseNum(profitResults.first[0]);
      final totalCostOfGoodsSold    = parseNum(profitResults.first[1]);
      final totalProfitBeforeOthers = totalRevenue - totalCostOfGoodsSold;

      // ========= مصاريف أخرى =========
      final otherExpRes = await db.query("""
        SELECT COALESCE(SUM(amount), 0)
        FROM sewing.expenses
        WHERE expense_date >= @start_date
          AND expense_date <= @end_date
          AND expense_type = @type_other
      """, substitutionValues: {
        'start_date': startDate,
        'end_date'  : endDate,
        'type_other': 'custom' // أو 'custom' لو هذا هو الاسم عندك
      });

      final otherExpenses = parseNum(otherExpRes.first[0]);
      final netProfit     = totalProfitBeforeOthers - otherExpenses;

      return Response.ok(jsonEncode({
        'total_revenue'             : totalRevenue,
        'total_cost_of_goods_sold'  : totalCostOfGoodsSold,
        'total_profit'              : totalProfitBeforeOthers,
        'other_expenses'            : otherExpenses,
        'net_profit'                : netProfit,
      }), headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to calculate season profit: $e'}),
        headers: {'Content-Type': 'application/json'}
      );
    }
  });
  return router;
}
