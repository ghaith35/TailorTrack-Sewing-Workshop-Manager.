import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:postgres/postgres.dart';
import 'dart:convert';

Router getClientsRoutes(PostgreSQLConnection db) {
  final router = Router();

  // GET /clients/
  router.get('/', (Request request) async {
    try {
      final result = await db.mappedResultsQuery(
        'SELECT id, full_name, phone, address FROM sewing.clients ORDER BY id DESC'
      );
      final clients = result.map((row) => row['clients']).toList();
      return Response.ok(jsonEncode(clients), headers: {'Content-Type': 'application/json'});
    } catch (e) {
      print('Error fetching clients: $e'); // Log the error to the console
      return Response.internalServerError(
        body: jsonEncode({'error': 'Database error', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // POST /clients/
  router.post('/', (Request request) async {
    try {
      final body = jsonDecode(await request.readAsString());
      await db.query(
        'INSERT INTO sewing.clients (full_name, phone, address) VALUES (@name, @phone, @address)',
        substitutionValues: {
          'name': body['full_name'],
          'phone': body['phone'],
          'address': body['address'],
        },
      );
return Response(
  201,
  body: jsonEncode({'status': 'created'}),
  headers: {'Content-Type': 'application/json'},
);    } catch (e) {
      print('Error saving client: $e'); // Log the error to the console
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to create client', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // PUT /clients/:id
  router.put('/<id|[0-9]+>', (Request request, String id) async {
    try {
      final body = jsonDecode(await request.readAsString());
      await db.query(
        'UPDATE sewing.clients SET full_name = @name, phone = @phone, address = @address WHERE id = @id',
        substitutionValues: {
          'id': int.parse(id),
          'name': body['full_name'],
          'phone': body['phone'],
          'address': body['address'],
        },
      );
      return Response.ok(jsonEncode({'status': 'updated'}));
    } catch (e) {
      print('Error updating client: $e'); // Log the error to the console
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to update client', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // DELETE /clients/:id
  router.delete('/<id|[0-9]+>', (Request request, String id) async {
    final cid = int.parse(id);
    try {
      await db.transaction((txn) async {
        // 1) delete all invoices for that client
        await txn.query(
          'DELETE FROM sewing.factures WHERE client_id = @cid',
          substitutionValues: {'cid': cid},
        );
        // 2) now delete the client
        await txn.query(
          'DELETE FROM sewing.clients WHERE id = @cid',
          substitutionValues: {'cid': cid},
        );
      });
      return Response.ok(
        jsonEncode({'status': 'deleted'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      print('Error deleting client: $e'); // Log the error to the console
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
