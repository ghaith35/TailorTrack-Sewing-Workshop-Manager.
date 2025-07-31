import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:postgres/postgres.dart';
import 'dart:convert';

Router getEmbrodryClientsRoutes(PostgreSQLConnection db) {
  final router = Router();

  // GET /embrodry/clients/
  router.get('/', (Request request) async {
    try {
      final result = await db.mappedResultsQuery(
        'SELECT id, full_name, phone, address FROM embroidery.clients ORDER BY id DESC'
      );
      final clients = result.map((row) => row['clients']).toList();
      return Response.ok(
        jsonEncode(clients),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Database error', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // POST /embrodry/clients/
  router.post('/', (Request request) async {
    final body = jsonDecode(await request.readAsString());
    try {
      await db.query(
        'INSERT INTO embroidery.clients (full_name, phone, address) '
        'VALUES (@name, @phone, @address)',
        substitutionValues: {
          'name': body['full_name'],
          'phone': body['phone'],
          'address': body['address'],
        },
      );
      return Response.ok(
        jsonEncode({'status': 'created'}),
        headers: {'Content-Type': 'application/json'},
      );
    } on PostgreSQLException catch (e) {
      // Handle duplicate-phone error
      if (e.code == '23505' && e.constraintName == 'clients_phone_key') {
        return Response(
          409,
          body: jsonEncode({'error': 'رقم الهاتف موجود بالفعل'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      // Other DB errors
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

  // PUT /embrodry/clients/:id
  router.put('/<id|[0-9]+>', (Request request, String id) async {
    final body = jsonDecode(await request.readAsString());
    try {
      await db.query(
        'UPDATE embroidery.clients '
        'SET full_name = @name, phone = @phone, address = @address '
        'WHERE id = @id',
        substitutionValues: {
          'id': int.parse(id),
          'name': body['full_name'],
          'phone': body['phone'],
          'address': body['address'],
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

  // DELETE /embrodry/clients/:id
  router.delete('/<id|[0-9]+>', (Request request, String id) async {
    final cid = int.parse(id);
    try {
      await db.transaction((txn) async {
        await txn.query(
          'DELETE FROM embroidery.factures WHERE client_id = @cid',
          substitutionValues: {'cid': cid},
        );
        await txn.query(
          'DELETE FROM embroidery.clients WHERE id = @cid',
          substitutionValues: {'cid': cid},
        );
      });
      return Response.ok(
        jsonEncode({'status': 'deleted'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({
          'error': 'Failed to delete client and related data',
          'details': e.toString(),
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  return router;
}
