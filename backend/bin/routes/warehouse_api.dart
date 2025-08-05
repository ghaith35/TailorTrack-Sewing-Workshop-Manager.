import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:postgres/postgres.dart';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:mime/mime.dart';

// Helper functions to parse numbers safely
num parseNum(dynamic value) => value is num ? value : (num.tryParse(value.toString()) ?? 0);
int parseInt(dynamic value) => value is int ? value : (int.tryParse(value.toString()) ?? 0);
Map<String, String> parseContentDisposition(String disposition) {
  final params = <String, String>{};
  final parts = disposition.split(';').map((s) => s.trim());
  for (final part in parts) {
    if (part.contains('=')) {
      final keyValue = part.split('=');
      final key = keyValue[0].trim();
      final value = keyValue[1].trim().replaceAll('"', '');
      params[key] = value;
    }
  }
  return params;
}
/// Recalculates and writes each model's global_price based on completed inventory
Future<void> recalcAllGlobalPrices(PostgreSQLConnection db) async {
  final idRows = await db.query('SELECT id FROM sewing.models');
  for (final idRow in idRows) {
    final modelId = idRow[0] as int;

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
    final autoQty = inv.first[1] as double;
    final totalQty = manualQty + autoQty;

    final costs = await calculateModelCosts(db, modelId);
    final manualCost = (costs['manual_total_cost'] as num).toDouble();
    final autoCost = (costs['automatic_total_cost'] as num).toDouble();

    final globalPrice = totalQty > 0
        ? (manualQty * manualCost + autoQty * autoCost) / totalQty
        : 0.0;

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

    final piecesRes = await db.query(r'''
      SELECT COALESCE(SUM(quantity), 0)
      FROM sewing.model_production
      WHERE date_trunc('month', produced_at)
            = date_trunc('month', CURRENT_DATE)
    ''');
    int pieces = parseInt(piecesRes.first[0]);
    if (pieces < 1) {
      print('Warning: pieces is zero for model $modelId, defaulting to 1');
      pieces = 1;
    }

    final sewSalRes = await db.query('''
      SELECT COALESCE(SUM(salary),0)
      FROM sewing.employees
      WHERE role = 'خياطة' AND seller_type = 'month' AND status = 'active'
    ''');
    final autoSewCost = parseNum(sewSalRes.first[0]) / pieces;

    final asmSalRes = await db.query('''
      SELECT COALESCE(SUM(salary),0)
      FROM sewing.employees
      WHERE role = 'فينيسيون' AND seller_type = 'month' AND status = 'active'
    ''');
    final autoAsmCost = parseNum(asmSalRes.first[0]) / pieces;

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

    final transportShare = await share('transport');
    const double repairShare = 0.0;

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

  router.post('/recalc-global-prices', (Request req) async {
    try {
      await recalcAllGlobalPrices(db);
      return Response.ok(
        jsonEncode({'status': 'global prices updated'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to recalc global prices: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  router.get('/product-inventory', (Request request) async {
    try {
      final results = await db.query(r'''
        SELECT 
          pi.id,
          m.id               AS model_id,
          m.name             AS model_name,
          m.sizes,
          m.nbr_of_sizes,
          pi.quantity,
          COALESCE(pb.average_cost, 0) AS global_price,
          m.image_url
        FROM sewing.product_inventory pi
        JOIN sewing.models m
          ON pi.model_id = m.id
        LEFT JOIN sewing.production_batches pb
          ON pi.production_batch_id = pb.id
        WHERE pi.warehouse_id = (
          SELECT id 
            FROM sewing.warehouses 
           WHERE type = 'ready' 
           LIMIT 1
        )
        ORDER BY m.name
      ''');

      List<Map<String, dynamic>> inventory = results.map((row) => {
            'id': parseInt(row[0]),
            'model_id': parseInt(row[1]),
            'model_name': row[2],
            'sizes': row[3],
            'nbr_of_sizes': parseInt(row[4]),
            'quantity': parseNum(row[5]),
            'global_price': parseNum(row[6]),
            'image_url': row[7] ?? '',
          }).toList();

      return Response.ok(
        jsonEncode(inventory),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch product inventory: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  router.post('/product-inventory', (Request req) async {
    try {
      final data = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final warehouseId = data['warehouse_id'] as int?;
      final modelId = data['model_id'] as int?;
      final quantity = (data['quantity'] as num?)?.toDouble();
      if (warehouseId == null || modelId == null || quantity == null || quantity <= 0) {
        return Response(
          400,
          body: jsonEncode({'error': 'Missing or invalid required fields'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      final res = await db.query(
        '''
        INSERT INTO sewing.product_inventory
          (warehouse_id, model_id, quantity)
        VALUES
          (@wid, @mid, @qty)
        RETURNING id
        ''',
        substitutionValues: {
          'wid': warehouseId,
          'mid': modelId,
          'qty': quantity,
        },
      );
      return Response.ok(
        jsonEncode({'id': res.first[0]}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to create product inventory: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  router.put('/product-inventory/<id|[0-9]+>', (Request req, String id) async {
    final invId = int.parse(id);
    try {
      final data = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final newQty = (data['quantity'] as num?)?.toDouble();
      final newMid = data['model_id'] as int?;
      final newWid = data['warehouse_id'] as int?;
      if (newQty == null || newMid == null || newWid == null || newQty <= 0) {
        return Response(
          400,
          body: jsonEncode({'error': 'Missing or invalid required fields'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      return await db.transaction((ctx) async {
        // 1) Lock & fetch old record
        final oldRows = await ctx.query(
          '''
          SELECT model_id, quantity
            FROM sewing.product_inventory
           WHERE id = @id
             FOR UPDATE
          ''',
          substitutionValues: {'id': invId},
        );
        if (oldRows.isEmpty) {
          return Response.notFound(
            jsonEncode({'error': 'Inventory item not found'}),
            headers: {'Content-Type': 'application/json'},
          );
        }
        final oldMid = oldRows.first[0] as int;
        final oldQty = (oldRows.first[1] as num).toDouble();

        // 2) Return raw-materials from old model
        final oldComps = await ctx.query(
          '''
          SELECT material_id, quantity_needed
            FROM sewing.model_components
           WHERE model_id = @mid
          ''',
          substitutionValues: {'mid': oldMid},
        );
        for (final comp in oldComps) {
          final matId = comp[0] as int;
          final per = (comp[1] as num).toDouble();
          await ctx.query(
            'UPDATE sewing.materials SET stock_quantity = stock_quantity + @r WHERE id = @m',
            substitutionValues: {'r': per * oldQty, 'm': matId},
          );
        }

        // 3) Update the inventory row
        await ctx.query(
          '''
          UPDATE sewing.product_inventory
             SET warehouse_id = @wid,
                 model_id     = @nmid,
                 quantity     = @nq
           WHERE id = @id
          ''',
          substitutionValues: {
            'wid': newWid,
            'nmid': newMid,
            'nq': newQty,
            'id': invId,
          },
        );

        // 4) Deduct raw-materials for new model
        final newComps = await ctx.query(
          '''
          SELECT material_id, quantity_needed
            FROM sewing.model_components
           WHERE model_id = @mid
          ''',
          substitutionValues: {'mid': newMid},
        );
        for (final comp in newComps) {
          final matId = comp[0] as int;
          final per = (comp[1] as num).toDouble();
          await ctx.query(
            'UPDATE sewing.materials SET stock_quantity = stock_quantity - @r WHERE id = @m',
            substitutionValues: {'r': per * newQty, 'm': matId},
          );
        }

        return Response.ok(
          jsonEncode({'status': 'updated'}),
          headers: {'Content-Type': 'application/json'},
        );
      });
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to update product inventory: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  router.delete('/product-inventory/<id|[0-9]+>', (Request req, String id) async {
    final invId = int.parse(id);
    try {
      return await db.transaction((ctx) async {
        // Lock & fetch
        final rows = await ctx.query(
          '''
          SELECT model_id, quantity
            FROM sewing.product_inventory
           WHERE id = @id
             FOR UPDATE
          ''',
          substitutionValues: {'id': invId},
        );
        if (rows.isEmpty) {
          return Response.notFound(
            jsonEncode({'error': 'Inventory item not found'}),
            headers: {'Content-Type': 'application/json'},
          );
        }
        final modelId = rows.first[0] as int;
        final qty = (rows.first[1] as num).toDouble();

        // Return raw-materials
        final comps = await ctx.query(
          '''
          SELECT material_id, quantity_needed
            FROM sewing.model_components
           WHERE model_id = @mid
          ''',
          substitutionValues: {'mid': modelId},
        );
        for (final comp in comps) {
          final matId = comp[0] as int;
          final per = (comp[1] as num).toDouble();
          await ctx.query(
            'UPDATE sewing.materials SET stock_quantity = stock_quantity + @r WHERE id = @m',
            substitutionValues: {'r': per * qty, 'm': matId},
          );
        }

        // Delete the inventory row
        await ctx.query(
          'DELETE FROM sewing.product_inventory WHERE id = @id',
          substitutionValues: {'id': invId},
        );

        return Response.ok(
          jsonEncode({'status': 'deleted'}),
          headers: {'Content-Type': 'application/json'},
        );
      });
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to delete product inventory: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  router.get('/material-types', (Request req) async {
    try {
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
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch material types: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  router.post('/material-types', (Request req) async {
    try {
      final data = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final typeName = (data['name'] as String?)?.trim();
      final specs = (data['specs'] as List?) ?? [];
      if (typeName == null || typeName.isEmpty) {
        return Response(
          400,
          body: jsonEncode({'error': 'اسم المادة الخام مطلوب'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Check for duplicate type name
      final existing = await db.query(
        'SELECT id FROM sewing.material_types WHERE name = @name',
        substitutionValues: {'name': typeName},
      );
      if (existing.isNotEmpty) {
        return Response(
          409,
          body: jsonEncode({'error': 'اسم نوع المادة موجود بالفعل'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      return await db.transaction((tx) async {
        final typeRes = await tx.query(
          'INSERT INTO sewing.material_types (name) VALUES (@name) RETURNING id',
          substitutionValues: {'name': typeName},
        );
        final typeId = typeRes.first[0] as int;
        for (final s in specs) {
          final specName = (s['name'] as String?)?.trim();
          if (specName != null && specName.isNotEmpty) {
            await tx.query(
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
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to create material type: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  router.put('/material-types/<id|[0-9]+>', (Request req, String id) async {
    final typeId = int.parse(id);
    try {
      final data = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final newName = (data['name'] as String?)?.trim();
      final specs = (data['specs'] as List?) ?? [];
      if (newName == null || newName.isEmpty) {
        return Response(
          400,
          body: jsonEncode({'error': 'اسم المادة الخام مطلوب'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Check for duplicate type name
      final existing = await db.query(
        'SELECT id FROM sewing.material_types WHERE name = @name AND id != @id',
        substitutionValues: {'name': newName, 'id': typeId},
      );
      if (existing.isNotEmpty) {
        return Response(
          409,
          body: jsonEncode({'error': 'اسم نوع المادة موجود بالفعل'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      return await db.transaction((tx) async {
        await tx.query(
          'UPDATE sewing.material_types SET name = @name WHERE id = @id',
          substitutionValues: {'id': typeId, 'name': newName},
        );

        final current = await tx.mappedResultsQuery(
          'SELECT id, name FROM sewing.material_specs WHERE type_id = @tid',
          substitutionValues: {'tid': typeId},
        );
        final existing = current.map((r) => r['material_specs']!).cast<Map>().toList();
        final keepNames = specs.map((s) => (s['name'] as String?)?.trim()).where((n) => n != null).toSet();

        for (final old in existing) {
          if (!keepNames.contains(old['name'])) {
            await tx.query(
              'DELETE FROM sewing.material_specs WHERE id = @sid',
              substitutionValues: {'sid': old['id']},
            );
          }
        }

        for (final s in specs) {
          final specName = (s['name'] as String?)?.trim();
          if (specName != null && specName.isNotEmpty) {
            if (s.containsKey('id') && s['id'] != null) {
              await tx.query(
                'UPDATE sewing.material_specs SET name = @n WHERE id = @sid',
                substitutionValues: {'sid': s['id'], 'n': specName},
              );
            } else {
              await tx.query(
                '''
                INSERT INTO sewing.material_specs (type_id, name)
                VALUES (@tid, @n)
                ON CONFLICT (type_id, name) DO NOTHING
                ''',
                substitutionValues: {'tid': typeId, 'n': specName},
              );
            }
          }
        }

        return Response.ok(
          jsonEncode({'status': 'updated'}),
          headers: {'Content-Type': 'application/json'},
        );
      });
    } catch (e) {
      print('❌ PUT /material-types/$id failed with error: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': 'فشل التحديث: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  router.delete('/material-types/<id|[0-9]+>', (Request req, String id) async {
    final typeId = int.parse(id);
    try {
      // Check if type has materials
      final materialCount = await db.query(
        'SELECT COUNT(*) FROM sewing.materials WHERE type_id = @tid',
        substitutionValues: {'tid': typeId},
      );
      if ((materialCount.first[0] as int) > 0) {
        return Response(
          409,
          body: jsonEncode({'error': 'لا يمكن حذف نوع المادة: يحتوي على مواد مرتبطة'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      return await db.transaction((tx) async {
        await tx.query(
          '''
          DELETE FROM sewing.material_spec_values
           WHERE spec_id IN (
             SELECT id FROM sewing.material_specs WHERE type_id = @tid
           )
          ''',
          substitutionValues: {'tid': typeId},
        );

        await tx.query(
          'DELETE FROM sewing.material_specs WHERE type_id = @tid',
          substitutionValues: {'tid': typeId},
        );

        await tx.query(
          'DELETE FROM sewing.material_types WHERE id = @tid',
          substitutionValues: {'tid': typeId},
        );

        return Response.ok(
          jsonEncode({'status': 'deleted'}),
          headers: {'Content-Type': 'application/json'},
        );
      });
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'فشل الحذف: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  router.get('/materials', (Request req) async {
    final typeId = int.tryParse(req.url.queryParameters['type_id'] ?? '');
    if (typeId == null) {
      return Response(
        400,
        body: jsonEncode({'error': 'type_id parameter required'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    try {
      final specsRows = await db.mappedResultsQuery(
        'SELECT id, name FROM sewing.material_specs WHERE type_id = @tid ORDER BY id',
        substitutionValues: {'tid': typeId},
      );
      final specs = specsRows.map((r) => r['material_specs']).toList();

      final matsRows = await db.mappedResultsQuery(
        '''
        SELECT m.id, m.code, m.stock_quantity, m.image_url
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

        final priceRows = await db.query(
          '''
          SELECT pi.unit_price
          FROM sewing.purchase_items pi
          JOIN sewing.purchases p ON p.id = pi.purchase_id
          WHERE pi.material_id = @mid
          ORDER BY p.purchase_date DESC, pi.id DESC
          LIMIT 1
          ''',
          substitutionValues: {'mid': materialId},
        );

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
          'image_url': mat['image_url'] ?? '',
          'last_unit_price': lastUnitPrice,
          'specs': specValues,
        });
      }

      return Response.ok(
        jsonEncode({'specs': specs, 'materials': mats}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch materials: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  router.post('/materials', (Request req) async {
    final contentType = req.headers['content-type'];
    if (contentType == null || !contentType.startsWith('multipart/form-data')) {
      return Response(
        400,
        body: jsonEncode({'error': 'Expected multipart/form-data'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    final boundary = contentType.split('boundary=').last;
    final transformer = MimeMultipartTransformer(boundary);
    final parts = transformer.bind(req.read());

    final fields = <String, String>{};
    String? imageUrl;

    try {
      await for (final part in parts) {
        final headers = part.headers;
        final disposition = headers['content-disposition'];
        if (disposition == null) continue;

        final dispositionParams = parseContentDisposition(disposition);
        final name = dispositionParams['name'];
        if (name == null) continue;

        if (name == 'image' && dispositionParams.containsKey('filename')) {
          final filename = dispositionParams['filename']!;
          final bytes = await part.fold<List<int>>([], (prev, chunk) => prev..addAll(chunk));
          final fname = p.basename(filename);
          final file = File('public/images/$fname');
          try {
            await file.create(recursive: true);
            await file.writeAsBytes(bytes);
            imageUrl = '/images/$fname';
          } catch (e) {
            return Response(
              500,
              body: jsonEncode({'error': 'Failed to save image: $e'}),
              headers: {'Content-Type': 'application/json'},
            );
          }
        } else {
          final content = await part.fold<StringBuffer>(StringBuffer(), (buf, chunk) => buf..write(utf8.decode(chunk)));
          fields[name] = content.toString();
        }
      }

      final typeId = int.tryParse(fields['type_id'] ?? '');
      final code = fields['code']?.trim();
      final specsJson = fields['specs'];
      if (typeId == null || code == null || specsJson == null) {
        return Response(
          400,
          body: jsonEncode({'error': 'Missing required fields'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Validate type_id exists
      final typeCheck = await db.query(
        'SELECT id FROM sewing.material_types WHERE id = @tid',
        substitutionValues: {'tid': typeId},
      );
      if (typeCheck.isEmpty) {
        return Response(
          400,
          body: jsonEncode({'error': 'Invalid type_id'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      List<dynamic> specs;
      try {
        specs = jsonDecode(specsJson) as List;
      } catch (e) {
        return Response(
          400,
          body: jsonEncode({'error': 'Invalid specs JSON'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      return await db.transaction((tx) async {
        final res = await tx.query(
          '''
          INSERT INTO sewing.materials (type_id, code, image_url, stock_quantity)
          VALUES (@type_id, @code, @image_url, 0)
          RETURNING id
          ''',
          substitutionValues: {
            'type_id': typeId,
            'code': code,
            'image_url': imageUrl ?? '',
          },
        );
        final newId = res.first[0] as int;

        for (final s in specs) {
          final specId = s['spec_id'] as int?;
          final value = (s['value'] as String?)?.trim();
          if (specId != null && value != null && value.isNotEmpty) {
            await tx.query(
              '''
              INSERT INTO sewing.material_spec_values (material_id, spec_id, value)
              VALUES (@mid, @sid, @val)
              ''',
              substitutionValues: {
                'mid': newId,
                'sid': specId,
                'val': value,
              },
            );
          }
        }

        return Response.ok(
          jsonEncode({'id': newId}),
          headers: {'Content-Type': 'application/json'},
        );
      });
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to create material: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  router.put('/materials/<id|[0-9]+>', (Request req, String id) async {
    final materialId = int.parse(id);
    final contentType = req.headers['content-type'];
    if (contentType == null || !contentType.startsWith('multipart/form-data')) {
      return Response(
        400,
        body: jsonEncode({'error': 'Expected multipart/form-data'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    final boundary = contentType.split('boundary=').last;
    final transformer = MimeMultipartTransformer(boundary);
    final parts = transformer.bind(req.read());

    final fields = <String, String>{};
    String? newImageUrl;
    bool clearImage = false;

    try {
      await for (final part in parts) {
        final headers = part.headers;
        final disposition = headers['content-disposition'];
        if (disposition == null) continue;

        final dispositionParams = parseContentDisposition(disposition);
        final name = dispositionParams['name'];
        if (name == null) continue;

        if (name == 'image') {
          if (dispositionParams.containsKey('filename')) {
            final filename = dispositionParams['filename']!;
            final bytes = await part.fold<List<int>>([], (prev, chunk) => prev..addAll(chunk));
            final fname = p.basename(filename);
            final file = File('public/images/$fname');
            try {
              await file.create(recursive: true);
              await file.writeAsBytes(bytes);
              newImageUrl = '/images/$fname';
            } catch (e) {
              return Response(
                500,
                body: jsonEncode({'error': 'Failed to save image: $e'}),
                headers: {'Content-Type': 'application/json'},
              );
            }
          } else {
            final content = await part.fold<StringBuffer>(StringBuffer(), (buf, chunk) => buf..write(utf8.decode(chunk)));
            if (content.toString().isEmpty) {
              clearImage = true;
            }
          }
        } else {
          final content = await part.fold<StringBuffer>(StringBuffer(), (buf, chunk) => buf..write(utf8.decode(chunk)));
          fields[name] = content.toString();
        }
      }

      final code = fields['code']?.trim();
      final specsJson = fields['specs'];
      if (code == null || specsJson == null) {
        return Response(
          400,
          body: jsonEncode({'error': 'Missing required fields'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Validate material_id exists
      final materialCheck = await db.query(
        'SELECT image_url FROM sewing.materials WHERE id = @id',
        substitutionValues: {'id': materialId},
      );
      if (materialCheck.isEmpty) {
        return Response.notFound(
          jsonEncode({'error': 'Material not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      final oldImageUrl = materialCheck.first[0] as String?;

      if ((newImageUrl != null || clearImage) && oldImageUrl != null && oldImageUrl.startsWith('/images/')) {
        try {
          final oldFile = File('public$oldImageUrl');
          if (await oldFile.exists()) await oldFile.delete();
        } catch (e) {
          print('Warning: Failed to delete old image $oldImageUrl: $e');
        }
      }

      List<dynamic> specs;
      try {
        specs = jsonDecode(specsJson) as List;
      } catch (e) {
        return Response(
          400,
          body: jsonEncode({'error': 'Invalid specs JSON'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      return await db.transaction((tx) async {
        await tx.query(
          '''
          UPDATE sewing.materials
          SET code = @code,
              image_url = @image_url
          WHERE id = @id
          ''',
          substitutionValues: {
            'id': materialId,
            'code': code,
            'image_url': clearImage ? '' : (newImageUrl ?? oldImageUrl ?? ''),
          },
        );

        for (final s in specs) {
          final specId = s['spec_id'] as int?;
          final value = (s['value'] as String?)?.trim();
          if (specId != null && value != null && value.isNotEmpty) {
            await tx.query(
              '''
              INSERT INTO sewing.material_spec_values (material_id, spec_id, value)
              VALUES (@mid, @sid, @val)
              ON CONFLICT (material_id, spec_id) DO UPDATE SET value = @val
              ''',
              substitutionValues: {
                'mid': materialId,
                'sid': specId,
                'val': value,
              },
            );
          }
        }

        return Response.ok(
          jsonEncode({'status': 'updated'}),
          headers: {'Content-Type': 'application/json'},
        );
      });
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to update material: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  /// DELETE /warehouse/materials/<id>
router.delete('/materials/<id|[0-9]+>', (Request req, String id) async {
  final materialId = int.parse(id);

  try {
    return await db.transaction((txn) async {
      // 1) Remove any raw_inventory entries for this material
      await txn.query(
        'DELETE FROM embroidery.raw_inventory WHERE material_id = @mid',
        substitutionValues: {'mid': materialId},
      );

      // 2) Now delete the material itself
      final deleteRes = await txn.query(
        'DELETE FROM embroidery.materials WHERE id = @mid',
        substitutionValues: {'mid': materialId},
      );

      if (deleteRes.affectedRowCount == 0) {
        // material not found → 404
        return Response.notFound(
          jsonEncode({'error': 'Material not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // 3) All done
      return Response.ok(
        jsonEncode({'status': 'deleted'}),
        headers: {'Content-Type': 'application/json'},
      );
    });
  } on PostgreSQLException catch (pgErr) {
    // If we still somehow hit a FK error, return 409 Conflict
    if (pgErr.code == '23503') {
      return Response(
        409,
        body: jsonEncode({'error': pgErr.message}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    // Other DB errors → 500
    return Response.internalServerError(
      body: jsonEncode({'error': pgErr.message}),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e) {
    return Response.internalServerError(
      body: jsonEncode({'error': e.toString()}),
      headers: {'Content-Type': 'application/json'},
    );
  }
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