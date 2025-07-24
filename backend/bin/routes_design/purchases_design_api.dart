// bin/routes/design_purchases_routes.dart
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:postgres/postgres.dart';

Router getDesignPurchasesRoutes(PostgreSQLConnection db) {
  final router = Router();

  // ============= List all purchases ==========================
  router.get('/', (Request req) async {
    final rows = await db.mappedResultsQuery(r'''
      SELECT 
        p.id,
        p.purchase_date,
        p.supplier_id,
        s.full_name AS supplier_name,
        p.amount_paid_on_creation,
        COALESCE(items.total, 0)         AS total,
        COALESCE(payments.extra_paid, 0) AS extra_paid
      FROM design.purchases p
      LEFT JOIN design.suppliers s ON s.id = p.supplier_id
      LEFT JOIN (
        SELECT purchase_id, SUM(quantity * unit_price) AS total
        FROM design.purchase_items
        GROUP BY purchase_id
      ) items ON items.purchase_id = p.id
      LEFT JOIN (
        SELECT purchase_id, SUM(amount_paid) AS extra_paid
        FROM design.purchase_payments
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
        FROM design.purchase_items pi
        LEFT JOIN design.materials m ON pi.material_id = m.id
        LEFT JOIN design.material_types mt ON m.type_id = mt.id
        WHERE pi.purchase_id = @pid
        ORDER BY pi.id
      ''', substitutionValues: {'pid': p['id']});

      result.add({
        'id'                      : p['id'],
        'purchase_date'           : p['purchase_date']?.toString(),
        'supplier_id'             : p['supplier_id'],
        'supplier_name'           : pr['suppliers']?['supplier_name'],
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

  // ============= Create purchase =============================
  router.post('/', (Request req) async {
    final data      = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    final items     = data['items'] as List? ?? [];
    final supplier  = data['supplier_id'] as int?;
    final paid0     = double.tryParse(data['amount_paid_on_creation']?.toString() ?? '0') ?? 0.0;

    final res = await db.query(r'''
      INSERT INTO design.purchases 
        (purchase_date, supplier_id, amount_paid_on_creation)
      VALUES (COALESCE(@date, CURRENT_DATE), @supplier, @paid)
      RETURNING id
    ''', substitutionValues: {
      'date'    : data['purchase_date'],
      'supplier': supplier,
      'paid'    : paid0,
    });
    final purchaseId = res.first[0] as int;

    for (final it in items) {
      final q   = double.tryParse(it['quantity'].toString())   ?? 0.0;
      final up  = double.tryParse(it['unit_price'].toString()) ?? 0.0;
      final mid = it['material_id'] as int;
      await db.query(r'''
        INSERT INTO design.purchase_items
          (purchase_id, material_id, quantity, unit_price)
        VALUES (@pid, @mid, @qty, @price)
      ''', substitutionValues: {
        'pid'  : purchaseId,
        'mid'  : mid,
        'qty'  : q,
        'price': up,
      });
      await db.query(
        'UPDATE design.materials SET stock_quantity = stock_quantity + @q WHERE id = @mid',
        substitutionValues: {'q': q, 'mid': mid},
      );
    }

    return Response.ok(jsonEncode({'id': purchaseId}),
        headers: {'Content-Type': 'application/json'});
  });

  // ============= Material types ==============================
  router.get('/material_types', (Request req) async {
    final rows = await db.mappedResultsQuery(
      'SELECT id, name FROM design.material_types ORDER BY name');
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
      'SELECT id, code FROM design.materials WHERE type_id = @type ORDER BY code',
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
      FROM design.materials m
      LEFT JOIN design.material_types mt ON m.type_id = mt.id
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
      'SELECT id, full_name, company_name FROM design.suppliers ORDER BY full_name');
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
      'SELECT id, name FROM design.seasons ORDER BY start_date DESC');
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
        s.full_name AS supplier_name,
        p.amount_paid_on_creation,
        COALESCE(items.total, 0) AS total,
        COALESCE(payments.extra_paid, 0) AS extra_paid
      FROM design.purchases p
      LEFT JOIN design.suppliers s ON s.id = p.supplier_id
      LEFT JOIN design.seasons se 
        ON p.purchase_date BETWEEN se.start_date AND se.end_date
      LEFT JOIN (
        SELECT purchase_id, SUM(quantity * unit_price) AS total
        FROM design.purchase_items
        GROUP BY purchase_id
      ) items ON items.purchase_id = p.id
      LEFT JOIN (
        SELECT purchase_id, SUM(amount_paid) AS extra_paid
        FROM design.purchase_payments
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
        FROM design.purchase_items pi
        LEFT JOIN design.materials m ON pi.material_id = m.id
        LEFT JOIN design.material_types mt ON m.type_id = mt.id
        WHERE pi.purchase_id = @pid
        ORDER BY pi.id
      ''', substitutionValues: {'pid': p['id']});

      result.add({
        'id'                      : p['id'],
        'purchase_date'           : p['purchase_date']?.toString(),
        'supplier_id'             : p['supplier_id'],
        'supplier_name'           : pr['suppliers']?['supplier_name'],
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
  router.post('/<purchaseId|[0-9]+>/items', (Request req, String purchaseId) async {
    final data  = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    final items = data['items'] as List? ?? [];
    final pid   = int.parse(purchaseId);

    // rollback old quantities
    final old = await db.mappedResultsQuery(
      'SELECT material_id, quantity FROM design.purchase_items WHERE purchase_id=@pid',
      substitutionValues: {'pid': pid});
    for (final oi in old) {
      await db.query(
        'UPDATE design.materials SET stock_quantity = stock_quantity - @q WHERE id=@mid',
        substitutionValues: {
          'q'  : oi['purchase_items']!['quantity'],
          'mid': oi['purchase_items']!['material_id']
        });
    }

    await db.query('DELETE FROM design.purchase_items WHERE purchase_id=@pid',
        substitutionValues: {'pid': pid});

    for (final it in items) {
      final q   = double.tryParse(it['quantity'].toString())   ?? 0.0;
      final up  = double.tryParse(it['unit_price'].toString()) ?? 0.0;
      final mid = it['material_id'] as int;
      await db.query(
        'INSERT INTO design.purchase_items (purchase_id, material_id, quantity, unit_price) '
        'VALUES (@pid, @mid, @qty, @price)',
        substitutionValues: {
          'pid'  : pid,
          'mid'  : mid,
          'qty'  : q,
          'price': up,
        });
      await db.query(
        'UPDATE design.materials SET stock_quantity = stock_quantity + @q WHERE id=@mid',
        substitutionValues: {'q': q, 'mid': mid});
    }

    return Response.ok(jsonEncode({'status': 'updated'}),
        headers: {'Content-Type': 'application/json'});
  });

  // ============= Edit purchase ================================
  router.put('/<id|[0-9]+>', (Request req, String id) async {
    final data     = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    final supplier = data['supplier_id'] as int?;
    final paid0    = double.tryParse(data['amount_paid_on_creation']?.toString() ?? '0') ?? 0.0;

    await db.query(r'''
      UPDATE design.purchases
         SET purchase_date = @date,
             supplier_id   = @supplier,
             amount_paid_on_creation = @paid
       WHERE id = @id
    ''', substitutionValues: {
      'id'      : int.parse(id),
      'date'    : data['purchase_date'],
      'supplier': supplier,
      'paid'    : paid0,
    });

    return Response.ok(jsonEncode({'status': 'updated'}),
        headers: {'Content-Type': 'application/json'});
  });

  // ============= Delete purchase ==============================
  router.delete('/<id|[0-9]+>', (Request req, String id) async {
    final pid = int.parse(id);

    final old = await db.mappedResultsQuery(
      'SELECT material_id, quantity FROM design.purchase_items WHERE purchase_id=@pid',
      substitutionValues: {'pid': pid});
    for (final oi in old) {
      await db.query(
        'UPDATE design.materials SET stock_quantity = stock_quantity - @q WHERE id=@mid',
        substitutionValues: {
          'q'  : oi['purchase_items']!['quantity'],
          'mid': oi['purchase_items']!['material_id']
        });
    }

    await db.query(
      'DELETE FROM design.purchases WHERE id=@id',
      substitutionValues: {'id': pid});

    return Response.ok(jsonEncode({'status': 'deleted'}),
        headers: {'Content-Type': 'application/json'});
  });

  return router;
}
