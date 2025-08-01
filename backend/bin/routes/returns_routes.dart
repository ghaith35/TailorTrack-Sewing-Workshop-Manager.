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
        'notes': row[8] ?? '',
        'created_at': row[9].toString(),
        'client_name': row[10] ?? '',
        'model_name': row[11] ?? '',
      }).toList();

      return Response.ok(
        jsonEncode(returns),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      print('Error fetching returns: $e');
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
      // print('Fetching facture $factureId');

      final factureResults = await db.query('''
        SELECT 
          f.id,
          f.client_id,
          f.facture_date,
          c.full_name AS client_name
        FROM sewing.factures f
        LEFT JOIN sewing.clients c ON f.client_id = c.id
        WHERE f.id = @facture_id
      ''', substitutionValues: {'facture_id': factureId});

      if (factureResults.isEmpty) {
        print('Facture $factureId not found');
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
          m.name AS model_name,
          fi.quantity - COALESCE(SUM(r.quantity), 0) AS available_quantity
        FROM sewing.facture_items fi
        JOIN sewing.models m ON fi.model_id = m.id
        LEFT JOIN sewing.returns r ON r.facture_id = fi.facture_id AND r.model_id = fi.model_id
        WHERE fi.facture_id = @facture_id
        GROUP BY fi.id, m.name
      ''', substitutionValues: {'facture_id': factureId});

      // print('Facture items for $factureId: ${itemResults.length} items');

      final facture = {
        'id': parseInt(factureResults.first[0]),
        'client_id': parseInt(factureResults.first[1]),
        'facture_date': factureResults.first[2]?.toString() ?? '',
        'client_name': factureResults.first[3] ?? '',
        'items': itemResults.map((row) => {
          'id': parseInt(row[0]),
          'facture_id': parseInt(row[1]),
          'model_id': parseInt(row[2]),
          'color': row[3] ?? '',
          'quantity': parseInt(row[4]),
          'unit_price': parseNum(row[5]),
          'model_name': row[6] ?? '',
          'available_quantity': parseInt(row[7]),
        }).toList(),
      };

      return Response.ok(
        jsonEncode(facture),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      print('Error fetching facture $id: $e\n$stackTrace');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch facture: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // POST /returns - Create new return
  // POST /returns - Create new return (and immediately stock it if ready-to-sell)
router.post('/', (Request request) async {
  try {
    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final factureId      = parseInt(body['facture_id']);
    final modelId        = parseInt(body['model_id']);
    final returnQuantity = parseInt(body['quantity']);
    final isReady        = body['is_ready_to_sell'] as bool? ?? false;
    final repairMaterials= body['repair_materials'] as List? ?? [];
    final repairCost     = parseNum(body['repair_cost']);
    final notes          = body['notes'] as String? ?? '';
    final returnDate     = body['return_date'] != null
        ? DateTime.parse(body['return_date'])
        : DateTime.now();

    return await db.transaction((txn) async {
      // 1) validate facture_item exists
      final fi = await txn.query('''
        SELECT quantity
        FROM sewing.facture_items
        WHERE facture_id = @f AND model_id = @m
        LIMIT 1
      ''', substitutionValues: {'f': factureId, 'm': modelId});
      if (fi.isEmpty) {
        return Response.notFound(jsonEncode({'error': 'Facture item not found'}), headers: {'Content-Type': 'application/json'});
      }
      final originalQty = parseInt(fi.first[0]);
      final alreadyReturned = parseInt((await txn.query('''
        SELECT COALESCE(SUM(quantity),0)
        FROM sewing.returns
        WHERE facture_id = @f AND model_id = @m
      ''', substitutionValues: {'f': factureId,'m': modelId})).first[0]);
      if (alreadyReturned + returnQuantity > originalQty) {
        return Response(400,
          body: jsonEncode({'error': 'الكمية المرتجعة تتجاوز المتاح (${originalQty - alreadyReturned})'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // 2) insert return
      final ins = await txn.query('''
        INSERT INTO sewing.returns (
          facture_id, model_id, quantity, return_date,
          is_ready_to_sell, repair_materials,
          repair_cost, notes, created_at, status
        ) VALUES (
          @f, @m, @q, @d, @ready,
          @rm, @rc, @notes, CURRENT_TIMESTAMP, 'pending'
        ) RETURNING id
      ''', substitutionValues: {
        'f'     : factureId,
        'm'     : modelId,
        'q'     : returnQuantity,
        'd'     : returnDate,
        'ready' : isReady,
        'rm'    : jsonEncode(repairMaterials),
        'rc'    : repairCost,
        'notes' : notes,
      });
      final newReturnId = parseInt(ins.first[0]);
      print('🟢 Return created: id=$newReturnId, ready=$isReady');

      // 3) if ready, merge into product_inventory
      if (isReady) {
        // a) find ready warehouse
        final whRes = await txn.query("SELECT id FROM sewing.warehouses WHERE type='ready' LIMIT 1");
        if (whRes.isEmpty) throw Exception('No ready warehouse found');
        final whId = parseInt(whRes.first[0]);

        // b) fetch color
        final fiDetail = await txn.query('''
          SELECT color
          FROM sewing.facture_items
          WHERE facture_id = @f AND model_id = @m
          LIMIT 1
        ''', substitutionValues: {'f': factureId,'m': modelId});
        final color = fiDetail.isNotEmpty ? fiDetail.first[0] as String? ?? '' : '';

        print('→ Merging into inventory: warehouse=$whId, model=$modelId, qty=$returnQuantity, color="$color"');

        await txn.query('''
          INSERT INTO sewing.product_inventory (
            warehouse_id, model_id, color, quantity, last_updated, production_batch_id
          ) VALUES (
            @wh, @mdl, @col, @qty, CURRENT_TIMESTAMP, NULL
          )
          ON CONFLICT ON CONSTRAINT product_inventory_wh_model_unique
          DO UPDATE SET
            quantity     = sewing.product_inventory.quantity + EXCLUDED.quantity,
            last_updated = CURRENT_TIMESTAMP
        ''', substitutionValues: {
          'wh' : whId,
          'mdl': modelId,
          'col': color,
          'qty': returnQuantity,
        });

        // c) log the new quantity
        final invRow = await txn.query('''
          SELECT quantity
          FROM sewing.product_inventory
          WHERE warehouse_id = @wh AND model_id = @mdl
        ''', substitutionValues: {'wh': whId,'mdl': modelId});
        final newQty = invRow.isNotEmpty ? parseInt(invRow.first[0]) : -1;
        print('→ New inventory.quantity is $newQty');
      }

      return Response(201,
        body: jsonEncode({
          'id': newReturnId,
          'message': 'Return created and stocked.',
          'is_ready_to_sell': isReady,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    });
  } catch (e, st) {
    print('🔴 Error in POST /returns: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Failed to create return: $e'}),
      headers: {'Content-Type': 'application/json'},
    );
  }
});


  // PATCH /returns/<id>/validate - Validate return to make it ready to sell
  router.patch('/<id>/validate', (Request request, String id) async {
    try {
      final bodyString = await request.readAsString();
      // print('Validating return $id with payload: $bodyString');

      Map<String, dynamic> body;
      try {
        body = bodyString.isNotEmpty ? jsonDecode(bodyString) : {};
      } catch (e) {
        // print('Invalid JSON payload: $e');
        return Response(400, body: jsonEncode({'error': 'Invalid JSON payload'}), headers: {'Content-Type': 'application/json'});
      }

      final returnId = int.parse(id);
      final repairCost = parseNum(body['repair_cost'] ?? 0.0);
      final repairMaterials = (body['repair_materials'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final isReadyToSell = body['is_ready_to_sell'] as bool? ?? true;

      // print('Parsed: returnId=$returnId, repairCost=$repairCost, repairMaterials=$repairMaterials, isReadyToSell=$isReadyToSell');

      return await db.transaction((txn) async {
        final returnExists = await txn.query('''
          SELECT id, model_id, quantity, facture_id
          FROM sewing.returns 
          WHERE id = @id
        ''', substitutionValues: {'id': returnId});

        if (returnExists.isEmpty) {
          print('Return $returnId not found');
          return Response.notFound(jsonEncode({'error': 'Return not found'}), headers: {'Content-Type': 'application/json'});
        }

        final modelId = parseInt(returnExists.first[1]);
        final quantity = parseInt(returnExists.first[2]);
        final factureId = parseInt(returnExists.first[3]);

        // print('Return details: modelId=$modelId, quantity=$quantity, factureId=$factureId');

        // Update returns table
        final updateReturnResult = await txn.query('''
          UPDATE sewing.returns 
          SET is_ready_to_sell = @is_ready_to_sell,
              repair_materials = @repair_materials,
              repair_cost = @repair_cost,
              status = 'validated'
          WHERE id = @id
          RETURNING id
        ''', substitutionValues: {
          'id': returnId,
          'is_ready_to_sell': isReadyToSell,
          'repair_cost': repairCost,
          'repair_materials': jsonEncode(repairMaterials),
        });

        // print('Return $returnId updated: ${updateReturnResult.isNotEmpty}');

        // Insert repair_cost into expenses table if > 0
        if (repairCost > 0) {
          final expenseResult = await txn.query('''
            INSERT INTO sewing.expenses (
              expense_type, description, amount, expense_date, created_at
            ) VALUES (
              @expense_type, @description, @amount, CURRENT_DATE, CURRENT_TIMESTAMP
            ) RETURNING id
          ''', substitutionValues: {
            'expense_type': 'custom',
            'description': 'تكلفة إصلاح الإرجاع رقم $returnId',
            'amount': repairCost,
          });
          // print('Expense inserted for return $returnId: id=${expenseResult.isNotEmpty ? expenseResult.first[0] : 'none'}');
        } else {
          // print('No expense inserted: repairCost=$repairCost');
        }

        // Deduct repair materials from materials.stock_quantity
        final materialErrors = <String>[];
        if (repairMaterials.isNotEmpty && quantity > 0) {
          for (var material in repairMaterials) {
            final materialId = parseInt(material['material_id']);
            final materialQuantityPerUnit = parseNum(material['quantity']);
            final totalDeductionQuantity = quantity * materialQuantityPerUnit;

            // print('Processing material: materialId=$materialId, materialQuantityPerUnit=$materialQuantityPerUnit, totalDeductionQuantity=$totalDeductionQuantity');

            if (materialId <= 0 || materialQuantityPerUnit <= 0) {
              materialErrors.add('Invalid material_id ($materialId) or quantity ($materialQuantityPerUnit)');
              continue;
            }

            final materialResults = await txn.query('''
              SELECT stock_quantity FROM sewing.materials
              WHERE id = @material_id
            ''', substitutionValues: {'material_id': materialId});

            if (materialResults.isEmpty) {
              materialErrors.add('Material ID $materialId not found');
              continue;
            }

            final currentStock = parseNum(materialResults.first[0]);
            if (currentStock < totalDeductionQuantity) {
              materialErrors.add('Insufficient stock for material ID $materialId: available=$currentStock, required=$totalDeductionQuantity');
              continue;
            }

            final updateMaterialResult = await txn.query('''
              UPDATE sewing.materials
              SET stock_quantity = stock_quantity - @quantity
              WHERE id = @material_id
              RETURNING id
            ''', substitutionValues: {
              'material_id': materialId,
              'quantity': totalDeductionQuantity,
            });

            // print('Material $materialId updated: ${updateMaterialResult.isNotEmpty ? 'id=${updateMaterialResult.first[0]}' : 'none'}');
          }
        } else {
          // print('No materials to deduct: repairMaterials=$repairMaterials, quantity=$quantity');
        }

        // Add to warehouse if ready to sell
        if (isReadyToSell) {
          final warehouseResults = await txn.query('''
            SELECT id FROM sewing.warehouses WHERE type = 'ready' LIMIT 1
          ''');
          if (warehouseResults.isEmpty) {
            materialErrors.add('No ready warehouse found');
          } else {
            final warehouseId = parseInt(warehouseResults.first[0]);
            // print('Warehouse ID: $warehouseId');

            final factureItemResults = await txn.query('''
              SELECT color
              FROM sewing.facture_items
              WHERE facture_id = @facture_id AND model_id = @model_id
              LIMIT 1
            ''', substitutionValues: {
              'facture_id': factureId,
              'model_id': modelId,
            });

            if (factureItemResults.isEmpty) {
              materialErrors.add('No facture item found for facture_id=$factureId, model_id=$modelId');
            } else {
              String? color = factureItemResults.first[0] as String?;
              // print('Color for inventory: $color');

              final inventoryResult = await txn.query('''
                INSERT INTO sewing.product_inventory (
                  warehouse_id, model_id, quantity, last_updated, color
                ) VALUES (
                  @warehouse_id, @model_id, @quantity, CURRENT_TIMESTAMP, @color
                ) ON CONFLICT (warehouse_id, model_id)
                DO UPDATE SET
                  quantity = sewing.product_inventory.quantity + EXCLUDED.quantity,
                  last_updated = CURRENT_TIMESTAMP
                RETURNING id
              ''', substitutionValues: {
                'warehouse_id': warehouseId,
                'model_id': modelId,
                'quantity': quantity,
                'color': color ?? '',
              });

              // print('Inventory updated: ${inventoryResult.isNotEmpty ? 'id=${inventoryResult.first[0]}' : 'none'}');
            }
          }
        }

        if (materialErrors.isNotEmpty) {
          return Response(400, body: jsonEncode({
            'error': 'Validation completed with issues',
            'material_errors': materialErrors,
          }), headers: {'Content-Type': 'application/json'});
        }

        return Response.ok(
          jsonEncode({
            'message': 'Return validated successfully',
            'return_id': returnId,
            'is_ready_to_sell': isReadyToSell,
            'repair_cost': repairCost,
          }),
          headers: {'Content-Type': 'application/json'},
        );
      });
    } catch (e, stackTrace) {
      // print('Error validating return $id: $e\n$stackTrace');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to validate return: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // DELETE /returns/<id> - Delete return
  router.delete('/<id>', (Request request, String id) async {
  try {
    final returnId = int.parse(id);

    return await db.transaction((txn) async {
      // 1) Fetch & lock the return row
      final r = await txn.query(r'''
        SELECT model_id,
               quantity,
               is_ready_to_sell,
               repair_materials,  -- JSONB → might come back as List or String
               repair_cost
        FROM sewing.returns
        WHERE id = @id
        FOR UPDATE
      ''', substitutionValues: {'id': returnId});

      if (r.isEmpty) {
        return Response.notFound(
          jsonEncode({'error': 'Return not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final modelId    = parseInt(r.first[0]);
      final returnQty  = parseInt(r.first[1]);
      final wasReady   = r.first[2] as bool;
      final rawField   = r.first[3];
      final repairCost = parseNum(r.first[4]);

      // 2) Decode repair_materials robustly
      List<dynamic> repairMaterials;
      if (rawField is String) {
        try {
          repairMaterials = jsonDecode(rawField) as List<dynamic>;
        } catch (_) {
          repairMaterials = [];
        }
      } else if (rawField is List) {
        repairMaterials = rawField;
      } else {
        repairMaterials = [];
      }

      // If you want to see what you’re about to add back:
      print('Rolling back materials for return $returnId: $repairMaterials');

      // 3) Roll *raw* materials back into stock
      for (final m in repairMaterials) {
        if (m is Map<String, dynamic>) {
          final matId   = parseInt(m['material_id']);
          final perUnit = parseNum(m['quantity']);
          final addQty  = (returnQty * perUnit).toInt();

          await txn.query(r'''
            UPDATE sewing.materials
            SET stock_quantity = stock_quantity + @add
            WHERE id = @mid
          ''', substitutionValues: {
            'add': addQty,
            'mid': matId,
          });
        }
      }

      // 4) Remove the repair-cost expense
      await txn.query(r'''
        DELETE FROM sewing.expenses
        WHERE expense_type = 'custom'
          AND description = @desc
      ''', substitutionValues: {
        'desc': 'تكلفة إصلاح الإرجاع رقم $returnId',
      });

      // 5) If it had been marked ready-to-sell, reverse that
      if (wasReady) {
        final wh = await txn.query(r'''
          SELECT id FROM sewing.warehouses
          WHERE type = 'ready'
          LIMIT 1
        ''');
        if (wh.isNotEmpty) {
          await txn.query(r'''
            UPDATE sewing.product_inventory
            SET quantity     = quantity - @qty,
                last_updated = CURRENT_TIMESTAMP
            WHERE warehouse_id = @wh
              AND model_id     = @mdl
          ''', substitutionValues: {
            'qty': returnQty,
            'wh' : parseInt(wh.first[0]),
            'mdl': modelId,
          });
        }
      }

      // 6) Finally delete the return row
      await txn.query(r'''
        DELETE FROM sewing.returns
        WHERE id = @id
      ''', substitutionValues: {'id': returnId});

      return Response.ok(
        jsonEncode({'message': 'Return deleted; materials, expenses, and inventory rolled back.'}),
        headers: {'Content-Type': 'application/json'},
      );
    });
  } catch (e, st) {
    print('Error deleting return $id: $e\n$st');
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
      print('Error fetching return stats: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch return stats: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // GET /materials - Fetch available materials
  router.get('/materials', (Request request) async {
    try {
      final results = await db.query('''
        SELECT id, code, stock_quantity 
        FROM sewing.materials 
        WHERE stock_quantity > 0
      ''');
      final materials = results.map((row) => {
        'id': parseInt(row[0]),
        'code': row[1] as String,
        'stock_quantity': parseNum(row[2]),
      }).toList();
      // print('Fetched materials: $materials');
      return Response.ok(
        jsonEncode(materials),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      print('Error fetching materials: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch materials: $e'}),
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