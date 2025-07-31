import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:postgres/postgres.dart';
import 'dart:convert';

Router getEmbrodrySuppliersRoutes(PostgreSQLConnection db) {
  final router = Router();

  // GET /embrodry/suppliers/
  router.get('/', (Request request) async {
    try {
      final result = await db.mappedResultsQuery(
        'SELECT id, full_name, phone, address, company_name '
        'FROM embroidery.suppliers ORDER BY id DESC'
      );
      final suppliers = result.map((row) => row['suppliers']).toList();
      return Response.ok(
        jsonEncode(suppliers),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Database error', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // POST /embrodry/suppliers/
  router.post('/', (Request request) async {
    final body = jsonDecode(await request.readAsString());
    try {
      await db.query(
        'INSERT INTO embroidery.suppliers '
        '(full_name, phone, address, company_name) '
        'VALUES (@name, @phone, @address, @company)',
        substitutionValues: {
          'name':    body['full_name'],
          'phone':   body['phone'],
          'address': body['address'],
          'company': body['company_name'],
        },
      );
      return Response.ok(
        jsonEncode({'status': 'created'}),
        headers: {'Content-Type': 'application/json'},
      );
    } on PostgreSQLException catch (e) {
      if (e.code == '23505' && e.constraintName == 'suppliers_phone_key') {
        return Response(
          409,
          body: jsonEncode({'error': 'رقم الهاتف موجود بالفعل'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      return Response.internalServerError(
        body: jsonEncode({'error': 'Database error', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Unexpected error', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // PUT /embrodry/suppliers/:id
  router.put('/<id|[0-9]+>', (Request request, String id) async {
    final body = jsonDecode(await request.readAsString());
    try {
      await db.query(
        'UPDATE embroidery.suppliers '
        'SET full_name = @name, phone = @phone, address = @address, '
        'company_name = @company WHERE id = @id',
        substitutionValues: {
          'id':      int.parse(id),
          'name':    body['full_name'],
          'phone':   body['phone'],
          'address': body['address'],
          'company': body['company_name'],
        },
      );
      return Response.ok(
        jsonEncode({'status': 'updated'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Database error', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // DELETE /embrodry/suppliers/:id
  router.delete('/<id|[0-9]+>', (Request request, String id) async {
    try {
      await db.query(
        'DELETE FROM embroidery.suppliers WHERE id = @id',
        substitutionValues: {'id': int.parse(id)},
      );
      return Response.ok(
        jsonEncode({'status': 'deleted'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to delete supplier', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  return router;
}
