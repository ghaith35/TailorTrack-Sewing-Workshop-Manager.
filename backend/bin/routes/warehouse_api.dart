import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:postgres/postgres.dart';
import 'dart:convert';

// Helper functions to parse numbers safely
num parseNum(dynamic value) => value is num ? value : (num.tryParse(value.toString()) ?? 0);
int parseInt(dynamic value) => value is int ? value : (int.tryParse(value.toString()) ?? 0);
/// Recalculates and writes each model's global_price based on completed inventory
Future<void> recalcAllGlobalPrices(PostgreSQLConnection db) async {
  // 1) get every model ID
  final idRows = await db.query('SELECT id FROM sewing.models');
  for (final idRow in idRows) {
    final modelId = idRow[0] as int;

    // 2) sum manual & automatic quantities for completed batches
    final inv = await db.query(r'''
      SELECT
        COALESCE(SUM(pb.manual_quantity),0)::float AS manual_qty,
        COALESCE(SUM(pb.automatic_quantity),0)::float AS auto_qty
      FROM sewing.product_inventory pi
      LEFT JOIN sewing.production_batches pb
        ON pi.model_id = pb.model_id
       AND pb.status = 'completed'
      WHERE pi.model_id = @mid
    ''', substitutionValues: {'mid': modelId});
    final manualQty = inv.first[0] as double;
    final autoQty   = inv.first[1] as double;
    final totalQty  = manualQty + autoQty;

    // 3) get cost breakdown (you already have this function)
    final costs = await calculateModelCosts(db, modelId);
    final manualCost = (costs['manual_total_cost'] as num).toDouble();
    final autoCost   = (costs['automatic_total_cost'] as num).toDouble();

    // 4) weighted average
    final globalPrice = totalQty > 0
      ? (manualQty * manualCost + autoQty * autoCost) / totalQty
      : 0.0;

    // 5) write back into models.global_price
    await db.query(r'''
      UPDATE sewing.models
         SET global_price = @gp
       WHERE id = @mid
    ''', substitutionValues: {
      'gp': globalPrice,
      'mid': modelId,
    });
  }
}

// Reusable function to calculate costs for a given model_id
Future<Map<String, dynamic>> calculateModelCosts(PostgreSQLConnection db, int modelId) async {
  try {
    // 1) Material cost
    final matRes = await db.query('''
      SELECT COALESCE(SUM(mc.quantity_needed * COALESCE(pr.avg_price,0)),0)
      FROM sewing.model_components mc
      LEFT JOIN (
        SELECT material_id, AVG(unit_price) AS avg_price
        FROM sewing.purchase_items GROUP BY material_id
      ) pr ON mc.material_id = pr.material_id
      WHERE mc.model_id = @id
    ''', substitutionValues: {'id': modelId});
    final materialCost = parseNum(matRes.first[0]);

    // 2) Static prices (cut, manual sewing, press, automatic assembly, additional services)
    final rowRes = await db.query('''
      SELECT cut_price,
             sewing_price,
             press_price,
             assembly_price,
             COALESCE(washing,0)+COALESCE(embroidery,0)+COALESCE(laser,0)
             +COALESCE(printing,0)+COALESCE(crochet,0) AS additional_services
      FROM sewing.models WHERE id = @id
    ''', substitutionValues: {'id': modelId});
    if (rowRes.isEmpty) {
      throw Exception('Model not found');
    }
    final row = rowRes.first;
    final cutPrice = parseNum(row[0]);
    final manualSewPrice = parseNum(row[1]);
    final pressPrice = parseNum(row[2]);
    final autoAssemblyPrice = parseNum(row[3]);
    final additionalServices = parseNum(row[4]);

    // 3) Total pieces produced this month (company-wide)
    final piecesRes = await db.query(r'''
      SELECT COALESCE(SUM(quantity), 0)
      FROM sewing.model_production
      WHERE date_trunc('month', produced_at)
            = date_trunc('month', CURRENT_DATE)
    ''');
    int pieces = parseInt(piecesRes.first[0]);
    if (pieces < 1) pieces = 1;

    // 4) Automatic Sewing share (خياطة آلي)
    final sewSalRes = await db.query('''
      SELECT COALESCE(SUM(salary),0)
      FROM sewing.employees
      WHERE role = 'خياطة' AND seller_type = 'month' AND status = 'active'
    ''');
    final autoSewCost = parseNum(sewSalRes.first[0]) / pieces;

    // 5) Automatic Assembly share (فينيسيون)
    final asmSalRes = await db.query('''
      SELECT COALESCE(SUM(salary),0)
      FROM sewing.employees
      WHERE role = 'فينيسيون' AND seller_type = 'month' AND status = 'active'
    ''');
    final autoAsmCost = parseNum(asmSalRes.first[0]) / pieces;

    // 6) Overhead shares (electricity, rent, maintenance, water)
    Future<double> share(String type) async {
      final r = await db.query('''
        SELECT COALESCE(SUM(amount),0)
        FROM sewing.expenses
        WHERE expense_type = @type
          AND date_trunc('month', expense_date) = date_trunc('month', CURRENT_DATE)
      ''', substitutionValues: {'type': type});
      return parseNum(r.first[0]) / pieces;
    }
    final electricityShare = await share('electricity');
    final rentShare = await share('rent');
    final maintenanceShare = await share('maintenance');
    final waterShare = await share('water');
    final overheadShare = electricityShare + rentShare + maintenanceShare + waterShare;

    // 7) Transport share
    final transportShare = await share('transport');

    // 8) Repair share
    const double repairShare = 0.0;

    // 9) Build manual vs. automatic totals
    final manualLabor = cutPrice + manualSewPrice + pressPrice;
    final manualTotal = materialCost + manualLabor + additionalServices + overheadShare + transportShare;
    final autoLabor = cutPrice + pressPrice + autoSewCost + autoAsmCost;
    final autoTotal = materialCost + autoLabor + additionalServices + overheadShare + transportShare;

    return {
      'pieces': pieces,
      'material_cost': materialCost,
      'manual_labor_cost': manualLabor,
      'automatic_labor_cost': autoLabor,
      'additional_services': additionalServices,
      'electricity_share': electricityShare,
      'rent_share': rentShare,
      'maintenance_share': maintenanceShare,
      'water_share': waterShare,
      'overhead_share': overheadShare,
      'transport_share': transportShare,
      'repair_share': repairShare,
      'manual_total_cost': manualTotal,
      'automatic_total_cost': autoTotal,
      'emballage_cost': autoAsmCost,
      'sewing_cost': autoSewCost,
    };
  } catch (e) {
    throw Exception('Failed to calculate model cost: $e');
  }
}

Router getWarehouseRoutes(PostgreSQLConnection db) {
  final router = Router();
// Trigger a full recalculation of every model's global_price
router.post('/recalc-global-prices', (Request req) async {
  try {
    await recalcAllGlobalPrices(db);
    return Response.ok(jsonEncode({'status': 'global prices updated'}));
  } catch (e) {
    return Response.internalServerError(
      body: jsonEncode({'error': 'Failed to recalc global prices: $e'}),
      headers: {'Content-Type': 'application/json'},
    );
  }
});

  // Updated /product-inventory endpoint
  router.get('/product-inventory', (Request req) async {
  try {
    // Fetch all inventory records, along with related model and production batch data
    final rows = await db.mappedResultsQuery('''
      SELECT 
        pi.id,
        pi.model_id,
        pi.quantity,
        m.name,
        m.sizes,
        m.nbr_of_sizes,
        COALESCE(SUM(pb.manual_quantity), 0) as manual_quantity,
        COALESCE(SUM(pb.automatic_quantity), 0) as automatic_quantity
      FROM sewing.product_inventory pi
      LEFT JOIN sewing.models m ON pi.model_id = m.id
      LEFT JOIN sewing.production_batches pb ON pi.model_id = pb.model_id
        AND (pb.status = 'completed' OR pb.status IS NULL)
      GROUP BY pi.id, pi.model_id, pi.quantity, m.name, m.sizes, m.nbr_of_sizes
      ORDER BY pi.model_id;
    ''');

    // Map to merge inventory per model_id
    final Map<int, Map<String, dynamic>> modelMap = {};

    for (final r in rows) {
      final pi = r['product_inventory']!;
      final model = r['models']!;
      final int modelId = pi['model_id'] as int;
      final double manualQuantity = parseNum(r['']?['manual_quantity'] ?? 0).toDouble();
      final double automaticQuantity = parseNum(r['']?['automatic_quantity'] ?? 0).toDouble();

      // If this model is not in the map yet, initialize it
      if (!modelMap.containsKey(modelId)) {
        // Calculate costs for this model (run once per model)
        final costs = await calculateModelCosts(db, modelId);

        // Global price needs to be recalculated after we finish summing all quantities!
        modelMap[modelId] = {
          'id': pi['id'],
          'model_id': modelId,
          'model_name': model['name'],
          'sizes': model['sizes'],
          'nbr_of_sizes': model['nbr_of_sizes'],
          'quantity': 0.0, // sum here
          'manual_quantity': 0.0,
          'automatic_quantity': 0.0,
          'costs': costs, // keep for now to avoid re-calling
        };
      }

      // Sum quantities for this model
      modelMap[modelId]!['quantity'] += (pi['quantity'] as num).toDouble();
      modelMap[modelId]!['manual_quantity'] += manualQuantity;
      modelMap[modelId]!['automatic_quantity'] += automaticQuantity;
    }

    // Now build the final list, calculate global price correctly
    final List<Map<String, dynamic>> finalList = [];

    for (final modelData in modelMap.values) {
      final double manualQuantity = modelData['manual_quantity'];
      final double automaticQuantity = modelData['automatic_quantity'];
      final double totalQuantity = manualQuantity + automaticQuantity;
      final costs = modelData['costs'];
      double globalPrice = 0.0;

      if (totalQuantity > 0) {
        globalPrice = (
          manualQuantity * (costs['manual_total_cost'] ?? 0.0) +
          automaticQuantity * (costs['automatic_total_cost'] ?? 0.0)
        ) / totalQuantity;
      }

      finalList.add({
  'id':        modelData['id'],        // ← inventory row id
  'model_id':  modelData['model_id'],
  'model_name':modelData['model_name'],
  'sizes':     modelData['sizes'],
  'nbr_of_sizes': modelData['nbr_of_sizes'],
  'quantity':  modelData['quantity'],
  'global_price': globalPrice,
});

    }

    // Debug: Print the response
    // print('API Response: $finalList');

    return Response.ok(
      jsonEncode(finalList),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e) {
    print('Error in /product-inventory: $e');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Failed to fetch product inventory: $e'}),
      headers: {'Content-Type': 'application/json'},
    );
  }
});


  // Other routes (unchanged from previous version)
  router.post('/product-inventory', (Request req) async {
    final data = jsonDecode(await req.readAsString());
    final res = await db.query(
      '''
      INSERT INTO sewing.product_inventory
        (warehouse_id, model_id, quantity)
      VALUES
        (@wid, @mid, @qty)
      RETURNING id
      ''',
      substitutionValues: {
        'wid': data['warehouse_id'],
        'mid': data['model_id'],
        'qty': data['quantity'],
      },
    );
    return Response.ok(
      jsonEncode({'id': res.first[0]}),
      headers: {'Content-Type': 'application/json'},
    );
  });

  router.put('/product-inventory/<id|[0-9]+>', (Request req, String id) async {
    final data = jsonDecode(await req.readAsString());
    await db.query(
      '''
      UPDATE sewing.product_inventory
      SET warehouse_id = @wid,
          model_id     = @mid,
          quantity     = @qty
      WHERE id = @id
      ''',
      substitutionValues: {
        'id': int.parse(id),
        'wid': data['warehouse_id'],
        'mid': data['model_id'],
        'qty': data['quantity'],
      },
    );
    return Response.ok(
      jsonEncode({'status': 'updated'}),
      headers: {'Content-Type': 'application/json'},
    );
  });

  router.delete('/product-inventory/<id|[0-9]+>', (Request req, String id) async {
    await db.query(
      'DELETE FROM sewing.product_inventory WHERE id = @id',
      substitutionValues: {'id': int.parse(id)},
    );
    return Response.ok(
      jsonEncode({'status': 'deleted'}),
      headers: {'Content-Type': 'application/json'},
    );
  });

  router.get('/material-types', (Request req) async {
    final typesRows = await db.mappedResultsQuery(
      'SELECT id, name FROM sewing.material_types ORDER BY id DESC',
    );
    final types = [];
    for (final t in typesRows) {
      final type = t['material_types']!;
      final specsRows = await db.mappedResultsQuery(
        'SELECT id, name FROM sewing.material_specs WHERE type_id=@tid ORDER BY id',
        substitutionValues: {'tid': type['id']},
      );
      types.add({
        'id': type['id'],
        'name': type['name'],
        'specs': specsRows.map((r) => r['material_specs']).toList(),
      });
    }
    return Response.ok(
      jsonEncode(types),
      headers: {'Content-Type': 'application/json'},
    );
  });

  router.post('/material-types', (Request req) async {
    final data = jsonDecode(await req.readAsString());
    final typeName = (data['name'] as String?)?.trim();
    final specs = (data['specs'] as List?) ?? [];
    if (typeName == null || typeName.isEmpty) {
      return Response(400, body: jsonEncode({'error': 'اسم المادة الخام مطلوب'}));
    }
    final typeRes = await db.query(
      'INSERT INTO sewing.material_types (name) VALUES (@name) RETURNING id',
      substitutionValues: {'name': typeName},
    );
    final typeId = typeRes.first[0] as int;
    for (final s in specs) {
      final specName = (s['name'] as String?)?.trim();
      if (specName != null && specName.isNotEmpty) {
        await db.query(
          'INSERT INTO sewing.material_specs (type_id, name) VALUES (@tid, @name)',
          substitutionValues: {'tid': typeId, 'name': specName},
        );
      }
    }
    return Response.ok(
      jsonEncode({'id': typeId}),
      headers: {'Content-Type': 'application/json'},
    );
  });

  router.put('/material-types/<id|[0-9]+>', (Request req, String id) async {
    final data = jsonDecode(await req.readAsString());
    final typeName = (data['name'] as String?)?.trim();
    final specs = (data['specs'] as List?) ?? [];
    if (typeName == null || typeName.isEmpty) {
      return Response(400, body: jsonEncode({'error': 'اسم المادة الخام مطلوب'}));
    }
    await db.query(
      'UPDATE sewing.material_types SET name=@name WHERE id=@id',
      substitutionValues: {'id': int.parse(id), 'name': typeName},
    );
    final currentSpecsRows = await db.mappedResultsQuery(
      'SELECT id, name FROM sewing.material_specs WHERE type_id=@tid',
      substitutionValues: {'tid': int.parse(id)},
    );
    final List<Map<String, dynamic>> currentSpecs = currentSpecsRows
        .map((r) => r['material_specs'])
        .where((spec) => spec != null)
        .cast<Map<String, dynamic>>()
        .toList();
    final newNames = specs
        .map((s) => (s['name'] as String?)?.trim() ?? '')
        .where((n) => n.isNotEmpty)
        .toSet();
    for (final old in currentSpecs) {
      final oldName = (old['name'] as String?)?.trim() ?? '';
      if (!newNames.contains(oldName)) {
        await db.query(
          'DELETE FROM sewing.material_specs WHERE id=@id',
          substitutionValues: {'id': old['id']},
        );
      }
    }
    for (final s in specs) {
      final specName = (s['name'] as String?)?.trim();
      if (s['id'] != null) {
        await db.query(
          'UPDATE sewing.material_specs SET name=@name WHERE id=@id',
          substitutionValues: {'id': s['id'], 'name': specName},
        );
      } else if (specName != null && specName.isNotEmpty) {
        await db.query(
          'INSERT INTO sewing.material_specs (type_id, name) VALUES (@tid, @name)',
          substitutionValues: {'tid': int.parse(id), 'name': specName},
        );
      }
    }
    return Response.ok(
      jsonEncode({'status': 'updated'}),
      headers: {'Content-Type': 'application/json'},
    );
  });

  router.delete('/material-types/<id|[0-9]+>', (Request req, String id) async {
    await db.query(
      'DELETE FROM sewing.material_types WHERE id=@id',
      substitutionValues: {'id': int.parse(id)},
    );
    return Response.ok(
      jsonEncode({'status': 'deleted'}),
      headers: {'Content-Type': 'application/json'},
    );
  });

  router.get('/materials', (Request req) async {
  final typeId = int.tryParse(req.url.queryParameters['type_id'] ?? '');
  if (typeId == null) {
    return Response(400, body: jsonEncode({'error': 'type_id parameter required'}));
  }
  
  final specsRows = await db.mappedResultsQuery(
    'SELECT id, name FROM sewing.material_specs WHERE type_id = @tid ORDER BY id',
    substitutionValues: {'tid': typeId},
  );
  final specs = specsRows.map((r) => r['material_specs']).toList();

  final matsRows = await db.mappedResultsQuery(
    '''
    SELECT m.id, m.code, m.stock_quantity
    FROM sewing.materials m
    WHERE m.type_id = @tid
    ORDER BY m.id DESC
    ''',
    substitutionValues: {'tid': typeId},
  );
  
  final mats = <Map<String, dynamic>>[];
  for (final m in matsRows) {
    final mat = m['materials']!;
    final materialId = mat['id'] as int;
    
    // Get the latest price for this specific material
    final priceRows = await db.query('''
      SELECT pi.unit_price
      FROM sewing.purchase_items pi
      JOIN sewing.purchases p ON p.id = pi.purchase_id
      WHERE pi.material_id = @mid
      ORDER BY p.purchase_date DESC, pi.id DESC
      LIMIT 1
    ''', substitutionValues: {'mid': materialId});
    
    // Safe type conversion using your existing parseNum helper
    double lastUnitPrice = 0.0;
    if (priceRows.isNotEmpty && priceRows.first[0] != null) {
      lastUnitPrice = parseNum(priceRows.first[0]).toDouble();
    }
    
    final valuesRows = await db.mappedResultsQuery(
      '''
      SELECT ms.id AS spec_id,
             ms.name AS spec_name,
             msv.value
      FROM sewing.material_specs ms
      LEFT JOIN sewing.material_spec_values msv
        ON ms.id = msv.spec_id AND msv.material_id = @mid
      WHERE ms.type_id = @tid
      ORDER BY ms.id
      ''',
      substitutionValues: {'mid': materialId, 'tid': typeId},
    );
    
    final specValues = valuesRows.map((r) {
      return {
        'spec_id': r['material_specs']!['spec_id'],
        'spec_name': r['material_specs']!['spec_name'],
        'value': r['material_spec_values']?['value'] ?? '',
      };
    }).toList();
    
    mats.add({
      'id': materialId,
      'code': mat['code'],
      'stock_quantity': parseNum(mat['stock_quantity']).toDouble(),
      'last_unit_price': lastUnitPrice,
      'specs': specValues,
    });
  }
  
  return Response.ok(
    jsonEncode({'specs': specs, 'materials': mats}),
    headers: {'Content-Type': 'application/json'},
  );
});



  router.post('/materials', (Request req) async {
    final data = jsonDecode(await req.readAsString());
    if (data['type_id'] == null || data['code'] == null) {
      return Response(400, body: jsonEncode({'error': 'type_id and code required'}));
    }
    final res = await db.query(
      '''
      INSERT INTO sewing.materials
        (type_id, code, stock_quantity)
      VALUES
        (@type_id, @code, @stock)
      RETURNING id
      ''',
      substitutionValues: {
        'type_id': data['type_id'],
        'code': data['code'],
        'stock': data['stock_quantity'] ?? 0,
      },
    );
    final newId = res.first[0] as int;
    if (data['specs'] is List) {
      for (final s in data['specs']) {
        if (s['spec_id'] != null && s['value'] != null) {
          await db.query(
            '''
            INSERT INTO sewing.material_spec_values
              (material_id, spec_id, value)
            VALUES
              (@mid, @sid, @val)
            ON CONFLICT (material_id, spec_id) DO UPDATE SET value = @val
            ''',
            substitutionValues: {
              'mid': newId,
              'sid': s['spec_id'],
              'val': s['value'],
            },
          );
        }
      }
    }
    return Response.ok(
      jsonEncode({'id': newId}),
      headers: {'Content-Type': 'application/json'},
    );
  });

  router.put('/materials/<id|[0-9]+>', (Request req, String id) async {
    final data = jsonDecode(await req.readAsString());
    await db.query(
      '''
      UPDATE sewing.materials
      SET code = @code,
          stock_quantity = @stock
      WHERE id = @id
      ''',
      substitutionValues: {
        'id': int.parse(id),
        'code': data['code'],
        'stock': data['stock_quantity'] ?? 0,
      },
    );
    if (data['specs'] is List) {
      for (final s in data['specs']) {
        if (s['spec_id'] != null && s['value'] != null) {
          await db.query(
            '''
            INSERT INTO sewing.material_spec_values
              (material_id, spec_id, value)
            VALUES
              (@mid, @sid, @val)
            ON CONFLICT (material_id, spec_id) DO UPDATE SET value = @val
            ''',
            substitutionValues: {
              'mid': int.parse(id),
              'sid': s['spec_id'],
              'val': s['value'],
            },
          );
        }
      }
    }
    return Response.ok(
      jsonEncode({'status': 'updated'}),
      headers: {'Content-Type': 'application/json'},
    );
  });

  router.delete('/materials/<id|[0-9]+>', (Request req, String id) async {
    await db.query(
      'DELETE FROM sewing.materials WHERE id = @id',
      substitutionValues: {'id': int.parse(id)},
    );
    return Response.ok(
      jsonEncode({'status': 'deleted'}),
      headers: {'Content-Type': 'application/json'},
    );
  });

  router.get('/<id>/cost', (Request request, String id) async {
    try {
      final modelId = int.parse(id);
      final costs = await calculateModelCosts(db, modelId);
      return Response.ok(
        jsonEncode(costs),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to calculate model cost: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  return router;
}