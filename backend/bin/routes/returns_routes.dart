import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:postgres/postgres.dart';
import 'dart:convert';

// Helper functions
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

Router getReturnsRoutes(PostgreSQLConnection db) {
  final router = Router();

  // GET /returns - Get all returns with details
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
          r.created_at,
          c.full_name as client_name,
          m.name as model_name
        FROM sewing.returns r
        LEFT JOIN sewing.factures f ON r.facture_id = f.id
        LEFT JOIN sewing.clients c ON f.client_id = c.id
        LEFT JOIN sewing.models m ON r.model_id = m.id
        ORDER BY r.created_at DESC
      ''');

      final returns = results.map((row) => {
        'id': parseInt(row[0]),
        'facture_id': parseInt(row[1]),
        'model_id': parseInt(row[2]),
        'quantity': parseInt(row[3]),
        'return_date': row[4].toString(),
        'is_ready_to_sell': row[5] as bool,
'repair_materials': row[6] ?? [],
        'repair_cost': parseNum(row[7]),
        'notes': row[8],
        'created_at': row[9].toString(),
        'client_name': row[10],
        'model_name': row[11],
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


  // POST /returns - Create new return
  // POST /returns - Create new return
router.post('/', (Request request) async {
  try {
    final body = jsonDecode(await request.readAsString());
    
    final factureId = parseInt(body['facture_id']);
    final modelId = parseInt(body['model_id']);
    final quantity = parseInt(body['quantity']);
    final isReadyToSell = body['is_ready_to_sell'] as bool;
    final repairMaterials = body['repair_materials'] as List? ?? [];
    final repairCost = parseNum(body['repair_cost']);
    final notes = body['notes'] as String? ?? '';

    return await db.transaction((txn) async {
      // Get the original color from facture items
      final factureItemResults = await txn.query('''
        SELECT color FROM sewing.facture_items 
        WHERE facture_id = @facture_id AND model_id = @model_id 
        LIMIT 1
      ''', substitutionValues: {
        'facture_id': factureId,
        'model_id': modelId,
      });

      final color = factureItemResults.isNotEmpty 
          ? (factureItemResults.first[0] ?? '') 
          : '';

      // 1. Insert return record
      final returnResults = await txn.query('''
        INSERT INTO sewing.returns (
          facture_id, model_id, quantity, is_ready_to_sell, 
          repair_materials, repair_cost, notes
        ) VALUES (
          @facture_id, @model_id, @quantity, @is_ready_to_sell,
          @repair_materials, @repair_cost, @notes
        ) RETURNING id
      ''', substitutionValues: {
        'facture_id': factureId,
        'model_id': modelId,
        'quantity': quantity,
        'is_ready_to_sell': isReadyToSell,
        'repair_materials': jsonEncode(repairMaterials),
        'repair_cost': repairCost,
        'notes': notes,
      });

      final returnId = parseInt(returnResults.first[0]);

      // Get warehouse_id for 'ready' warehouse
      final warehouseResults = await txn.query('''
        SELECT id FROM sewing.warehouses WHERE type = 'ready' LIMIT 1
      ''');
      if (warehouseResults.isEmpty) {
        throw Exception('No ready warehouse found');
      }
      final warehouseId = parseInt(warehouseResults.first[0]);

      // Handle inventory update (for both ready-to-sell and after-repair cases)
      // Check for existing inventory row
      final existingInventoryResults = await txn.query('''
        SELECT id, quantity FROM sewing.product_inventory
        WHERE warehouse_id = @warehouse_id
          AND model_id = @model_id
          AND color = @color
          AND size = @size
          AND production_batch_id IS NULL
        LIMIT 1
      ''', substitutionValues: {
        'warehouse_id': warehouseId,
        'model_id': modelId,
        'color': color,
        'size': '', // Default empty size since facture_items doesn’t provide size
      });

      if (!isReadyToSell) {
        // Process repair materials
        for (final material in repairMaterials) {
          final materialId = parseInt(material['material_id']);
          final materialQuantity = parseNum(material['quantity']);

          final stockResults = await txn.query('''
            SELECT stock_quantity FROM sewing.materials WHERE id = @material_id
          ''', substitutionValues: {'material_id': materialId});

          if (stockResults.isEmpty) {
            throw Exception('Material not found: $materialId');
          }

          final availableStock = parseNum(stockResults.first[0]);
          if (availableStock < materialQuantity) {
            throw Exception('Insufficient stock for material $materialId. Available: $availableStock, Required: $materialQuantity');
          }

          await txn.query('''
            UPDATE sewing.materials 
            SET stock_quantity = stock_quantity - @quantity
            WHERE id = @material_id
          ''', substitutionValues: {
            'material_id': materialId,
            'quantity': materialQuantity,
          });
        }

        // Add repair expense
        if (repairCost > 0) {
          await txn.query('''
            INSERT INTO sewing.expenses (
              expense_type, description, amount, expense_date
            ) VALUES (
              'custom', 'تكلفة إصلاح مرتجع رقم ' || @return_id, @amount, CURRENT_DATE
            )
          ''', substitutionValues: {
            'return_id': returnId,
            'amount': repairCost,
          });
        }
      }

      // Update or insert inventory
      if (existingInventoryResults.isNotEmpty) {
        final existingId = parseInt(existingInventoryResults.first[0]);
        await txn.query('''
          UPDATE sewing.product_inventory
          SET quantity = quantity + @quantity,
              last_updated = CURRENT_TIMESTAMP
          WHERE id = @id
        ''', substitutionValues: {
          'quantity': quantity,
          'id': existingId,
        });
      } else {
        await txn.query('''
          INSERT INTO sewing.product_inventory (
            warehouse_id, model_id, color, size, quantity, last_updated, production_batch_id
          ) VALUES (
            @warehouse_id, @model_id, @color, @size, @quantity, CURRENT_TIMESTAMP, NULL
          )
        ''', substitutionValues: {
          'warehouse_id': warehouseId,
          'model_id': modelId,
          'color': color,
          'size': '', // Default empty size
          'quantity': quantity,
        });
      }

      return Response(201,
        body: jsonEncode({
          'id': returnId,
          'message': 'Return processed successfully',
          'is_ready_to_sell': isReadyToSell,
          'repair_cost': repairCost,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    });
  } catch (e) {
    return Response.internalServerError(
      body: jsonEncode({'error': 'Failed to create return: $e'}),
      headers: {'Content-Type': 'application/json'},
    );
  }
});

  // DELETE /returns/<id> - Delete return
  router.delete('/<id>', (Request request, String id) async {
    try {
      final results = await db.query('''
        DELETE FROM sewing.returns WHERE id = @id RETURNING id
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

  // GET /returns/stats - Get return statistics
  router.get('/stats', (Request request) async {
    try {
      final results = await db.query('''
        SELECT 
          COUNT(*) as total_returns,
          COUNT(CASE WHEN is_ready_to_sell = true THEN 1 END) as ready_to_sell,
          COUNT(CASE WHEN is_ready_to_sell = false THEN 1 END) as needs_repair,
          COALESCE(SUM(repair_cost), 0) as total_repair_cost,
          COALESCE(SUM(quantity), 0) as total_quantity
        FROM sewing.returns
      ''');

      final stats = {
        'total_returns': parseInt(results.first[0]),
        'ready_to_sell': parseInt(results.first[1]),
        'needs_repair': parseInt(results.first[2]),
        'total_repair_cost': parseNum(results.first[3]),
        'total_quantity': parseInt(results.first[4]),
      };

      return Response.ok(
        jsonEncode(stats),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch return stats: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });
router.all('/<ignored|.*>', (Request request) {
  return Response.notFound(jsonEncode({'error': 'Route not found'}), headers: {'Content-Type': 'application/json'});
});
  return router;
}
