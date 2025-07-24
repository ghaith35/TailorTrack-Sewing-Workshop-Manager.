import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:postgres/postgres.dart';

Router getDesignClientsRoutes(PostgreSQLConnection db) {
  final router = Router();

  // GET /design/clients/
  router.get('/', (Request request) async {
    try {
      final result = await db.mappedResultsQuery(
        'SELECT id, full_name, phone, address FROM design.clients ORDER BY id DESC'
      );
      final clients = result.map((row) => row['clients']).toList();
      return Response.ok(jsonEncode(clients),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Database error', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // POST /design/clients/
  router.post('/', (Request request) async {
    try {
      final body = jsonDecode(await request.readAsString());
      await db.query(
        '''
        INSERT INTO design.clients (full_name, phone, address)
        VALUES (@name, @phone, @address)
        ''',
        substitutionValues: {
          'name': body['full_name'],
          'phone': body['phone'],
          'address': body['address'],
        },
      );
      return Response(201,
          body: jsonEncode({'status': 'created'}),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to create client', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // PUT /design/clients/:id
  router.put('/<id|[0-9]+>', (Request request, String id) async {
    try {
      final body = jsonDecode(await request.readAsString());
      final updated = await db.execute(
        '''
        UPDATE design.clients
        SET full_name=@name, phone=@phone, address=@address
        WHERE id=@id
        ''',
        substitutionValues: {
          'id': int.parse(id),
          'name': body['full_name'],
          'phone': body['phone'],
          'address': body['address'],
        },
      );
      if (updated == 0) {
        return Response.notFound(jsonEncode({'error': 'Client not found'}));
      }
      return Response.ok(jsonEncode({'status': 'updated'}),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to update client', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // DELETE /design/clients/:id
  // إذا حبيت تحذف فواتير العميل أولاً (كما في الخياطة) خليه داخل transaction:
  router.delete('/<id|[0-9]+>', (Request request, String id) async {
    final cid = int.parse(id);
    try {
      await db.transaction((txn) async {
        await txn.query('DELETE FROM design.factures WHERE client_id=@cid', substitutionValues: {'cid': cid});
        await txn.query('DELETE FROM design.clients  WHERE id=@cid',     substitutionValues: {'cid': cid});
      });
      return Response.ok(jsonEncode({'status': 'deleted'}),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to delete client and related data', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  return router;
}
