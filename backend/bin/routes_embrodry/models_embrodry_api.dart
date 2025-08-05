import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf_multipart/shelf_multipart.dart';
import 'package:path/path.dart' as p;

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

  // ─── LIST ─────────────────────────────────────────────
  router.get('/', (Request req) async {
    try {
      final qp  = req.url.queryParameters;
      final cid = int.tryParse(qp['client_id'] ?? '');
      final sid = int.tryParse(qp['season_id'] ?? '');

      final where = <String>[];
      final sv    = <String, dynamic>{};

      if (cid != null) {
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
        m.image_url,
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
            'image_url':      r[12] as String?,
            'created_at':     (r[13] as DateTime).toIso8601String(),
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

  // ─── GET ONE ─────────────────────────────────────────
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
        m.image_url,
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
        'image_url':      r[12] as String?,
        'created_at':     (r[13] as DateTime).toIso8601String(),
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

  // ─── CREATE ─────────────────────────────────────────
  router.post('/', (Request request) async {
    final form = request.formData();
    if (form == null) {
      return Response(400,
        body: jsonEncode({'error': 'Expected multipart/form-data'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    final fields = <String, String>{};
    String? imageUrl;

    await for (final part in form.formData) {
      if (part.filename != null) {
        final bytes = await part.part.readBytes();
        final fname = p.basename(part.filename!);
        final file  = File('public/images/$fname');
        await file.create(recursive: true);
        await file.writeAsBytes(bytes);
        imageUrl = '/images/$fname';
      } else {
        fields[part.name] = await part.part.readString();
      }
    }

    try {
      final d = DateTime.parse(fields['model_date']!);
      final newId = await db.transaction((tx) async {
        final res = await tx.query('''
          INSERT INTO embroidery.models
            (client_id, season_id, model_date,
             model_name, stitch_price, stitch_number,
             description, model_type, image_url)
          VALUES
            (@cid, @sid, @d, @mn, @sp, @sn, @desc, @mt, @img)
          RETURNING id
        ''', substitutionValues: {
          'cid': fields['client_id'] != 'null'
              ? int.tryParse(fields['client_id']!)
              : null,
          'sid': fields['season_id'] != 'null'
              ? int.tryParse(fields['season_id']!)
              : null,
          'd'  : d,
          'mn' : fields['model_name']!,
          'sp' : _d(fields['stitch_price']),
          'sn' : _i(fields['stitch_number']),
          'desc': fields['description'],
          'mt' : fields['model_type']!,
          'img': imageUrl ?? '',
        });
        return res.first[0] as int;
      });
      return Response(201,
        body: jsonEncode({'id': newId}),
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
      print('POST /embrodry/models error: $e\n$st');
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // ─── UPDATE ─────────────────────────────────────────
  router.put('/<id|[0-9]+>', (Request request, String id) async {
    final form = request.formData();
    if (form == null) {
      return Response(400,
        body: jsonEncode({'error': 'Expected multipart/form-data'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    final fields = <String, String>{};
    String? newImageUrl;
    bool clearImage = false;

    await for (final part in form.formData) {
      if (part.name == 'image' && part.filename == null) {
        final text = await part.part.readString();
        if (text.isEmpty) clearImage = true;
      } else if (part.filename != null) {
        final bytes = await part.part.readBytes();
        final fname = p.basename(part.filename!);
        final target = File('public/images/$fname');
        await target.create(recursive: true);
        await target.writeAsBytes(bytes);
        newImageUrl = '/images/$fname';
      } else {
        fields[part.name] = await part.part.readString();
      }
    }

    // delete old file if replaced/cleared
    if (newImageUrl != null || clearImage) {
      final oldRes = await db.query(
        'SELECT image_url FROM embroidery.models WHERE id = @id',
        substitutionValues: {'id': int.parse(id)},
      );
      if (oldRes.isNotEmpty) {
        final oldUrl = oldRes.first[0] as String?;
        if (oldUrl != null && oldUrl.startsWith('/images/')) {
          final oldFile = File('public${oldUrl}');
          if (await oldFile.exists()) await oldFile.delete();
        }
      }
    }

    try {
      final modelDate = DateTime.parse(fields['model_date']!);

      final rows = await db.query('''
      UPDATE embroidery.models SET
        client_id     = @cid,
        season_id     = @sid,
        model_date    = @d,
        model_name    = @mn,
        stitch_price  = @sp,
        stitch_number = @sn,
        description   = @desc,
        model_type    = @mt,
        image_url     = @img
      WHERE id = @id
      RETURNING id
      ''', substitutionValues: {
        'id'  : int.parse(id),
        'cid' : fields['client_id']  != 'null'
            ? int.tryParse(fields['client_id']!)  : null,
        'sid' : fields['season_id']  != 'null'
            ? int.tryParse(fields['season_id']!)  : null,
        'd'   : modelDate,
        'mn'  : fields['model_name']!,
        'sp'  : _d(fields['stitch_price']),
        'sn'  : _i(fields['stitch_number']),
        'desc': fields['description'],
        'mt'  : fields['model_type']!,
        'img' : clearImage ? '' : (newImageUrl ?? fields['image_url'] ?? ''),
      });

      if (rows.isEmpty) {
        return Response.notFound(
          jsonEncode({'error': 'not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final updatedId = rows.first[0] as int;
      return Response.ok(
        jsonEncode({'id': updatedId}),
        headers: {'Content-Type': 'application/json'},
      );
    } on PostgreSQLException catch (e) {
      if (e.code == '23505') {
        return Response(400,
          body: jsonEncode({
            'error'  : 'duplicate_model_name',
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

  // ─── DELETE ─────────────────────────────────────────
  router.delete('/<id|[0-9]+>', (Request req, String id) async {
    try {
      final modelId = int.parse(id);

      // delete stored image file if exists
      final imgRes = await db.query(
        'SELECT image_url FROM embroidery.models WHERE id = @id',
        substitutionValues: {'id': modelId},
      );
      if (imgRes.isNotEmpty) {
        final imageUrl = imgRes.first[0] as String?;
        if (imageUrl != null && imageUrl.startsWith('/images/')) {
          final file = File('public${imageUrl}');
          if (await file.exists()) await file.delete();
        }
      }

      final count = await db.execute(
        'DELETE FROM embroidery.models WHERE id = @id',
        substitutionValues: {'id': modelId},
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

  // ─── HELPERS ────────────────────────────────────────
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
