import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:postgres/postgres.dart';

Router getDesignSuppliersRoutes(PostgreSQLConnection db) {
  final router = Router();

  // GET /design/suppliers/
  router.get('/', (Request request) async {
    try {
      final result = await db.mappedResultsQuery(
        'SELECT id, full_name, phone, address, company_name FROM design.suppliers ORDER BY id DESC'
      );
      final suppliers = result.map((row) => row['suppliers']).toList();
      return Response.ok(jsonEncode(suppliers),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Database error', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // POST /design/suppliers/
  router.post('/', (Request request) async {
    try {
      final body = jsonDecode(await request.readAsString());
      await db.query(
        '''
        INSERT INTO design.suppliers (full_name, phone, address, company_name)
        VALUES (@name, @phone, @address, @company)
        ''',
        substitutionValues: {
          'name': body['full_name'],
          'phone': body['phone'],
          'address': body['address'],
          'company': body['company_name'],
        },
      );
      return Response(201,
          body: jsonEncode({'status': 'created'}),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to create supplier', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // PUT /design/suppliers/:id
  router.put('/<id|[0-9]+>', (Request request, String id) async {
    try {
      final body = jsonDecode(await request.readAsString());
      final updated = await db.execute(
        '''
        UPDATE design.suppliers
        SET full_name = @name, phone = @phone, address = @address, company_name = @company
        WHERE id = @id
        ''',
        substitutionValues: {
          'id': int.parse(id),
          'name': body['full_name'],
          'phone': body['phone'],
          'address': body['address'],
          'company': body['company_name'],
        },
      );
      if (updated == 0) {
        return Response.notFound(jsonEncode({'error': 'Supplier not found'}));
      }
      return Response.ok(jsonEncode({'status': 'updated'}),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to update supplier', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // DELETE /design/suppliers/:id
  router.delete('/<id|[0-9]+>', (Request request, String id) async {
    try {
      final deleted = await db.execute(
        'DELETE FROM design.suppliers WHERE id = @id',
        substitutionValues: {'id': int.parse(id)},
      );
      if (deleted == 0) {
        return Response.notFound(jsonEncode({'error': 'Supplier not found'}));
      }
      return Response.ok(jsonEncode({'status': 'deleted'}),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to delete supplier', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  return router;
}
