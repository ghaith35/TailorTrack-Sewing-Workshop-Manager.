import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:postgres/postgres.dart';
import 'dart:convert';

double parseNum(dynamic v) {
  if (v is String) return double.tryParse(v) ?? 0.0;
  if (v is num) return v.toDouble();
  return 0.0;
}

int parseInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

Router getEmbrodryReturnsRoutes(PostgreSQLConnection db) {
  final router = Router();

  // GET all returns (now including model.total_price)
  router.get('/', (Request request) async {
    try {
      final results = await db.query('''
        SELECT 
          r.id,
          r.facture_id,
          r.model_id,
          r.quantity,
          r.return_date,
          r.is_ready_to_sell,
          r.repair_materials,
          r.repair_cost,
          r.notes,
          r.all_loss,
          r.created_at,
          c.full_name   AS client_name,
          m.model_name  AS model_name,
          m.total_price AS model_total_price
        FROM embroidery.returns r
        LEFT JOIN embroidery.factures f  ON r.facture_id = f.id
        LEFT JOIN embroidery.clients c   ON f.client_id   = c.id
        LEFT JOIN embroidery.models m    ON r.model_id     = m.id
        ORDER BY r.created_at DESC
      ''');

      final returns = results.map((row) {
        return {
          'id'               : parseInt(row[0]),
          'facture_id'       : parseInt(row[1]),
          'model_id'         : parseInt(row[2]),
          'quantity'         : parseInt(row[3]),
          'return_date'      : row[4]?.toString(),
          'is_ready_to_sell' : row[5] is bool ? row[5] : row[5] == 1,
          'repair_materials' : () {
                                 final v = row[6];
                                 if (v == null) return <dynamic>[];
                                 if (v is String) {
                                   try { return jsonDecode(v); } catch (_) { return <dynamic>[]; }
                                 }
                                 if (v is List) return v;
                                 return <dynamic>[];
                               }(),
          'repair_cost'      : parseNum(row[7]),
          'notes'            : row[8]?.toString() ?? '',
          'all_loss'         : row[9] is bool ? row[9] : row[9] == 1,
          'created_at'       : row[10]?.toString(),
          'client_name'      : row[11]?.toString() ?? '',
          'model_name'       : row[12]?.toString() ?? '',
          'total_price'      : parseNum(row[13]),
        };
      }).toList();

      return Response.ok(
        jsonEncode(returns),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch returns: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // GET /returns/<id> - Get facture details with available quantities
  router.get('/<id>', (Request request, String id) async {
    try {
      final factureId = int.parse(id);

      final factureResults = await db.query('''
        SELECT 
          f.id,
          f.client_id,
          f.facture_date,
          c.full_name AS client_name
        FROM embroidery.factures f
        LEFT JOIN embroidery.clients c ON f.client_id = c.id
        WHERE f.id = @facture_id
      ''', substitutionValues: {'facture_id': factureId});

      if (factureResults.isEmpty) {
        return Response.notFound(
          jsonEncode({'error': 'Facture not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final itemResults = await db.query('''
        SELECT 
          fi.id,
          fi.facture_id,
          fi.model_id,
          fi.color,
          fi.quantity,
          fi.unit_price,
          m.model_name AS model_name,
          fi.quantity - COALESCE(SUM(r.quantity), 0) AS available_quantity
        FROM embroidery.facture_items fi
        JOIN embroidery.models m ON fi.model_id = m.id
        LEFT JOIN embroidery.returns r 
          ON r.facture_id = fi.facture_id 
         AND r.model_id   = fi.model_id
        WHERE fi.facture_id = @facture_id
        GROUP BY fi.id, m.model_name
      ''', substitutionValues: {'facture_id': factureId});

      final facture = {
        'id'          : parseInt(factureResults.first[0]),
        'client_id'   : parseInt(factureResults.first[1]),
        'facture_date': factureResults.first[2]?.toString() ?? '',
        'client_name' : factureResults.first[3] ?? '',
        'items'       : itemResults.map((row) => {
          'id'                 : parseInt(row[0]),
          'facture_id'         : parseInt(row[1]),
          'model_id'           : parseInt(row[2]),
          'color'              : row[3] ?? '',
          'quantity'           : parseInt(row[4]),
          'unit_price'         : parseNum(row[5]),
          'model_name'         : row[6] ?? '',
          'available_quantity' : parseInt(row[7]),
        }).toList(),
      };

      return Response.ok(
        jsonEncode(facture),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch facture: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });
  // POST: create return + log expenses
  router.post('/', (Request request) async {
  try {
    final body             = jsonDecode(await request.readAsString());
    final factureId        = parseInt(body['facture_id']);
    final modelId          = parseInt(body['model_id']);
    final quantity         = parseInt(body['quantity']);         // number of pieces returned
    final repairMaterials  = body['repair_materials'] as List? ?? [];
    final repairCost       = parseNum(body['repair_cost']);
    final notes            = body['notes'] as String? ?? '';
    final allLoss          = (body['all_loss'] as bool?) ?? false;

    return await db.transaction((txn) async {
      // 1) Check available quantity
      final factureItemResults = await txn.query(r'''
        SELECT id, quantity
          FROM embroidery.facture_items
         WHERE facture_id = @facture_id AND model_id = @model_id
         LIMIT 1
      ''', substitutionValues: {
        'facture_id': factureId,
        'model_id'  : modelId,
      });
      if (factureItemResults.isEmpty) {
        return Response.notFound(
          jsonEncode({'error': 'Facture item not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      final originalQuantity = parseInt(factureItemResults.first[1]);
      final existingReturns = await txn.query(r'''
        SELECT COALESCE(SUM(quantity),0)
          FROM embroidery.returns
         WHERE facture_id = @facture_id AND model_id = @model_id
      ''', substitutionValues: {
        'facture_id': factureId,
        'model_id'  : modelId,
      });
      final totalReturned = parseInt(existingReturns.first[0]);
      if (totalReturned + quantity > originalQuantity) {
        return Response(
          400,
          body: jsonEncode({
            'error': 'الكمية المرتجعة تتجاوز الكمية المتاحة (${originalQuantity - totalReturned})'
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // 2) Insert the return record
      final insertResult = await txn.query(r'''
        INSERT INTO embroidery.returns (
          facture_id, model_id, quantity, is_ready_to_sell,
          repair_materials, repair_cost, notes, all_loss
        ) VALUES (
          @facture_id, @model_id, @quantity, FALSE,
          @repair_materials, @repair_cost, @notes, @all_loss
        )
        RETURNING id
      ''', substitutionValues: {
        'facture_id'       : factureId,
        'model_id'         : modelId,
        'quantity'         : quantity,
        'repair_materials' : jsonEncode(repairMaterials),
        'repair_cost'      : repairCost,
        'notes'            : notes,
        'all_loss'         : allLoss,
      });
      final returnId = parseInt(insertResult.first[0]);

      // 3) Expense logging
      if (allLoss) {
        // Total‐loss
        final modelRow = await txn.query(
          'SELECT total_price FROM embroidery.models WHERE id = @model_id',
          substitutionValues: {'model_id': modelId},
        );
        final modelPrice = parseNum(modelRow.first[0]);
        final totalLoss  = modelPrice * quantity;
        await txn.query(r'''
          INSERT INTO embroidery.expenses (
            expense_type, description, amount, expense_date
          ) VALUES (
            'custom', @desc, @amount, CURRENT_DATE
          )
        ''', substitutionValues: {
          'desc'   : 'خسارة مرتجع: فاتورة $factureId موديل $modelId',
          'amount' : totalLoss,
        });

      } else {
        // Repair → only per‐material 'raw_materials' rows, correctly scaled by returned quantity
        for (final m in repairMaterials) {
          final perPieceQty   = parseNum(m['quantity']);     // material units per piece
          final unitCost      = parseNum(m['cost']) / perPieceQty;
          final totalMatQty   = perPieceQty * quantity;      // total material units used
          final totalMatCost  = unitCost * totalMatQty;      // total cost for all returned pieces

          if (totalMatQty > 0) {
            await txn.query(r'''
              INSERT INTO embroidery.expenses (
                expense_type, material_id, quantity, unit_price,
                amount, description, expense_date
              ) VALUES (
                'raw_materials', @material_id, @qty, @unit_price,
                @amount, @desc, CURRENT_DATE
              )
            ''', substitutionValues: {
              'material_id': parseInt(m['material_id']),
              'qty'        : totalMatQty,
              'unit_price' : unitCost,
              'amount'     : totalMatCost,
              'desc'       : 'مادة إصلاح مرتجع: فاتورة $factureId موديل $modelId',
            });

            // Deduct stock atomically
            final updated = await txn.execute(r'''
              UPDATE embroidery.materials
                 SET stock_quantity = stock_quantity - @q
               WHERE id = @mid AND stock_quantity >= @q
            ''', substitutionValues: {
              'q'  : totalMatQty,
              'mid': parseInt(m['material_id']),
            });
            if (updated == 0) {
              return Response(
                400,
                body: jsonEncode({
                  'error': 'لا توجد كمية كافية من المادة ${m['material_id']} (المتوفّرة أقل من $totalMatQty)'
                }),
                headers: {'Content-Type': 'application/json'},
              );
            }
          }
        }
      }

      // 4) Success
      return Response(
        201,
        body: jsonEncode({
          'id'     : returnId,
          'message': 'Embroidery return processed successfully'
        }),
        headers: {'Content-Type': 'application/json'},
      );
    });
  } catch (e) {
    return Response.internalServerError(
      body: jsonEncode({'error': 'Failed to create embroidery return: $e'}),
      headers: {'Content-Type': 'application/json'},
    );
  }
});

  // PATCH: validate return (add to ready inventory)
  router.patch('/<id>/validate', (Request request, String id) async {
    try {
      final returnId = int.parse(id);

      await db.transaction((txn) async {
        // 1) Mark as ready
        await txn.query('''
          UPDATE embroidery.returns
          SET is_ready_to_sell = TRUE
          WHERE id = @id
        ''', substitutionValues: {'id': returnId});

        // 2) Fetch return data
        final returnData = await txn.query(
          'SELECT model_id, quantity FROM embroidery.returns WHERE id = @id',
          substitutionValues: {'id': returnId});
        if (returnData.isEmpty) throw Exception('Return not found');
        final modelId = parseInt(returnData.first[0]);
        final qty     = parseInt(returnData.first[1]);

        // 3) Get a ready warehouse
        final wh = await txn.query('''
          SELECT id FROM embroidery.warehouses WHERE type = 'ready' LIMIT 1
        ''');
        if (wh.isEmpty) throw Exception('No ready warehouse found');
        final warehouseId = parseInt(wh.first[0]);

        // 4) Upsert into product_inventory
        await txn.query('''
          INSERT INTO embroidery.product_inventory (
            warehouse_id, model_id, quantity, last_updated, color, size_label
          ) VALUES (
            @w, @m, @q, CURRENT_TIMESTAMP, '', ''
          )
          ON CONFLICT (warehouse_id, model_id, color, size_label)
          DO UPDATE SET
            quantity     = embroidery.product_inventory.quantity + EXCLUDED.quantity,
            last_updated = CURRENT_TIMESTAMP
        ''', substitutionValues: {
          'w': warehouseId,
          'm': modelId,
          'q': qty,
        });
      });

      return Response.ok(
        jsonEncode({'message': 'Return validated and added to warehouse successfully'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to validate return: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // DELETE
  router.delete('/<id>', (Request request, String id) async {
    try {
      final results = await db.query('''
        DELETE FROM embroidery.returns WHERE id = @id RETURNING id
      ''', substitutionValues: {'id': int.parse(id)});
      if (results.isEmpty) {
        return Response.notFound(
          jsonEncode({'error': 'Return not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      return Response.ok(
        jsonEncode({'message': 'Return deleted successfully'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to delete return: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  router.all('/<ignored|.*>', (Request request) {
    return Response.notFound(
      jsonEncode({'error': 'Route not found'}),
      headers: {'Content-Type': 'application/json'},
    );
  });

  return router;
}
