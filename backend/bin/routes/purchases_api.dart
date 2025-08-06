import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:postgres/postgres.dart';
num _parseNum(dynamic v) => v is num ? v : (num.tryParse(v?.toString() ?? '') ?? 0);
double _parseDouble(dynamic v) => _parseNum(v).toDouble();


Router getPurchasesRoutes(PostgreSQLConnection db) {
  final router = Router();

  // ─── List all purchases ────────────────────────────────────────────────
  router.get('/', (Request req) async {
    final rows = await db.mappedResultsQuery(r'''
      SELECT 
        p.id,
        p.purchase_date,
        p.supplier_id,
        s.full_name AS supplier_name,
        p.amount_paid_on_creation,
        p.driver, -- Include driver in the selection
        COALESCE(items.total, 0) AS total,
        COALESCE(payments.extra_paid, 0) AS extra_paid
      FROM sewing.purchases p
      LEFT JOIN sewing.suppliers s ON s.id = p.supplier_id
      LEFT JOIN (
        SELECT purchase_id, SUM(quantity * unit_price) AS total
        FROM sewing.purchase_items
        GROUP BY purchase_id
      ) items ON items.purchase_id = p.id
      LEFT JOIN (
        SELECT purchase_id, SUM(amount_paid) AS extra_paid
        FROM sewing.purchase_payments
        GROUP BY purchase_id
      ) payments ON payments.purchase_id = p.id
      ORDER BY p.id DESC
    ''');

    final List<Map<String, dynamic>> result = [];
    for (final pr in rows) {
      final p        = pr['purchases']!;
      final defaults = pr['']!;

      final total            = double.tryParse(defaults['total']?.toString() ?? '0') ?? 0.0;
      final extraPaid        = double.tryParse(defaults['extra_paid']?.toString() ?? '0') ?? 0.0;
      final paidOnCreation   = double.tryParse(p['amount_paid_on_creation']?.toString() ?? '0') ?? 0.0;
      final totalPaid        = paidOnCreation + extraPaid;

      final itemsRows = await db.mappedResultsQuery(r'''
        SELECT pi.id, pi.material_id, pi.quantity, pi.unit_price,
               m.code, mt.name AS type_name
        FROM sewing.purchase_items pi
        LEFT JOIN sewing.materials m ON pi.material_id = m.id
        LEFT JOIN sewing.material_types mt ON m.type_id = mt.id
        WHERE pi.purchase_id = @pid
        ORDER BY pi.id
      ''', substitutionValues: {'pid': p['id']});

      result.add({
        'id':                       p['id'],
        'purchase_date':            p['purchase_date']?.toString(),
        'supplier_id':              p['supplier_id'],
        'supplier_name':            pr['suppliers']!['supplier_name'],
        'driver':                   p['driver'], // Include driver in the result
        'amount_paid_on_creation':  paidOnCreation,
        'extra_paid':               extraPaid,
        'total_paid':               totalPaid,
        'total':                    total,
        'items':                    itemsRows.map((r) => {
          'id':            r['purchase_items']!['id'],
          'material_id':   r['purchase_items']!['material_id'],
          'quantity':      r['purchase_items']!['quantity'],
          'unit_price':    r['purchase_items']!['unit_price'],
          'material_code': r['materials']?['code'],
          'type_name':     r['material_types']?['type_name'],
        }).toList(),
      });
    }

    return Response.ok(jsonEncode(result),
        headers: {'Content-Type': 'application/json'});
  });

  // ─── Create a 

  // ─── Create a new purchase ────────────────────────────────────────────
  router.post('/', (Request req) async {
    final data      = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    final items     = data['items'] as List? ?? [];
    final supplier  = data['supplier_id'] as int?;
    final paid0     = double.tryParse(data['amount_paid_on_creation']?.toString() ?? '0') ?? 0.0;
    final driver     = data['driver'] as String? ?? 'غير محدد'; // Get the driver

    final res = await db.query(r'''
      INSERT INTO sewing.purchases 
        (purchase_date, supplier_id, amount_paid_on_creation, driver)
      VALUES (COALESCE(@date, CURRENT_DATE), @supplier, @paid, @driver)
      RETURNING id
    ''', substitutionValues: {
      'date':     data['purchase_date'],
      'supplier': supplier,
      'paid':     paid0,
      'driver':   driver, // Include driver in the query
    });
    final purchaseId = res.first[0] as int;

    for (final it in items) {
      final q   = double.tryParse(it['quantity'].toString())   ?? 0.0;
      final up  = double.tryParse(it['unit_price'].toString()) ?? 0.0;
      final mid = it['material_id'] as int;
      await db.query(r'''
        INSERT INTO sewing.purchase_items
          (purchase_id, material_id, quantity, unit_price)
        VALUES (@pid, @mid, @qty, @price)
      ''', substitutionValues: {
        'pid':   purchaseId,
        'mid':   mid,
        'qty':   q,
        'price': up,
      });
      await db.query(
        'UPDATE sewing.materials SET stock_quantity = stock_quantity + @q WHERE id = @mid',
        substitutionValues: {'q': q, 'mid': mid},
      );
    }

    return Response.ok(jsonEncode({'id': purchaseId}),
        headers: {'Content-Type': 'application/json'});
  });

  // ─── Material types for dropdown ───────────────────────────────────────
  router.get('/material_types', (Request req) async {
    final rows = await db.mappedResultsQuery(
      'SELECT id, name FROM sewing.material_types ORDER BY name');
    final list = rows.map((r) => {
      'id':   r['material_types']!['id'],
      'name': r['material_types']!['name'],
    }).toList();
    return Response.ok(jsonEncode(list),
        headers: {'Content-Type': 'application/json'});
  });

  // ─── Materials by type for cascading dropdown ─────────────────────────
 router.get('/materials/by_type/<typeId|[0-9]+>', (Request req, String typeId) async {
  final typeIdNum = int.parse(typeId);
  final searchQuery = req.url.queryParameters['q']?.trim() ?? '';
  final queryParams = <String, dynamic>{'type': typeIdNum}; // Use dynamic type for queryParams
  String sql = '''
    SELECT
      m.id,
      m.code,
      m.image_url,
      mt.name AS type_name
    FROM sewing.materials m
    LEFT JOIN sewing.material_types mt ON m.type_id = mt.id
    WHERE m.type_id = @type
  ''';
  if (searchQuery.isNotEmpty) {
    sql += ' AND m.code ILIKE @q';
    queryParams['q'] = '%$searchQuery%'; // String value for ILIKE
  }
  sql += ' ORDER BY m.code';
  
  final rows = await db.mappedResultsQuery(sql, substitutionValues: queryParams);
  final list = rows.map((r) => {
    'id': r['materials']!['id'],
    'code': r['materials']!['code'],
    'image_url': r['materials']!['image_url'] ?? '',
    'type_name': r['material_types']?['type_name'],
  }).toList();
  return Response.ok(jsonEncode(list),
      headers: {'Content-Type': 'application/json'});
});

  // ─── List all materials ────────────────────────────────────────────────
  router.get('/materials', (Request req) async {
    final rows = await db.mappedResultsQuery(r'''
      SELECT
        m.id,
        m.code,
        mt.name AS type_name
      FROM sewing.materials m
      LEFT JOIN sewing.material_types mt ON m.type_id = mt.id
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

  // ─── List suppliers for dropdown ──────────────────────────────────────
  router.get('/suppliers', (Request req) async {
    final rows = await db.mappedResultsQuery(
      'SELECT id, full_name, company_name FROM sewing.suppliers ORDER BY full_name');
    final list = rows.map((r) => {
      'id'  : r['suppliers']!['id'],
      'name': '${r['suppliers']!['full_name']}'
               '${r['suppliers']!['company_name'] != null ? ' (${r['suppliers']!['company_name']})' : ''}',
    }).toList();
    return Response.ok(jsonEncode(list),
        headers: {'Content-Type': 'application/json'});
  });

  // ─── List seasons for dropdown ────────────────────────────────────────
  router.get('/seasons', (Request req) async {
    final rows = await db.mappedResultsQuery(
      'SELECT id, name FROM sewing.seasons ORDER BY start_date DESC');
    final list = rows.map((r) => {
      'id'  : r['seasons']!['id'],
      'name': r['seasons']!['name'],
    }).toList();
    return Response.ok(jsonEncode(list),
        headers: {'Content-Type': 'application/json'});
  });

  // ─── Get purchases filtered by season ────────────────────────────────
  router.get('/by_season/<seasonId|[0-9]+>', (Request req, String seasonId) async {
    final sid = int.parse(seasonId);
    final rows = await db.mappedResultsQuery(r'''
      SELECT 
        p.id,
        p.purchase_date,
        p.supplier_id,
        s.full_name AS supplier_name,
        p.amount_paid_on_creation,
        COALESCE(items.total, 0) AS total,
        COALESCE(payments.extra_paid, 0) AS extra_paid
      FROM sewing.purchases p
      LEFT JOIN sewing.suppliers s ON s.id = p.supplier_id
      LEFT JOIN sewing.seasons se 
        ON p.purchase_date BETWEEN se.start_date AND se.end_date
      LEFT JOIN (
        SELECT purchase_id, SUM(quantity * unit_price) AS total
        FROM sewing.purchase_items
        GROUP BY purchase_id
      ) items ON items.purchase_id = p.id
      LEFT JOIN (
        SELECT purchase_id, SUM(amount_paid) AS extra_paid
        FROM sewing.purchase_payments
        GROUP BY purchase_id
      ) payments ON payments.purchase_id = p.id
      WHERE se.id = @sid OR @sid = 0
      ORDER BY p.id DESC
    ''', substitutionValues: {'sid': sid});

    final List<Map<String, dynamic>> result = [];
    for (final pr in rows) {
      final p        = pr['purchases']!;
      final defaults = pr['']!;

      final total  = double.tryParse(defaults['total']?.toString() ?? '0') ?? 0.0;
      final extra  = double.tryParse(defaults['extra_paid']?.toString() ?? '0') ?? 0.0;
      final paid0  = double.tryParse(p['amount_paid_on_creation']?.toString() ?? '0') ?? 0.0;
      final paid   = paid0 + extra;

      final itemsRows = await db.mappedResultsQuery(r'''
        SELECT pi.id, pi.material_id, pi.quantity, pi.unit_price,
               m.code, mt.name AS type_name
        FROM sewing.purchase_items pi
        LEFT JOIN sewing.materials m ON pi.material_id = m.id
        LEFT JOIN sewing.material_types mt ON m.type_id = mt.id
        WHERE pi.purchase_id = @pid
        ORDER BY pi.id
      ''', substitutionValues: {'pid': p['id']});

      result.add({
        'id':                       p['id'],
        'purchase_date':            p['purchase_date']?.toString(),
        'supplier_id':              p['supplier_id'],
        'supplier_name':            pr['suppliers']!['supplier_name'],
        'amount_paid_on_creation':  paid0,
        'extra_paid':               extra,
        'total_paid':               paid,
        'total':                    total,
        'items':                    itemsRows.map((r) => {
          'id':            r['purchase_items']!['id'],
          'material_id':   r['purchase_items']!['material_id'],
          'quantity':      r['purchase_items']!['quantity'],
          'unit_price':    r['purchase_items']!['unit_price'],
          'material_code': r['materials']?['code'],
          'type_name':     r['material_types']?['type_name'],
        }).toList(),
      });
    }

    return Response.ok(jsonEncode(result),
        headers: {'Content-Type': 'application/json'});
  });

  // ─── Replace line‐items on a purchase ─────────────────────────────────
  // ─── Delete a purchase ────────────────────────────────────────────────
router.delete('/<id|[0-9]+>', (Request req, String id) async {
    final pid = int.parse(id);

    return await db.transaction((ctx) async {
      // 1) Load all items
      final oldRows = await ctx.mappedResultsQuery(
        'SELECT material_id, quantity FROM sewing.purchase_items WHERE purchase_id=@pid',
        substitutionValues: {'pid': pid},
      );

      // 2) Ensure each material has enough stock to roll back
      for (final r in oldRows) {
        final mid = r['purchase_items']!['material_id'] as int;
        final need = _parseDouble(r['purchase_items']!['quantity']);
        final stockRes = await ctx.query(
          'SELECT stock_quantity FROM sewing.materials WHERE id=@mid',
          substitutionValues: {'mid': mid},
        );
        final have = _parseDouble(stockRes.first[0]);
        if (have < need) {
          return Response(
            400,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'error': 'لا يمكن حذف الشراء: المادة $mid مخزونها الحالي $have، لكن يلزم $need.'
            }),
          );
        }
      }

      // 3) Deduct stock
      for (final r in oldRows) {
        final mid = r['purchase_items']!['material_id'] as int;
        final q   = _parseDouble(r['purchase_items']!['quantity']);
        await ctx.query(
          'UPDATE sewing.materials SET stock_quantity = stock_quantity - @q WHERE id=@mid',
          substitutionValues: {'q': q, 'mid': mid},
        );
      }

      // 4) Remove all payments for this purchase
      await ctx.query(
        'DELETE FROM sewing.purchase_payments WHERE purchase_id=@pid',
        substitutionValues: {'pid': pid},
      );

      // 5) Delete the purchase (cascade deletes its items)
      await ctx.query(
        'DELETE FROM sewing.purchases WHERE id=@pid',
        substitutionValues: {'pid': pid},
      );

      return Response.ok(
        jsonEncode({'status': 'deleted'}),
        headers: {'Content-Type': 'application/json'},
      );
    });
  });


// ─── Replace line‐items AND initial payment on a purchase ─────────────
router.post('/<purchaseId|[0-9]+>/items', (Request req, String purchaseId) async {
  final data  = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
  final items = data['items'] as List? ?? [];
  final pid   = int.parse(purchaseId);
  // allow optionally changing the on-creation payment here:
  final newPaid0 = double.tryParse(
    data['amount_paid_on_creation']?.toString() ?? ''
  );

  return await db.transaction((ctx) async {
    // 1) rollback old quantities
    final old = await ctx.mappedResultsQuery(
      'SELECT material_id, quantity FROM sewing.purchase_items WHERE purchase_id=@pid',
      substitutionValues: {'pid': pid}
    );
    for (final oi in old) {
      await ctx.query(
        'UPDATE sewing.materials '
        'SET stock_quantity = stock_quantity - @q '
        'WHERE id = @mid',
        substitutionValues: {
          'q': (oi['purchase_items']!['quantity'] as num).toDouble(),
          'mid': oi['purchase_items']!['material_id'] as int
        }
      );
    }

    // 2) delete old items
    await ctx.query(
      'DELETE FROM sewing.purchase_items WHERE purchase_id=@pid',
      substitutionValues: {'pid': pid}
    );

    // 3) insert new items & update stock
    for (final it in items) {
      final q   = double.tryParse(it['quantity'].toString())   ?? 0.0;
      final up  = double.tryParse(it['unit_price'].toString()) ?? 0.0;
      final mid = it['material_id'] as int;
      await ctx.query(
        'INSERT INTO sewing.purchase_items '
        '(purchase_id, material_id, quantity, unit_price) '
        'VALUES (@pid, @mid, @qty, @price)',
        substitutionValues: {
          'pid':   pid,
          'mid':   mid,
          'qty':   q,
          'price': up
        }
      );
      await ctx.query(
        'UPDATE sewing.materials '
        'SET stock_quantity = stock_quantity + @q '
        'WHERE id = @mid',
        substitutionValues: {'q': q, 'mid': mid}
      );
    }

    // 4) update the on-creation payment if provided
    if (newPaid0 != null) {
      await ctx.query(
        'UPDATE sewing.purchases '
        'SET amount_paid_on_creation = @paid '
        'WHERE id = @pid',
        substitutionValues: {'paid': newPaid0, 'pid': pid}
      );
    }

    return Response.ok(
      jsonEncode({'status': 'updated'}),
      headers: {'Content-Type': 'application/json'}
    );
  });
});

  // ─── Edit a purchase ──────────────────────────────────────────────────
  // ─── Modify a purchase ────────────────────────────────────────────────
router.put('/<id|[0-9]+>', (Request req, String id) async {
    final pid      = int.parse(id);
    final data     = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    final items    = (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final newPaid0 = data.containsKey('amount_paid_on_creation')
        ? _parseDouble(data['amount_paid_on_creation'])
        : null;
    final supplier = data['supplier_id'] as int?;
    final driver   = data['driver'] as String? ?? 'غير محدد';
    final date     = data['purchase_date'];

    return await db.transaction((ctx) async {
      // 1) Fetch old items
      final oldRows = await ctx.mappedResultsQuery(
        'SELECT material_id, quantity FROM sewing.purchase_items WHERE purchase_id=@pid',
        substitutionValues: {'pid': pid},
      );

      // 2) Check raw-warehouse stock for each old item
      for (final r in oldRows) {
        final mid = r['purchase_items']!['material_id'] as int;
        final need = _parseDouble(r['purchase_items']!['quantity']);
        final stockRes = await ctx.query(
          'SELECT stock_quantity FROM sewing.materials WHERE id=@mid',
          substitutionValues: {'mid': mid},
        );
        final have = _parseDouble(stockRes.first[0]);
        if (have < need) {
          return Response(
            400,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'error': 'لا يمكن تعديل الشراء: المادة $mid مخزونها الحالي $have، لكن يلزم $need.'
            }),
          );
        }
      }

      // 3) Roll back old stock
      for (final r in oldRows) {
        final mid = r['purchase_items']!['material_id'] as int;
        final q   = _parseDouble(r['purchase_items']!['quantity']);
        await ctx.query(
          'UPDATE sewing.materials SET stock_quantity = stock_quantity - @q WHERE id=@mid',
          substitutionValues: {'q': q, 'mid': mid},
        );
      }

      // 4) Delete old items
      await ctx.query(
        'DELETE FROM sewing.purchase_items WHERE purchase_id=@pid',
        substitutionValues: {'pid': pid},
      );

      // 5) Insert new items & bump stock
      for (final it in items) {
        final mid = it['material_id'] as int;
        final q   = _parseDouble(it['quantity']);
        final up  = _parseDouble(it['unit_price']);
        await ctx.query(
          'INSERT INTO sewing.purchase_items '
          '(purchase_id, material_id, quantity, unit_price) '
          'VALUES (@pid, @mid, @qty, @price)',
          substitutionValues: {
            'pid':   pid,
            'mid':   mid,
            'qty':   q,
            'price': up,
          },
        );
        await ctx.query(
          'UPDATE sewing.materials SET stock_quantity = stock_quantity + @q WHERE id=@mid',
          substitutionValues: {'q': q, 'mid': mid},
        );
      }

      // 6) Update purchase header (date, supplier, driver, and optional payment)
      final cols = [
        'purchase_date = @date',
        'supplier_id   = @supplier',
        'driver        = @driver'
      ];
      final vals = {
        'id':       pid,
        'date':     date,
        'supplier': supplier,
        'driver':   driver,
      };
      if (newPaid0 != null) {
        cols.add('amount_paid_on_creation = @paid');
        vals['paid'] = newPaid0;
      }

      await ctx.query(
        'UPDATE sewing.purchases SET ${cols.join(', ')} WHERE id = @id',
        substitutionValues: vals,
      );

      return Response.ok(
        jsonEncode({'status': 'updated'}),
        headers: {'Content-Type': 'application/json'},
      );
    });
  });

  // ─── Delete a purchase ────────────────────────────────────────────────
  // router.delete('/<id|[0-9]+>', (Request req, String id) async {
  //   final pid = int.parse(id);

  //   // Roll back quantities
  //   final old = await db.mappedResultsQuery(
  //     'SELECT material_id, quantity FROM sewing.purchase_items WHERE purchase_id=@pid',
  //     substitutionValues: {'pid': pid});
  //   for (final oi in old) {
  //     await db.query(
  //       'UPDATE sewing.materials SET stock_quantity = stock_quantity - @q WHERE id=@mid',
  //       substitutionValues: {
  //         'q':  oi['purchase_items']!['quantity'],
  //         'mid': oi['purchase_items']!['material_id']
  //       });
  //   }

  //   // Delete purchase
  //   await db.query(
  //     'DELETE FROM sewing.purchases WHERE id=@id',
  //     substitutionValues: {'id': pid});

  //   return Response.ok(jsonEncode({'status': 'deleted'}),
  //       headers: {'Content-Type': 'application/json'});
  // });

  return router;
}
