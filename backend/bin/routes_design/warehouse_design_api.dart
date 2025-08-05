import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:postgres/postgres.dart';

double _num(dynamic v) =>
    v == null ? 0.0 : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0);
int _int(dynamic v) =>
    v == null ? 0 : (v is num ? v.toInt() : int.tryParse(v.toString()) ?? 0);

String _yyyyMMdd(DateTime? d) => d == null ? '' : d.toIso8601String().substring(0, 10);

Router getDesignWarehouseRoutes(PostgreSQLConnection db) {
  final router = Router();

  // ---------------- READY PRODUCTS ----------------

  // GET /design/warehouse/product-inventory?client_id=&season_id=
  // Returns each inventory row (id) + model info including image_url
  router.get('/product-inventory', (Request req) async {
    final qp = req.url.queryParameters;
    final clientId = int.tryParse(qp['client_id'] ?? '');
    final seasonId = int.tryParse(qp['season_id'] ?? '');

    final where = <String>[];
    final vals = <String, dynamic>{};

    if (clientId != null) {
      where.add('m.client_id = @cid');
      vals['cid'] = clientId;
    }
    if (seasonId != null) {
      where.add('m.season_id = @sid');
      vals['sid'] = seasonId;
    }
    final whereSql = where.isEmpty ? '' : 'WHERE ' + where.join(' AND ');

    final rows = await db.query('''
      SELECT
        pi.id,
        pi.quantity,
        m.id          AS model_id,
        m.model_name,
        m.marker_name,
        m.model_date,
        m.length,
        m.width,
        m.util_percent,
        m.placed,
        m.sizes_text,
        m.price,
        m.description,
        m.image_url,
        c.id          AS client_id,
        c.full_name   AS client_name,
        s.id          AS season_id,
        s.name        AS season_name
      FROM design.product_inventory pi
      JOIN design.models   m ON m.id = pi.model_id
      JOIN design.clients  c ON c.id = m.client_id
      LEFT JOIN design.seasons s ON s.id = m.season_id
      $whereSql
      ORDER BY pi.id DESC
    ''', substitutionValues: vals);

    final out = rows.map((r) => {
          'id'           : r[0],
          'quantity'     : _num(r[1]),
          'model_id'     : r[2],
          'model_name'   : r[3],
          'marker_name'  : r[4],
          'model_date'   : _yyyyMMdd(r[5] as DateTime?),
          'length'       : _num(r[6]),
          'width'        : _num(r[7]),
          'util_percent' : _num(r[8]),
          'placed'       : r[9],
          'sizes_text'   : r[10] ?? '',
          'price'        : _num(r[11]),
          'description'  : r[12],
          'image_url'    : r[13] ?? '',
          'client_id'    : r[14],
          'client_name'  : r[15],
          'season_id'    : r[16],
          'season_name'  : r[17],
        }).toList();

    return Response.ok(jsonEncode(out), headers: {'Content-Type': 'application/json'});
  });

  // POST /design/warehouse/product-inventory
  // body: { warehouse_id:1, model_id:##, quantity:## }
  // => if (warehouse_id, model_id) already exists, just add to quantity
  router.post('/product-inventory', (Request req) async {
    try {
      final data = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final wid = _int(data['warehouse_id'] ?? 1);
      final mid = _int(data['model_id']);
      final qty = _num(data['quantity']);

      if (mid == 0 || qty <= 0) {
        return Response(400,
            body: jsonEncode({'error': 'model_id and positive quantity required'}),
            headers: {'Content-Type': 'application/json'});
      }

      // UPSERT: if (warehouse_id, model_id) exists, just add to its quantity
      final rows = await db.query(r'''
        INSERT INTO design.product_inventory (warehouse_id, model_id, quantity)
        VALUES (@w, @m, @q)
        ON CONFLICT (warehouse_id, model_id) 
          DO UPDATE 
            SET quantity     = product_inventory.quantity + EXCLUDED.quantity,
                last_updated = CURRENT_TIMESTAMP
        RETURNING id;
      ''', substitutionValues: {
        'w': wid,
        'm': mid,
        'q': qty,
      });

      return Response.ok(
        jsonEncode({'id': rows.first[0]}),
        headers: {'Content-Type': 'application/json'}
      );
    } catch (e, st) {
      print('ERROR POST /design/warehouse/product-inventory: $e\n$st');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Create/Upsert failed', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // PUT /design/warehouse/product-inventory/<id>
  router.put('/product-inventory/<id|[0-9]+>', (Request req, String id) async {
    try {
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      await db.query('''
        UPDATE design.product_inventory
           SET warehouse_id = @w,
               model_id     = @m,
               quantity     = @q,
               last_updated = CURRENT_TIMESTAMP
         WHERE id = @id
      ''', substitutionValues: {
        'id': int.parse(id),
        'w' : _int(body['warehouse_id'] ?? 1),
        'm' : _int(body['model_id']),
        'q' : _num(body['quantity']),
      });
      return Response.ok(jsonEncode({'status': 'updated'}),
          headers: {'Content-Type': 'application/json'});
    } catch (e, st) {
      print('ERROR PUT /design/warehouse/product-inventory/$id: $e\n$st');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Update failed', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // DELETE /design/warehouse/product-inventory/<id>
  router.delete('/product-inventory/<id|[0-9]+>', (Request req, String id) async {
    try {
      await db.query('DELETE FROM design.product_inventory WHERE id = @id',
          substitutionValues: {'id': int.parse(id)});
      return Response.ok(jsonEncode({'status': 'deleted'}),
          headers: {'Content-Type': 'application/json'});
    } catch (e, st) {
      print('ERROR DELETE /design/warehouse/product-inventory/$id: $e\n$st');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Delete failed', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // ---------------- RAW MATERIALS ----------------
  // GET /design/warehouse/material-types
  router.get('/material-types', (Request req) async {
    try {
      final typesRes =
          await db.query('SELECT id, name FROM design.material_types ORDER BY id DESC');
      final out = <Map<String, dynamic>>[];

      for (final row in typesRes) {
        final typeId = row[0] as int;
        final specsRes = await db.query(
          'SELECT id, name FROM design.material_specs WHERE type_id=@tid ORDER BY id',
          substitutionValues: {'tid': typeId},
        );
        out.add({
          'id': typeId,
          'name': row[1],
          'specs': specsRes
              .map((s) => {'id': s[0] as int, 'name': s[1] as String})
              .toList(),
        });
      }

      return Response.ok(jsonEncode(out), headers: {'Content-Type': 'application/json'});
    } catch (e, st) {
      print('ERR GET /material-types $e\n$st');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch material types', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // POST /design/warehouse/material-types
  router.post('/material-types', (Request req) async {
    try {
      final d = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final name = (d['name'] ?? '').toString().trim();
      if (name.isEmpty) {
        return Response(400,
            body: jsonEncode({'error': 'name required'}),
            headers: {'Content-Type': 'application/json'});
      }
      final specs = (d['specs'] as List? ?? [])
          .map<Map<String, dynamic>>((e) => e as Map<String, dynamic>)
          .toList();

      final tRes = await db.query(
        'INSERT INTO design.material_types (name) VALUES (@n) RETURNING id',
        substitutionValues: {'n': name},
      );
      final tid = tRes.first[0] as int;
      for (var s in specs) {
        final sname = (s['name'] ?? '').toString().trim();
        if (sname.isNotEmpty) {
          await db.query(
            'INSERT INTO design.material_specs (type_id, name) VALUES(@tid, @n)',
            substitutionValues: {'tid': tid, 'n': sname},
          );
        }
      }
      return Response.ok(jsonEncode({'id': tid}),
          headers: {'Content-Type': 'application/json'});
    } catch (e, st) {
      print('ERR POST /material-types $e\n$st');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Create type failed', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // PUT /design/warehouse/material-types/<id>
  router.put('/material-types/<id|[0-9]+>', (Request req, String id) async {
    try {
      final d = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final name = (d['name'] ?? '').toString().trim();
      final specs = (d['specs'] as List? ?? [])
          .map<Map<String, dynamic>>((e) => e as Map<String, dynamic>)
          .toList();

      await db.query(
        'UPDATE design.material_types SET name=@n WHERE id=@id',
        substitutionValues: {'id': int.parse(id), 'n': name},
      );

      await db.query(
        'DELETE FROM design.material_specs WHERE type_id=@tid',
        substitutionValues: {'tid': int.parse(id)},
      );
      for (var s in specs) {
        final sname = (s['name'] ?? '').toString().trim();
        if (sname.isNotEmpty) {
          await db.query(
            'INSERT INTO design.material_specs (type_id, name) VALUES(@tid, @n)',
            substitutionValues: {'tid': int.parse(id), 'n': sname},
          );
        }
      }

      return Response.ok(jsonEncode({'status': 'updated'}),
          headers: {'Content-Type': 'application/json'});
    } catch (e, st) {
      print('ERR PUT /material-types $e\n$st');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Update type failed', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // DELETE /design/warehouse/material-types/<id>
  router.delete('/material-types/<id|[0-9]+>', (Request req, String id) async {
    try {
      await db.query(
        'DELETE FROM design.material_types WHERE id=@id',
        substitutionValues: {'id': int.parse(id)},
      );
      return Response.ok(jsonEncode({'status': 'deleted'}),
          headers: {'Content-Type': 'application/json'});
    } catch (e, st) {
      print('ERR DEL /material-types $e\n$st');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Delete type failed', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // GET /design/warehouse/materials?type_id=#
  router.get('/materials', (Request req) async {
    try {
      final tid = int.tryParse(req.url.queryParameters['type_id'] ?? '');
      if (tid == null) {
        return Response(400,
            body: jsonEncode({'error': 'type_id required'}),
            headers: {'Content-Type': 'application/json'});
      }

      final specsRes = await db.query(
        'SELECT id, name FROM design.material_specs WHERE type_id=@tid ORDER BY id',
        substitutionValues: {'tid': tid},
      );
      final specsList = specsRes
          .map((r) => {'id': r[0] as int, 'name': (r[1] ?? '').toString()})
          .toList();

      final matsRes = await db.query('''
        SELECT id, code, stock_quantity
        FROM design.materials
        WHERE type_id=@tid
        ORDER BY id DESC
      ''', substitutionValues: {'tid': tid});

      final matsOut = <Map<String, dynamic>>[];
      for (final m in matsRes) {
        final mid = m[0] as int;
        final priceRes = await db.query('''
          SELECT pi.unit_price
          FROM design.purchase_items pi
          JOIN design.purchases p ON p.id = pi.purchase_id
          WHERE pi.material_id=@mid
          ORDER BY p.purchase_date DESC, pi.id DESC
          LIMIT 1
        ''', substitutionValues: {'mid': mid});
        final lastPrice = priceRes.isNotEmpty ? _num(priceRes.first[0]) : 0.0;

        final valRes = await db.query('''
          SELECT ms.id AS spec_id, ms.name AS spec_name, msv.value
          FROM design.material_specs ms
          LEFT JOIN design.material_spec_values msv
            ON ms.id = msv.spec_id AND msv.material_id = @mid
          WHERE ms.type_id = @tid
          ORDER BY ms.id
        ''', substitutionValues: {'mid': mid, 'tid': tid});

        final vals = valRes
            .map((r) => {
                  'spec_id'  : r[0],
                  'spec_name': r[1],
                  'value'    : r[2] ?? '',
                })
            .toList();

        matsOut.add({
          'id'             : mid,
          'code'           : m[1],
          'stock_quantity' : _num(m[2]),
          'last_unit_price': lastPrice,
          'specs'          : vals,
        });
      }

      return Response.ok(
        jsonEncode({'specs': specsList, 'materials': matsOut}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, st) {
      print('ERR GET /materials $e\n$st');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch materials', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // POST /design/warehouse/materials
  router.post('/materials', (Request req) async {
    try {
      final d = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final res = await db.query(
        'INSERT INTO design.materials (type_id, code, stock_quantity) VALUES(@t,@c,@s) RETURNING id',
        substitutionValues: {
          't': d['type_id'],
          'c': d['code'],
          's': _num(d['stock_quantity']),
        },
      );
      final mid = res.first[0] as int;
      final specs = (d['specs'] as List? ?? [])
          .map<Map<String, dynamic>>((e) => e as Map<String, dynamic>)
          .toList();
      for (final s in specs) {
        await db.query('''
          INSERT INTO design.material_spec_values (material_id, spec_id, value)
          VALUES (@mid, @sid, @v)
          ON CONFLICT (material_id, spec_id) DO UPDATE SET value=@v
        ''', substitutionValues: {
          'mid': mid,
          'sid': s['spec_id'],
          'v'  : s['value'],
        });
      }
      return Response.ok(jsonEncode({'id': mid}),
          headers: {'Content-Type': 'application/json'});
    } catch (e, st) {
      print('ERR POST /materials $e\n$st');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Create material failed', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // PUT /design/warehouse/materials/<id>
  router.put('/materials/<id|[0-9]+>', (Request req, String id) async {
    try {
      final d = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      await db.query(
        'UPDATE design.materials SET code=@c, stock_quantity=@s WHERE id=@id',
        substitutionValues: {
          'id': int.parse(id),
          'c' : d['code'],
          's' : _num(d['stock_quantity']),
        },
      );
      final specs = (d['specs'] as List? ?? [])
          .map<Map<String, dynamic>>((e) => e as Map<String, dynamic>)
          .toList();
      for (final s in specs) {
        await db.query('''
          INSERT INTO design.material_spec_values (material_id, sp
ec_id, value)
          VALUES (@mid, @sid, @v)
          ON CONFLICT (material_id, spec_id) DO UPDATE SET value=@v
        ''', substitutionValues: {
          'mid': int.parse(id),
          'sid': s['spec_id'],
          'v'  : s['value'],
        });
      }
      return Response.ok(jsonEncode({'status': 'updated'}),
          headers: {'Content-Type': 'application/json'});
    } catch (e, st) {
      print('ERR PUT /materials $e\n$st');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Update material failed', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // DELETE /design/warehouse/materials/<id>
  router.delete('/materials/<id|[0-9]+>', (Request req, String id) async {
    try {
      await db.query(
        'DELETE FROM design.materials WHERE id=@id',
        substitutionValues: {'id': int.parse(id)},
      );
      return Response.ok(jsonEncode({'status': 'deleted'}),
          headers: {'Content-Type': 'application/json'});
    } catch (e, st) {
      print('ERR DEL /materials $e\n$st');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Delete material failed', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  return router;
}