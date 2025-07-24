import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:postgres/postgres.dart';
import 'dart:convert';

Router getSeasonRoutes(PostgreSQLConnection db) {
  final router = Router();

  double parseNum(dynamic v) =>
      v == null ? 0.0 : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0);

  int parseInt(dynamic v) =>
      v == null ? 0 : (v is num ? v.toInt() : int.tryParse(v.toString()) ?? 0);

  // =====================
  // SEASONS CRUD
  // =====================

  // Create a new season
  router.post('/', (Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final name = data['name'] as String;
      final startDate = DateTime.parse(data['start_date']);
      final endDate = DateTime.parse(data['end_date']);

      final result = await db.query("""
        INSERT INTO sewing.seasons (name, start_date, end_date)
        VALUES (@name, @start_date, @end_date)
        RETURNING id, name, start_date, end_date
      """, substitutionValues: {
        'name': name,
        'start_date': startDate,
        'end_date': endDate,
      });

      final newSeason = result.first;
      return Response(201,
          body: jsonEncode({
            'id': parseInt(newSeason[0]),
            'name': newSeason[1],
            'start_date': newSeason[2].toString(),
            'end_date': newSeason[3].toString(),
          }),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': 'Failed to create season: $e'}),
          headers: {'Content-Type': 'application/json'});
    }
  });

  // Get all seasons
  router.get('/', (Request request) async {
    try {
      final results = await db.query("""
        SELECT id, name, start_date, end_date
        FROM sewing.seasons
        ORDER BY start_date DESC
      """);

      final seasons = results.map((row) => {
        'id': parseInt(row[0]),
        'name': row[1],
        'start_date': row[2].toString(),
        'end_date': row[3].toString(),
      }).toList();

      return Response.ok(jsonEncode(seasons), headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': 'Failed to fetch seasons: $e'}),
          headers: {'Content-Type': 'application/json'});
    }
  });

  // Get a specific season by ID
  router.get('/<id>', (Request request, String id) async {
    try {
      final results = await db.query("""
        SELECT id, name, start_date, end_date
        FROM sewing.seasons
        WHERE id = @id
      """, substitutionValues: {'id': parseInt(id)});

      if (results.isEmpty) {
        return Response.notFound(jsonEncode({'error': 'Season not found'}),
            headers: {'Content-Type': 'application/json'});
      }

      final season = results.first;
      return Response.ok(jsonEncode({
        'id': parseInt(season[0]),
        'name': season[1],
        'start_date': season[2].toString(),
        'end_date': season[3].toString(),
      }), headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': 'Failed to fetch season: $e'}),
          headers: {'Content-Type': 'application/json'});
    }
  });

  // Update a season
  router.put('/<id>', (Request request, String id) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final name = data['name'] as String;
      final startDate = DateTime.parse(data['start_date']);
      final endDate = DateTime.parse(data['end_date']);

      await db.query("""
        UPDATE sewing.seasons
        SET name = @name, start_date = @start_date, end_date = @end_date
        WHERE id = @id
      """, substitutionValues: {
        'id': parseInt(id),
        'name': name,
        'start_date': startDate,
        'end_date': endDate,
      });

      return Response.ok(jsonEncode({'message': 'Season updated successfully'}),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': 'Failed to update season: $e'}),
          headers: {'Content-Type': 'application/json'});
    }
  });

  // Delete a season
  router.delete('/<id>', (Request request, String id) async {
    try {
      await db.query("""
        DELETE FROM sewing.seasons
        WHERE id = @id
      """, substitutionValues: {'id': parseInt(id)});

      return Response.ok(jsonEncode({'message': 'Season deleted successfully'}),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': 'Failed to delete season: $e'}),
          headers: {'Content-Type': 'application/json'});
    }
  });

  // =====================
  // SEASON PROFIT CALCULATION
  // =====================

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


