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
  'localhost', 5432, 'osama',
  username: 'postgres',
  password: 'ghaith\$',
);

// CORS
Middleware corsHeaders() => (Handler h) {
  return (Request r) async {
    if (r.method == 'OPTIONS') {
      return Response.ok('', headers: _cors);
    }
    final resp = await h(r);
    return resp.change(headers: {...resp.headers, ..._cors});
  };
};
const _cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type,Authorization',
};

// JWT verification
Middleware verifyJwt(String secret) => (inner) {
  return (Request req) async {
    final auth = req.headers['authorization'];
    if (auth == null || !auth.startsWith('Bearer ')) {
      return Response.forbidden(jsonEncode({'error': 'Missing token'}));
    }
    try {
      final token = auth.substring(7);
      final jwt = JWT.verify(token, SecretKey(secret));
      return await inner(req.change(context: {
        'userId': jwt.payload['id'],
        'role': jwt.payload['role'],
      }));
    } on JWTException catch (e) {
      return Response.forbidden(jsonEncode({'error': e.message}));
    }
  };
};

// Admin-only guard
Middleware onlyAdmin() => (inner) {
  return (Request req) {
    final role = req.context['role'];
    if (role != 'Admin' && role != 'SuperAdmin') {
      return Response.forbidden(jsonEncode({'error': 'Admin only'}));
    }
    return inner(req);
  };
};

// Public auth routes
Router authRouter(String superPin, String jwtSecret) {
  final router = Router();

  router.post('/login', (Request req) async {
    final body = jsonDecode(await req.readAsString());
    final username = body['username'] as String? ?? '';
    final password = body['password'] as String? ?? '';

    final rows = await db.query(
      'SELECT id, password_hash, role, is_active FROM public.users WHERE username=@u',
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
    final token = jwt.sign(
      SecretKey(jwtSecret),
      expiresIn: const Duration(hours: 8),
    );
    return Response.ok(
      jsonEncode({'token': token, 'role': row[2]}),
      headers: {'Content-Type': 'application/json'},
    );
  });

  router.post('/restore', (Request req) async {
    final body = jsonDecode(await req.readAsString());
    if (body['superPin'] != superPin) {
      return Response.forbidden(jsonEncode({'error': 'Invalid superPin'}));
    }
    final jwt = JWT({'role': 'SuperAdmin'}, issuer: 'lan-erp');
    final token = jwt.sign(
      SecretKey(jwtSecret),
      expiresIn: const Duration(minutes: 30),
    );
    return Response.ok(
      jsonEncode({'token': token, 'role': 'SuperAdmin'}),
      headers: {'Content-Type': 'application/json'},
    );
  });

  return router;
}

// Admin user-management routes
Router adminRouter(PostgreSQLConnection db, String superPin) {
  final router = Router();

  // 1️⃣ List users
  router.get('/users', (Request req) async {
    final rolesParam = req.url.queryParameters['roles'];
    final sql = rolesParam != null
        ? 'SELECT id,username,role,is_active,created_at,updated_at FROM public.users WHERE role = ANY(@roles)'
        : 'SELECT id,username,role,is_active,created_at,updated_at FROM public.users';
    final subs = rolesParam != null
        ? {'roles': rolesParam.split(',')}
        : <String, dynamic>{};

    final mapped = await db.mappedResultsQuery(sql, substitutionValues: subs);
    final users = mapped.map((row) {
      final u = row['users']!;
      return {
        'id': u['id'],
        'username': u['username'],
        'role': u['role'],
        'is_active': u['is_active'],
        'created_at': u['created_at']?.toString(),
        'updated_at': u['updated_at']?.toString(),
      };
    }).toList();
    return Response.ok(jsonEncode(users), headers: {'Content-Type': 'application/json'});
  });

  // helper to enforce Admin vs SuperAdmin
  bool canManage(Request req, String targetRole) {
    final me = req.context['role'] as String;
    if (me == 'SuperAdmin') return true;
    // Admin can only manage Manager & Accountant
    return (targetRole == 'Manager' || targetRole == 'Accountant');
  }

  // 2️⃣ Create user
  router.post('/users', (Request req) async {
    final body = jsonDecode(await req.readAsString());
    final me = req.context['role'] as String;
    final targetRole = body['role'] as String;
    if (me == 'Admin' && !canManage(req, targetRole)) {
      return Response.forbidden(jsonEncode({'error': 'Cannot create users with that role'}));
    }
    final username = body['username'] as String;
    final rawPass = body['initialPassword'] as String;
    final hash = BCrypt.hashpw(rawPass, BCrypt.gensalt());
    await db.query(
      'INSERT INTO public.users (username,password_hash,role) VALUES (@u,@h,@r)',
      substitutionValues: {'u': username, 'h': hash, 'r': targetRole},
    );
    return Response.ok(jsonEncode({'status': 'created'}), headers: {'Content-Type': 'application/json'});
  });

  // 3️⃣ Reset password
  router.post('/users/<id>/reset-password', (Request req, String id) async {
    final body = jsonDecode(await req.readAsString());
    final newPass = body['newPassword'] as String;
    // fetch target's role
    final rows = await db.query(
      'SELECT role FROM public.users WHERE id=@i',
      substitutionValues: {'i': int.parse(id)},
    );
    if (rows.isEmpty) return Response.notFound(jsonEncode({'error': 'Not found'}));
    final targetRole = rows.first[0] as String;
    if (!canManage(req, targetRole)) {
      return Response.forbidden(jsonEncode({'error': 'Cannot reset password for that role'}));
    }
    final hash = BCrypt.hashpw(newPass, BCrypt.gensalt());
    await db.query(
      'UPDATE public.users SET password_hash=@h, updated_at=NOW() WHERE id=@i',
      substitutionValues: {'h': hash, 'i': int.parse(id)},
    );
    return Response.ok(jsonEncode({'status': 'password reset'}), headers: {'Content-Type': 'application/json'});
  });

  // 4️⃣ Hard-delete user
  router.delete('/users/<id>', (Request req, String id) async {
    final rows = await db.query(
      'SELECT role FROM public.users WHERE id=@i',
      substitutionValues: {'i': int.parse(id)},
    );
    if (rows.isEmpty) return Response.notFound(jsonEncode({'error': 'Not found'}));
    final targetRole = rows.first[0] as String;
    if (!canManage(req, targetRole)) {
      return Response.forbidden(jsonEncode({'error': 'Cannot delete that role'}));
    }
    await db.query('DELETE FROM public.users WHERE id=@i',
      substitutionValues: {'i': int.parse(id)},
    );
    return Response.ok(jsonEncode({'status': 'deleted'}), headers: {'Content-Type': 'application/json'});
  });

  return router;
}

Future<void> main() async {
  const jwtSecret = 'ghaith\$';
  const superPin = 'ghaith\$';

  await db.open();
  print('✅ Database connected');

  final router = Router();

  // 1️⃣ Admin routes first (protected)
  router.mount(
    '/auth/admin/',
    Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware(corsHeaders())
        .addMiddleware(verifyJwt(jwtSecret))
        .addMiddleware(onlyAdmin())
        .addHandler(adminRouter(db, superPin)),
  );

  // 2️⃣ Public auth
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
