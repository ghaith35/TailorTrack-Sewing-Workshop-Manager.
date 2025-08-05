// bin/routes_embrodry/purchases_embrodry_api.dart

import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:postgres/postgres.dart';

Router getEmbrodryPurchasesRoutes(PostgreSQLConnection db) {
  final router = Router();

  // ============= List all purchases ==========================
  // GET all purchases
  router.get('/', (Request req) async {
    final rows = await db.mappedResultsQuery(r'''
      SELECT 
        p.id,
        p.purchase_date,
        p.supplier_id,
        s.full_name      AS supplier_name,
        p.driver         AS driver,
        p.amount_paid_on_creation,
        COALESCE(items.total, 0)         AS total,
        COALESCE(payments.extra_paid, 0) AS extra_paid
      FROM embroidery.purchases p
      LEFT JOIN embroidery.suppliers s ON s.id = p.supplier_id
      LEFT JOIN (
        SELECT purchase_id, SUM(quantity * unit_price) AS total
        FROM embroidery.purchase_items
        GROUP BY purchase_id
      ) items ON items.purchase_id = p.id
      LEFT JOIN (
        SELECT purchase_id, SUM(amount_paid) AS extra_paid
        FROM embroidery.purchase_payments
        GROUP BY purchase_id
      ) payments ON payments.purchase_id = p.id
      ORDER BY p.id DESC
    ''');

    final List<Map<String, dynamic>> result = [];
    for (final pr in rows) {
      final p        = pr['purchases']!;
      final defaults = pr['']!;

      final total   = double.tryParse(defaults['total']?.toString() ?? '0') ?? 0.0;
      final extra   = double.tryParse(defaults['extra_paid']?.toString() ?? '0') ?? 0.0;
      final paid0   = double.tryParse(p['amount_paid_on_creation']?.toString() ?? '0') ?? 0.0;
      final paid    = paid0 + extra;

      final itemsRows = await db.mappedResultsQuery(r'''
        SELECT pi.id, pi.material_id, pi.quantity, pi.unit_price,
               m.code, mt.name AS type_name
        FROM embroidery.purchase_items pi
        LEFT JOIN embroidery.materials m ON pi.material_id = m.id
        LEFT JOIN embroidery.material_types mt ON m.type_id = mt.id
        WHERE pi.purchase_id = @pid
        ORDER BY pi.id
      ''', substitutionValues: {'pid': p['id']});

      result.add({
        'id'                      : p['id'],
        'purchase_date'           : p['purchase_date']?.toString(),
        'supplier_id'             : p['supplier_id'],
'supplier_name': pr['suppliers']?['supplier_name'],
        'driver'                  : p['driver'],
        'amount_paid_on_creation' : paid0,
        'extra_paid'              : extra,
        'total_paid'              : paid,
        'total'                   : total,
        'items'                   : itemsRows.map((r) => {
          'id'            : r['purchase_items']!['id'],
          'material_id'   : r['purchase_items']!['material_id'],
          'quantity'      : r['purchase_items']!['quantity'],
          'unit_price'    : r['purchase_items']!['unit_price'],
          'material_code' : r['materials']?['code'],
          'type_name'     : r['material_types']?['type_name'],
        }).toList(),
      });
    }

    return Response.ok(jsonEncode(result),
        headers: {'Content-Type': 'application/json'});
  });

  // POST a new purchase
  router.post('/', (Request req) async {
  final data     = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
  final items    = data['items']             as List?   ?? [];
  final supplier = data['supplier_id']       as int?;
  final driver   = data['driver']            as String?;
  final paid0    = double.tryParse(data['amount_paid_on_creation']?.toString() ?? '0') ?? 0.0;

  if (supplier == null) {
    return Response.badRequest(
      body: jsonEncode({'error': 'supplier_id is required'}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  return await db.transaction((txn) async {
    // 1) create the purchase
    final res = await txn.query(r'''
      INSERT INTO embroidery.purchases 
        (purchase_date, supplier_id, driver, amount_paid_on_creation)
      VALUES (COALESCE(@date, CURRENT_DATE), @supplier, @driver, @paid)
      RETURNING id
    ''', substitutionValues: {
      'date'    : data['purchase_date'],
      'supplier': supplier,
      'driver'  : driver,
      'paid'    : paid0,
    });
    final purchaseId = res.first[0] as int;

    // 2) find your "raw" warehouse once
    final whRes = await txn.query(r'''
      SELECT id FROM embroidery.warehouses 
      WHERE type = 'raw' LIMIT 1
    ''');
    if (whRes.isEmpty) {
      throw Exception('No raw warehouse defined');
    }
    final rawWarehouseId = whRes.first[0] as int;

    // 3) for each line item: insert, bump material, upsert raw_inventory
    for (final raw in items.cast<Map<String, dynamic>>()) {
      final materialId = raw['material_id'] as int?;
      final qty        = double.tryParse(raw['quantity']?.toString() ?? '0')   ?? 0.0;
      final price      = double.tryParse(raw['unit_price']?.toString() ?? '0') ?? 0.0;
      if (materialId == null || qty <= 0 || price < 0) continue;

      // a) insert into purchase_items
      await txn.query(r'''
        INSERT INTO embroidery.purchase_items 
          (purchase_id, material_id, quantity, unit_price)
        VALUES (@pid, @mid, @qty, @price)
      ''', substitutionValues: {
        'pid'  : purchaseId,
        'mid'  : materialId,
        'qty'  : qty,
        'price': price,
      });

      // b) bump the global stock_quantity
      await txn.query(r'''
        UPDATE embroidery.materials
        SET stock_quantity = stock_quantity + @q
        WHERE id = @mid
      ''', substitutionValues: {
        'q'  : qty,
        'mid': materialId,
      });

      // c) upsert into raw_inventory
      await txn.query(r'''
        INSERT INTO embroidery.raw_inventory
          (warehouse_id, material_id, quantity)
        VALUES (@wh, @mid, @q)
        ON CONFLICT (warehouse_id, material_id)
        DO UPDATE SET
          quantity     = embroidery.raw_inventory.quantity + EXCLUDED.quantity,
          last_updated = CURRENT_TIMESTAMP
      ''', substitutionValues: {
        'wh' : rawWarehouseId,
        'mid': materialId,
        'q'  : qty,
      });
    }

    // 4) all done!
    return Response.ok(
      jsonEncode({'id': purchaseId}),
      headers: {'Content-Type': 'application/json'},
    );
  });
});


  // PUT to update a purchase
  router.put('/<id|[0-9]+>', (Request req, String id) async {
    final data     = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    final supplier = data['supplier_id'] as int?;
    final driver   = data['driver']      as String?;
    final paid0    = double.tryParse(data['amount_paid_on_creation']?.toString() ?? '0') ?? 0.0;

    if (supplier == null) {
      return Response.badRequest(body: jsonEncode({'error': 'supplier_id is required'}));
    }

    await db.query(r'''
      UPDATE embroidery.purchases
         SET purchase_date            = @date,
             supplier_id              = @supplier,
             driver                   = @driver,
             amount_paid_on_creation  = @paid
       WHERE id = @id
    ''', substitutionValues: {
      'id'       : int.parse(id),
      'date'     : data['purchase_date'],
      'supplier' : supplier,
      'driver'   : driver,
      'paid'     : paid0,
    });

    return Response.ok(jsonEncode({'status': 'updated'}),
        headers: {'Content-Type': 'application/json'});
  });

  // ============= Material types ==============================
  router.get('/material_types', (Request req) async {
    final rows = await db.mappedResultsQuery(
      'SELECT id, name FROM embroidery.material_types ORDER BY name');
    final list = rows.map((r) => {
      'id'  : r['material_types']!['id'],
      'name': r['material_types']!['name'],
    }).toList();
    return Response.ok(jsonEncode(list),
        headers: {'Content-Type': 'application/json'});
  });

  // ============= Materials by type ===========================
  router.get('/materials/by_type/<typeId|[0-9]+>', (Request req, String typeId) async {
    final rows = await db.mappedResultsQuery(
      'SELECT id, code FROM embroidery.materials WHERE type_id = @type ORDER BY code',
      substitutionValues: {'type': int.parse(typeId)});
    final list = rows.map((r) => {
      'id'  : r['materials']!['id'],
      'code': r['materials']!['code'],
    }).toList();
    return Response.ok(jsonEncode(list),
        headers: {'Content-Type': 'application/json'});
  });

  // ============= All materials ===============================
  router.get('/materials', (Request req) async {
    final rows = await db.mappedResultsQuery(r'''
      SELECT
        m.id,
        m.code,
        mt.name AS type_name
      FROM embroidery.materials m
      LEFT JOIN embroidery.material_types mt ON m.type_id = mt.id
      ORDER BY m.code
    ''');
    final list = rows.map((r) => {
      'id'       : r['materials']!['id'],
      'code'     : r['materials']!['code'],
      'type_name': r['material_types']?['type_name'],
    }).toList();
    return Response.ok(jsonEncode(list),
        headers: {'Content-Type': 'application/json'});
  });

  // ============= Suppliers ===================================
  router.get('/suppliers', (Request req) async {
    final rows = await db.mappedResultsQuery(
      'SELECT id, full_name, company_name FROM embroidery.suppliers ORDER BY full_name');
    final list = rows.map((r) => {
      'id'  : r['suppliers']!['id'],
      'name': '${r['suppliers']!['full_name']}'
              '${r['suppliers']!['company_name'] != null ? ' (${r['suppliers']!['company_name']})' : ''}',
    }).toList();
    return Response.ok(jsonEncode(list),
        headers: {'Content-Type': 'application/json'});
  });

  // ============= Seasons =====================================
  router.get('/seasons', (Request req) async {
    final rows = await db.mappedResultsQuery(
      'SELECT id, name FROM embroidery.seasons ORDER BY start_date DESC');
    final list = rows.map((r) => {
      'id'  : r['seasons']!['id'],
      'name': r['seasons']!['name'],
    }).toList();
    return Response.ok(jsonEncode(list),
        headers: {'Content-Type': 'application/json'});
  });

  // ============= Filter by season =============================
  router.get('/by_season/<seasonId|[0-9]+>', (Request req, String seasonId) async {
    final sid = int.parse(seasonId);
    final rows = await db.mappedResultsQuery(r'''
      SELECT 
        p.id,
        p.purchase_date,
        p.supplier_id,
        s.full_name      AS supplier_name,
        p.driver         AS driver,
        p.amount_paid_on_creation,
        COALESCE(items.total, 0)         AS total,
        COALESCE(payments.extra_paid, 0) AS extra_paid
      FROM embroidery.purchases p
      LEFT JOIN embroidery.suppliers s ON s.id = p.supplier_id
      LEFT JOIN embroidery.seasons se 
        ON p.purchase_date BETWEEN se.start_date AND se.end_date
      LEFT JOIN (
        SELECT purchase_id, SUM(quantity * unit_price) AS total
        FROM embroidery.purchase_items
        GROUP BY purchase_id
      ) items ON items.purchase_id = p.id
      LEFT JOIN (
        SELECT purchase_id, SUM(amount_paid) AS extra_paid
        FROM embroidery.purchase_payments
        GROUP BY purchase_id
      ) payments ON payments.purchase_id = p.id
      WHERE se.id = @sid OR @sid = 0
      ORDER BY p.id DESC
    ''', substitutionValues: {'sid': sid});

    final List<Map<String, dynamic>> result = [];
    for (final pr in rows) {
      final p        = pr['purchases']!;
      final defaults = pr['']!;

      final total = double.tryParse(defaults['total']?.toString() ?? '0') ?? 0.0;
      final extra = double.tryParse(defaults['extra_paid']?.toString() ?? '0') ?? 0.0;
      final paid0 = double.tryParse(p['amount_paid_on_creation']?.toString() ?? '0') ?? 0.0;
      final paid  = paid0 + extra;

      final itemsRows = await db.mappedResultsQuery(r'''
        SELECT pi.id, pi.material_id, pi.quantity, pi.unit_price,
               m.code, mt.name AS type_name
        FROM embroidery.purchase_items pi
        LEFT JOIN embroidery.materials m ON pi.material_id = m.id
        LEFT JOIN embroidery.material_types mt ON m.type_id = mt.id
        WHERE pi.purchase_id = @pid
        ORDER BY pi.id
      ''', substitutionValues: {'pid': p['id']});

      result.add({
        'id'                      : p['id'],
        'purchase_date'           : p['purchase_date']?.toString(),
        'supplier_id'             : p['supplier_id'],
        'supplier_name'           : pr['suppliers']?['supplier_name'],
        'driver'                  : p['driver'],
        'amount_paid_on_creation' : paid0,
        'extra_paid'              : extra,
        'total_paid'              : paid,
        'total'                   : total,
        'items'                   : itemsRows.map((r) => {
          'id'            : r['purchase_items']!['id'],
          'material_id'   : r['purchase_items']!['material_id'],
          'quantity'      : r['purchase_items']!['quantity'],
          'unit_price'    : r['purchase_items']!['unit_price'],
          'material_code' : r['materials']?['code'],
          'type_name'     : r['material_types']?['type_name'],
        }).toList(),
      });
    }

    return Response.ok(jsonEncode(result),
        headers: {'Content-Type': 'application/json'});
  });

  // ============= Replace line items ===========================
  // router.post('/<purchaseId|[0-9]+>/items', (Request req, String purchaseId) async {
  //   final data  = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
  //   final items = data['items'] as List? ?? [];
  //   final pid   = int.parse(purchaseId);

  //   // rollback old quantities
  //   final old = await db.mappedResultsQuery(
  //     'SELECT material_id, quantity FROM embroidery.purchase_items WHERE purchase_id=@pid',
  //     substitutionValues: {'pid': pid});
  //   for (final oi in old) {
  //     await db.query(
  //       'UPDATE embroidery.materials SET stock_quantity = stock_quantity - @q WHERE id=@mid',
  //       substitutionValues: {
  //         'q'  : oi['purchase_items']!['quantity'],
  //         'mid': oi['purchase_items']!['material_id']
  //       });
  //   }

  //   await db.query('DELETE FROM embroidery.purchase_items WHERE purchase_id=@pid',
  //       substitutionValues: {'pid': pid});
  //   for (final it in items) {
  //     final q   = double.tryParse(it['quantity'].toString())   ?? 0.0;
  //     final up  = double.tryParse(it['unit_price'].toString()) ?? 0.0;
  //     final mid = it['material_id'] as int;
  //     await db.query(
  //       'INSERT INTO embroidery.purchase_items (purchase_id, material_id, quantity, unit_price) VALUES (@pid, @mid, @qty, @price)',
  //       substitutionValues: {'pid': pid, 'mid': mid, 'qty': q, 'price': up});
  //     await db.query(
  //       'UPDATE embroidery.materials SET stock_quantity = stock_quantity + @q WHERE id=@mid',
  //       substitutionValues: {'q': q, 'mid': mid});
  //   }

  //   return Response.ok(jsonEncode({'status': 'updated'}), headers: {'Content-Type': 'application/json'});
  // });

  // ============= Edit purchase ================================
  // router.put('/<id|[0-9]+>', (Request req, String id) async {
  //   final data     = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
  //   final supplier = data['supplier_id'] as int?;
  //   final driver   = data['driver']      as String?;
  //   final paid0    = double.tryParse(data['amount_paid_on_creation']?.toString() ?? '0') ?? 0.0;

  //   await db.query(r'''
  //     UPDATE embroidery.purchases
  //        SET purchase_date            = @date,
  //            supplier_id              = @supplier,
  //            driver                   = @driver,
  //            amount_paid_on_creation  = @paid
  //      WHERE id = @id
  //   ''', substitutionValues: {
  //     'id'       : int.parse(id),
  //     'date'     : data['purchase_date'],
  //     'supplier' : supplier,
  //     'driver'   : driver,
  //     'paid'     : paid0,
  //   });

  //   return Response.ok(jsonEncode({'status': 'updated'}),
  //       headers: {'Content-Type': 'application/json'});
  // });

  // ============= Delete purchase ==============================
  // ─── Delete a purchase ────────────────────────────────────────────────
// ======================== DELETE PURCHASE (using materials.stock_quantity) ========================
router.delete('/<id|[0-9]+>', (Request req, String id) async {
  final pid = int.parse(id);
  try {
    return await db.transaction((txn) async {
      // 1) Load purchased items
      final items = await txn.query(r'''
        SELECT material_id, quantity
        FROM embroidery.purchase_items
        WHERE purchase_id = @pid
      ''', substitutionValues: {'pid': pid});

      // 2) For each item, check & deduct from materials.stock_quantity
      for (final row in items) {
        final mid = row[0] as int;
        final qty = (row[1] as num).toDouble();

        // a) check stock_quantity
        final mat = await txn.query(r'''
          SELECT stock_quantity
          FROM embroidery.materials
          WHERE id = @mid
        ''', substitutionValues: {'mid': mid});
        final stockAvail = mat.isNotEmpty
            ? (mat.first[0] as num).toDouble()
            : 0.0;
        if (stockAvail < qty) {
          return Response(
            400,
            body: jsonEncode({
              'error':
                'Cannot delete purchase $pid: stock for material $mid is insufficient. '
                'Available: $stockAvail, required: $qty'
            }),
            headers: {'Content-Type': 'application/json'},
          );
        }

        // b) deduct from stock_quantity
        await txn.query(r'''
          UPDATE embroidery.materials
          SET stock_quantity = stock_quantity - @q
          WHERE id = @mid
        ''', substitutionValues: {
          'mid': mid,
          'q'  : qty,
        });
      }

      // 3) Delete related debts/payments
      await txn.query(r'''
        DELETE FROM embroidery.purchase_payments
        WHERE purchase_id = @pid
      ''', substitutionValues: {'pid': pid});

      // 4) Delete items & purchase
      await txn.query(
        'DELETE FROM embroidery.purchase_items WHERE purchase_id = @pid',
        substitutionValues: {'pid': pid});
      await txn.query(
        'DELETE FROM embroidery.purchases WHERE id = @pid',
        substitutionValues: {'pid': pid});

      return Response.ok(
        jsonEncode({'deleted': pid}),
        headers: {'Content-Type': 'application/json'},
      );
    });
  } catch (e, st) {
    print('❌ DELETE PURCHASE $pid ERROR: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Delete failed', 'details': e.toString()}),
      headers: {'Content-Type': 'application/json'},
    );
  }
});


// ======================== REPLACE LINE ITEMS (using materials.stock_quantity) ========================
router.post('/<purchaseId|[0-9]+>/items', (Request req, String purchaseId) async {
  final pid = int.parse(purchaseId);
  final data = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
  final newItems = (data['items'] as List).cast<Map<String, dynamic>>();

  try {
    return await db.transaction((txn) async {
      // 1) Roll back old items: deduct from stock_quantity
      final old = await txn.query(r'''
        SELECT material_id, quantity
        FROM embroidery.purchase_items
        WHERE purchase_id = @pid
      ''', substitutionValues: {'pid': pid});

      for (final row in old) {
        final mid = row[0] as int;
        final qty = (row[1] as num).toDouble();

        // a) check stock_quantity before rollback
        final mat = await txn.query(r'''
          SELECT stock_quantity
          FROM embroidery.materials
          WHERE id = @mid
        ''', substitutionValues: {'mid': mid});
        final stockAvail = mat.isNotEmpty
            ? (mat.first[0] as num).toDouble()
            : 0.0;
        if (stockAvail < qty) {
          return Response(
            400,
            body: jsonEncode({
              'error':
                'Cannot rollback items for purchase $pid: stock for material $mid is insufficient. '
                'Available: $stockAvail, needed rollback: $qty'
            }),
            headers: {'Content-Type': 'application/json'},
          );
        }

        // b) deduct from stock_quantity
        await txn.query(r'''
          UPDATE embroidery.materials
          SET stock_quantity = stock_quantity - @q
          WHERE id = @mid
        ''', substitutionValues: {
          'mid': mid,
          'q'  : qty,
        });
      }

      // 2) Delete old lines
      await txn.query(
        'DELETE FROM embroidery.purchase_items WHERE purchase_id = @pid',
        substitutionValues: {'pid': pid});

      // 3) Insert & bump new items
      for (final it in newItems) {
        final mid = it['material_id'] as int;
        final qty = double.tryParse(it['quantity'].toString()) ?? 0.0;
        final price = double.tryParse(it['unit_price'].toString()) ?? 0.0;
        if (qty <= 0) continue;

        // a) insert new line
        await txn.query(r'''
          INSERT INTO embroidery.purchase_items
            (purchase_id, material_id, quantity, unit_price)
          VALUES (@pid, @mid, @q, @price)
        ''', substitutionValues: {
          'pid'  : pid,
          'mid'  : mid,
          'q'    : qty,
          'price': price,
        });

        // b) bump stock_quantity
        await txn.query(r'''
          UPDATE embroidery.materials
          SET stock_quantity = stock_quantity + @q
          WHERE id = @mid
        ''', substitutionValues: {
          'mid': mid,
          'q'  : qty,
        });
      }

      return Response.ok(
        jsonEncode({'status': 'updated'}),
        headers: {'Content-Type': 'application/json'},
      );
    });
  } catch (e, st) {
    print('❌ REPLACE ITEMS FOR PURCHASE $pid ERROR: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Replace items failed', 'details': e.toString()}),
      headers: {'Content-Type': 'application/json'},
    );
  }
});

  return router;
}
