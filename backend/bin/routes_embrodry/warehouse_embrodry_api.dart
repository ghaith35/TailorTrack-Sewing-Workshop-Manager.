// lib/routes_embrodry/warehouse_embrodry_api.dart

import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:postgres/postgres.dart';

Router getEmbrodryWarehouseRoutes(PostgreSQLConnection db) {
  final router = Router();

  double _d(v) =>
      v == null ? 0.0 : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0);
  int _i(v) =>
      v == null ? 0 : (v is num ? v.toInt() : int.tryParse(v.toString()) ?? 0);
  String _fmt(DateTime? d) =>
      d == null ? '' : d.toIso8601String().split('T').first;

  // ── PRODUCT INVENTORY ─────────────────────────────────

  // GET  /product-inventory
  router.get('/product-inventory', (Request req) async {
    try {
      final qp    = req.url.queryParameters;
      final cid   = int.tryParse(qp['client_id'] ?? '');
      final sid   = int.tryParse(qp['season_id'] ?? '');
      final where = <String>[];
      final sv    = <String, dynamic>{};

      if (cid != null) {
        where.add('m.client_id = @cid');
        sv['cid'] = cid;
      }
      if (sid != null) {
        where.add('m.season_id = @sid');
        sv['sid'] = sid;
      }
      final whereSql = where.isEmpty ? '' : 'WHERE ' + where.join(' AND ');

      final rows = await db.query('''
        SELECT
          pi.id,
          pi.quantity,
          pi.color,
          pi.size_label,
          m.id          AS model_id,
          m.model_date,
          m.model_name,
          m.stitch_price,
          m.stitch_number,
          m.total_price,
          m.image_url,
          m.description,
          m.model_type,
          c.id          AS client_id,
          c.full_name   AS client_name,
          s.id          AS season_id,
          s.name        AS season_name
        FROM embroidery.product_inventory pi
        JOIN embroidery.models       m ON m.id = pi.model_id
        LEFT JOIN embroidery.clients c ON c.id = m.client_id
        LEFT JOIN embroidery.seasons s ON s.id = m.season_id
        $whereSql
        ORDER BY pi.id DESC
      ''', substitutionValues: sv);

      final out = rows.map((r) => {
            'id'           : r[0],
            'quantity'     : _d(r[1]),
            'color'        : r[2] as String? ?? '',
            'size_label'   : r[3] as String? ?? '',
            'model_id'     : r[4],
            'model_date'   : _fmt(r[5] as DateTime?),
            'model_name'   : r[6],
            'stitch_price' : _d(r[7]),
            'stitch_number': _i(r[8]),
            'total_price'  : _d(r[9]),
            'image_url'    : r[10] as String? ?? '',
            'description'  : r[11] as String? ?? '',
            'model_type'   : r[12] as String,
            'client_id'    : r[13],
            'client_name'  : r[14] as String? ?? '',
            'season_id'    : r[15],
            'season_name'  : r[16] as String? ?? '',
          }).toList();

      return Response.ok(jsonEncode(out),
          headers: {'Content-Type': 'application/json'});
    } catch (e, st) {
      print('ERROR GET /product-inventory: $e\n$st');
      return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {'Content-Type': 'application/json'});
    }
  });
  // POST /product-inventory
  // POST /product-inventory
router.post('/product-inventory', (Request req) async {
  try {
    final data = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    final wid   = _i(data['warehouse_id'] ?? 1);
    final mid   = _i(data['model_id']);
    final color = (data['color'] ?? '').toString();
    final size  = (data['size_label'] ?? '').toString();
    final qty   = _d(data['quantity']);

    if (mid == 0 || qty <= 0) {
      return Response(400,
        body: jsonEncode({
          'error': 'model_id and positive quantity required'
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // INSERT … ON CONFLICT DO UPDATE
    final res = await db.query(r'''
      INSERT INTO embroidery.product_inventory
        (warehouse_id, model_id, color, size_label, quantity)
      VALUES
        (@w, @m, @c, @s, @q)
      ON CONFLICT (warehouse_id, model_id, color, size_label)
      DO UPDATE
        SET quantity     = embroidery.product_inventory.quantity + EXCLUDED.quantity,
            last_updated = CURRENT_TIMESTAMP
      RETURNING id
    ''', substitutionValues: {
      'w': wid,
      'm': mid,
      'c': color,
      's': size,
      'q': qty,
    });

    final newId = res.first[0] as int;
    return Response.ok(
      jsonEncode({'id': newId}),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e, st) {
    print('ERROR POST /product-inventory: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': e.toString()}),
      headers: {'Content-Type': 'application/json'},
    );
  }
});

  // PUT /product-inventory/<id>
  router.put('/product-inventory/<id|[0-9]+>', (Request req, String id) async {
    try {
      final data = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      await db.query('''
        UPDATE embroidery.product_inventory SET
          warehouse_id = @w,
          model_id     = @m,
          color        = @c,
          size_label   = @s,
          quantity     = @q,
          last_updated = CURRENT_TIMESTAMP
        WHERE id = @id
      ''', substitutionValues: {
        'id': int.parse(id),
        'w' : _i(data['warehouse_id'] ?? 1),
        'm' : _i(data['model_id']),
        'c' : data['color'] ?? '',
        's' : data['size_label'] ?? '',
        'q' : _d(data['quantity']),
      });
      return Response.ok(jsonEncode({'status': 'updated'}),
          headers: {'Content-Type': 'application/json'});
    } catch (e, st) {
      print('ERROR PUT /product-inventory: $e\n$st');
      return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {'Content-Type': 'application/json'});
    }
  });

  // DELETE /product-inventory/<id>
  router.delete('/product-inventory/<id|[0-9]+>', (Request req, String id) async {
    try {
      await db.query('DELETE FROM embroidery.product_inventory WHERE id=@id',
          substitutionValues: {'id': int.parse(id)});
      return Response.ok(jsonEncode({'status': 'deleted'}),
          headers: {'Content-Type': 'application/json'});
    } catch (e, st) {
      print('ERROR DELETE /product-inventory: $e\n$st');
      return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {'Content-Type': 'application/json'});
    }
  });

  // ── RAW MATERIAL TYPES ───────────────────────────────

  // GET  /material-types
  router.get('/material-types', (Request _) async {
    try {
      final rows = await db.query(
        'SELECT id, name FROM embroidery.material_types ORDER BY id DESC');
      final out = await Future.wait(rows.map((r) async {
        final tid = r[0] as int;
        final specs = await db.query('''
          SELECT id, name FROM embroidery.material_specs
          WHERE type_id = @tid ORDER BY id
        ''', substitutionValues: {'tid': tid});
        return {
          'id':   tid,
          'name': r[1],
          'specs': specs
              .map((s) => {'id': s[0] as int, 'name': s[1] as String})
              .toList(),
        };
      }));
      return Response.ok(jsonEncode(out),
          headers: {'Content-Type': 'application/json'});
    } catch (e, st) {
      print('ERROR GET /material-types: $e\n$st');
      return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {'Content-Type': 'application/json'});
    }
  });

  // POST /material-types
  router.post('/material-types', (Request req) async {
    try {
      final d    = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final name = (d['name'] ?? '').toString().trim();
      if (name.isEmpty) {
        return Response(400,
            body: jsonEncode({'error': 'name required'}),
            headers: {'Content-Type': 'application/json'});
      }
      final specs = (d['specs'] as List? ?? []).cast<Map<String, dynamic>>();
      final res   = await db.query(
        'INSERT INTO embroidery.material_types (name) VALUES (@n) RETURNING id',
        substitutionValues: {'n': name});
      final tid = res.first[0] as int;
      for (var s in specs) {
        final nm = (s['name'] ?? '').toString().trim();
        if (nm.isNotEmpty) {
          await db.query(
            'INSERT INTO embroidery.material_specs (type_id, name) VALUES (@tid, @nm)',
            substitutionValues: {'tid': tid, 'nm': nm},
          );
        }
      }
      return Response.ok(jsonEncode({'id': tid}),
          headers: {'Content-Type': 'application/json'});
    } catch (e, st) {
      print('ERROR POST /material-types: $e\n$st');
      return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {'Content-Type': 'application/json'});
    }
  });

  // PUT /material-types/<id>
  router.put('/material-types/<id|[0-9]+>', (Request req, String id) async {
    try {
      final d     = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final name  = (d['name'] ?? '').toString().trim();
      final specs = (d['specs'] as List? ?? []).cast<Map<String, dynamic>>();
      await db.query('UPDATE embroidery.material_types SET name=@n WHERE id=@id',
          substitutionValues: {'id': int.parse(id), 'n': name});
      await db.query('DELETE FROM embroidery.material_specs WHERE type_id=@tid',
          substitutionValues: {'tid': int.parse(id)});
      for (var s in specs) {
        final nm = (s['name'] ?? '').toString().trim();
        if (nm.isNotEmpty) {
          await db.query(
            'INSERT INTO embroidery.material_specs (type_id, name) VALUES (@tid, @nm)',
            substitutionValues: {'tid': int.parse(id), 'nm': nm},
          );
        }
      }
      return Response.ok(jsonEncode({'status': 'updated'}),
          headers: {'Content-Type': 'application/json'});
    } catch (e, st) {
      print('ERROR PUT /material-types: $e\n$st');
      return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {'Content-Type': 'application/json'});
    }
  });

  // DELETE /material-types/<id>
  router.delete('/material-types/<id|[0-9]+>', (Request req, String id) async {
    try {
      await db.query(
        'DELETE FROM embroidery.material_types WHERE id=@id',
        substitutionValues: {'id': int.parse(id)});
      return Response.ok(jsonEncode({'status': 'deleted'}),
          headers: {'Content-Type': 'application/json'});
    } catch (e, st) {
      print('ERROR DELETE /material-types: $e\n$st');
      return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {'Content-Type': 'application/json'});
    }
  });

  // ── RAW MATERIALS ────────────────────────────────────

  // GET  /materials?type_id=#
  router.get('/materials', (Request req) async {
    try {
      final tid = int.tryParse(req.url.queryParameters['type_id'] ?? '');
      if (tid == null) {
        return Response(400,
            body: jsonEncode({'error': 'type_id required'}),
            headers: {'Content-Type': 'application/json'});
      }

      final specsRes = await db.query('''
        SELECT id, name FROM embroidery.material_specs
        WHERE type_id=@tid ORDER BY id
      ''', substitutionValues: {'tid': tid});
      final specs = specsRes
          .map((r) => {'id': r[0] as int, 'name': r[1] as String})
          .toList();

      final matsRes = await db.query('''
        SELECT id, code, stock_quantity
        FROM embroidery.materials
        WHERE type_id=@tid
        ORDER BY id DESC
      ''', substitutionValues: {'tid': tid});

      final mats = <Map<String, dynamic>>[];
      for (final m in matsRes) {
        final mid = m[0] as int;
        final priceRes = await db.query('''
          SELECT unit_price FROM embroidery.purchase_items
          WHERE material_id=@mid
          ORDER BY id DESC LIMIT 1
        ''', substitutionValues: {'mid': mid});
        final last = priceRes.isNotEmpty ? _d(priceRes.first[0]) : 0.0;

        final valsRes = await db.query('''
          SELECT spec_id, value FROM embroidery.material_spec_values
          WHERE material_id=@mid
          ORDER BY spec_id
        ''', substitutionValues: {'mid': mid});

        final vals = valsRes
            .map((r) => {'spec_id': r[0], 'value': r[1] as String})
            .toList();

        mats.add({
          'id': mid,
          'code': m[1],
          'stock_quantity': _d(m[2]),
          'last_unit_price': last,
          'specs': vals,
        });
      }

      return Response.ok(jsonEncode({'specs': specs, 'materials': mats}),
          headers: {'Content-Type': 'application/json'});
    } catch (e, st) {
      print('ERROR GET /materials: $e\n$st');
      return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {'Content-Type': 'application/json'});
    }
  });

  // POST /materials
  router.post('/materials', (Request req) async {
    try {
      final d = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final res = await db.query('''
        INSERT INTO embroidery.materials (type_id, code, stock_quantity)
        VALUES (@t,@c,@s) RETURNING id
      ''', substitutionValues: {
        't': d['type_id'],
        'c': d['code'],
        's': _d(d['stock_quantity']),
      });
      final id = res.first[0] as int;
      for (var s in (d['specs'] as List).cast<Map<String, dynamic>>()) {
        await db.query('''
          INSERT INTO embroidery.material_spec_values
            (material_id, spec_id, value)
          VALUES (@mid,@sid,@v)
          ON CONFLICT(material_id,spec_id) DO UPDATE SET value=@v
        ''', substitutionValues: {
          'mid': id,
          'sid': s['spec_id'],
          'v'  : s['value'],
        });
      }
      return Response.ok(jsonEncode({'id': id}),
          headers: {'Content-Type': 'application/json'});
    } catch (e, st) {
      print('ERROR POST /materials: $e\n$st');
      return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {'Content-Type': 'application/json'});
    }
  });

  // PUT /materials/<id>
  router.put('/materials/<id|[0-9]+>', (Request req, String id) async {
    try {
      final d = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      await db.query('''
        UPDATE embroidery.materials SET code=@c, stock_quantity=@s WHERE id=@id
      ''', substitutionValues: {
        'id': int.parse(id),
        'c' : d['code'],
        's' : _d(d['stock_quantity']),
      });
      for (var s in (d['specs'] as List).cast<Map<String, dynamic>>()) {
        await db.query('''
          INSERT INTO embroidery.material_spec_values
            (material_id, spec_id, value)
          VALUES (@mid,@sid,@v)
          ON CONFLICT(material_id,spec_id) DO UPDATE SET value=@v
        ''', substitutionValues: {
          'mid': int.parse(id),
          'sid': s['spec_id'],
          'v'  : s['value'],
        });
      }
      return Response.ok(jsonEncode({'status': 'updated'}),
          headers: {'Content-Type': 'application/json'});
    } catch (e, st) {
      print('ERROR PUT /materials: $e\n$st');
      return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {'Content-Type': 'application/json'});
    }
  });

  // DELETE /materials/<id>
  router.delete('/materials/<id|[0-9]+>', (Request req, String id) async {
    try {
      await db.query('DELETE FROM embroidery.materials WHERE id=@id',
          substitutionValues: {'id': int.parse(id)});
      return Response.ok(jsonEncode({'status': 'deleted'}),
          headers: {'Content-Type': 'application/json'});
    } catch (e, st) {
      print('ERROR DELETE /materials: $e\n$st');
      return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {'Content-Type': 'application/json'});
    }
  });

  return router;
}
