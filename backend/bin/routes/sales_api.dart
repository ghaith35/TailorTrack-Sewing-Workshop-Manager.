import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:postgres/postgres.dart';
import 'dart:convert';

double parseNum(dynamic v) {
  if (v is String) {
    return double.tryParse(v) ?? 0.0;
  }
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

Router getSalesRoutes(PostgreSQLConnection db) {
  final router = Router();

  // === FACTURES LIST FOR SIDEBAR ===
  router.get('/factures', (Request request) async {
    try {
      final results = await db.query("""
        SELECT f.id, f.client_id, c.full_name, f.facture_date, f.total_amount,
               COALESCE(SUM(fp.amount_paid), 0) as total_paid
        FROM sewing.factures f
        JOIN sewing.clients c ON f.client_id = c.id
        LEFT JOIN sewing.facture_payments fp ON f.id = fp.facture_id
        GROUP BY f.id, c.full_name
        ORDER BY f.id DESC
      """);

      final factures = results.map((row) => {
        "id": parseInt(row[0]),
        "client_id": parseInt(row[1]),
        "client_name": row[2],
        "facture_date": row[3].toString(),
        "total_amount": parseNum(row[4]),
        "total_paid": parseNum(row[5]),
        "remaining_amount": parseNum(row[4]) - parseNum(row[5]),
      }).toList();

      return Response.ok(jsonEncode(factures), headers: {"Content-Type": "application/json"});
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({"error": "Failed to fetch factures: $e"}),
        headers: {"Content-Type": "application/json"},
      );
    }
  });
  
  router.get('/factures/<id>', (Request request, String id) async {
    try {
      // Fetch facture details
      final factureRow = await db.query("""
        SELECT f.id, f.facture_date, f.total_amount,
               f.amount_paid_on_creation,
               c.full_name, c.phone, c.address
        FROM sewing.factures f
        JOIN sewing.clients c ON f.client_id = c.id
        WHERE f.id = @id
      """, substitutionValues: {"id": int.parse(id)});

      if (factureRow.isEmpty) {
        return Response.notFound(
          jsonEncode({"error": "Facture not found"}),
          headers: {"Content-Type": "application/json"},
        );
      }

      final f = factureRow.first;

      // Fetch payments (excluding amount_paid_on_creation)
      final pays = await db.query("""
        SELECT amount_paid, payment_date
        FROM sewing.facture_payments
        WHERE facture_id = @id
        ORDER BY payment_date
      """, substitutionValues: {"id": int.parse(id)});
      
      final paysList = pays.map((r) => {
        "amount_paid": parseNum(r[0]),
        "payment_date": r[1].toString(),
      }).toList();

      // Fetch facture items with model cost for profit calculation
      final items = await db.query("""
        SELECT fi.id, fi.model_id, m.name, fi.color, fi.quantity, fi.unit_price, m.global_price
        FROM sewing.facture_items fi
        JOIN sewing.models m ON fi.model_id = m.id
        WHERE fi.facture_id = @id
      """, substitutionValues: {"id": int.parse(id)});
      
      final itemsList = items.map((r) {
        final quantity = parseInt(r[4]);
        final unitPrice = parseNum(r[5]);
        final globalPrice = parseNum(r[6]);
        final profitPerPiece = unitPrice - globalPrice;
        
        return {
          "id": r[0],
          "model_id": r[1],
          "model_name": r[2],
          "color": r[3],
          "quantity": quantity,
          "unit_price": unitPrice,
          "line_total": quantity * unitPrice,
          "profit_per_piece": profitPerPiece,
        };
      }).toList();

      // Calculate total paid including initial payment
      final totalPaid = paysList.fold<double>(
        parseNum(f[3]), // amount_paid_on_creation
        (sum, p) => sum + parseNum(p["amount_paid"]),
      );
      final remaining = parseNum(f[2]) - totalPaid;

      // Build response
      final data = {
        "id": f[0],
        "facture_date": f[1].toString(),
        "total_amount": parseNum(f[2]),
        "amount_paid_on_creation": parseNum(f[3]),
        "client_name": f[4],
        "client_phone": f[5],
        "client_address": f[6],
        "payments": paysList,
        "total_paid": totalPaid,
        "remaining_amount": remaining,
        "items": itemsList,
      };

      return Response.ok(
        jsonEncode(data),
        headers: {"Content-Type": "application/json"},
      );
    } catch (e) {
      print('Error fetching facture details: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": "Failed to fetch facture details: $e"}),
        headers: {"Content-Type": "application/json"},
      );
    }
  });

  // === MODELS ===
  router.get('/models', (Request req) async {
    try {
      final rows = await db.query("""
        SELECT DISTINCT
          m.id,
          m.name,
          COALESCE(SUM(pi.quantity), 0) AS available_quantity,
          m.global_price AS cost_price
        FROM sewing.models m
        LEFT JOIN sewing.product_inventory pi
          ON pi.model_id = m.id
        LEFT JOIN sewing.warehouses w
          ON pi.warehouse_id = w.id AND w.type = 'ready'
        GROUP BY m.id
        ORDER BY m.name
      """);
      
      final models = rows.map((r) {
        return {
          'id': r[0] as int,
          'name': r[1] as String,
          'available_quantity': parseInt(r[2]),
          'cost_price': parseNum(r[3]),
        };
      }).toList();
      
      return Response.ok(jsonEncode(models),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({"error": "Failed to fetch models: $e"}),
        headers: {"Content-Type": "application/json"},
      );
    }
  });

  // === CLIENTS ===
  router.get('/clients', (Request req) async {
    try {
      final rows = await db.query("""
        SELECT DISTINCT id, full_name, phone, address
        FROM sewing.clients
        ORDER BY full_name
      """);
      
      final clients = rows.map((r) => {
        'id': r[0] as int,
        'full_name': r[1] as String,
        'phone': r[2] as String,
        'address': r[3] as String,
      }).toList();
      
      return Response.ok(jsonEncode(clients),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({"error": "Failed to fetch clients: $e"}),
        headers: {"Content-Type": "application/json"},
      );
    }
  });

  // === CREATE FACTURE WITH FIFO DEDUCTION ===
  router.post('/factures', (Request req) async {
    final payload = jsonDecode(await req.readAsString());
    final int clientId = payload['client_id'];
    final double totalAmount = parseNum(payload['total_amount']);
    final double paidOnCreation = parseNum(payload['amount_paid_on_creation']);
    final List items = payload['items'];
final String? factureDate = payload['facture_date'] as String?;
  final DateTime parsedDate = factureDate != null
      ? DateTime.parse(factureDate)
      : DateTime.now();
    return await db.transaction((txn) async {
      // 1) Check stock availability for all items
      for (var it in items) {
        final modelId = it['model_id'];
        final color = it['color'] as String?;
        final requestedQty = parseInt(it['quantity']);
        
        final stockRes = await txn.query("""
          SELECT COALESCE(SUM(pi.quantity), 0) as total_stock
          FROM sewing.product_inventory pi
          JOIN sewing.warehouses w
            ON pi.warehouse_id = w.id AND w.type = 'ready'
          WHERE pi.model_id = @mid
            ${color != null ? 'AND pi.color = @color' : ''}
        """, substitutionValues: {
          'mid': modelId,
          if (color != null) 'color': color,
        });
        
        final availableStock = parseNum(stockRes.first[0]);
        if (availableStock < requestedQty) {
          return Response(
            400,
            body: jsonEncode({
              'error': 'Not enough stock for model $modelId ${color ?? ''}. Available: $availableStock, requested: $requestedQty.'
            }),
            headers: {'Content-Type': 'application/json'},
          );
        }
      }

      // 2) Insert facture without facture_name
      final insertFact = await txn.query("""
      INSERT INTO sewing.factures
        (client_id, total_amount, amount_paid_on_creation, facture_date)
      VALUES (@cid, @total, @paid, @date)
      RETURNING id
    """, substitutionValues: {
      'cid': clientId,
      'total': totalAmount,
      'paid': paidOnCreation,
      'date': parsedDate,  // NEW: Add date parameter
    });
      final factureId = insertFact.first[0] as int;

      // 3) Insert items & deduct inventory using FIFO
      for (var it in items) {
        final modelId = it['model_id'];
        final color = it['color'] as String?;
        var remainingQty = parseInt(it['quantity']);
        final unitPrice = parseNum(it['unit_price']);

        // Insert facture item
        await txn.query("""
          INSERT INTO sewing.facture_items
            (facture_id, model_id, color, quantity, unit_price)
          VALUES (@fid, @mid, @color, @qty, @unit)
        """, substitutionValues: {
          'fid': factureId,
          'mid': modelId,
          'color': color,
          'qty': remainingQty,
          'unit': unitPrice,
        });

        // FIFO deduction: Get inventory records ordered by oldest first
        final inventoryRecords = await txn.query("""
          SELECT pi.id, pi.quantity
          FROM sewing.product_inventory pi
          JOIN sewing.warehouses w
            ON pi.warehouse_id = w.id AND w.type = 'ready'
          WHERE pi.model_id = @mid
            ${color != null ? 'AND pi.color = @color' : ''}
            AND pi.quantity > 0
          ORDER BY pi.last_updated ASC, pi.id ASC
        """, substitutionValues: {
          'mid': modelId,
          if (color != null) 'color': color,
        });

        // Deduct from each record using FIFO
        for (var record in inventoryRecords) {
          if (remainingQty <= 0) break;
          
          final recordId = record[0] as int;
          final recordQty = parseNum(record[1]);
          final deductQty = remainingQty > recordQty ? recordQty : remainingQty.toDouble();
          
          await txn.query("""
            UPDATE sewing.product_inventory
            SET quantity = quantity - @deduct, last_updated = NOW()
            WHERE id = @id
          """, substitutionValues: {
            'id': recordId,
            'deduct': deductQty,
          });
          
          remainingQty -= deductQty.toInt();
        }
      }

      return Response(201,
          body: jsonEncode({'id': factureId}),
          headers: {'Content-Type': 'application/json'});
    });
  });

  router.post('/factures/<id>/pay', (Request req, String id) async {
    try {
      final payload = jsonDecode(await req.readAsString());
      final amount = parseNum(payload['amount']);
      if (amount <= 0) {
        return Response(
          400,
          body: jsonEncode({'error': 'Amount must be positive'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Fetch facture's unpaid amount
      final unpaidRow = await db.query("""
        SELECT total_amount - COALESCE(amount_paid_on_creation, 0) -
          COALESCE((SELECT SUM(amount_paid) FROM sewing.facture_payments WHERE facture_id = @fid), 0)
        FROM sewing.factures WHERE id = @fid
      """, substitutionValues: {'fid': int.parse(id)});
      if (unpaidRow.isEmpty) {
        return Response(
          404,
          body: jsonEncode({'error': 'Facture not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final unpaid = parseNum(unpaidRow.first[0]);
      if (unpaid <= 0) {
        return Response(
          400,
          body: jsonEncode({'error': 'No unpaid amount left for this facture'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      if (amount > unpaid) {
        return Response(
          400,
          body: jsonEncode({'error': 'Cannot pay more than remaining facture amount', 'remaining': unpaid}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Insert payment
      await db.query("""
        INSERT INTO sewing.facture_payments (facture_id, amount_paid, payment_date)
        VALUES (@fid, @amount, CURRENT_DATE)
      """, substitutionValues: {'fid': int.parse(id), 'amount': amount});

      return Response.ok(
        jsonEncode({'status': 'success', 'facture_id': id, 'paid': amount}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      print('Error in /factures/<id>/pay: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Payment failed', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // === DELETE FACTURE ===
  router.delete('/factures/<id>', (Request req, String id) async {
    try {
      await db.query(
        'DELETE FROM sewing.factures WHERE id = @id',
        substitutionValues: {'id': int.parse(id)},
      );
      return Response.ok(jsonEncode({'deleted': id}),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({"error": "Failed to delete facture: $e"}),
        headers: {"Content-Type": "application/json"},
      );
    }
  });

////////////////////////////////////////////////////////////////

router.get('/clients/<id>/factures', (Request request, String id) async {
  try {
    final factures = await db.query("""
      SELECT f.id, f.facture_date, f.total_amount, f.amount_paid_on_creation,
             COALESCE(SUM(fp.amount_paid), 0) as payments,
             (f.total_amount - f.amount_paid_on_creation - COALESCE(SUM(fp.amount_paid), 0)) as remaining
      FROM sewing.factures f
      LEFT JOIN sewing.facture_payments fp ON f.id = fp.facture_id
      WHERE f.client_id = @cid
      GROUP BY f.id
      ORDER BY f.facture_date DESC, f.id DESC
    """, substitutionValues: {'cid': int.parse(id)});

    final result = [];
    for (final f in factures) {
      // For each facture, also fetch its items (as in /factures/<id>)
      final items = await db.query("""
        SELECT fi.id, fi.model_id, m.name, fi.color, fi.quantity, fi.unit_price, m.global_price
        FROM sewing.facture_items fi
        JOIN sewing.models m ON fi.model_id = m.id
        WHERE fi.facture_id = @fid
      """, substitutionValues: {'fid': f[0]});

      final itemsList = items.map((r) {
        final quantity = parseInt(r[4]);
        final unitPrice = parseNum(r[5]);
        final globalPrice = parseNum(r[6]);
        return {
          "id": r[0],
          "model_id": r[1],
          "model_name": r[2],
          "color": r[3],
          "quantity": quantity,
          "unit_price": unitPrice,
          "line_total": quantity * unitPrice,
          "profit_per_piece": unitPrice - globalPrice,
        };
      }).toList();

      result.add({
        "id": f[0],
        "facture_date": f[1].toString(),
        "total_amount": parseNum(f[2]),
        "amount_paid_on_creation": parseNum(f[3]),
        "total_paid": parseNum(f[3]) + parseNum(f[4]), // paid on creation + payments
        "remaining_amount": parseNum(f[5]),
        "items": itemsList,
      });
    }

    return Response.ok(jsonEncode(result), headers: {"Content-Type": "application/json"});
  } catch (e) {
    return Response.internalServerError(
      body: jsonEncode({"error": "Failed to fetch client factures: $e"}),
      headers: {"Content-Type": "application/json"},
    );
  }
});


router.get('/clients/<id>/account', (Request request, String id) async {
  try {
    // 1. Factures
    final factures = await db.query("""
      SELECT id, facture_date, total_amount, amount_paid_on_creation
      FROM sewing.factures
      WHERE client_id = @cid
    """, substitutionValues: {'cid': int.parse(id)});

    // 2. Payments (including on creation)
    final payments = await db.query("""
      SELECT fp.facture_id, fp.amount_paid, fp.payment_date
      FROM sewing.facture_payments fp
      JOIN sewing.factures f ON fp.facture_id = f.id
      WHERE f.client_id = @cid
    """, substitutionValues: {'cid': int.parse(id)});

    // 3. Build rows
    final rows = <Map<String, dynamic>>[];

    // Facture credit entries
    for (final f in factures) {
      rows.add({
        'date': f[1].toString(),
        'type': 'facture',
        'facture_id': f[0],
        'label': 'فاتورة',
        'amount': parseNum(f[2]), // positive
      });
      // Pay on creation
      if (parseNum(f[3]) > 0) {
        rows.add({
          'date': f[1].toString(),
          'type': 'pay_on_creation',
          'facture_id': f[0],
          'label': 'دفع عند إنشاء الفاتورة',
          'amount': -parseNum(f[3]),
        });
      }
    }
    // Facture payments
    for (final p in payments) {
      rows.add({
        'date': p[2].toString(),
        'type': 'payment',
        'facture_id': p[0],
        'label': 'دفعة على الفاتورة',
        'amount': -parseNum(p[1]),
      });
    }

    // 4. Sort by date (and facture id for stability)
    rows.sort((a, b) {
      final d1 = DateTime.parse(a['date']);
      final d2 = DateTime.parse(b['date']);
      final cmp = d1.compareTo(d2);
      if (cmp != 0) return cmp;
      return (a['facture_id'] as int).compareTo(b['facture_id'] as int);
    });

    // 5. Calculate totals
    final totalFactures = factures.fold<double>(0, (sum, f) => sum + parseNum(f[2]));
    final totalPaid = factures.fold<double>(0, (sum, f) => sum + parseNum(f[3])) +
      payments.fold<double>(0, (sum, p) => sum + parseNum(p[1]));
    final remaining = totalFactures - totalPaid;

    final result = {
      'entries': rows,
      'summary': {
        'total': totalFactures,
        'paid': totalPaid,
        'remaining': remaining,
      }
    };

    return Response.ok(jsonEncode(result), headers: {"Content-Type": "application/json"});
  } catch (e) {
    return Response.internalServerError(
      body: jsonEncode({"error": "Failed to fetch client account: $e"}),
      headers: {"Content-Type": "application/json"},
    );
  }
});
router.get('/models/<id>/clients', (Request request, String id) async {
  try {
    final rows = await db.query("""
      SELECT c.id, c.full_name, c.phone, c.address,
             f.id as facture_id, f.facture_date,
             fi.quantity, fi.unit_price
      FROM sewing.facture_items fi
      JOIN sewing.factures f ON fi.facture_id = f.id
      JOIN sewing.clients c ON f.client_id = c.id
      WHERE fi.model_id = @mid
      ORDER BY f.facture_date DESC, f.id DESC
    """, substitutionValues: {'mid': int.parse(id)});

    final result = rows.map((r) => {
      'client_id': r[0],
      'client_name': r[1],
      'client_phone': r[2],
      'client_address': r[3],
      'facture_id': r[4],
      'facture_date': r[5].toString(),
      'quantity': r[6],
      'unit_price': r[7],
    }).toList();

    return Response.ok(jsonEncode(result), headers: {"Content-Type": "application/json"});
  } catch (e) {
    return Response.internalServerError(
      body: jsonEncode({"error": "Failed to fetch model clients: $e"}),
      headers: {"Content-Type": "application/json"},
    );
  }
});









// Add after your existing routes in getSalesRoutes function

// === SEASONS ===
router.get('/seasons', (Request req) async {
  try {
    final rows = await db.query("""
      SELECT id, name, start_date, end_date
      FROM sewing.seasons
      ORDER BY start_date DESC
    """);
    
    final seasons = rows.map((r) => {
      'id': r[0] as int,
      'name': r[1] as String,
      'start_date': r[2].toString(),
      'end_date': r[3].toString(),
    }).toList();
    
    return Response.ok(jsonEncode(seasons),
        headers: {'Content-Type': 'application/json'});
  } catch (e) {
    return Response.internalServerError(
      body: jsonEncode({"error": "Failed to fetch seasons: $e"}),
      headers: {"Content-Type": "application/json"},
    );
  }
});
// بعد /seasons
router.get('/clients/by_season/<sid>', (Request req, String sid) async {
  try {
    final rows = await db.query("""
      SELECT DISTINCT c.id, c.full_name, c.phone, c.address
      FROM sewing.factures f
      JOIN sewing.clients c ON f.client_id = c.id
      JOIN sewing.seasons s ON f.facture_date BETWEEN s.start_date AND s.end_date
      WHERE s.id = @sid
      ORDER BY c.full_name
    """, substitutionValues: {'sid': int.parse(sid)});
    final clients = rows.map((r)=> {
      'id': r[0],
      'full_name': r[1],
      'phone': r[2],
      'address': r[3],
    }).toList();
    return Response.ok(jsonEncode(clients), headers: {'Content-Type':'application/json'});
  } catch(e){
    return Response.internalServerError(body: jsonEncode({'error': e.toString()}), headers:{'Content-Type':'application/json'});
  }
});

router.get('/models/by_season/<sid>', (Request req, String sid) async {
  try {
    final rows = await db.query("""
      SELECT DISTINCT m.id, m.name, m.global_price AS cost_price,
             COALESCE(SUM(pi.quantity),0) AS available_quantity
      FROM sewing.facture_items fi
      JOIN sewing.factures f ON fi.facture_id = f.id
      JOIN sewing.seasons s ON f.facture_date BETWEEN s.start_date AND s.end_date
      JOIN sewing.models m ON fi.model_id = m.id
      LEFT JOIN sewing.product_inventory pi ON pi.model_id = m.id
      LEFT JOIN sewing.warehouses w ON pi.warehouse_id = w.id AND w.type = 'ready'
      WHERE s.id = @sid
      GROUP BY m.id
      ORDER BY m.name
    """, substitutionValues: {'sid': int.parse(sid)});
    final models = rows.map((r)=> {
      'id': r[0],
      'name': r[1],
      'cost_price': parseNum(r[2]),
      'available_quantity': parseInt(r[3]),
    }).toList();
    return Response.ok(jsonEncode(models), headers: {'Content-Type':'application/json'});
  } catch(e){
    return Response.internalServerError(body: jsonEncode({'error': e.toString()}), headers:{'Content-Type':'application/json'});
  }
});

// === FACTURES BY SEASON ===
router.get('/factures/by_season/<seasonId>', (Request req, String seasonId) async {
  try {
    final results = await db.query("""
      SELECT f.id, f.client_id, c.full_name, f.facture_date, f.total_amount,
             COALESCE(SUM(fp.amount_paid), 0) as total_paid
      FROM sewing.factures f
      JOIN sewing.clients c ON f.client_id = c.id
      JOIN sewing.seasons s ON f.facture_date BETWEEN s.start_date AND s.end_date
      LEFT JOIN sewing.facture_payments fp ON f.id = fp.facture_id
      WHERE s.id = @sid
      GROUP BY f.id, c.full_name
      ORDER BY f.id DESC
    """, substitutionValues: {"sid": int.parse(seasonId)});

    final factures = results.map((row) => {
      "id": parseInt(row[0]),
      "client_id": parseInt(row[1]),
      "client_name": row[2],
      "facture_date": row[3].toString(),
      "total_amount": parseNum(row[4]),
      "total_paid": parseNum(row[5]),
      "remaining_amount": parseNum(row[4]) - parseNum(row[5]),
    }).toList();

    return Response.ok(jsonEncode(factures), headers: {"Content-Type": "application/json"});
  } catch (e) {
    return Response.internalServerError(
      body: jsonEncode({"error": "Failed to fetch factures by season: $e"}),
      headers: {"Content-Type": "application/json"},
    );
  }
});

// === FACTURES SUMMARY ===
router.get('/factures/summary', (Request req) async {
  try {
    final results = await db.query("""
      SELECT 
        COUNT(*) as total_factures,
        COALESCE(SUM(f.total_amount), 0) as total_income,
        COALESCE(SUM(f.total_amount - COALESCE(f.amount_paid_on_creation, 0) - 
          COALESCE((SELECT SUM(fp.amount_paid) FROM sewing.facture_payments fp WHERE fp.facture_id = f.id), 0)), 0) as total_remaining,
        COALESCE(SUM(
          (SELECT SUM(fi.quantity * (fi.unit_price - m.global_price))
           FROM sewing.facture_items fi
           JOIN sewing.models m ON fi.model_id = m.id
           WHERE fi.facture_id = f.id)
        ), 0) as total_profit
      FROM sewing.factures f
    """);

    final row = results.first;
    final summary = {
      "total_factures": parseInt(row[0]),
      "total_income": parseNum(row[1]),
      "total_remaining": parseNum(row[2]),
      "total_profit": parseNum(row[3]),
    };

    return Response.ok(jsonEncode(summary), headers: {"Content-Type": "application/json"});
  } catch (e) {
    return Response.internalServerError(
      body: jsonEncode({"error": "Failed to fetch factures summary: $e"}),
      headers: {"Content-Type": "application/json"},
    );
  }
});

// === CLIENT TRANSACTIONS BY DATE RANGE ===
// === CLIENT TRANSACTIONS BY DATE RANGE ===
router.get('/clients/<id>/transactions', (Request request, String id) async {
  try {
    final startDate = request.url.queryParameters['start_date'];
    final endDate = request.url.queryParameters['end_date'];
    
    String dateFilter = '';
    Map<String, dynamic> substitutionValues = {'cid': int.parse(id)};
    
    if (startDate != null && endDate != null) {
      // Fix: Use proper date range without adding extra day
      dateFilter = 'AND f.facture_date >= @start_date AND f.facture_date <= @end_date';
      substitutionValues['start_date'] = startDate;
      substitutionValues['end_date'] = endDate;
    }

    // Rest of the code remains the same...
    final factures = await db.query("""
      SELECT f.id, f.facture_date, f.total_amount, f.amount_paid_on_creation,
             COALESCE(SUM(fp.amount_paid), 0) as payments
      FROM sewing.factures f
      LEFT JOIN sewing.facture_payments fp ON f.id = fp.facture_id
      WHERE f.client_id = @cid $dateFilter
      GROUP BY f.id
      ORDER BY f.facture_date DESC, f.id DESC
    """, substitutionValues: substitutionValues);

    final payments = await db.query("""
      SELECT fp.facture_id, fp.amount_paid, fp.payment_date
      FROM sewing.facture_payments fp
      JOIN sewing.factures f ON fp.facture_id = f.id
      WHERE f.client_id = @cid $dateFilter
    """, substitutionValues: substitutionValues);

    final rows = <Map<String, dynamic>>[];

    // Add facture entries
    for (final f in factures) {
      rows.add({
        'date': f[1].toString(),
        'type': 'facture',
        'facture_id': f[0],
        'label': 'فاتورة',
        'amount': parseNum(f[2]),
      });
      
      if (parseNum(f[3]) > 0) {
        rows.add({
          'date': f[1].toString(),
          'type': 'pay_on_creation',
          'facture_id': f[0],
          'label': 'دفع عند إنشاء الفاتورة',
          'amount': -parseNum(f[3]),
        });
      }
    }

    // Add payment entries
    for (final p in payments) {
      rows.add({
        'date': p[2].toString(),
        'type': 'payment',
        'facture_id': p[0],
        'label': 'دفعة على الفاتورة',
        'amount': -parseNum(p[1]),
      });
    }

    rows.sort((a, b) {
      final d1 = DateTime.parse(a['date']);
      final d2 = DateTime.parse(b['date']);
      return d1.compareTo(d2);
    });

    return Response.ok(jsonEncode(rows), headers: {"Content-Type": "application/json"});
  } catch (e) {
    return Response.internalServerError(
      body: jsonEncode({"error": "Failed to fetch client transactions: $e"}),
      headers: {"Content-Type": "application/json"},
    );
  }
});


  return router;
}
