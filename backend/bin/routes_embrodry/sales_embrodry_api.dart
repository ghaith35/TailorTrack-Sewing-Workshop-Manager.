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

Response _okJson(Object data) => Response.ok(
      jsonEncode(data),
      headers: {'Content-Type': 'application/json'},
    );

Response _errJson(Object data, {int code = 500}) => Response(
      code,
      body: jsonEncode(data),
      headers: {'Content-Type': 'application/json'},
    );

// ------------------------ Router ------------------------
Router getEmbroiderySalesRoutes(PostgreSQLConnection db) {
  final router = Router();

  // ======================== MODELS (for sidebar) ========================
 router.get('/models', (Request req) async {
    try {
      final rows = await db.query('''
        SELECT
          m.id,
          m.model_name,
          m.stitch_price,
          COALESCE(SUM(pi.quantity), 0) AS available_quantity,
          m.stitch_number,
          m.model_type,
          m.image_url
        FROM embroidery.models m
        LEFT JOIN embroidery.product_inventory pi
          ON pi.model_id = m.id
          AND pi.warehouse_id = (
            SELECT id FROM embroidery.warehouses WHERE type='ready' LIMIT 1
          )
        GROUP BY m.id, m.model_name, m.stitch_price, m.stitch_number, m.model_type, m.image_url
        ORDER BY m.model_name
      ''');

      final list = rows.map((r) => {
            'id': _parseInt(r[0]),
            'model_name': r[1] as String,
            'stitch_price': _parseNum(r[2]),
            'available_quantity': _parseInt(r[3]),
            'stitch_number': _parseInt(r[4]),
            'model_type': r[5] as String,
            'image_url': r[6] as String?,
          }).toList();

      return _okJson(list);
    } catch (e, st) {
      print('MODELS ERROR: $e\n$st');
      return _errJson({'error': 'Failed to fetch models', 'details': e.toString()});
    }
  });

  // ======================== CLIENTS (for sidebar) ========================
  router.get('/clients', (Request req) async {
    try {
      final rows = await db.query('''
        SELECT id, full_name, phone, address
        FROM embroidery.clients
        ORDER BY full_name
      ''');

      final list = rows.map((r) => {
            'id': _parseInt(r[0]),
            'full_name': r[1] as String,
            'phone': r[2] as String?,
            'address': r[3] as String?,
          }).toList();

      return _okJson(list);
    } catch (e, st) {
      print('CLIENTS ERROR: $e\n$st');
      return _errJson({'error': 'Failed to fetch clients', 'details': e.toString()});
    }
  });

  // ======================== FACTURES LIST ========================
 router.get('/factures', (Request req) async {
  try {
    final rows = await db.query('''
      SELECT f.id,
             f.client_id,
             c.full_name,
             f.facture_date,
             f.total_amount,
             f.amount_paid_on_creation,
             COALESCE(SUM(fp.amount_paid), 0) AS extra_paid
      FROM embroidery.factures f
      JOIN embroidery.clients c ON f.client_id = c.id
      LEFT JOIN embroidery.facture_payments fp ON f.id = fp.facture_id
      GROUP BY f.id, c.full_name
      ORDER BY f.id DESC
    ''');

    final list = rows.map((r) {
      final total       = _parseNum(r[4]);
      final paidOnInit  = _parseNum(r[5]);
      final extraPaid   = _parseNum(r[6]);
      final paid        = paidOnInit + extraPaid;
      return {
        'id': _parseInt(r[0]),
        'client_id': _parseInt(r[1]),
        'client_name': r[2],
        'facture_date': r[3].toString(),
        'total_amount': total,
        'total_paid': paid,
        'remaining_amount': total - paid,
      };
    }).toList();

    return _okJson(list);
  } catch (e, st) {
    print('FACTURES LIST ERROR: $e\n$st');
    return _errJson({'error': 'Failed to fetch factures', 'details': e.toString()});
  }
});

  // ======================== FACTURE DETAILS ========================
router.get('/factures/<fid|[0-9]+>', (Request req, String fid) async {
  try {
    final factureId = int.parse(fid);

    // Header
    final fRow = await db.query('''
      SELECT f.id, f.facture_date, f.total_amount, f.amount_paid_on_creation,
             c.full_name, c.phone, c.address
      FROM embroidery.factures f
      JOIN embroidery.clients c ON f.client_id = c.id
      WHERE f.id = @id
    ''', substitutionValues: {'id': factureId});
    if (fRow.isEmpty) {
      return Response.notFound(jsonEncode({'error': 'Not found'}),
          headers: {'Content-Type': 'application/json'});
    }
    final f = fRow.first;

    // Payments
    final payRows = await db.query('''
      SELECT amount_paid, payment_date
      FROM embroidery.facture_payments
      WHERE facture_id = @id
      ORDER BY payment_date
    ''', substitutionValues: {'id': factureId});
    final payments = payRows
        .map((r) => {
              'amount_paid': _parseNum(r[0]),
              'payment_date': r[1].toString(),
            })
        .toList();

    // Items
    final itemRows = await db.query('''
      SELECT fi.id, fi.model_id, m.model_name, fi.quantity, fi.unit_price,
             COALESCE(fi.color, '—'), m.stitch_number, m.model_type, m.image_url
      FROM embroidery.facture_items fi
      JOIN embroidery.models m ON fi.model_id = m.id
      WHERE fi.facture_id = @id
    ''', substitutionValues: {'id': factureId});
    final items = itemRows.map((r) {
      final qty = _parseInt(r[3]);
      final unit = _parseNum(r[4]);
      return {
        'id': _parseInt(r[0]),
        'model_id': _parseInt(r[1]),
        'model_name': r[2],
        'quantity': qty,
        'unit_price': unit,
        'color': r[5],
        'stitch_number': _parseInt(r[6]),
        'model_type': r[7],
        'image_url': r[8] as String?,
        'line_total': qty * unit,
      };
    }).toList();

    // Returns
    final returnRows = await db.query('''
      SELECT r.id, r.model_id, m.model_name, r.quantity, r.return_date,
             r.is_ready_to_sell, r.repair_cost, r.notes
      FROM embroidery.returns r
      JOIN embroidery.models m ON r.model_id = m.id
      WHERE r.facture_id = @id
      ORDER BY r.return_date DESC
    ''', substitutionValues: {'id': factureId});
    final returns = returnRows.map((r) => {
          'id': _parseInt(r[0]),
          'model_id': _parseInt(r[1]),
          'model_name': r[2],
          'quantity': _parseInt(r[3]),
          'return_date': r[4].toString(),
          'is_ready_to_sell': r[5] as bool,
          'repair_cost': _parseNum(r[6]),
          'notes': r[7] ?? '',
        }).toList();

    final paidOnCreation = _parseNum(f[3]);
    final extraPaid =
        payments.fold<double>(0, (s, p) => s + _parseNum(p['amount_paid']));
    final totalPaid = paidOnCreation + extraPaid;
    final totalAmount = _parseNum(f[2]);
    final remaining = totalAmount - totalPaid;

    return _okJson({
      'id': f[0],
      'facture_date': f[1].toString(),
      'total_amount': totalAmount,
      'amount_paid_on_creation': paidOnCreation,
      'client_name': f[4],
      'client_phone': f[5],
      'client_address': f[6],
      'payments': payments,
      'total_paid': totalPaid,
      'remaining_amount': remaining,
      'items': items,
      'returns': returns,
    });
  } catch (e, st) {
    print('FACTURE DETAIL ERROR: $e\n$st');
    return _errJson({'error': 'Failed to fetch details', 'details': e.toString()});
  }
});

  // ======================== CREATE FACTURE + FIFO ========================
  router.post('/factures', (Request req) async {
    try {
      final payload =
          jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final clientId = _parseInt(payload['client_id']);
      final totalAmount = _parseNum(payload['total_amount']);
      final paidOnCreation = _parseNum(payload['amount_paid_on_creation']);
      final items = payload['items'] as List<dynamic>;
      final dateStr = payload['facture_date'] as String?;
      final factureDate =
          dateStr != null ? DateTime.parse(dateStr) : DateTime.now();

      return await db.transaction((txn) async {
        // 1) Check stock
        for (final it in items) {
          final mid = _parseInt(it['model_id']);
          final reqQty = _parseInt(it['quantity']);
          final stockRes = await txn.query('''
            SELECT COALESCE(SUM(pi.quantity),0)
            FROM embroidery.product_inventory pi
            JOIN embroidery.warehouses w
              ON pi.warehouse_id=w.id AND w.type='ready'
            WHERE pi.model_id=@mid
          ''', substitutionValues: {'mid': mid});
          final avail = _parseNum(stockRes.first[0]);
          if (avail < reqQty) {
            return _errJson({
              'error':
                  'Insufficient stock for model $mid. Available: $avail, requested: $reqQty'
            }, code: 400);
          }
        }

        // 2) Insert facture
        final ins = await txn.query('''
          INSERT INTO embroidery.factures
            (client_id, total_amount, amount_paid_on_creation, facture_date)
          VALUES (@cid, @total, @paid, @date)
          RETURNING id
        ''', substitutionValues: {
          'cid': clientId,
          'total': totalAmount,
          'paid': paidOnCreation,
          'date': factureDate,
        });
        final fid = ins.first[0] as int;

        // 3) Insert items using model's stitch_price + FIFO deduction
        for (final it in items) {
          final mid = _parseInt(it['model_id']);
          int remaining = _parseInt(it['quantity']);

          // Fetch the model's stitch_price
          final priceRow = await txn.query('''
            SELECT stitch_price FROM embroidery.models WHERE id=@mid
          ''', substitutionValues: {'mid': mid});
          final unitPrice = _parseNum(priceRow.first[0]);

          // Insert with server-determined price
          await txn.query('''
            INSERT INTO embroidery.facture_items
              (facture_id, model_id, quantity, unit_price)
            VALUES (@fid, @mid, @qty, @unit)
          ''', substitutionValues: {
            'fid': fid,
            'mid': mid,
            'qty': remaining,
            'unit': unitPrice,
          });

          // FIFO deduction loop
          final invRows = await txn.query('''
            SELECT pi.id, pi.quantity
            FROM embroidery.product_inventory pi
            JOIN embroidery.warehouses w
              ON pi.warehouse_id=w.id AND w.type='ready'
            WHERE pi.model_id=@mid AND pi.quantity>0
            ORDER BY pi.last_updated ASC, pi.id ASC
          ''', substitutionValues: {'mid': mid});

          for (final inv in invRows) {
            if (remaining <= 0) break;
            final recId = _parseInt(inv[0]);
            final recQty = _parseNum(inv[1]);
            final deduct = remaining > recQty ? recQty : remaining.toDouble();

            await txn.query('''
              UPDATE embroidery.product_inventory
              SET quantity=quantity-@ded, last_updated=NOW()
              WHERE id=@id
            ''', substitutionValues: {
              'id': recId,
              'ded': deduct,
            });

            remaining -= deduct.toInt();
          }
        }

        return Response(201,
            body: jsonEncode({'id': fid}),
            headers: {'Content-Type': 'application/json'});
      });
    } catch (e, st) {
      print('CREATE FACTURE ERROR: $e\n$st');
      return _errJson({'error': 'Create failed', 'details': e.toString()});
    }
  });

  // ======================== PAY FACTURE ========================
  router.post('/factures/<fid|[0-9]+>/pay', (Request req, String fid) async {
    try {
      final amount = _parseNum(
          (jsonDecode(await req.readAsString()) as Map)['amount']);
      if (amount <= 0) {
        return _errJson({'error': 'Amount must be positive'}, code: 400);
      }
      final factureId = int.parse(fid);
      final unpaidRow = await db.query('''
        SELECT total_amount - amount_paid_on_creation
          - COALESCE((SELECT SUM(amount_paid)
                      FROM embroidery.facture_payments
                      WHERE facture_id=@fid),0)
        FROM embroidery.factures
        WHERE id=@fid
      ''',substitutionValues: {'fid': factureId});
      if (unpaidRow.isEmpty) {
        return _errJson({'error': 'Not found'}, code: 404);
      }
      final unpaid = _parseNum(unpaidRow.first[0]);
      if (amount > unpaid) {
        return _errJson(
            {'error': 'Cannot pay more than remaining', 'remaining': unpaid},
            code: 400);
      }
      await db.query('''
        INSERT INTO embroidery.facture_payments
          (facture_id, amount_paid, payment_date)
        VALUES (@fid, @amt, CURRENT_DATE)
      ''', substitutionValues: {'fid': factureId, 'amt': amount});
      return _okJson({'status': 'success', 'facture_id': factureId, 'paid': amount});
    } catch (e, st) {
      print('PAY ERROR: $e\n$st');
      return _errJson({'error': 'Payment failed', 'details': e.toString()});
    }
  });

  // ======================== DELETE FACTURE ========================
// ======================== DELETE FACTURE (with inventory restore) ========================
router.delete('/factures/<fid|[0-9]+>', (Request req, String fid) async {
  try {
    final factureId = int.parse(fid);

    return await db.transaction((txn) async {
      // 1) Fetch all items on this facture
      final itemRows = await txn.query(
        '''
        SELECT model_id, quantity
        FROM embroidery.facture_items
        WHERE facture_id = @fid
        ''',
        substitutionValues: {'fid': factureId},
      );

      // 2) Look up the "ready" warehouse ID
      final whRow = await txn.query(
        '''
        SELECT id FROM embroidery.warehouses
        WHERE type = 'ready'
        LIMIT 1
        '''
      );
      final readyWid = whRow.first[0] as int;

      // 3) For each item, add its quantity back into product_inventory
      for (final row in itemRows) {
        final mid = _parseInt(row[0]);
        final qty = _parseNum(row[1]);

        // Try to update an existing inventory record
        final updateResult = await txn.query(
          '''
          UPDATE embroidery.product_inventory
          SET quantity = quantity + @qty,
              last_updated = NOW()
          WHERE model_id = @mid
            AND warehouse_id = @wid
          ''',
          substitutionValues: {
            'qty': qty,
            'mid': mid,
            'wid': readyWid,
          },
        );

        // If no row was updated, insert a new one
        if (updateResult.affectedRowCount == 0) {
          await txn.query(
            '''
            INSERT INTO embroidery.product_inventory
              (warehouse_id, model_id, quantity)
            VALUES
              (@wid, @mid, @qty)
            ''',
            substitutionValues: {
              'wid': readyWid,
              'mid': mid,
              'qty': qty,
            },
          );
        }
      }

      // 4) Delete the facture (assumes cascade delete on items/payments)
      await txn.query(
        '''
        DELETE FROM embroidery.factures
        WHERE id = @fid
        ''',
        substitutionValues: {'fid': factureId},
      );

      return _okJson({'deleted': factureId});
    });
  } catch (e, st) {
    print('DELETE FACTURE ERROR: $e\n$st');
    return _errJson(
      {'error': 'Delete failed', 'details': e.toString()},
      code: 500,
    );
  }
});


  // ======================== CLIENT FACTURES ========================
  router.get('/clients/<cid|[0-9]+>/factures', (Request req, String cid) async {
  try {
    final clientId = int.parse(cid);
    final factRows = await db.query('''
      SELECT f.id, f.facture_date, f.total_amount, f.amount_paid_on_creation,
             COALESCE(SUM(fp.amount_paid),0) AS paid,
             (f.total_amount - f.amount_paid_on_creation 
              - COALESCE(SUM(fp.amount_paid),0)) AS remaining
      FROM embroidery.factures f
      LEFT JOIN embroidery.facture_payments fp
        ON f.id=fp.facture_id
      WHERE f.client_id=@cid
      GROUP BY f.id
      ORDER BY f.facture_date DESC, f.id DESC
    ''', substitutionValues: {'cid': clientId});

    final result = <Map<String, dynamic>>[];

    for (final f in factRows) {
      final items = await db.query('''
        SELECT fi.id, fi.model_id, m.model_name, fi.quantity, fi.unit_price,
               COALESCE(fi.color, '—'), m.stitch_number, m.model_type, m.image_url
        FROM embroidery.facture_items fi
        JOIN embroidery.models m ON fi.model_id=m.id
        WHERE fi.facture_id=@fid
      ''', substitutionValues: {'fid': f[0]});

      final itemList = items.map((r) {
        final qty = _parseInt(r[3]);
        final up = _parseNum(r[4]);
        return {
          'id': _parseInt(r[0]),
          'model_id': _parseInt(r[1]),
          'model_name': r[2],
          'quantity': qty,
          'unit_price': up,
          'color': r[5],
          'stitch_number': _parseInt(r[6]),
          'model_type': r[7],
          'image_url': r[8] as String?,
          'line_total': qty * up,
        };
      }).toList();

      final returnRows = await db.query('''
        SELECT r.id, r.model_id, m.model_name, r.quantity, r.return_date,
               r.is_ready_to_sell, r.repair_cost, r.notes
        FROM embroidery.returns r
        JOIN embroidery.models m ON r.model_id = m.id
        WHERE r.facture_id = @fid
        ORDER BY r.return_date DESC
      ''', substitutionValues: {'fid': f[0]});

      final returns = returnRows.map((r) => {
            'id': _parseInt(r[0]),
            'model_id': _parseInt(r[1]),
            'model_name': r[2],
            'quantity': _parseInt(r[3]),
            'return_date': r[4].toString(),
            'is_ready_to_sell': r[5] as bool,
            'repair_cost': _parseNum(r[6]),
            'notes': r[7] ?? '',
          }).toList();

      result.add({
        'id': f[0],
        'facture_date': f[1].toString(),
        'total_amount': _parseNum(f[2]),
        'amount_paid_on_creation': _parseNum(f[3]),
        'total_paid': _parseNum(f[3]) + _parseNum(f[4]),
        'remaining_amount': _parseNum(f[5]),
        'items': itemList,
        'returns': returns,
      });
    }

    return _okJson(result);
  } catch (e, st) {
    print('CLIENT FACTURES ERROR: $e\n$st');
    return _errJson({'error': 'Failed to fetch client factures', 'details': e.toString()});
  }
});

  // ======================== CLIENT TRANSACTIONS (with date filter) ========================
  router.get('/clients/<cid|[0-9]+>/transactions', (Request req, String cid) async {
  try {
    final clientId = int.parse(cid);

    final start = req.url.queryParameters['start_date'];
    final end   = req.url.queryParameters['end_date'];

    // Build two filters: one for factures (by facture_date)
    // and one for payments (by payment_date)
    final factureFilter = StringBuffer();
    final paymentFilter = StringBuffer();
    final params = <String, dynamic>{'cid': clientId};

    if (start != null && end != null) {
      factureFilter.write(' AND f.facture_date >= @start_date AND f.facture_date <= @end_date ');
      paymentFilter.write(' AND fp.payment_date >= @start_date AND fp.payment_date <= @end_date ');
      params['start_date'] = start;
      params['end_date']   = end;
    }

    // 1) Facture rows (positive amounts) + on-creation payments (negative)
    final factRows = await db.query('''
      SELECT f.id, f.facture_date, f.total_amount, f.amount_paid_on_creation
      FROM embroidery.factures f
      WHERE f.client_id=@cid ${factureFilter.toString()}
      ORDER BY f.facture_date DESC, f.id DESC
    ''', substitutionValues: params);

    // 2) Extra payments (negative amounts)
    final payRows = await db.query('''
      SELECT fp.facture_id, fp.amount_paid, fp.payment_date
      FROM embroidery.facture_payments fp
      JOIN embroidery.factures f ON f.id = fp.facture_id
      WHERE f.client_id=@cid ${paymentFilter.toString()}
      ORDER BY fp.payment_date ASC, fp.id ASC
    ''', substitutionValues: params);

    final rows = <Map<String, dynamic>>[];

    // Invoices (positive) and on-creation payment (negative)
    for (final f in factRows) {
      final fid  = _parseInt(f[0]);
      final fdt  = f[1].toString();
      final tot  = _parseNum(f[2]);
      final aoc  = _parseNum(f[3]);

      rows.add({
        'date': fdt,
        'type': 'facture',
        'facture_id': fid,
        'label': 'فاتورة',
        'amount': tot, // positive
      });

      if (aoc > 0) {
        rows.add({
          'date': fdt,
          'type': 'pay_on_creation',
          'facture_id': fid,
          'label': 'دفعة عند الإنشاء',
          'amount': -aoc, // negative
        });
      }
    }

    // Extra payments (negative)
    for (final p in payRows) {
      rows.add({
        'date': p[2].toString(),
        'type': 'payment',
        'facture_id': _parseInt(p[0]),
        'label': 'دفعة',
        'amount': -_parseNum(p[1]),
      });
    }

    // Oldest first
    rows.sort((a, b) {
      final d1 = DateTime.parse(a['date']);
      final d2 = DateTime.parse(b['date']);
      return d1.compareTo(d2);
    });

    return _okJson(rows);
  } catch (e, st) {
    print('TRANSACTIONS ERROR: $e\n$st');
    return _errJson({'error': 'Failed to fetch transactions', 'details': e.toString()});
  }
});

  // ======================== MODEL BUYERS ========================
  router.get('/models/<mid|[0-9]+>/clients', (Request req, String mid) async {
    try {
      final modelId = int.parse(mid);
      final rows = await db.query('''
        SELECT c.id, c.full_name, c.phone, c.address,
               f.id AS facture_id, f.facture_date,
               fi.quantity, fi.unit_price,
               m.model_type, m.stitch_number
        FROM embroidery.facture_items fi
        JOIN embroidery.factures f ON fi.facture_id=f.id
        JOIN embroidery.clients c ON f.client_id=c.id
        JOIN embroidery.models m ON fi.model_id = m.id
        WHERE fi.model_id=@mid
        ORDER BY f.facture_date DESC, f.id DESC
      ''', substitutionValues: {'mid': modelId});

      final list = rows.map((r) => {
            'client_id': _parseInt(r[0]),
            'client_name': r[1],
            'client_phone': r[2],
            'client_address': r[3],
            'facture_id': _parseInt(r[4]),
            'facture_date': r[5].toString(),
            'quantity': _parseInt(r[6]),
            'unit_price': _parseNum(r[7]),
            'model_type': r[8],
            'stitch_number': _parseInt(r[9]),
          }).toList();

      return _okJson(list);
    } catch (e, st) {
      print('MODEL BUYERS ERROR: $e\n$st');
      return _errJson({'error': 'Failed to fetch model buyers', 'details': e.toString()});
    }
  });

  // ======================== SEASONS ========================
  router.get('/seasons', (Request req) async {
    try {
      final rows = await db.query('''
        SELECT id, name, start_date, end_date
        FROM embroidery.seasons
        ORDER BY start_date DESC
      ''');

      final list = rows.map((r) => {
            'id': _parseInt(r[0]),
            'name': r[1] as String,
            'start_date': r[2].toString(),
            'end_date': r[3].toString(),
          }).toList();

      return _okJson(list);
    } catch (e, st) {
      print('SEASONS ERROR: $e\n$st');
      return _errJson({'error': 'Failed to fetch seasons', 'details': e.toString()});
    }
  });

  // ======================== FILTERED ROUTES BY SEASON ========================
  router.get('/clients/by_season/<sid|[0-9]+>', (Request req, String sid) async {
    try {
      final seasonId = int.parse(sid);
      final rows = await db.query('''
        SELECT DISTINCT c.id, c.full_name, c.phone, c.address
        FROM embroidery.factures f
        JOIN embroidery.clients c ON f.client_id=c.id
        JOIN embroidery.seasons s
          ON f.facture_date BETWEEN s.start_date AND s.end_date
        WHERE s.id=@sid
        ORDER BY c.full_name
      ''', substitutionValues: {'sid': seasonId});

      final list = rows.map((r) => {
            'id': _parseInt(r[0]),
            'full_name': r[1] as String,
            'phone': r[2] as String?,
            'address': r[3] as String?,
          }).toList();

      return _okJson(list);
    } catch (e, st) {
      print('CLIENTS BY SEASON ERROR: $e\n$st');
      return _errJson({'error': 'Failed to fetch', 'details': e.toString()});
    }
  });
  // ======================== SEARCH MODELS ========================
  router.get('/models/search', (Request req) async {
    final q = (req.url.queryParameters['q'] ?? '').toLowerCase();
    final sid = req.url.queryParameters['season_id'];
    final sql = StringBuffer('''
      SELECT
        m.id,
        m.model_name,
        m.stitch_price,
        COALESCE(SUM(pi.quantity),0) AS available_quantity,
        m.stitch_number,
        m.model_type
      FROM embroidery.models m
      LEFT JOIN embroidery.product_inventory pi
        ON pi.model_id = m.id
        AND pi.warehouse_id = (
          SELECT id FROM embroidery.warehouses WHERE type='ready' LIMIT 1
        )
    ''');
    final subs = <String, dynamic>{};
    if (sid != null) {
      sql.write(' JOIN embroidery.seasons s ON m.model_date BETWEEN s.start_date AND s.end_date');
      sql.write(' WHERE s.id = @sid AND LOWER(m.model_name) LIKE @q');
      subs['sid'] = int.parse(sid);
      subs['q'] = '%$q%';
    } else {
      sql.write(' WHERE LOWER(m.model_name) LIKE @q');
      subs['q'] = '%$q%';
    }
    sql.write(' GROUP BY m.id ORDER BY m.model_name');
    try {
      final rows = await db.query(sql.toString(), substitutionValues: subs);
      final out = rows.map((r) => {
        'id': _parseInt(r[0]),
        'model_name': r[1],
        'stitch_price': _parseNum(r[2]),
        'available_quantity': _parseInt(r[3]),
        'stitch_number': _parseInt(r[4]),
        'model_type': r[5],
      }).toList();
      return _okJson(out);
    } catch (e, st) {
      print('MODEL SEARCH ERROR: $e\n$st');
      return _errJson({'error': 'Model search failed', 'details': e.toString()});
    }
  });

  // ======================== SEARCH CLIENTS ========================
  router.get('/clients/search', (Request req) async {
    final q = (req.url.queryParameters['q'] ?? '').toLowerCase();
    try {
      final rows = await db.query('''
        SELECT id, full_name, phone, address
        FROM embroidery.clients
        WHERE LOWER(full_name) LIKE @q
        ORDER BY full_name
      ''', substitutionValues: {'q': '%$q%'});
      final out = rows.map((r) => {
        'id': _parseInt(r[0]),
        'full_name': r[1],
        'phone': r[2],
        'address': r[3],
      }).toList();
      return _okJson(out);
    } catch (e, st) {
      print('CLIENT SEARCH ERROR: $e\n$st');
      return _errJson({'error': 'Client search failed', 'details': e.toString()});
    }
  });

  router.get('/models/by_season/<sid|[0-9]+>', (Request req, String sid) async {
  try {
    final seasonId = int.parse(sid);
    final rows = await db.query('''
      SELECT
        m.id,
        m.model_name,
        m.stitch_price,
        COALESCE(SUM(pi.quantity),0) AS available_quantity,
        m.image_url
      FROM embroidery.models m
      JOIN embroidery.seasons s
        ON m.model_date BETWEEN s.start_date AND s.end_date
      LEFT JOIN embroidery.product_inventory pi
        ON pi.model_id=m.id
        AND pi.warehouse_id=(
          SELECT id FROM embroidery.warehouses WHERE type='ready' LIMIT 1
        )
      WHERE s.id=@sid
      GROUP BY m.id, m.model_name, m.stitch_price, m.image_url
      ORDER BY m.model_name
    ''', substitutionValues: {'sid': seasonId});

    final list = rows.map((r) => {
          'id': _parseInt(r[0]),
          'model_name': r[1],
          'stitch_price': _parseNum(r[2]),
          'available_quantity': _parseInt(r[3]),
          'image_url': r[4] as String?,
        }).toList();

    return _okJson(list);
  } catch (e, st) {
    print('MODELS BY SEASON ERROR: $e\n$st');
    return _errJson({'error': e.toString()});
  }
});

  router.get('/factures/by_season/<sid|[0-9]+>', (Request req, String sid) async {
    try {
      final seasonId = int.parse(sid);
      final rows = await db.query('''
        SELECT f.id, f.client_id, c.full_name, f.facture_date, f.total_amount,
               COALESCE(SUM(fp.amount_paid),0) AS total_paid
        FROM embroidery.factures f
        JOIN embroidery.clients c ON f.client_id=c.id
        JOIN embroidery.seasons s
          ON f.facture_date BETWEEN s.start_date AND s.end_date
        LEFT JOIN embroidery.facture_payments fp
          ON f.id=fp.facture_id
        WHERE s.id=@sid
        GROUP BY f.id, c.full_name
        ORDER BY f.id DESC
      ''', substitutionValues: {'sid': seasonId});

      final list = rows.map((r) {
        final total = _parseNum(r[4]);
        final paid = _parseNum(r[5]);
        return {
          'id': _parseInt(r[0]),
          'client_id': _parseInt(r[1]),
          'client_name': r[2],
          'facture_date': r[3].toString(),
          'total_amount': total,
          'total_paid': paid,
          'remaining_amount': total - paid,
        };
      }).toList();

      return _okJson(list);
    } catch (e, st) {
      print('FACTURES BY SEASON ERROR: $e\n$st');
      return _errJson({'error': 'Failed to fetch', 'details': e.toString()});
    }
  });

  // ======================== FACTURES SUMMARY ========================
  router.get('/factures/summary', (Request req) async {
    try {
      final rows = await db.query('''
        SELECT
          COUNT(*)         AS total_factures,
          COALESCE(SUM(total_amount),0) AS total_income,
          COALESCE(SUM(
            total_amount - amount_paid_on_creation
            - COALESCE((SELECT SUM(amount_paid)
                        FROM embroidery.facture_payments
                        WHERE facture_id=f.id),0)
          ),0) AS total_remaining
        FROM embroidery.factures f
      ''');

      final r = rows.first;
      return _okJson({
        'total_factures': _parseInt(r[0]),
        'total_income': _parseNum(r[1]),
        'total_remaining': _parseNum(r[2]),
      });
    } catch (e, st) {
      print('SUMMARY ERROR: $e\n$st');
      return _errJson({'error': 'Failed to fetch summary', 'details': e.toString()});
    }
  });

  return router;
}