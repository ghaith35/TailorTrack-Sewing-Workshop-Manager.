import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:postgres/postgres.dart';

/// Helper to convert a dynamic value (num, String, or null) into a Dart double.
double _toDouble(dynamic v) {
  if (v == null) return 0.0;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0.0;
  throw FormatException('Cannot convert ${v.runtimeType} to double');
}
double parseNum(dynamic v) {
  if (v is String) {
    return double.tryParse(v) ?? 0.0;
  }
  if (v is num) return v.toDouble();
  return 0.0;
}

Router getDebtsRoutes(PostgreSQLConnection db) {
  final router = Router();

  // GET /debts/suppliers — list supplier debts, now including last purchase date
  router.get('/suppliers', (Request req) async {
    try {
      final rows = await db.query(r'''
        SELECT
          s.id                         AS supplier_id,
          s.full_name,
          s.company_name,
          COALESCE(tp.total_purchases, 0)        AS total_purchases,
          COALESCE(pd.on_creation_total, 0)      AS on_creation_total,
          COALESCE(pp.extra_payments_total, 0)   AS extra_payments_total,
          COALESCE(ad.last_date::text, '')       AS last_date
        FROM sewing.suppliers s

        LEFT JOIN (
          SELECT p.supplier_id, SUM(pi.quantity * pi.unit_price) AS total_purchases
          FROM sewing.purchases p
          JOIN sewing.purchase_items pi
            ON pi.purchase_id = p.id
          GROUP BY p.supplier_id
        ) tp ON tp.supplier_id = s.id

        LEFT JOIN (
          SELECT supplier_id, SUM(COALESCE(amount_paid_on_creation,0)) AS on_creation_total
          FROM sewing.purchases
          GROUP BY supplier_id
        ) pd ON pd.supplier_id = s.id

        LEFT JOIN (
          SELECT p.supplier_id, SUM(pp.amount_paid) AS extra_payments_total
          FROM sewing.purchase_payments pp
          JOIN sewing.purchases p
            ON pp.purchase_id = p.id
          GROUP BY p.supplier_id
        ) pp ON pp.supplier_id = s.id

        LEFT JOIN (
          SELECT supplier_id, MAX(purchase_date) AS last_date
          FROM sewing.purchases
          GROUP BY supplier_id
        ) ad ON ad.supplier_id = s.id

        ORDER BY s.id DESC;
      ''');

      final data = rows.map((r) {
        final purchases = _toDouble(r[3]);
        final onCreated  = _toDouble(r[4]);
        final extraPaid  = _toDouble(r[5]);
        return {
          'id'              : r[0] as int,
          'full_name'       : r[1] as String?,
          'company_name'    : r[2] as String?,
          'total_purchases' : purchases,
          'total_paid'      : onCreated + extraPaid,
          'debt'            : purchases - (onCreated + extraPaid),
          'date'            : r[6].toString(),
        };
      }).toList();

      return Response.ok(
        jsonEncode(data),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      print('Error in /debts/suppliers: $e');
      return Response.internalServerError(
        body: jsonEncode({
          'error': 'Failed to fetch supplier debts',
          'details': e.toString(),
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // POST /debts/suppliers/<id>/pay — apply a payment to oldest purchases
  router.post('/suppliers/<id>/pay', (Request req, String id) async {
    try {
      final payload = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final amount  = (payload['amount'] as num).toDouble();
      double remaining = amount;

      final purchases = await db.query(r'''
        SELECT
          p.id,
          COALESCE(p.amount_paid_on_creation, 0) AS amount_paid_on_creation,
          COALESCE(pi.total_amount, 0)            AS total_amount,
          COALESCE(pp.extra_paid, 0)              AS extra_paid
        FROM sewing.purchases p

        LEFT JOIN (
          SELECT purchase_id, SUM(quantity * unit_price) AS total_amount
          FROM sewing.purchase_items
          GROUP BY purchase_id
        ) pi
          ON pi.purchase_id = p.id

        LEFT JOIN (
          SELECT purchase_id, SUM(amount_paid) AS extra_paid
          FROM sewing.purchase_payments
          GROUP BY purchase_id
        ) pp
          ON pp.purchase_id = p.id

        WHERE p.supplier_id = @sid
        ORDER BY p.purchase_date, p.id;
      ''', substitutionValues: {'sid': int.parse(id)});

      for (final row in purchases) {
        final pid        = row[0] as int;
        final onCreation = _toDouble(row[1]);
        final total      = _toDouble(row[2]);
        final extraPaid  = _toDouble(row[3]);
        final due        = total - onCreation - extraPaid;
        if (due <= 0) continue;

        final pay = due >= remaining ? remaining : due;
        await db.query(r'''
          INSERT INTO sewing.purchase_payments
          (purchase_id, amount_paid, payment_date, notes)
          VALUES (@pid, @amt, NOW(), @notes);
        ''', substitutionValues: {
          'pid'   : pid,
          'amt'   : pay,
          'notes' : payload['notes'] as String? ?? '',
        });

        remaining -= pay;
        if (remaining <= 0) break;
      }

      return Response.ok(
        jsonEncode({
          'status'          : 'success',
          'amount_used'     : amount - remaining,
          'amount_remaining': remaining,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      print('Error in /debts/suppliers/<id>/pay: $e');
      return Response.internalServerError(
        body: jsonEncode({
          'error'  : 'Payment processing failed',
          'details': e.toString(),
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // GET /debts/clients — list client debts, now including last invoice date
  router.get('/clients', (Request req) async {
    try {
      final rows = await db.query(r'''
        SELECT
          c.id                               AS client_id,
          c.full_name,
          c.phone,
          c.address,
          COALESCE(ci.total_invoiced, 0)     AS total_invoiced,
          COALESCE(fc.on_creation_total, 0)  AS on_creation_total,
          COALESCE(fp.extra_payments_total, 0) AS extra_payments_total,
          COALESCE(ad.last_date::text, '')     AS last_date
        FROM sewing.clients c

        LEFT JOIN (
          SELECT client_id, SUM(total_amount) AS total_invoiced
          FROM sewing.factures
          GROUP BY client_id
        ) ci
          ON ci.client_id = c.id

        LEFT JOIN (
          SELECT client_id, SUM(COALESCE(amount_paid_on_creation,0)) AS on_creation_total
          FROM sewing.factures
          GROUP BY client_id
        ) fc
          ON fc.client_id = c.id

        LEFT JOIN (
          SELECT f.client_id, SUM(fp.amount_paid) AS extra_payments_total
          FROM sewing.facture_payments fp
          JOIN sewing.factures f ON fp.facture_id = f.id
          GROUP BY f.client_id
        ) fp
          ON fp.client_id = c.id

        LEFT JOIN (
          SELECT client_id, MAX(facture_date) AS last_date
          FROM sewing.factures
          GROUP BY client_id
        ) ad
          ON ad.client_id = c.id

        ORDER BY c.id DESC;
      ''');

      final data = rows.map((r) {
        final invoiced  = _toDouble(r[4]);
        final onCreated = _toDouble(r[5]);
        final extraPaid = _toDouble(r[6]);
        return {
          'id'             : r[0] as int,
          'full_name'      : r[1] as String?,
          'phone'          : r[2] as String?,
          'address'        : r[3] as String?,
          'total_invoiced' : invoiced,
          'total_paid'     : onCreated + extraPaid,
          'debt'           : invoiced - (onCreated + extraPaid),
          'date'           : r[7].toString(),
        };
      }).toList();

      return Response.ok(
        jsonEncode(data),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      print('Error in /debts/clients: $e');
      return Response.internalServerError(
        body: jsonEncode({
          'error'  : 'Failed to fetch client debts',
          'details': e.toString(),
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // POST /debts/clients/<id>/pay — apply a payment to oldest invoices
  router.post('/clients/<id>/pay', (Request req, String id) async {
  try {
    final payload = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    final amount = (payload['amount'] as num).toDouble();
    final fromDeposit = payload['from_deposit'] as bool? ?? false;
    double remaining = amount;

    // Validate deposit if used
    if (fromDeposit) {
      final depositRes = await db.query(
        'SELECT COALESCE(SUM(amount), 0) FROM sewing.deposits WHERE client_id = @cid AND used = FALSE',
        substitutionValues: {'cid': int.parse(id)},
      );
      final availableDeposit = parseNum(depositRes.first[0]);
      if (availableDeposit < amount) {
        return Response(400,
            body: jsonEncode({
              'error': 'Insufficient deposit',
              'available': availableDeposit,
              'requested': amount,
            }),
            headers: {'Content-Type': 'application/json'});
      }
    }

    final invoices = await db.query(r'''
      SELECT
        f.id,
        COALESCE(f.amount_paid_on_creation, 0) AS amount_paid_on_creation,
        COALESCE((SELECT SUM(amount_paid) FROM sewing.facture_payments WHERE facture_id = f.id), 0) AS extra_paid,
        f.total_amount
      FROM sewing.factures f
      WHERE f.client_id = @cid
      ORDER BY f.facture_date, f.id;
    ''', substitutionValues: {'cid': int.parse(id)});

    for (var r in invoices) {
      final fid = r[0] as int;
      final onCreation = parseNum(r[1]);
      final extraPaid = parseNum(r[2]);
      final totalAmt = parseNum(r[3]);
      final paidSoFar = onCreation + extraPaid;
      final unpaid = totalAmt - paidSoFar;
      if (unpaid <= 0) continue;

      final pay = unpaid >= remaining ? remaining : unpaid;
      await db.query(r'''
        INSERT INTO sewing.facture_payments
        (facture_id, amount_paid, payment_date, from_deposit)
        VALUES (@fid, @pay, CURRENT_DATE, @fromDeposit);
      ''', substitutionValues: {
        'fid': fid,
        'pay': pay,
        'fromDeposit': fromDeposit,
      });

      remaining -= pay;
      if (remaining <= 0) break;
    }

    // Mark deposit as used if applicable
    if (fromDeposit && (amount - remaining) > 0) {
      await db.query(
        'UPDATE sewing.deposits SET used = TRUE WHERE client_id = @cid AND used = FALSE LIMIT 1',
        substitutionValues: {'cid': int.parse(id)},
      );
    }

    return Response.ok(
      jsonEncode({
        'status': 'success',
        'amount_used': amount - remaining,
        'amount_remaining': remaining,
      }),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e) {
    print('Error in /clients/<id>/pay: $e');
    return Response.internalServerError(
      body: jsonEncode({
        'error': 'Payment processing failed',
        'details': e.toString(),
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }
});
  router.get('/clients/deposits', (Request req) async {
    try {
      final rows = await db.query(r'''
        SELECT p.id, p.client_id, c.full_name, p.value, p.amount, p.payment_date::text, p.notes
        FROM sewing.client_credit_payments p
        JOIN sewing.clients c ON c.id = p.client_id
        ORDER BY p.payment_date DESC;
      ''');
      final data = rows.map((r) => {
        'id': r[0] as int,
        'client_id': r[1] as int,
        'client_name': r[2] as String?,
        'value': _toDouble(r[3]),
        'amount': _toDouble(r[4]),
        'payment_date': r[5] as String,
        'notes': r[6] as String?,
      }).toList();
      return Response.ok(jsonEncode(data), headers: {'Content-Type':'application/json'});
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error':'Failed to fetch deposits','details':e.toString()}),
        headers: {'Content-Type':'application/json'},
      );
    }
  });

  router.post('/clients/clients/deposits', (Request req) async {
    return Response.notFound('Use /clients/deposits');
  });

  router.post('/clients/deposits', (Request req) async {
    try {
      final body = jsonDecode(await req.readAsString()) as Map<String,dynamic>;
      final cid = body['client_id'] as int;
      final amt = (body['amount'] as num).toDouble();
      final notes = body['notes'] as String?;
      final result = await db.query(r'''
        INSERT INTO sewing.client_credit_payments(client_id, amount, value, notes)
        VALUES (@cid, @amt, @amt, @notes)
        RETURNING id;
      ''', substitutionValues: {'cid':cid,'amt':amt,'notes':notes});
      return Response.ok(jsonEncode({'status':'success','id':result.first[0]}), headers: {'Content-Type':'application/json'});
    } catch(e) {
      return Response.internalServerError(
        body: jsonEncode({'error':'Failed to create deposit','details':e.toString()}),
        headers: {'Content-Type':'application/json'},
      );
    }
  });

  router.put('/clients/deposits/<id>', (Request req, String id) async {
    try {
      final body = jsonDecode(await req.readAsString()) as Map<String,dynamic>;
      final amt = (body['amount'] as num).toDouble();
      final notes = body['notes'] as String?;
      await db.query(r'''
        UPDATE sewing.client_credit_payments
        SET amount = @amt, notes = @notes
        WHERE id = @id;
      ''', substitutionValues:{'amt':amt,'notes':notes,'id':int.parse(id)});
      return Response.ok(jsonEncode({'status':'success'}), headers: {'Content-Type':'application/json'});
    } catch(e) {
      return Response.internalServerError(
        body: jsonEncode({'error':'Failed to edit deposit','details':e.toString()}),
        headers: {'Content-Type':'application/json'},
      );
    }
  });

  router.delete('/clients/deposits/<id>', (Request req, String id) async {
    try {
      await db.query(r'DELETE FROM sewing.client_credit_payments WHERE id = @id;', substitutionValues:{'id':int.parse(id)});
      return Response.ok(jsonEncode({'status':'success'}), headers: {'Content-Type':'application/json'});
    } catch(e) {
      return Response.internalServerError(
        body: jsonEncode({'error':'Failed to delete deposit','details':e.toString()}),
        headers: {'Content-Type':'application/json'},
      );
    }
  });
router.post('/clients/<id>/deposit/use', (Request req, String id) async {
  try {
    final bodyRaw = await req.readAsString();
    print('>>> /deposit/use body: $bodyRaw');
    final body = jsonDecode(bodyRaw) as Map<String, dynamic>;

    if (!body.containsKey('amount')) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Missing "amount" field'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    final requested = (body['amount'] as num).toDouble();
    final cid = int.parse(id);

    final rows = await db.query(r'''
      SELECT id, amount
      FROM sewing.client_credit_payments
      WHERE client_id = @cid AND amount > 0
      ORDER BY payment_date, id
    ''', substitutionValues: {'cid': cid});

    double totalAvail = rows.fold(0.0, (sum, r) => sum + _toDouble(r[1]));
    final toUse = requested <= totalAvail ? requested : totalAvail;
    double remainingToUse = toUse;

    for (final r in rows) {
      final depId = r[0] as int;
      final avail = _toDouble(r[1]);
      if (avail <= 0) continue;

      final useAmt = avail >= remainingToUse ? remainingToUse : avail;
      final newAmt = avail - useAmt;

      // Always update the amount, even if it's zero
      await db.query(r'''
        UPDATE sewing.client_credit_payments
          SET amount = @newAmt
        WHERE id = @depId
      ''', substitutionValues: {
        'newAmt': newAmt,
        'depId': depId,
      });

      remainingToUse -= useAmt;
      if (remainingToUse <= 0) break;
    }

    return Response.ok(
      jsonEncode({
        'status': 'success',
        'amount_requested': requested,
        'amount_used': toUse,
      }),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e, st) {
    print('Error in /clients/<id>/deposit/use: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Failed to use deposit', 'details': e.toString()}),
      headers: {'Content-Type': 'application/json'},
    );
  }
});

  return router;
}