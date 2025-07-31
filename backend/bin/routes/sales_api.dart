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

      // Fetch returns for this facture
      final returns = await db.query("""
        SELECT r.id, r.model_id, m.name as model_name, r.quantity, r.return_date,
               r.is_ready_to_sell, r.repair_cost, r.notes
        FROM sewing.returns r
        JOIN sewing.models m ON r.model_id = m.id
        WHERE r.facture_id = @id
        ORDER BY r.return_date DESC
      """, substitutionValues: {"id": int.parse(id)});

      final returnsList = returns.map((r) => {
        "id": parseInt(r[0]),
        "model_id": parseInt(r[1]),
        "model_name": r[2],
        "quantity": parseInt(r[3]),
        "return_date": r[4].toString(),
        "is_ready_to_sell": r[5] as bool,
        "repair_cost": parseNum(r[6]),
        "notes": r[7] ?? '',
      }).toList();

      final totalPaid = paysList.fold<double>(
        parseNum(f[3]),
        (sum, p) => sum + parseNum(p["amount_paid"]),
      );
      final remaining = parseNum(f[2]) - totalPaid;

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
        "returns": returnsList,
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
        headers: {"Content-Type": 'application/json'},
      );
    }
  });

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

      final insertFact = await txn.query("""
        INSERT INTO sewing.factures
          (client_id, total_amount, amount_paid_on_creation, facture_date)
        VALUES (@cid, @total, @paid, @date)
        RETURNING id
      """, substitutionValues: {
        'cid': clientId,
        'total': totalAmount,
        'paid': paidOnCreation,
        'date': parsedDate,
      });
      final factureId = insertFact.first[0] as int;

      for (var it in items) {
        final modelId = it['model_id'];
        final color = it['color'] as String?;
        var remainingQty = parseInt(it['quantity']);
        final unitPrice = parseNum(it['unit_price']);

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

        final returns = await db.query("""
          SELECT r.id, r.model_id, m.name as model_name, r.quantity, r.return_date,
                 r.is_ready_to_sell, r.repair_cost, r.notes
          FROM sewing.returns r
          JOIN sewing.models m ON r.model_id = m.id
          WHERE r.facture_id = @fid
          ORDER BY r.return_date DESC
        """, substitutionValues: {"fid": f[0]});

        final returnsList = returns.map((r) => {
          "id": parseInt(r[0]),
          "model_id": parseInt(r[1]),
          "model_name": r[2],
          "quantity": parseInt(r[3]),
          "return_date": r[4].toString(),
          "is_ready_to_sell": r[5] as bool,
          "repair_cost": parseNum(r[6]),
          "notes": r[7] ?? '',
        }).toList();

        result.add({
          "id": f[0],
          "facture_date": f[1].toString(),
          "total_amount": parseNum(f[2]),
          "amount_paid_on_creation": parseNum(f[3]),
          "total_paid": parseNum(f[3]) + parseNum(f[4]),
          "remaining_amount": parseNum(f[5]),
          "items": itemsList,
          "returns": returnsList,
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
      final factures = await db.query("""
        SELECT id, facture_date, total_amount, amount_paid_on_creation
        FROM sewing.factures
        WHERE client_id = @cid
      """, substitutionValues: {'cid': int.parse(id)});

      final payments = await db.query("""
        SELECT fp.facture_id, fp.amount_paid, fp.payment_date
        FROM sewing.facture_payments fp
        JOIN sewing.factures f ON fp.facture_id = f.id
        WHERE f.client_id = @cid
      """, substitutionValues: {'cid': int.parse(id)});

      final rows = <Map<String, dynamic>>[];

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
        final cmp = d1.compareTo(d2);
        if (cmp != 0) return cmp;
        return (a['facture_id'] as int).compareTo(b['facture_id'] as int);
      });

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
      final clients = rows.map((r) => {
        'id': r[0],
        'full_name': r[1],
        'phone': r[2],
        'address': r[3],
      }).toList();
      return Response.ok(jsonEncode(clients), headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  router.get('/models/by_season/<sid>', (Request req, String sid) async {
    try {
      final rows = await db.query("""
        SELECT DISTINCT m.id, m.name, m.global_price AS cost_price,
               COALESCE(SUM(pi.quantity), 0) AS available_quantity
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
      final models = rows.map((r) => {
        'id': r[0],
        'name': r[1],
        'cost_price': parseNum(r[2]),
        'available_quantity': parseInt(r[3]),
      }).toList();
      return Response.ok(jsonEncode(models), headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

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

  router.get('/clients/<id>/transactions', (Request request, String id) async {
    try {
      final Map<String, dynamic> subs = {
        'cid': int.parse(id),
      };

      final qp = request.url.queryParameters;
      final hasRange = qp['start_date'] != null && qp['end_date'] != null;

      String factureDateFilter = '';
      String paymentDateFilter = '';
      if (hasRange) {
        factureDateFilter =
            'AND f.facture_date >= @start_date AND f.facture_date <= @end_date';
        paymentDateFilter =
            'AND fp.payment_date >= @start_date AND fp.payment_date <= @end_date';
        subs['start_date'] = qp['start_date']!;
        subs['end_date'] = qp['end_date']!;
      }

      final factures = await db.query(r'''
        SELECT
          f.id,
          f.facture_date,
          f.total_amount,
          f.amount_paid_on_creation
        FROM sewing.factures f
        WHERE f.client_id = @cid
          ''' +
          (hasRange ? factureDateFilter : '') +
      r'''
        ORDER BY f.facture_date DESC, f.id DESC;
      ''', substitutionValues: subs);

      final List<Map<String, dynamic>> rows = [];

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

      final payments = await db.query(r'''
        SELECT
          fp.facture_id,
          fp.amount_paid,
          fp.payment_date,
          fp.from_deposit
        FROM sewing.facture_payments fp
        JOIN sewing.factures f
          ON fp.facture_id = f.id
        WHERE f.client_id = @cid
          ''' +
          (hasRange ? paymentDateFilter : '') +
      r'''
        ORDER BY fp.payment_date, fp.facture_id;
      ''', substitutionValues: subs);

      for (final p in payments) {
        rows.add({
          'date': p[2].toString(),
          'type': 'payment',
          'facture_id': p[0],
          'label': p[3] as bool ? 'دفعة من الإيداع' : 'دفعة على الفاتورة',
          'amount': -parseNum(p[1]),
          'from_deposit': p[3] as bool,
        });
      }

      rows.sort((a, b) {
        final da = DateTime.parse(a['date']);
        final db = DateTime.parse(b['date']);
        final cmp = da.compareTo(db);
        if (cmp != 0) return cmp;
        final fa = a['facture_id'] as int? ?? 0;
        final fb = b['facture_id'] as int? ?? 0;
        return fa.compareTo(fb);
      });

      return Response.ok(
        jsonEncode(rows),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, st) {
      print('Error in /clients/<id>/transactions: $e\n$st');
      return Response.internalServerError(
        body: jsonEncode({
          'error': 'Failed to fetch client transactions',
          'details': e.toString(),
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  return router;
}