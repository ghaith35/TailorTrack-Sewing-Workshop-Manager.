// lib/routes/design_debts_api.dart

import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:postgres/postgres.dart';

double _toDouble(dynamic v) {
  if (v == null) return 0.0;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0.0;
  throw FormatException('Cannot convert ${v.runtimeType} to double');
}

Router getDesignDebtsRoutes(PostgreSQLConnection db) {
  final router = Router();

  // ===================== SUPPLIERS =====================
  // GET /design/debts/suppliers
  router.get('/suppliers', (Request req) async {
    try {
      // Optionally parse year & month filters (if you want real filtering at DB level)
      final qp = req.requestedUri.queryParameters;
      final year = qp['year'];
      final month = qp['month'];

      // Base query (same logic as sewing, but using design schema)
      final rows = await db.query(r'''
        SELECT
          s.id                         AS supplier_id,
          s.full_name,
          s.company_name,
          COALESCE(tp.total_purchases, 0)        AS total_purchases,
          COALESCE(pd.on_creation_total, 0)      AS on_creation_total,
          COALESCE(pp.extra_payments_total, 0)   AS extra_payments_total,
          COALESCE(ad.last_date::text, '')       AS last_date
        FROM design.suppliers s

        LEFT JOIN (
          SELECT p.supplier_id, SUM(pi.quantity * pi.unit_price) AS total_purchases
          FROM design.purchases p
          JOIN design.purchase_items pi
            ON pi.purchase_id = p.id
          GROUP BY p.supplier_id
        ) tp ON tp.supplier_id = s.id

        LEFT JOIN (
          SELECT supplier_id, SUM(COALESCE(amount_paid_on_creation,0)) AS on_creation_total
          FROM design.purchases
          GROUP BY supplier_id
        ) pd ON pd.supplier_id = s.id

        LEFT JOIN (
          SELECT p.supplier_id, SUM(pp.amount_paid) AS extra_payments_total
          FROM design.purchase_payments pp
          JOIN design.purchases p
            ON pp.purchase_id = p.id
          GROUP BY p.supplier_id
        ) pp ON pp.supplier_id = s.id

        LEFT JOIN (
          SELECT supplier_id, MAX(purchase_date) AS last_date
          FROM design.purchases
          GROUP BY supplier_id
        ) ad ON ad.supplier_id = s.id

        ORDER BY s.id DESC;
      ''');

      final data = rows.map((r) {
        final purchases = _toDouble(r[3]);
        final onCreated  = _toDouble(r[4]);
        final extraPaid  = _toDouble(r[5]);
        final map = {
          'id'              : r[0] as int,
          'full_name'       : r[1] as String?,
          'company_name'    : r[2] as String?,
          'total_purchases' : purchases,
          'total_paid'      : onCreated + extraPaid,
          'debt'            : purchases - (onCreated + extraPaid),
          'date'            : r[6].toString(),
        };
        return map;
      }).toList();

      // Optionally filter year/month in Dart side (simple)
      if (year != null && month != null) {
        final y = int.tryParse(year);
        final m = month;
        final filtered = data.where((e) {
          final d = e['date'] as String?;
          if (d == null || !d.contains('-')) return false;
          final parts = d.split('-');
          return parts[0] == y.toString() && parts[1] == m;
        }).toList();
        return Response.ok(jsonEncode(filtered),
            headers: {'Content-Type': 'application/json'});
      }

      return Response.ok(jsonEncode(data),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({
          'error': 'Failed to fetch design supplier debts',
          'details': e.toString(),
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // POST /design/debts/suppliers/<id>/pay
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
        FROM design.purchases p

        LEFT JOIN (
          SELECT purchase_id, SUM(quantity * unit_price) AS total_amount
          FROM design.purchase_items
          GROUP BY purchase_id
        ) pi  ON pi.purchase_id = p.id

        LEFT JOIN (
          SELECT purchase_id, SUM(amount_paid) AS extra_paid
          FROM design.purchase_payments
          GROUP BY purchase_id
        ) pp  ON pp.purchase_id = p.id

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
          INSERT INTO design.purchase_payments
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
      return Response.internalServerError(
        body: jsonEncode({
          'error'  : 'Payment processing failed (design suppliers)',
          'details': e.toString(),
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // ===================== CLIENTS =====================
  // GET /design/debts/clients
  router.get('/clients', (Request req) async {
    try {
      final qp = req.requestedUri.queryParameters;
      final year = qp['year'];
      final month = qp['month'];

      final rows = await db.query(r'''
        SELECT
          c.id                               AS client_id,
          c.full_name,
          c.phone,
          c.address,
          COALESCE(ci.total_invoiced, 0)       AS total_invoiced,
          COALESCE(fc.on_creation_total, 0)    AS on_creation_total,
          COALESCE(fp.extra_payments_total, 0) AS extra_payments_total,
          COALESCE(ad.last_date::text, '')     AS last_date
        FROM design.clients c

        LEFT JOIN (
          SELECT client_id, SUM(total_amount) AS total_invoiced
          FROM design.factures
          GROUP BY client_id
        ) ci ON ci.client_id = c.id

        LEFT JOIN (
          SELECT client_id, SUM(COALESCE(amount_paid_on_creation,0)) AS on_creation_total
          FROM design.factures
          GROUP BY client_id
        ) fc ON fc.client_id = c.id

        LEFT JOIN (
          SELECT f.client_id, SUM(fp.amount_paid) AS extra_payments_total
          FROM design.facture_payments fp
          JOIN design.factures f ON fp.facture_id = f.id
          GROUP BY f.client_id
        ) fp ON fp.client_id = c.id

        LEFT JOIN (
          SELECT client_id, MAX(facture_date) AS last_date
          FROM design.factures
          GROUP BY client_id
        ) ad ON ad.client_id = c.id

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

      if (year != null && month != null) {
        final y = int.tryParse(year);
        final m = month;
        final filtered = data.where((e) {
          final d = e['date'] as String?;
          if (d == null || !d.contains('-')) return false;
          final parts = d.split('-');
          return parts[0] == y.toString() && parts[1] == m;
        }).toList();
        return Response.ok(jsonEncode(filtered),
            headers: {'Content-Type': 'application/json'});
      }

      return Response.ok(jsonEncode(data),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({
          'error'  : 'Failed to fetch design client debts',
          'details': e.toString(),
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // POST /design/debts/clients/<id>/pay
  router.post('/clients/<id>/pay', (Request req, String id) async {
    try {
      final payload = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final amount  = (payload['amount'] as num).toDouble();
      double remaining = amount;

      final invoices = await db.query(r'''
        SELECT
          f.id,
          COALESCE(f.amount_paid_on_creation, 0) AS amount_paid_on_creation,
          COALESCE((
            SELECT SUM(amount_paid)
            FROM design.facture_payments
            WHERE facture_id = f.id
          ), 0)                                 AS extra_paid,
          f.total_amount
        FROM design.factures f
        WHERE f.client_id = @cid
        ORDER BY f.facture_date, f.id;
      ''', substitutionValues: {'cid': int.parse(id)});

      for (var r in invoices) {
        final fid        = r[0] as int;
        final onCreation = _toDouble(r[1]);
        final extraPaid  = _toDouble(r[2]);
        final totalAmt   = _toDouble(r[3]);
        final paidSoFar  = onCreation + extraPaid;
        final unpaid     = totalAmt - paidSoFar;
        if (unpaid <= 0) continue;

        final pay = unpaid >= remaining ? remaining : unpaid;
        await db.query(r'''
          INSERT INTO design.facture_payments
          (facture_id, amount_paid, payment_date)
          VALUES (@fid, @pay, CURRENT_DATE);
        ''', substitutionValues: {
          'fid': fid,
          'pay': pay,
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
      return Response.internalServerError(
        body: jsonEncode({
          'error'  : 'Payment processing failed (design clients)',
          'details': e.toString(),
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  return router;
}
