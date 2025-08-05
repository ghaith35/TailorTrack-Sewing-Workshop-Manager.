// lib/routes_design/design_models_api.dart

import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf_multipart/shelf_multipart.dart';
import 'package:path/path.dart' as p;

Router getDesignModelsRoutes(PostgreSQLConnection db) {
  final router = Router();

  double _d(v) => v == null ? 0.0 : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0);
  int _i(v) => v == null ? 0 : (v is num ? v.toInt() : int.tryParse(v.toString()) ?? 0);

  double _parsePercent(dynamic v) {
    if (v == null) return 0.0;
    var s = v.toString().trim();
    if (s.endsWith('%')) s = s.substring(0, s.length - 1);
    return double.tryParse(s) ?? 0.0;
  }

  String _slashify(String sizes) => sizes
      .split(',')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .map((p) => p.replaceFirst(':', '/'))
      .join(', ');

  Future<int?> _findSeasonIdByDate(PostgreSQLExecutionContext c, DateTime d) async {
    final rows = await c.query('''
      SELECT id FROM design.seasons
      WHERE @d BETWEEN start_date AND end_date
      ORDER BY id DESC
      LIMIT 1
    ''', substitutionValues: {'d': d});
    return rows.isEmpty ? null : rows.first[0] as int;
  }

  // ====== LIST ======
  router.get('/', (Request req) async {
    try {
      final qp = req.url.queryParameters;
      final cid = int.tryParse(qp['client_id'] ?? '');
      final sid = int.tryParse(qp['season_id'] ?? '');
      final from = qp['from'];
      final to = qp['to'];

      final where = <String>[];
      final sv = <String, dynamic>{};

      if (cid != null) {
        where.add('m.client_id = @cid');
        sv['cid'] = cid;
      }
      if (sid != null) {
        where.add('m.season_id = @sid');
        sv['sid'] = sid;
      }
      if (from != null) {
        where.add('m.model_date >= @from');
        sv['from'] = DateTime.parse(from);
      }
      if (to != null) {
        where.add('m.model_date <= @to');
        sv['to'] = DateTime.parse(to);
      }

      final whereSql = where.isEmpty ? '' : 'WHERE ' + where.join(' AND ');

      final rows = await db.query('''
        SELECT 
          m.id, m.client_id, c.full_name,
          m.season_id, s.name,
          m.model_date,
          m.model_name, m.marker_name,
          m.length, m.width,
          m.util_percent, m.placed,
          m.sizes_text, m.price, m.description,
          m.image_url, m.created_at
        FROM design.models m
        JOIN design.clients c ON m.client_id = c.id
        LEFT JOIN design.seasons s ON m.season_id = s.id
        $whereSql
        ORDER BY m.id DESC
      ''', substitutionValues: sv);

      final list = rows.map((r) {
        final util = _d(r[10]);
        final sizesTxt = (r[12] ?? '').toString();
        return {
          'id': r[0],
          'client_id': r[1],
          'client_name': r[2],
          'season_id': r[3],
          'season_name': r[4],
          'model_date': r[5].toString(),
          'model_name': r[6],
          'marker_name': r[7],
          'length': _d(r[8]),
          'width': _d(r[9]),
          'util_percent': util,
          'util_percent_str': '${util.toStringAsFixed(2)}%',
          'placed': r[11],
          'sizes_text': sizesTxt,
          'sizes_slash': _slashify(sizesTxt),
          'price': _d(r[13]),
          'description': r[14],
          'image_url': r[15],
          'created_at': r[16]?.toString(),
        };
      }).toList();

      return Response.ok(jsonEncode(list), headers: {'Content-Type': 'application/json'});
    } catch (e, st) {
      print('GET /design/models error: $e\n$st');
      return Response.internalServerError(
        body: jsonEncode({'error': 'db error', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // ====== GET ONE ======
  router.get('/<id|[0-9]+>', (Request req, String id) async {
    try {
      final rows = await db.query('''
        SELECT 
          m.id, m.client_id, c.full_name,
          m.season_id, s.name,
          m.model_date,
          m.model_name, m.marker_name,
          m.length, m.width,
          m.util_percent, m.placed,
          m.sizes_text, m.price, m.description,
          m.image_url, m.created_at
        FROM design.models m
        JOIN design.clients c ON m.client_id = c.id
        LEFT JOIN design.seasons s ON m.season_id = s.id
        WHERE m.id = @id
      ''', substitutionValues: {'id': int.parse(id)});
      if (rows.isEmpty) return Response.notFound(jsonEncode({'error': 'not found'}));
      final r = rows.first;
      final util = _d(r[10]);
      final sizesTxt = (r[12] ?? '').toString();
      return Response.ok(jsonEncode({
        'id': r[0],
        'client_id': r[1],
        'client_name': r[2],
        'season_id': r[3],
        'season_name': r[4],
        'model_date': r[5].toString(),
        'model_name': r[6],
        'marker_name': r[7],
        'length': _d(r[8]),
        'width': _d(r[9]),
        'util_percent': util,
        'util_percent_str': '${util.toStringAsFixed(2)}%',
        'placed': r[11],
        'sizes_text': sizesTxt,
        'sizes_slash': _slashify(sizesTxt),
        'price': _d(r[13]),
        'description': r[14],
        'image_url': r[15],
        'created_at': r[16]?.toString(),
      }), headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'db error', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // ====== CREATE ======
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
        final file = File('public/images/$fname');
        await file.create(recursive: true);
        await file.writeAsBytes(bytes);
        imageUrl = '/images/$fname';
      } else {
        fields[part.name] = await part.part.readString();
      }
    }

    try {
      final modelDate = DateTime.parse(fields['model_date']!);
      final newId = await db.transaction((tx) async {
        final seasonId = await _findSeasonIdByDate(tx, modelDate);
        final rs = await tx.query('''
          INSERT INTO design.models
            (client_id, season_id, model_date,
             model_name, marker_name, length, width,
             util_percent, placed, sizes_text, price,
             description, image_url)
          VALUES
            (@client, @season, @mdate,
             @mn, @mr, @l, @w,
             @u, @pl, @sizes, @price,
             @desc, @img)
          RETURNING id
        ''', substitutionValues: {
          'client': _i(fields['client_id']),
          'season': seasonId,
          'mdate': modelDate,
          'mn': fields['model_name'],
          'mr': fields['marker_name'],
          'l': _d(fields['length']),
          'w': _d(fields['width']),
          'u': _parsePercent(fields['util_percent']),
          'pl': (fields['placed'] ?? '').toString(),
          'sizes': (fields['sizes_text'] ?? '').toString(),
          'price': _d(fields['price']),
          'desc': fields['description'],
          'img': imageUrl ?? '',
        });
        return rs.first[0] as int;
      });

      return Response(201,
        body: jsonEncode({'id': newId}),
        headers: {'Content-Type': 'application/json'});
    } on PostgreSQLException catch (e) {
      if (e.code == '23505') {
        return Response(409,
          body: jsonEncode({
            'error': 'duplicate_name',
            'message': 'Model name already exists'
          }),
          headers: {'Content-Type': 'application/json'});
      }
      print('POST /design/models error: $e\n${e.stackTrace}');
      return Response.internalServerError(
        body: jsonEncode({'error': 'create failed', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'});
    }
  });

  // ====== UPDATE ======
  // ====== UPDATE ======
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

  // Delete old file if replaced/cleared
  if (newImageUrl != null || clearImage) {
    final oldRes = await db.query(
      'SELECT image_url FROM design.models WHERE id = @id',
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
    final updatedId = await db.transaction((tx) async {
      final seasonId = await _findSeasonIdByDate(tx, modelDate);
      final rows = await tx.query('''
        UPDATE design.models SET
          client_id    = @client,
          season_id    = @season,
          model_date   = @mdate,
          model_name   = @mn,
          marker_name  = @mr,
          length       = @l,
          width        = @w,
          util_percent = @u,
          placed       = @pl,
          sizes_text   = @sizes,
          price        = @price,
          description  = @desc,
          image_url    = @img
        WHERE id = @id
        RETURNING id
      ''', substitutionValues: {
        'id': int.parse(id),
        'client': _i(fields['client_id']),
        'season': seasonId,
        'mdate': modelDate,
        'mn': fields['model_name'],
        'mr': fields['marker_name'],
        'l': _d(fields['length']),
        'w': _d(fields['width']),
        'u': _parsePercent(fields['util_percent']),
        'pl': (fields['placed'] ?? '').toString(),
        'sizes': (fields['sizes_text'] ?? '').toString(),
        'price': _d(fields['price']),
        'desc': fields['description'],
        'img': clearImage ? '' : (newImageUrl ?? fields['image_url'] ?? ''),
      });
      if (rows.isEmpty) {
        throw Exception('No rows updated');
      }
      return rows.first[0] as int;
    });

    return Response.ok(
      jsonEncode({'id': updatedId}),
      headers: {'Content-Type': 'application/json'},
    );
  } on PostgreSQLException catch (e) {
    if (e.code == '23505') {
      return Response(409,
        body: jsonEncode({
          'error': 'duplicate_name',
          'message': 'Model name already exists'
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
    print('PUT /design/models error: $e\n${e.stackTrace}');
    return Response.internalServerError(
      body: jsonEncode({'error': 'update failed', 'details': e.toString()}),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e, st) {
    print('PUT /design/models error: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': 'update failed', 'details': e.toString()}),
      headers: {'Content-Type': 'application/json'},
    );
  }
});

  // ====== DELETE ======
  router.delete('/<id|[0-9]+>', (Request req, String id) async {
    try {
      final modelId = int.parse(id);

      // Delete stored image file if exists
      final imgRes = await db.query(
        'SELECT image_url FROM design.models WHERE id = @id',
        substitutionValues: {'id': modelId},
      );
      if (imgRes.isNotEmpty) {
        final imageUrl = imgRes.first[0] as String?;
        if (imageUrl != null && imageUrl.startsWith('/images/')) {
          final file = File('public${imageUrl}');
          if (await file.exists()) await file.delete();
        }
      }

      final count = await db.execute('DELETE FROM design.models WHERE id=@id',
        substitutionValues: {'id': modelId});
      if (count == 0) return Response.notFound(jsonEncode({'error': 'not found'}));
      return Response.ok(jsonEncode({'status': 'deleted'}),
        headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'delete failed', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'});
    }
  });

  // ====== HELP ENDPOINTS ======
  router.get('/clients', (Request req) async {
    try {
      final rows = await db.query(
        'SELECT id, full_name FROM design.clients ORDER BY full_name');
      final list = rows.map((r) => {'id': r[0], 'full_name': r[1]}).toList();
      return Response.ok(jsonEncode(list),
        headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'Content-Type': 'application/json'});
    }
  });

  router.get('/seasons', (Request req) async {
    try {
      final rows = await db.query(
        'SELECT id, name FROM design.seasons ORDER BY start_date DESC');
      final list = rows.map((r) => {'id': r[0], 'name': r[1]}).toList();
      return Response.ok(jsonEncode(list),
        headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'Content-Type': 'application/json'});
    }
  });

  return router;
}