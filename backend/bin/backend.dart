import 'dart:io';
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:postgres/postgres.dart';
import 'package:bcrypt/bcrypt.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

// Domain route imports
import 'routes/clients_api.dart';
import 'routes/warehouse_api.dart';
import 'routes/employees_api.dart';
import 'routes/purchases_api.dart';
import 'routes/models_api.dart';
import 'routes/sales_api.dart';
import 'routes/season_api.dart';
import 'routes/expenses_api.dart';
import 'routes/suppliers_api.dart';
import 'routes/debts_api.dart';
import 'routes/returns_routes.dart';

import 'routes_design/clients_design_api.dart';
import 'routes_design/suppliers_design_api.dart';
import 'routes_design/warehouse_design_api.dart';
import 'routes_design/models_design_api.dart';
import 'routes_design/purchases_design_api.dart';
import 'routes_design/sales_design_api.dart';
import 'routes_design/season_design_api.dart';
import 'routes_design/expenses_design_api.dart';
import 'routes_design/debts_design_api.dart';

import 'routes_embrodry/clients_embrodry_api.dart';
import 'routes_embrodry/warehouse_embrodry_api.dart';
import 'routes_embrodry/employees_embrodry_api.dart';
import 'routes_embrodry/purchases_embrodry_api.dart';
import 'routes_embrodry/models_embrodry_api.dart';
import 'routes_embrodry/sales_embrodry_api.dart';
import 'routes_embrodry/season_embrodry_api.dart';
import 'routes_embrodry/expenses_embrodry_api.dart';
import 'routes_embrodry/suppliers_embrodry_api.dart';
import 'routes_embrodry/debts_embrodry_api.dart';
import 'routes_embrodry/returns_embrodry_api.dart';

// PostgreSQL connection
final db = PostgreSQLConnection(
  'localhost',
  5432,
  'osama',
  username: 'postgres',
  password: 'ghaith\$',
);

// CORS middleware
Middleware corsHeaders() {
  return (Handler handler) {
    return (Request request) async {
      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: _corsHeaders);
      }
      final response = await handler(request);
      return response.change(headers: {
        ...response.headers,
        ..._corsHeaders,
      });
    };
  };
}

const _corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Origin, Content-Type, Accept, Authorization',
};

// JWT verification middleware factory
Middleware verifyJwt(String jwtSecret) {
  return (Handler inner) {
    return (Request req) async {
      final auth = req.headers['authorization'];
      if (auth == null || !auth.startsWith('Bearer ')) {
        return Response.forbidden(jsonEncode({'error': 'Missing token'}));
      }
      final token = auth.substring(7);
      try {
        final jwt = JWT.verify(token, SecretKey(jwtSecret));
        return await inner(req.change(context: {
          'userId': jwt.payload['id'],
          'role': jwt.payload['role'],
        }));
      } on JWTExpiredException {
        return Response.forbidden(jsonEncode({'error': 'Token expired'}));
      } on JWTException {
        return Response.forbidden(jsonEncode({'error': 'Invalid token'}));
      }
    };
  };
}

// Admin-only guard
Middleware onlyAdmin() {
  return (Handler inner) {
    return (Request req) {
      final role = req.context['role'] as String?;
      if (role != 'Admin' && role != 'SuperAdmin') {
        return Response.forbidden(jsonEncode({'error': 'Admin only'}));
      }
      return inner(req);
    };
  };
}

// Auth routes (login + restore)
Router authRouter(String superPin, String jwtSecret) {
  final router = Router();

  // POST /auth/login
  router.post('/login', (Request req) async {
    final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    final username = body['username'] as String? ?? '';
    final password = body['password'] as String? ?? '';

    final rows = await db.query(
      'SELECT id, password_hash, role, is_active FROM public.users WHERE username = @u',
      substitutionValues: {'u': username},
    );
    if (rows.isEmpty) {
      return Response.forbidden(jsonEncode({'error': 'Invalid credentials'}));
    }
    final row = rows.first;
    if (!(row[3] as bool)) {
      return Response.forbidden(jsonEncode({'error': 'Inactive account'}));
    }
    if (!BCrypt.checkpw(password, row[1] as String)) {
      return Response.forbidden(jsonEncode({'error': 'Invalid credentials'}));
    }

    final jwt = JWT({'id': row[0], 'role': row[2]}, issuer: 'lan-erp');
    final token = jwt.sign(SecretKey(jwtSecret), expiresIn: const Duration(hours: 8));

    return Response.ok(
      jsonEncode({'token': token, 'role': row[2]}),
      headers: {'Content-Type': 'application/json'},
    );
  });

  // POST /auth/restore
  router.post('/restore', (Request req) async {
    final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    if (body['superPin'] != superPin) {
      return Response.forbidden(jsonEncode({'error': 'Invalid superPin'}));
    }
    final jwt = JWT({'role': 'SuperAdmin'}, issuer: 'lan-erp');
    final token = jwt.sign(SecretKey(jwtSecret), expiresIn: const Duration(minutes: 30));
    return Response.ok(
      jsonEncode({'token': token, 'role': 'SuperAdmin'}),
      headers: {'Content-Type': 'application/json'},
    );
  });

  return router;
}

// Admin user-management routes (create, list, update, reset, delete)
Router adminRouter(PostgreSQLConnection db, { required String superPin }) {
  final router = Router();

  // 1️⃣ List users (optionally by roles)
  router.get('/users', (Request req) async {
    final rolesParam = req.url.queryParameters['roles'];
    final sql = rolesParam != null
        ? '''SELECT id,username,role,is_active,created_at,updated_at
             FROM public.users WHERE role = ANY(@roles)'''
        : '''SELECT id,username,role,is_active,created_at,updated_at
             FROM public.users''';
    final subs = rolesParam != null ? {'roles': rolesParam.split(',')} : <String, dynamic>{};

    final mapped = await db.mappedResultsQuery(sql, substitutionValues: subs);
    final users = mapped.map((row) {
      final u = row['users']!;
      return {
        'id'         : u['id'],
        'username'   : u['username'],
        'role'       : u['role'],
        'is_active'  : u['is_active'],
        'created_at' : u['created_at']?.toString(),
        'updated_at' : u['updated_at']?.toString(),
      };
    }).toList();

    return Response.ok(jsonEncode(users), headers: {'Content-Type':'application/json'});
  });

  // 2️⃣ Create user
  router.post('/users', (Request req) async {
    final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    final hash = BCrypt.hashpw(body['initialPassword'] as String, BCrypt.gensalt());
    await db.query(
      'INSERT INTO public.users (username,password_hash,role) VALUES (@u,@h,@r)',
      substitutionValues: {
        'u': body['username'],
        'h': hash,
        'r': body['role'],
      },
    );
    return Response.ok(jsonEncode({'status':'created'}), headers: {'Content-Type':'application/json'});
  });

  // 3️⃣ Update user
  router.put('/users/<id>', (Request req, String id) async {
    final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    final updates = <String>[];
    final subs = <String, dynamic>{ 'id': int.parse(id) };
    if (body.containsKey('username')) {
      updates.add('username=@u'); subs['u'] = body['username'];
    }
    if (body.containsKey('role')) {
      updates.add('role=@r'); subs['r'] = body['role'];
    }
    if (body.containsKey('isActive')) {
      updates.add('is_active=@ia'); subs['ia'] = body['isActive'];
    }
    if (updates.isEmpty) {
      return Response.badRequest(
        body: jsonEncode({'error':'Nothing to update'}),
        headers: {'Content-Type':'application/json'},
      );
    }
    final sql = '''
      UPDATE public.users
         SET ${updates.join(',')}, updated_at=NOW()
       WHERE id=@id
    ''';
    await db.query(sql, substitutionValues: subs);
    return Response.ok(jsonEncode({'status':'updated'}), headers: {'Content-Type':'application/json'});
  });

  // 4️⃣ Reset password
  router.post('/users/<id>/reset-password', (Request req, String id) async {
    final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    final hash = BCrypt.hashpw(body['newPassword'] as String, BCrypt.gensalt());
    await db.query(
      '''UPDATE public.users
            SET password_hash=@h, updated_at=NOW()
          WHERE id=@id''',
      substitutionValues: { 'h': hash, 'id': int.parse(id) },
    );
    return Response.ok(jsonEncode({'status':'password reset'}), headers: {'Content-Type':'application/json'});
  });

  // 5️⃣ Soft-delete (deactivate)
  router.delete('/users/<id>', (Request req, String id) async {
    final userId = int.parse(id);
    // Actually remove the row:
    final result = await db.execute(
      'DELETE FROM public.users WHERE id = @id',
      substitutionValues: {'id': userId},
    );
    // result is number of rows affected; if 0, no such user existed
    if (result == 0) {
      return Response.notFound(
        jsonEncode({'error': 'User not found'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    return Response.ok(
      jsonEncode({'status': 'deleted'}),
      headers: {'Content-Type': 'application/json'},
    );
  });
  return router;
}

Future<void> main() async {
  const jwtSecret = 'ghaith\$';
  const superPin  = 'ghaith\$';

  await db.open();
  print('✅ Database connected');

  final router = Router();

  // 1️⃣ Mount admin routes *first*
  router.mount(
    '/auth/admin/',
    Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(corsHeaders())
      .addMiddleware(verifyJwt(jwtSecret))
      .addMiddleware(onlyAdmin())
      .addHandler(adminRouter(db, superPin: superPin)),
  );

  // 2️⃣ Then mount public auth routes
  router.mount(
    '/auth/',
    Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(corsHeaders())
      .addHandler(authRouter(superPin, jwtSecret)),
  );
    router.mount('/clients/',   getClientsRoutes(db));
  router.mount('/sewing/',    getWarehouseRoutes(db));
  router.mount('/employees/', getEmployeesRoutes(db));
  router.mount('/purchases/', getPurchasesRoutes(db));
  router.mount('/purchases', getPurchasesRoutes(db));

  router.mount('/models/',    getModelsRoutes(db));
  router.mount('/sales/',     getSalesRoutes(db));
  router.mount('/seasons',    getSeasonRoutes(db));
  router.mount('/expenses/',  getExpensesRoutes(db));
  router.mount('/suppliers/', getSuppliersRoutes(db));
  router.mount('/debts/',     getDebtsRoutes(db));
  router.mount('/returns/',   getReturnsRoutes(db));

  // ── NEW design mounts (each tab = separate file) ────────
  router.mount('/design/clients/',    getDesignClientsRoutes(db));
  router.mount('/design/clients',    getDesignClientsRoutes(db));

  router.mount('/design/suppliers/',  getDesignSuppliersRoutes(db));
  router.mount('/design/warehouse/', getDesignWarehouseRoutes(db));
  router.mount('/design/models/',     getDesignModelsRoutes(db));
  router.mount('/design/purchases/',  getDesignPurchasesRoutes(db));
  router.mount('/design/sales/',      getDesignSalesRoutes(db));
  router.mount('/design/seasons/',    getDesignSeasonRoutes(db));
  router.mount('/design/expenses/',   getDesignExpensesRoutes(db));
  router.mount('/design/debts/',      getDesignDebtsRoutes(db));
  // router.mount('/design/returns/',    getDesignReturnsRoutes(db));
  router.mount('/design/sales',      getDesignSalesRoutes(db));
  router.mount('/design/purchases',  getDesignPurchasesRoutes(db));

  router.mount('/design/seasons',    getDesignSeasonRoutes(db));
  router.mount('/design/warehouse',  getDesignWarehouseRoutes(db));
  router.mount('/design/models', getDesignModelsRoutes(db));
  router.mount('/design/debts',      getDesignDebtsRoutes(db));
  // router.mount('/design/returns',    getDesignReturnsRoutes(db));
  router.mount('/design/expenses',   getDesignExpensesRoutes(db));

  router.mount('/embrodry/clients/',    getEmbrodryClientsRoutes(db));
  router.mount('/embrodry/warehouse/',  getEmbrodryWarehouseRoutes(db));
  router.mount('/embrodry/employees/',  getEmbrodryEmployeesRoutes(db));
  router.mount('/embrodry/purchases/',  getEmbrodryPurchasesRoutes(db));
  router.mount('/embrodry/models/',     getEmbrodryModelsRoutes(db));
  router.mount('/embrodry/sales/',      getEmbroiderySalesRoutes(db));
  router.mount('/embrodry/seasons/',    getEmbrodrySeasonRoutes(db));
  router.mount('/embrodry/expenses/',   getEmbrodryExpensesRoutes(db));
  router.mount('/embrodry/suppliers/',  getEmbrodrySuppliersRoutes(db));
  router.mount('/embrodry/debts/',      getEmbrodryDebtsRoutes(db));
  router.mount('/embrodry/returns/',    getEmbrodryReturnsRoutes(db));
  router.mount('/embrodry/seasons',    getEmbrodrySeasonRoutes(db));
  router.mount('/embrodry/expenses',   getEmbrodryExpensesRoutes(db));
  router.mount('/embrodry/purchases',  getEmbrodryPurchasesRoutes(db));
  router.mount('/embrodry/debts',      getEmbrodryDebtsRoutes(db));
  router.mount('/embrodry/models',     getEmbrodryModelsRoutes(db));
  router.mount('/embrodry/returns',    getEmbrodryReturnsRoutes(db));
  router.mount('/embrodry/sales',      getEmbroiderySalesRoutes(db));
  router.mount('/embroidery-employees',  getEmbrodryEmployeesRoutes(db));

  router.mount('/embrodry/warehouse',  getEmbrodryWarehouseRoutes(db));

  final handler = Pipeline()
    .addMiddleware(logRequests())
    .addMiddleware(corsHeaders())
    .addHandler(router);

  final server = await serve(handler, InternetAddress.anyIPv4, 8888);
  print('✅ Server running on port ${server.port}');
}
