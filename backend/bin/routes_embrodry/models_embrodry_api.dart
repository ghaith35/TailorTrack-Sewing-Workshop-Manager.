import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:postgres/postgres.dart';

Router getEmbrodryModelsRoutes(PostgreSQLConnection db) {
  final router = Router();

  double _d(v) => v == null
      ? 0.0
      : (v is num
          ? v.toDouble()
          : double.tryParse(v.toString()) ?? 0.0);
  int _i(v) => v == null
      ? 0
      : (v is num
          ? v.toInt()
          : int.tryParse(v.toString()) ?? 0);

  // ─── LIST ───────────────────────────────────────────────
  router.get('/', (Request req) async {
    try {
      final qp  = req.url.queryParameters;
      final cid = int.tryParse(qp['client_id'] ?? '');
      final sid = int.tryParse(qp['season_id'] ?? '');

      final where = <String>[];
      final sv    = <String, dynamic>{};

      if (cid != null) {
        // cid == -1 means NULL filter (no client)
        if (cid < 0) {
          where.add('m.client_id IS NULL');
        } else {
          where.add('m.client_id = @cid');
          sv['cid'] = cid;
        }
      }
      if (sid != null) {
        where.add('m.season_id = @sid');
        sv['sid'] = sid;
      }
      final whereSql = where.isEmpty ? '' : 'WHERE ' + where.join(' AND ');

      final rows = await db.query('''
      SELECT
        m.id,
        m.client_id, c.full_name,
        m.season_id, s.name,
        m.model_date,
        m.model_name,
        m.stitch_price,
        m.stitch_number,
        m.total_price,
        m.description,
        m.model_type,
        m.created_at
      FROM embroidery.models m
      LEFT JOIN embroidery.clients c ON m.client_id = c.id
      LEFT JOIN embroidery.seasons s ON m.season_id = s.id
      $whereSql
      ORDER BY m.created_at DESC
      ''', substitutionValues: sv);

      final list = rows.map((r) => {
            'id':             r[0] as int,
            'client_id':      r[1] as int?,
            'client_name':    r[2] as String?,
            'season_id':      r[3] as int?,
            'season_name':    r[4] as String?,
            'model_date':     (r[5] as DateTime).toIso8601String(),
            'model_name':     r[6] as String,
            'stitch_price':   _d(r[7]),
            'stitch_number':  _i(r[8]),
            'total_price':    _d(r[9]),
            'description':    r[10] as String?,
            'model_type':     r[11] as String,
            'created_at':     (r[12] as DateTime).toIso8601String(),
          }).toList();

      return Response.ok(
        jsonEncode(list),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, st) {
      print('GET /embrodry/models error: $e\n$st');
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // ─── GET ONE ───────────────────────────────────────────
  router.get('/<id|[0-9]+>', (Request req, String id) async {
    try {
      final rows = await db.query('''
      SELECT
        m.id,
        m.client_id, c.full_name,
        m.season_id, s.name,
        m.model_date,
        m.model_name,
        m.stitch_price,
        m.stitch_number,
        m.total_price,
        m.description,
        m.model_type,
        m.created_at
      FROM embroidery.models m
      LEFT JOIN embroidery.clients c ON m.client_id = c.id
      LEFT JOIN embroidery.seasons s ON m.season_id = s.id
      WHERE m.id = @id
      ''', substitutionValues: {'id': int.parse(id)});

      if (rows.isEmpty) {
        return Response.notFound(
          jsonEncode({'error': 'not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      final r = rows.first;
      final m = {
        'id':             r[0] as int,
        'client_id':      r[1] as int?,
        'client_name':    r[2] as String?,
        'season_id':      r[3] as int?,
        'season_name':    r[4] as String?,
        'model_date':     (r[5] as DateTime).toIso8601String(),
        'model_name':     r[6] as String,
        'stitch_price':   _d(r[7]),
        'stitch_number':  _i(r[8]),
        'total_price':    _d(r[9]),
        'description':    r[10] as String?,
        'model_type':     r[11] as String,
        'created_at':     (r[12] as DateTime).toIso8601String(),
      };
      return Response.ok(
        jsonEncode(m),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // ─── CREATE ────────────────────────────────────────────
  // ─── CREATE ────────────────────────────────────────────
router.post('/', (Request req) async {
  try {
    final data = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    final d = DateTime.parse(data['model_date'] as String);
    final newId = await db.transaction((tx) async {
      final res = await tx.query('''
        INSERT INTO embroidery.models
          (client_id, season_id, model_date,
           model_name, stitch_price, stitch_number,
           description, model_type)
        VALUES
          (@cid, @sid, @d, @mn, @sp, @sn, @desc, @mt)
        RETURNING id
      ''', substitutionValues: {
        'cid': data['client_id'],
        'sid': data['season_id'],
        'd'  : d,
        'mn' : data['model_name'],
        'sp' : _d(data['stitch_price']),
        'sn' : _i(data['stitch_number']),
        'desc': data['description'],
        'mt' : data['model_type'],
      });
      return res.first[0] as int;
    });
    return Response(201,
      body: jsonEncode({'id': newId}),
      headers: {'Content-Type': 'application/json'},
    );
  } on PostgreSQLException catch (e) {
    if (e.code == '23505' /* unique_violation */) {
      return Response(400,
        body: jsonEncode({
          'error': 'duplicate_model_name',
          'message': 'اسم الموديل مستخدم مسبقاً'
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
    rethrow;  // let other errors bubble up
  } catch (e, st) {
    print('POST /embrodry/models error: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': e.toString()}),
      headers: {'Content-Type': 'application/json'},
    );
  }
});

// ─── UPDATE ────────────────────────────────────────────
router.put('/<id|[0-9]+>', (Request req, String id) async {
  try {
    final data = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    final d = DateTime.parse(data['model_date'] as String);
    final count = await db.execute('''
      UPDATE embroidery.models SET
        client_id     = @cid,
        season_id     = @sid,
        model_date    = @d,
        model_name    = @mn,
        stitch_price  = @sp,
        stitch_number = @sn,
        description   = @desc,
        model_type    = @mt
      WHERE id = @id
    ''', substitutionValues: {
      'id'  : int.parse(id),
      'cid' : data['client_id'],
      'sid' : data['season_id'],
      'd'   : d,
      'mn'  : data['model_name'],
      'sp'  : _d(data['stitch_price']),
      'sn'  : _i(data['stitch_number']),
      'desc': data['description'],
      'mt'  : data['model_type'],
    });
    if (count == 0) {
      return Response.notFound(
        jsonEncode({'error': 'not found'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    return Response.ok(
      jsonEncode({'status': 'updated'}),
      headers: {'Content-Type': 'application/json'},
    );
  } on PostgreSQLException catch (e) {
    if (e.code == '23505') {
      return Response(400,
        body: jsonEncode({
          'error': 'duplicate_model_name',
          'message': 'اسم الموديل مستخدم مسبقاً'
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
    rethrow;
  } catch (e, st) {
    print('PUT /embrodry/models error: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': e.toString()}),
      headers: {'Content-Type': 'application/json'},
    );
  }
});

  // ─── DELETE ────────────────────────────────────────────
  router.delete('/<id|[0-9]+>', (Request req, String id) async {
    try {
      final count = await db.execute(
        'DELETE FROM embroidery.models WHERE id = @id',
        substitutionValues: {'id': int.parse(id)},
      );
      if (count == 0) {
        return Response.notFound(
          jsonEncode({'error': 'not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      return Response.ok(
        jsonEncode({'status': 'deleted'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // ─── HELPERS ───────────────────────────────────────────
  router.get('/clients', (Request _) async {
    try {
      final rows = await db.query(
          'SELECT id, full_name FROM embroidery.clients ORDER BY full_name');
      final list = rows
          .map((r) => {'id': r[0] as int, 'full_name': r[1] as String})
          .toList();
      return Response.ok(jsonEncode(list),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  router.get('/seasons', (Request _) async {
    try {
      final rows = await db.query(
          'SELECT id, name FROM embroidery.seasons ORDER BY start_date DESC');
      final list = rows
          .map((r) => {'id': r[0] as int, 'name': r[1] as String})
          .toList();
      return Response.ok(jsonEncode(list),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  return router;
}
