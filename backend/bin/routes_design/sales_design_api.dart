// bin/routes/design_sales_routes.dart
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:postgres/postgres.dart';

// ------------------------ Helpers ------------------------
double _parseNum(dynamic v) {
  if (v == null) return 0.0;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0.0;
  return 0.0;
}

int _parseInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

// Safe json response
Response _okJson(Object data) =>
    Response.ok(jsonEncode(data), headers: {'Content-Type': 'application/json'});

Response _errJson(Object data, {int code = 500}) => Response(code,
    body: jsonEncode(data), headers: {'Content-Type': 'application/json'});

// ------------------------ Router ------------------------
Router getDesignSalesRoutes(PostgreSQLConnection db) {
  final router = Router();

  // ======================== FACTURES LIST (Sidebar) ========================
  router.get('/factures', (Request request) async {
    try {
      final rows = await db.query("""
        SELECT f.id,
               f.client_id,
               c.full_name,
               f.facture_date,
               f.total_amount,
               COALESCE(SUM(fp.amount_paid), 0) AS total_paid
        FROM design.factures f
        JOIN design.clients c ON f.client_id = c.id
        LEFT JOIN design.facture_payments fp ON f.id = fp.facture_id
        GROUP BY f.id, c.full_name
        ORDER BY f.id DESC
      """);

      final list = rows.map((r) {
        final total = _parseNum(r[4]);
        final paid  = _parseNum(r[5]);
        return {
          'id'              : _parseInt(r[0]),
          'client_id'       : _parseInt(r[1]),
          'client_name'     : r[2],
          'facture_date'    : r[3].toString(),
          'total_amount'    : total,
          'total_paid'      : paid,
          'remaining_amount': total - paid,
        };
      }).toList();

      return _okJson(list);
    } catch (e, st) {
      print('factures list error: $e\n$st');
      return _errJson({'error': 'Failed to fetch factures', 'details': e.toString()});
    }
  });

  // ======================== FACTURE DETAILS ========================
  router.get('/factures/<id|[0-9]+>', (Request request, String id) async {
    try {
      final fid = int.parse(id);

      final fRow = await db.query("""
        SELECT f.id, f.facture_date, f.total_amount, f.amount_paid_on_creation,
               c.full_name, c.phone, c.address
        FROM design.factures f
        JOIN design.clients c ON f.client_id = c.id
        WHERE f.id = @id
      """, substitutionValues: {'id': fid});

      if (fRow.isEmpty) {
        return Response.notFound(jsonEncode({'error': 'Facture not found'}),
            headers: {'Content-Type': 'application/json'});
      }

      final f = fRow.first;

      final payRows = await db.query("""
        SELECT amount_paid, payment_date
        FROM design.facture_payments
        WHERE facture_id = @id
        ORDER BY payment_date
      """, substitutionValues: {'id': fid});

      final payments = payRows
          .map((r) => {
                'amount_paid': _parseNum(r[0]),
                'payment_date': r[1].toString(),
              })
          .toList();

      // === items: NO more 'color' column ===
      final itemRows = await db.query("""
        SELECT fi.id, fi.model_id, m.model_name,
               fi.quantity, fi.unit_price
        FROM design.facture_items fi
        JOIN design.models m ON fi.model_id = m.id
        WHERE fi.facture_id = @id
      """, substitutionValues: {'id': fid});

      final items = itemRows.map((r) {
        final qty  = _parseInt(r[3]);
        final unit = _parseNum(r[4]);
        return {
          'id'         : r[0],
          'model_id'   : r[1],
          'model_name' : r[2],
          'quantity'   : qty,
          'unit_price' : unit,
          'line_total' : qty * unit,
        };
      }).toList();

      final paidOnCreate = _parseNum(f[3]);
      final extraPaid    = payments.fold<double>(0.0, (s, p) => s + _parseNum(p['amount_paid']));
      final totalPaid    = paidOnCreate + extraPaid;
      final totalAmount  = _parseNum(f[2]);
      final remaining    = totalAmount - totalPaid;

      final data = {
        'id'                     : f[0],
        'facture_date'           : f[1].toString(),
        'total_amount'           : totalAmount,
        'amount_paid_on_creation': paidOnCreate,
        'client_name'            : f[4],
        'client_phone'           : f[5],
        'client_address'         : f[6],
        'payments'               : payments,
        'total_paid'             : totalPaid,
        'remaining_amount'       : remaining,
        'items'                  : items,
      };

      return _okJson(data);
    } catch (e, st) {
      print('facture detail error: $e\n$st');
      return _errJson({'error': 'Failed to fetch facture details', 'details': e.toString()});
    }
  });

  // ======================== MODELS (for sidebar) ========================
  router.get('/models', (Request req) async {
    try {
      final rows = await db.query("""
        SELECT 
          m.id,
          m.model_name,
          COALESCE(SUM(pi.quantity), 0) AS qty,
          m.price
        FROM design.models m
        LEFT JOIN design.product_inventory pi 
          ON pi.model_id = m.id
        LEFT JOIN design.warehouses w 
          ON pi.warehouse_id = w.id AND w.type = 'ready'
        GROUP BY m.id
        ORDER BY m.model_name
      """);

      final list = rows.map((r) => {
            'id'                : _parseInt(r[0]),
            'name'              : r[1] as String,
            'available_quantity': _parseInt(r[2]),
            'price'             : _parseNum(r[3]),
          }).toList();

      return _okJson(list);
    } catch (e, st) {
      print('models error: $e\n$st');
      return _errJson({'error': 'Failed to fetch models', 'details': e.toString()});
    }
  });

  // ======================== CLIENTS (for sidebar) ========================
  router.get('/clients', (Request req) async {
    try {
      final rows = await db.query("""
        SELECT id, full_name, phone, address
        FROM design.clients
        ORDER BY full_name
      """);

      final list = rows
          .map((r) => {
                'id'       : _parseInt(r[0]),
                'full_name': r[1] as String,
                'phone'    : r[2] as String?,
                'address'  : r[3] as String?,
              })
          .toList();

      return _okJson(list);
    } catch (e, st) {
      print('clients error: $e\n$st');
      return _errJson({'error': 'Failed to fetch clients', 'details': e.toString()});
    }
  });

  // ======================== CREATE FACTURE + FIFO DEDUCTION ========================
  router.post('/factures', (Request req) async {
    try {
      final payload = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final int clientId           = _parseInt(payload['client_id']);
      final double totalAmount     = _parseNum(payload['total_amount']);
      final double paidOnCreation  = _parseNum(payload['amount_paid_on_creation']);
      final List<dynamic> items    = payload['items'] as List<dynamic>;
      final String? dateStr        = payload['facture_date'] as String?;
      final DateTime factureDate   = dateStr != null
          ? DateTime.parse(dateStr)
          : DateTime.now();

      return await db.transaction((txn) async {
        // 1) Check stock (no color)
        for (final it in items) {
          final modelId = _parseInt(it['model_id']);
          final int reqQty = _parseInt(it['quantity']);

          final stockRes = await txn.query("""
            SELECT COALESCE(SUM(pi.quantity), 0)
            FROM design.product_inventory pi
            JOIN design.warehouses w 
              ON pi.warehouse_id = w.id AND w.type = 'ready'
            WHERE pi.model_id = @mid
          """, substitutionValues: {'mid': modelId});

          final available = _parseNum(stockRes.first[0]);
          if (available < reqQty) {
            return _errJson({
              'error':
                  'Not enough stock for model $modelId. Available: $available, requested: $reqQty'
            }, code: 400);
          }
        }

        // 2) Insert facture
        final ins = await txn.query("""
          INSERT INTO design.factures
            (client_id, facture_name, total_amount, amount_paid_on_creation, facture_date)
          VALUES (@cid, @fname, @total, @paid, @date)
          RETURNING id
        """, substitutionValues: {
          'cid'  : clientId,
          'fname': 'فاتورة',
          'total': totalAmount,
          'paid' : paidOnCreation,
          'date' : factureDate,
        });

        final fid = ins.first[0] as int;

        // 3) Insert items & FIFO
        for (final it in items) {
          final modelId  = _parseInt(it['model_id']);
          int remaining   = _parseInt(it['quantity']);
          final double unit = _parseNum(it['unit_price']);

          // insert item (no color)
          await txn.query("""
            INSERT INTO design.facture_items
              (facture_id, model_id, quantity, unit_price)
            VALUES (@fid, @mid, @qty, @unit)
          """, substitutionValues: {
            'fid'  : fid,
            'mid'  : modelId,
            'qty'  : remaining,
            'unit' : unit,
          });

          // FIFO deduction (no color)
          final invRows = await txn.query("""
            SELECT pi.id, pi.quantity
            FROM design.product_inventory pi
            JOIN design.warehouses w 
              ON pi.warehouse_id = w.id AND w.type = 'ready'
            WHERE pi.model_id = @mid
              AND pi.quantity > 0
            ORDER BY pi.last_updated ASC, pi.id ASC
          """, substitutionValues: {'mid': modelId});

          for (final inv in invRows) {
            if (remaining <= 0) break;
            final recId   = _parseInt(inv[0]);
            final recQty  = _parseNum(inv[1]);
            final deduct  = remaining > recQty ? recQty : remaining.toDouble();

            await txn.query("""
              UPDATE design.product_inventory
              SET quantity = quantity - @ded, last_updated = NOW()
              WHERE id = @id
            """, substitutionValues: {'id': recId, 'ded': deduct});

            remaining -= deduct.toInt();
          }
        }

        return Response(201,
            body: jsonEncode({'id': fid}),
            headers: {'Content-Type': 'application/json'});
      });
    } catch (e, st) {
      print('create facture error: $e\n$st');
      return _errJson({'error': 'Failed to create facture', 'details': e.toString()});
    }
  });

  // ======================== PAY FACTURE ========================
  router.post('/factures/<id|[0-9]+>/pay', (Request req, String id) async {
    try {
      final payload = jsonDecode(await req.readAsString());
      final amount  = _parseNum(payload['amount']);
      if (amount <= 0) {
        return _errJson({'error': 'Amount must be positive'}, code: 400);
      }
      final fid = int.parse(id);

      final unpaidRow = await db.query("""
        SELECT total_amount - COALESCE(amount_paid_on_creation,0) -
               COALESCE((SELECT SUM(amount_paid) FROM design.facture_payments WHERE facture_id = @fid),0)
        FROM design.factures
        WHERE id = @fid
      """, substitutionValues: {'fid': fid});

      if (unpaidRow.isEmpty) {
        return _errJson({'error': 'Facture not found'}, code: 404);
      }

      final unpaid = _parseNum(unpaidRow.first[0]);
      if (unpaid <= 0) {
        return _errJson({'error': 'No unpaid amount left for this facture'}, code: 400);
      }
      if (amount > unpaid) {
        return _errJson({'error': 'Cannot pay more than remaining', 'remaining': unpaid}, code: 400);
      }

      await db.query("""
        INSERT INTO design.facture_payments (facture_id, amount_paid, payment_date)
        VALUES (@fid, @amount, CURRENT_DATE)
      """, substitutionValues: {'fid': fid, 'amount': amount});

      return _okJson({'status': 'success', 'facture_id': fid, 'paid': amount});
    } catch (e, st) {
      print('pay facture error: $e\n$st');
      return _errJson({'error': 'Payment failed', 'details': e.toString()});
    }
  });

  // ======================== DELETE FACTURE ========================
  router.delete('/factures/<id|[0-9]+>', (Request req, String id) async {
    try {
      final fid = int.parse(id);
      await db.query('DELETE FROM design.factures WHERE id = @id',
          substitutionValues: {'id': fid});
      return _okJson({'deleted': fid});
    } catch (e, st) {
      print('delete facture error: $e\n$st');
      return _errJson({'error': 'Failed to delete facture', 'details': e.toString()});
    }
  });

  // ======================== CLIENT FACTURES (expanded) ========================
  router.get('/clients/<id|[0-9]+>/factures', (Request req, String id) async {
    try {
      final cid = int.parse(id);
      final factRows = await db.query("""
        SELECT f.id, f.facture_date, f.total_amount, f.amount_paid_on_creation,
               COALESCE(SUM(fp.amount_paid), 0) AS payments,
               (f.total_amount - f.amount_paid_on_creation - COALESCE(SUM(fp.amount_paid), 0)) AS remaining
        FROM design.factures f
        LEFT JOIN design.facture_payments fp ON f.id = fp.facture_id
        WHERE f.client_id = @cid
        GROUP BY f.id
        ORDER BY f.facture_date DESC, f.id DESC
      """, substitutionValues: {'cid': cid});

      final result = <Map<String, dynamic>>[];

      for (final f in factRows) {
        // fetch items without color
        final itemRows = await db.query("""
          SELECT fi.id, fi.model_id, m.model_name, fi.quantity, fi.unit_price
          FROM design.facture_items fi
          JOIN design.models m ON fi.model_id = m.id
          WHERE fi.facture_id = @fid
        """, substitutionValues: {'fid': f[0]});

        final items = itemRows.map((r) {
          final qty = _parseInt(r[3]);
          final up  = _parseNum(r[4]);
          return {
            'id'          : r[0],
            'model_id'    : r[1],
            'model_name'  : r[2],
            'quantity'    : qty,
            'unit_price'  : up,
            'line_total'  : qty * up,
          };
        }).toList();

        result.add({
          'id'                     : f[0],
          'facture_date'           : f[1].toString(),
          'total_amount'           : _parseNum(f[2]),
          'amount_paid_on_creation': _parseNum(f[3]),
          'total_paid'             : _parseNum(f[3]) + _parseNum(f[4]),
          'remaining_amount'       : _parseNum(f[5]),
          'items'                  : items,
        });
      }

      return _okJson(result);
    } catch (e, st) {
      print('client factures error: $e\n$st');
      return _errJson({'error': 'Failed to fetch client factures', 'details': e.toString()});
    }
  });

  // ======================== CLIENT ACCOUNT / TRANSACTIONS ========================
  router.get('/clients/<id|[0-9]+>/transactions', (Request req, String id) async {
    try {
      final cid = int.parse(id);
      final start = req.url.queryParameters['start_date'];
      final end   = req.url.queryParameters['end_date'];

      String dateFilter = '';
      final params = <String, dynamic>{'cid': cid};

      if (start != null && end != null) {
        dateFilter = 'AND f.facture_date >= @start_date AND f.facture_date <= @end_date';
        params['start_date'] = start;
        params['end_date']   = end;
      }

      final factRows = await db.query("""
        SELECT f.id, f.facture_date, f.total_amount, f.amount_paid_on_creation,
               COALESCE(SUM(fp.amount_paid), 0) AS payments
        FROM design.factures f
        LEFT JOIN design.facture_payments fp ON f.id = fp.facture_id
        WHERE f.client_id = @cid $dateFilter
        GROUP BY f.id
        ORDER BY f.facture_date DESC, f.id DESC
      """, substitutionValues: params);

      final payRows = await db.query("""
        SELECT fp.facture_id, fp.amount_paid, fp.payment_date
        FROM design.facture_payments fp
        JOIN design.factures f ON fp.facture_id = f.id
        WHERE f.client_id = @cid $dateFilter
      """, substitutionValues: params);

      final rows = <Map<String, dynamic>>[];

      for (final f in factRows) {
        rows.add({
          'date'      : f[1].toString(),
          'type'      : 'facture',
          'facture_id': f[0],
          'label'     : 'فاتورة',
          'amount'    : _parseNum(f[2]),
        });

        final pay0 = _parseNum(f[3]);
        if (pay0 > 0) {
          rows.add({
            'date'      : f[1].toString(),
            'type'      : 'pay_on_creation',
            'facture_id': f[0],
            'label'     : 'دفعة عند الإنشاء',
            'amount'    : -pay0,
          });
        }
      }

      for (final p in payRows) {
        rows.add({
          'date'      : p[2].toString(),
          'type'      : 'payment',
          'facture_id': p[0],
          'label'     : 'دفعة على الفاتورة',
          'amount'    : -_parseNum(p[1]),
        });
      }

      rows.sort((a, b) {
        final d1 = DateTime.parse(a['date']);
        final d2 = DateTime.parse(b['date']);
        return d1.compareTo(d2);
      });

      return _okJson(rows);
    } catch (e, st) {
      print('client transactions error: $e\n$st');
      return _errJson({'error': 'Failed to fetch client transactions', 'details': e.toString()});
    }
  });

  // ======================== MODEL BUYERS ========================
  router.get('/models/<id|[0-9]+>/clients', (Request req, String id) async {
    try {
      final mid = int.parse(id);
      final rows = await db.query("""
        SELECT c.id, c.full_name, c.phone, c.address,
               f.id AS facture_id, f.facture_date,
               fi.quantity, fi.unit_price
        FROM design.facture_items fi
        JOIN design.factures f ON fi.facture_id = f.id
        JOIN design.clients  c ON f.client_id  = c.id
        WHERE fi.model_id = @mid
        ORDER BY f.facture_date DESC, f.id DESC
      """, substitutionValues: {'mid': mid});

      final list = rows.map((r) => {
            'client_id'     : _parseInt(r[0]),
            'client_name'   : r[1],
            'client_phone'  : r[2],
            'client_address': r[3],
            'facture_id'    : _parseInt(r[4]),
            'facture_date'  : r[5].toString(),
            'quantity'      : _parseInt(r[6]),
            'unit_price'    : _parseNum(r[7]),
          }).toList();

      return _okJson(list);
    } catch (e, st) {
      print('model clients error: $e\n$st');
      return _errJson({'error': 'Failed to fetch model clients', 'details': e.toString()});
    }
  });

  // ======================== SEASONS ========================
  router.get('/seasons', (Request req) async {
    try {
      final rows = await db.query("""
        SELECT id, name, start_date, end_date
        FROM design.seasons
        ORDER BY start_date DESC
      """);

      final list = rows
          .map((r) => {
                'id'        : _parseInt(r[0]),
                'name'      : r[1] as String,
                'start_date': r[2].toString(),
                'end_date'  : r[3].toString(),
              })
          .toList();

      return _okJson(list);
    } catch (e, st) {
      print('seasons error: $e\n$st');
      return _errJson({'error': 'Failed to fetch seasons', 'details': e.toString()});
    }
  });

  // ======================== FILTER BY SEASON ========================
  router.get('/clients/by_season/<sid|[0-9]+>', (Request req, String sid) async {
    try {
      final rows = await db.query("""
        SELECT DISTINCT c.id, c.full_name, c.phone, c.address
        FROM design.factures f
        JOIN design.clients  c ON f.client_id = c.id
        JOIN design.seasons  s ON f.facture_date BETWEEN s.start_date AND s.end_date
        WHERE s.id = @sid
        ORDER BY c.full_name
      """, substitutionValues: {'sid': int.parse(sid)});

      final list = rows
          .map((r) => {
                'id'       : _parseInt(r[0]),
                'full_name': r[1] as String,
                'phone'    : r[2] as String?,
                'address'  : r[3] as String?,
              })
          .toList();

      return _okJson(list);
    } catch (e, st) {
      print('clients by season error: $e\n$st');
      return _errJson({'error': e.toString()});
    }
  });

  router.get('/models/by_season/<sid|[0-9]+>', (Request req, String sid) async {
    try {
      final rows = await db.query("""
        SELECT 
          m.id,
          m.model_name,
          m.price,
          COALESCE(SUM(pi.quantity),0) AS available_quantity
        FROM design.models m
        JOIN design.seasons s ON m.model_date BETWEEN s.start_date AND s.end_date
        LEFT JOIN design.product_inventory pi ON pi.model_id = m.id
        LEFT JOIN design.warehouses w ON pi.warehouse_id = w.id AND w.type = 'ready'
        WHERE s.id = @sid
        GROUP BY m.id
        ORDER BY m.model_name
      """, substitutionValues: {'sid': int.parse(sid)});

      final list = rows
          .map((r) => {
                'id'                : _parseInt(r[0]),
                'name'              : r[1] as String,
                'price'             : _parseNum(r[2]),
                'available_quantity': _parseInt(r[3]),
              })
          .toList();

      return _okJson(list);
    } catch (e, st) {
      print('models by season error: $e\n$st');
      return _errJson({'error': e.toString()});
    }
  });

  router.get('/factures/by_season/<sid|[0-9]+>', (Request req, String sid) async {
    try {
      final rows = await db.query("""
        SELECT f.id, f.client_id, c.full_name, f.facture_date, f.total_amount,
               COALESCE(SUM(fp.amount_paid), 0) AS total_paid
        FROM design.factures f
        JOIN design.clients c ON f.client_id = c.id
        JOIN design.seasons s ON f.facture_date BETWEEN s.start_date AND s.end_date
        LEFT JOIN design.facture_payments fp ON f.id = fp.facture_id
        WHERE s.id = @sid
        GROUP BY f.id, c.full_name
        ORDER BY f.id DESC
      """, substitutionValues: {'sid': int.parse(sid)});

      final list = rows.map((r) {
        final total = _parseNum(r[4]);
        final paid  = _parseNum(r[5]);
        return {
          'id'              : _parseInt(r[0]),
          'client_id'       : _parseInt(r[1]),
          'client_name'     : r[2],
          'facture_date'    : r[3].toString(),
          'total_amount'    : total,
          'total_paid'      : paid,
          'remaining_amount': total - paid,
        };
      }).toList();

      return _okJson(list);
    } catch (e, st) {
      print('factures by season error: $e\n$st');
      return _errJson({'error': 'Failed to fetch factures by season', 'details': e.toString()});
    }
  });

  // ======================== FACTURES SUMMARY ========================
  router.get('/factures/summary', (Request req) async {
    try {
      final rows = await db.query("""
        SELECT 
          COUNT(*)                             AS total_factures,
          COALESCE(SUM(f.total_amount), 0)     AS total_income,
          COALESCE(SUM(
            f.total_amount 
            - COALESCE(f.amount_paid_on_creation, 0)
            - COALESCE((SELECT SUM(fp.amount_paid)
                        FROM design.facture_payments fp
                        WHERE fp.facture_id = f.id), 0)
          ), 0) AS total_remaining
        FROM design.factures f
      """);

      final r = rows.first;
      final summary = {
        'total_factures' : _parseInt(r[0]),
        'total_income'   : _parseNum(r[1]),
        'total_remaining': _parseNum(r[2]),
      };

      return _okJson(summary);
    } catch (e, st) {
      print('summary error: $e\n$st');
      return _errJson({'error': 'Failed to fetch summary', 'details': e.toString()});
    }
  });

  return router;
}
