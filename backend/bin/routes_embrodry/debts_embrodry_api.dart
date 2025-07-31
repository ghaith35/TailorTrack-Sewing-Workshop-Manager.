// bin/routes_embrodry/debts_embrodry_api.dart

import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:postgres/postgres.dart';

/// Convert a numeric/string/nullable to Dart double.
double _toDouble(dynamic v) {
  if (v == null) return 0.0;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0.0;
  throw FormatException('Cannot convert ${v.runtimeType} to double');
}

/// Convert a numeric/string/nullable to Dart int.
int _toInt(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  throw FormatException('Cannot convert ${v.runtimeType} to int');
}

Router getEmbrodryDebtsRoutes(PostgreSQLConnection db) {
  final router = Router();

  // ─── Supplier debts ───────────────────────

  // GET /suppliers
  router.get('/suppliers', (Request req) async {
    try {
      final rows = await db.query(r'''
        SELECT
          s.id                         AS supplier_id,
          s.full_name,
          s.company_name,
          COALESCE(tp.total_purchases, 0)      AS total_purchases,
          COALESCE(pd.on_creation_total, 0)    AS on_creation_total,
          COALESCE(pp.extra_payments_total, 0) AS extra_payments_total,
          COALESCE(ad.last_date::text, '')     AS last_date
        FROM embroidery.suppliers s

        LEFT JOIN (
          SELECT p.supplier_id, SUM(pi.quantity * pi.unit_price) AS total_purchases
          FROM embroidery.purchases p
          JOIN embroidery.purchase_items pi
            ON pi.purchase_id = p.id
          GROUP BY p.supplier_id
        ) tp ON tp.supplier_id = s.id

        LEFT JOIN (
          SELECT supplier_id, SUM(COALESCE(amount_paid_on_creation,0)) AS on_creation_total
          FROM embroidery.purchases
          GROUP BY supplier_id
        ) pd ON pd.supplier_id = s.id

        LEFT JOIN (
          SELECT p.supplier_id, SUM(pp.amount_paid) AS extra_payments_total
          FROM embroidery.purchase_payments pp
          JOIN embroidery.purchases p
            ON pp.purchase_id = p.id
          GROUP BY p.supplier_id
        ) pp ON pp.supplier_id = s.id

        LEFT JOIN (
          SELECT supplier_id, MAX(purchase_date) AS last_date
          FROM embroidery.purchases
          GROUP BY supplier_id
        ) ad ON ad.supplier_id = s.id

        ORDER BY s.id DESC;
      ''');

      final data = rows.map((r) {
        final totalPur = _toDouble(r[3]);
        final paidOnC = _toDouble(r[4]);
        final extra   = _toDouble(r[5]);
        return {
          'id'              : r[0] as int,
          'full_name'       : r[1] as String?,
          'company_name'    : r[2] as String?,
          'total_purchases' : totalPur,
          'total_paid'      : paidOnC + extra,
          'debt'            : totalPur - (paidOnC + extra),
          'date'            : r[6] as String,
        };
      }).toList();

      return Response.ok(jsonEncode(data),
          headers: {'Content-Type': 'application/json'});
    } catch (e, st) {
      print('Error in /embrodry/debts/suppliers: $e\n$st');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch supplier debts', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // POST /suppliers/<id>/pay
  router.post('/suppliers/<id|[0-9]+>/pay', (Request req, String id) async {
    try {
      final payload  = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final amount   = (payload['amount'] as num).toDouble();
      double remaining = amount;

      final purchases = await db.query(r'''
        SELECT
          p.id,
          COALESCE(p.amount_paid_on_creation, 0) AS amount_paid_on_creation,
          COALESCE(pi.total_amount, 0)           AS total_amount,
          COALESCE(pp.extra_paid, 0)             AS extra_paid
        FROM embroidery.purchases p

        LEFT JOIN (
          SELECT purchase_id, SUM(quantity * unit_price) AS total_amount
          FROM embroidery.purchase_items
          GROUP BY purchase_id
        ) pi ON pi.purchase_id = p.id

        LEFT JOIN (
          SELECT purchase_id, SUM(amount_paid) AS extra_paid
          FROM embroidery.purchase_payments
          GROUP BY purchase_id
        ) pp ON pp.purchase_id = p.id

        WHERE p.supplier_id = @sid
        ORDER BY p.purchase_date, p.id;
      ''', substitutionValues: {'sid': int.parse(id)});

      for (final row in purchases) {
        final pid        = row[0] as int;
        final onCreation = _toDouble(row[1]);
        final totalAmt   = _toDouble(row[2]);
        final extraPaid  = _toDouble(row[3]);
        final due        = totalAmt - onCreation - extraPaid;
        if (due <= 0) continue;

        final pay = due >= remaining ? remaining : due;
        await db.query(r'''
          INSERT INTO embroidery.purchase_payments
            (purchase_id, amount_paid, payment_date, notes)
          VALUES (@pid, @amt, CURRENT_DATE, @notes);
        ''', substitutionValues: {
          'pid'   : pid,
          'amt'   : pay,
          'notes' : payload['notes'] as String? ?? '',
        });

        remaining -= pay;
        if (remaining <= 0) break;
      }

      return Response.ok(jsonEncode({
        'status'          : 'success',
        'amount_used'     : amount - remaining,
        'amount_remaining': remaining,
      }), headers: {'Content-Type': 'application/json'});
    } catch (e, st) {
      print('Error in /embrodry/debts/suppliers/<id>/pay: $e\n$st');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Payment processing failed', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // ─── Client debts ─────────────────────────

  // GET /clients
  router.get('/clients', (Request req) async {
    try {
      final rows = await db.query(r'''
        SELECT
          c.id,
          c.full_name,
          c.phone,
          COALESCE(ci.total_invoiced, 0)         AS total_invoiced,
          COALESCE(fc.on_creation_total, 0)      AS on_creation_total,
          COALESCE(fp.extra_payments_total, 0)   AS extra_payments_total,
          COALESCE(ad.last_date::text, '')       AS last_date
        FROM embroidery.clients c

        LEFT JOIN (
          SELECT client_id, SUM(total_amount) AS total_invoiced
          FROM embroidery.factures
          GROUP BY client_id
        ) ci ON ci.client_id = c.id

        LEFT JOIN (
          SELECT client_id, SUM(COALESCE(amount_paid_on_creation,0)) AS on_creation_total
          FROM embroidery.factures
          GROUP BY client_id
        ) fc ON fc.client_id = c.id

        LEFT JOIN (
          SELECT f.client_id, SUM(fp.amount_paid) AS extra_payments_total
          FROM embroidery.facture_payments fp
          JOIN embroidery.factures f ON fp.facture_id = f.id
          GROUP BY f.client_id
        ) fp ON fp.client_id = c.id

        LEFT JOIN (
          SELECT client_id, MAX(facture_date) AS last_date
          FROM embroidery.factures
          GROUP BY client_id
        ) ad ON ad.client_id = c.id

        ORDER BY c.id DESC;
      ''');

      final data = rows.map((r) {
        final invoiced  = _toDouble(r[3]);
        final onCreated = _toDouble(r[4]);
        final extraPaid = _toDouble(r[5]);
        return {
          'id'              : r[0] as int,
          'full_name'       : r[1] as String?,
          'phone'           : r[2] as String?,
          'total_invoiced'  : invoiced,
          'total_paid'      : onCreated + extraPaid,
          'debt'            : invoiced - (onCreated + extraPaid),
          'date'            : r[6] as String,
        };
      }).toList();

      return Response.ok(jsonEncode(data),
          headers: {'Content-Type': 'application/json'});
    } catch (e, st) {
      print('Error in /embrodry/debts/clients: $e\n$st');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch client debts', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // POST /clients/<id>/pay
  router.post('/clients/<id|[0-9]+>/pay', (Request req, String id) async {
    try {
      final payload  = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final amount   = (payload['amount'] as num).toDouble();
      double remaining = amount;

      final invoices = await db.query(r'''
        SELECT
          f.id,
          COALESCE(f.amount_paid_on_creation, 0) AS amount_paid_on_creation,
          COALESCE((
            SELECT SUM(amount_paid)
            FROM embroidery.facture_payments
            WHERE facture_id = f.id
          ), 0)                                 AS extra_paid,
          f.total_amount
        FROM embroidery.factures f
        WHERE f.client_id = @cid
        ORDER BY f.facture_date, f.id;
      ''', substitutionValues: {'cid': int.parse(id)});

      for (final r in invoices) {
        final fid        = r[0] as int;
        final onCreation = _toDouble(r[1]);
        final extraPaid  = _toDouble(r[2]);
        final totalAmt   = _toDouble(r[3]);
        final due        = totalAmt - (onCreation + extraPaid);
        if (due <= 0) continue;

        final pay = due >= remaining ? remaining : due;
        await db.query(r'''
          INSERT INTO embroidery.facture_payments
            (facture_id, amount_paid, payment_date, method, notes)
          VALUES (@fid, @pay, CURRENT_DATE, @method, @notes);
        ''', substitutionValues: {
          'fid'    : fid,
          'pay'    : pay,
          'method' : payload['method'] as String? ?? '',
          'notes'  : payload['notes']  as String? ?? '',
        });

        remaining -= pay;
        if (remaining <= 0) break;
      }

      return Response.ok(jsonEncode({
        'status'          : 'success',
        'amount_used'     : amount - remaining,
        'amount_remaining': remaining,
      }), headers: {'Content-Type': 'application/json'});
    } catch (e, st) {
      print('Error in /embrodry/debts/clients/<id>/pay: $e\n$st');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Payment processing failed', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // ─── Client deposits ──────────────────────

  // GET /clients/deposits
  router.get('/clients/deposits', (Request req) async {
    try {
      final rows = await db.query(r'''
        SELECT p.id, p.client_id, c.full_name, p.amount, p.payment_date::text, p.notes
        FROM embroidery.client_credit_payments p
        JOIN embroidery.clients c ON c.id = p.client_id
        ORDER BY p.payment_date DESC;
      ''');

      final data = rows.map((r) => {
        'id'          : r[0] as int,
        'client_id'   : r[1] as int,
        'client_name' : r[2] as String?,
        'amount'      : _toDouble(r[3]),
        'payment_date': r[4] as String,
        'notes'       : r[5] as String?,
      }).toList();

      return Response.ok(jsonEncode(data),
          headers: {'Content-Type':'application/json'});
    } catch (e, st) {
      print('Error in GET /embrodry/debts/clients/deposits: $e\n$st');
      return Response.internalServerError(
        body: jsonEncode({'error':'Failed to fetch deposits','details':e.toString()}),
       	headers: {'Content-Type':'application/json'},
      );
    }
  });

  // POST /clients/deposits
  router.post('/clients/deposits', (Request req) async {
    try {
      final body = jsonDecode(await req.readAsString()) as Map<String,dynamic>;
      final cid  = _toInt(body['client_id']);
      final amt  = _toDouble(body['amount']);
      final notes= body['notes'] as String?;

      final result = await db.query(r'''
        INSERT INTO embroidery.client_credit_payments(client_id, amount, notes)
        VALUES (@cid, @amt, @notes)
        RETURNING id;
      ''', substitutionValues:{
        'cid'  : cid,
        'amt'  : amt,
        'notes': notes,
      });

      return Response.ok(jsonEncode({'status':'success','id':result.first[0]}),
          headers: {'Content-Type':'application/json'});
    } catch(e, st) {
      print('Error in POST /embrodry/debts/clients/deposits: $e\n$st');
      return Response.internalServerError(
        body: jsonEncode({'error':'Failed to create deposit','details':e.toString()}),
        headers: {'Content-Type':'application/json'},
      );
    }
  });

  // PUT /clients/deposits/<id>
  router.put('/clients/deposits/<id|[0-9]+>', (Request req, String id) async {
    try {
      final body = jsonDecode(await req.readAsString()) as Map<String,dynamic>;
      final amt  = _toDouble(body['amount']);
      final notes= body['notes'] as String?;

      await db.query(r'''
        UPDATE embroidery.client_credit_payments
        SET amount = @amt, notes = @notes
        WHERE id = @id;
      ''', substitutionValues:{
        'amt'  : amt,
        'notes': notes,
        'id'   : int.parse(id),
      });

      return Response.ok(jsonEncode({'status':'success'}),
          headers: {'Content-Type':'application/json'});
    } catch(e, st) {
      print('Error in PUT /embrodry/debts/clients/deposits/$id: $e\n$st');
      return Response.internalServerError(
        body: jsonEncode({'error':'Failed to edit deposit','details':e.toString()}),
        headers: {'Content-Type':'application/json'},
      );
    }
  });

  // DELETE /clients/deposits/<id>
  router.delete('/clients/deposits/<id|[0-9]+>', (Request req, String id) async {
    try {
      await db.query(
        'DELETE FROM embroidery.client_credit_payments WHERE id = @id;',
        substitutionValues: {'id': int.parse(id)});
      return Response.ok(jsonEncode({'status':'success'}),
          headers: {'Content-Type':'application/json'});
    } catch(e, st) {
      print('Error in DELETE /embrodry/debts/clients/deposits/$id: $e\n$st');
      return Response.internalServerError(
        body: jsonEncode({'error':'Failed to delete deposit','details':e.toString()}),
        headers: {'Content-Type':'application/json'},
      );
    }
  });

  // POST /clients/<id>/deposit/use
  router.post('/clients/<id|[0-9]+>/deposit/use', (Request req, String id) async {
    try {
      final bodyRaw = await req.readAsString();
      final body    = jsonDecode(bodyRaw) as Map<String, dynamic>;
      final requested = _toDouble(body['amount']);
      final cid       = int.parse(id);

      // Fetch all positive deposits
      final rows = await db.query(r'''
        SELECT id, amount
        FROM embroidery.client_credit_payments
        WHERE client_id = @cid AND amount > 0
        ORDER BY payment_date, id
      ''', substitutionValues: {'cid': cid});

      double totalAvail     = rows.fold(0.0, (sum, r) => sum + _toDouble(r[1]));
      final double toUse    = requested <= totalAvail ? requested : totalAvail;
      double remainingToUse = toUse;

      for (final r in rows) {
        final depId = r[0] as int;
        final avail = _toDouble(r[1]);
        if (avail <= 0) continue;

        final useAmt = avail >= remainingToUse ? remainingToUse : avail;
        final newAmt = avail - useAmt;

        if (newAmt > 0) {
          await db.query(r'''
            UPDATE embroidery.client_credit_payments
            SET amount = @newAmt
            WHERE id = @depId;
          ''', substitutionValues: {'newAmt': newAmt, 'depId': depId});
        } else {
          await db.query(r'''
            DELETE FROM embroidery.client_credit_payments
            WHERE id = @depId;
          ''', substitutionValues: {'depId': depId});
        }

        remainingToUse -= useAmt;
        if (remainingToUse <= 0) break;
      }

      return Response.ok(jsonEncode({
        'status'          : 'success',
        'amount_requested': requested,
        'amount_used'     : toUse,
      }), headers: {'Content-Type':'application/json'});
    } catch (e, st) {
      print('Error in /embrodry/debts/clients/<id>/deposit/use: $e\n$st');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to use deposit', 'details': e.toString()}),
        headers: {'Content-Type':'application/json'},
      );
    }
  });

  return router;
}
