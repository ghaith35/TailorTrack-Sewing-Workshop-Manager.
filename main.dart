import 'dart:io';
import 'dart:convert';
import 'dart:async';
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
import 'dart:io';  // makes HttpConnectionInfo available

// Server discovery functionality
typedef _Timer = Timer;
class ServerDiscovery {
  static RawDatagramSocket? _socket;
  static _Timer?           _broadcastTimer;

  /// Pass in the port your HTTP server actually bound to.
  static Future<void> startBroadcast(int serverPort) async {
    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _socket!.broadcastEnabled = true;
      final broadcast = InternetAddress('255.255.255.255');

      _broadcastTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        final message = 'SEWING_SERVER:$serverPort:${DateTime.now().millisecondsSinceEpoch}';
        _socket?.send(message.codeUnits, broadcast, 9999);
      });

      print('🎯 Server discovery broadcast started, announcing port \$serverPort');
    } catch (e) {
      print('❌ Failed to start server discovery: \$e');
    }
  }

  static void stopBroadcast() {
    _broadcastTimer?.cancel();
    _socket?.close();
    print('🛑 Server discovery broadcast stopped');
  }
}

// Get local IP address (async)
Future<String> getLocalIPAddress() async {
  try {
    for (var interface in await NetworkInterface.list()) {
      for (var addr in interface.addresses) {
        if (addr.type == InternetAddressType.IPv4 &&
            !addr.isLoopback &&
            !addr.address.startsWith('169.254')) {
          return addr.address;
        }
      }
    }
  } catch (e) {
    print('Error getting local IP: \$e');
  }
  return 'localhost';
}

// Enhanced PostgreSQL connection with environment variables
final db = PostgreSQLConnection(
  Platform.environment['DB_HOST'] ?? 'localhost',
  int.parse(Platform.environment['DB_PORT'] ?? '5432'),
  Platform.environment['DB_NAME'] ?? 'osama',
  username: Platform.environment['DB_USER'] ?? 'postgres',
  password: Platform.environment['DB_PASS'] ?? 'ghaith\$',
);

// Security headers middleware
Middleware securityHeaders() {
  return (Handler handler) {
    return (Request request) async {
      final response = await handler(request);
      return response.change(headers: {
        ...response.headers,
        'X-Content-Type-Options': 'nosniff',
        'X-Frame-Options': 'DENY',
        'X-XSS-Protection': '1; mode=block',
        'Strict-Transport-Security': 'max-age=31536000; includeSubDomains',
        'Referrer-Policy': 'strict-origin-when-cross-origin',
      });
    };
  };
}

// Rate limiting middleware
Map<String, List<DateTime>> _requestLog = {};
Middleware rateLimit({int maxRequests = 100, Duration window = const Duration(minutes: 1)}) {
  return (Handler handler) {
    return (Request request) async {
      final connInfo = request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
      final clientIP = connInfo?.remoteAddress.address ?? 'unknown';
      final now = DateTime.now();

      _requestLog[clientIP] ??= [];
      _requestLog[clientIP]!.removeWhere((t) => now.difference(t) > window);
      if (_requestLog[clientIP]!.length >= maxRequests) {
        return Response(429, body: jsonEncode({'error': 'Rate limit exceeded'}));
      }
      _requestLog[clientIP]!.add(now);
      return await handler(request);
    };
  };
}

// CORS middleware
typedef _Headers = Map<String, String>;
const _corsHeaders = <String,String>{
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Origin, Content-Type, Accept, Authorization, X-Requested-With',
  'Access-Control-Max-Age': '86400',
};
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

// JWT verification middleware
Middleware verifyJwt(String jwtSecret) {
  return (Handler inner) {
    return (Request req) async {
      final auth = req.headers['authorization'];
      if (auth == null || !auth.startsWith('Bearer ')) {
        return Response.forbidden(jsonEncode({'error': 'Missing or invalid token format'}));
      }
      final token = auth.substring(7);
      try {
        final jwt = JWT.verify(token, SecretKey(jwtSecret));
        return inner(req.change(context: {
          'userId': jwt.payload['id'],
          'role': jwt.payload['role'],
          'tokenIat': jwt.payload['iat'],
        }));
      } on JWTExpiredException {
        return Response.forbidden(jsonEncode({'error': 'Token expired', 'code': 'TOKEN_EXPIRED'}));
      } on JWTException catch (e) {
        return Response.forbidden(jsonEncode({'error': 'Invalid token', 'details': e.message}));
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
        return Response.forbidden(jsonEncode({'error': 'Admin privileges required'}));
      }
      return inner(req);
    };
  };
}

// Health check
Router healthRouter() {
  final router = Router();

  router.get('/health', (Request req) async {
    try {
      await db.query('SELECT 1');
      return Response.ok(jsonEncode({
        'status': 'healthy',
        'timestamp': DateTime.now().toIso8601String(),
        'server': 'Sewing Management System',
        'version': '1.0.0',
        'database': 'connected'
      }), headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({
          'status': 'unhealthy',
          'error': 'Database connection failed',
          'timestamp': DateTime.now().toIso8601String()
        }),
        headers: {'Content-Type':'application/json'}
      );
    }
  });

  router.get('/info', (Request req) async {
    final localIP = await getLocalIPAddress();
    // serverPort will be captured below in main()
    return Response.ok(jsonEncode({
      'server_ip': localIP,
      'server_port': _infoPort,
      'server_name': 'Sewing Management System',
      'lan_address': 'http://\$localIP:\$_infoPort',
      'timestamp': DateTime.now().toIso8601String()
    }), headers: {'Content-Type':'application/json'});
  });

  return router;
}

// Placeholder for dynamic infoPort; will be set in main()
int _infoPort = 0;

/
// Enhanced auth routes
Router authRouter(String superPin, String jwtSecret) {
  final router = Router();

  // Enhanced login with better error handling
  router.post('/login', (Request req) async {
    try {
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final username = body['username'] as String? ?? '';
      final password = body['password'] as String? ?? '';

      if (username.isEmpty || password.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Username and password are required'}),
          headers: {'Content-Type': 'application/json'}
        );
      }

      final rows = await db.query(
        'SELECT id, password_hash, role, is_active FROM public.users WHERE username = @u',
        substitutionValues: {'u': username},
      );
      
      if (rows.isEmpty) {
        await Future.delayed(Duration(milliseconds: 500)); // Prevent timing attacks
        return Response.forbidden(jsonEncode({'error': 'Invalid credentials'}));
      }
      
      final row = rows.first;
      if (!(row[3] as bool)) {
        return Response.forbidden(jsonEncode({'error': 'Account is deactivated'}));
      }
      
      if (!BCrypt.checkpw(password, row[1] as String)) {
        await Future.delayed(Duration(milliseconds: 500)); // Prevent timing attacks
        return Response.forbidden(jsonEncode({'error': 'Invalid credentials'}));
      }

      final jwt = JWT({
        'id': row[0], 
        'role': row[2],
        'username': username,
        'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      }, issuer: 'sewing-management-system');
      
      final token = jwt.sign(SecretKey(jwtSecret), expiresIn: const Duration(hours: 8));

      // Log successful login
      print('✅ User $username (${row[2]}) logged in successfully');

      return Response.ok(
        jsonEncode({
          'token': token, 
          'role': row[2],
          'username': username,
          'expires_in': 8 * 60 * 60, // 8 hours in seconds
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      print('❌ Login error: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error'}),
        headers: {'Content-Type': 'application/json'}
      );
    }
  });

  // Enhanced restore endpoint
  router.post('/restore', (Request req) async {
    try {
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      if (body['superPin'] != superPin) {
        await Future.delayed(Duration(seconds: 1)); // Slow down brute force
        return Response.forbidden(jsonEncode({'error': 'Invalid superPin'}));
      }
      
      final jwt = JWT({
        'role': 'SuperAdmin',
        'username': 'SuperAdmin',
        'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      }, issuer: 'sewing-management-system');
      
      final token = jwt.sign(SecretKey(jwtSecret), expiresIn: const Duration(minutes: 30));
      
      print('⚠️  SuperAdmin access granted via restore pin');
      
      return Response.ok(
        jsonEncode({
          'token': token, 
          'role': 'SuperAdmin',
          'username': 'SuperAdmin',
          'expires_in': 30 * 60, // 30 minutes in seconds
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      print('❌ Restore error: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error'}),
        headers: {'Content-Type': 'application/json'}
      );
    }
  });

  return router;
}

// Enhanced admin router (keeping your existing logic)
Router adminRouter(PostgreSQLConnection db, { required String superPin }) {
  final router = Router();

  // List users (unchanged)
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

  // Create user (unchanged)
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

  // Update user (unchanged)
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

  // Reset password (unchanged)
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

  // Delete user (unchanged)
  router.delete('/users/<id>', (Request req, String id) async {
    final userId = int.parse(id);
    final result = await db.execute(
      'DELETE FROM public.users WHERE id = @id',
      substitutionValues: {'id': userId},
    );
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
  final jwtSecret  = Platform.environment['JWT_SECRET'] ?? 'ghaith\$';
  final superPin   = Platform.environment['SUPER_PIN']  ?? 'ghaith\$';
  final serverPort = int.parse(Platform.environment['SERVER_PORT'] ?? '8888');
  _infoPort = serverPort;

  print('🚀 Starting Sewing Management System Server on port \$serverPort...');

  try {
    await db.open();
    print('✅ Database connected successfully');
  } catch (e) {
    print('❌ Database connection failed: \$e');
    exit(1);
  }

  final router = Router()
    ..mount('/', healthRouter())
    ..mount('/auth/admin/', Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(corsHeaders())
      .addMiddleware(securityHeaders())
      .addMiddleware(rateLimit(maxRequests: 50))
      .addMiddleware(verifyJwt(jwtSecret))
      .addMiddleware(onlyAdmin())
      .addHandler(adminRouter(db, superPin: superPin)))
    ..mount('/auth/', Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(corsHeaders())
      .addMiddleware(securityHeaders())
      .addMiddleware(rateLimit(maxRequests: 20))
      .addHandler(authRouter(superPin, jwtSecret)))
 router.mount('/clients/',   apiPipeline.addHandler(getClientsRoutes(db)));
  router.mount('/sewing/',    apiPipeline.addHandler(getWarehouseRoutes(db)));
  router.mount('/employees/', apiPipeline.addHandler(getEmployeesRoutes(db)));
  router.mount('/purchases/', apiPipeline.addHandler(getPurchasesRoutes(db)));
  router.mount('/purchases',  apiPipeline.addHandler(getPurchasesRoutes(db)));
  router.mount('/models/',    apiPipeline.addHandler(getModelsRoutes(db)));
  router.mount('/sales/',     apiPipeline.addHandler(getSalesRoutes(db)));
  router.mount('/seasons',    apiPipeline.addHandler(getSeasonRoutes(db)));
  router.mount('/expenses/',  apiPipeline.addHandler(getExpensesRoutes(db)));
  router.mount('/suppliers/', apiPipeline.addHandler(getSuppliersRoutes(db)));
  router.mount('/debts/',     apiPipeline.addHandler(getDebtsRoutes(db)));
  router.mount('/returns/',   apiPipeline.addHandler(getReturnsRoutes(db)));

  // Design routes
  router.mount('/design/clients/',    apiPipeline.addHandler(getDesignClientsRoutes(db)));
  router.mount('/design/clients',     apiPipeline.addHandler(getDesignClientsRoutes(db)));
  router.mount('/design/suppliers/',  apiPipeline.addHandler(getDesignSuppliersRoutes(db)));
  router.mount('/design/warehouse/',  apiPipeline.addHandler(getDesignWarehouseRoutes(db)));
  router.mount('/design/models/',     apiPipeline.addHandler(getDesignModelsRoutes(db)));
  router.mount('/design/purchases/',  apiPipeline.addHandler(getDesignPurchasesRoutes(db)));
  router.mount('/design/sales/',      apiPipeline.addHandler(getDesignSalesRoutes(db)));
  router.mount('/design/seasons/',    apiPipeline.addHandler(getDesignSeasonRoutes(db)));
  router.mount('/design/expenses/',   apiPipeline.addHandler(getDesignExpensesRoutes(db)));
  router.mount('/design/debts/',      apiPipeline.addHandler(getDesignDebtsRoutes(db)));
  router.mount('/design/sales',       apiPipeline.addHandler(getDesignSalesRoutes(db)));
  router.mount('/design/purchases',   apiPipeline.addHandler(getDesignPurchasesRoutes(db)));
  router.mount('/design/seasons',     apiPipeline.addHandler(getDesignSeasonRoutes(db)));
  router.mount('/design/warehouse',   apiPipeline.addHandler(getDesignWarehouseRoutes(db)));
  router.mount('/design/models',      apiPipeline.addHandler(getDesignModelsRoutes(db)));
  router.mount('/design/debts',       apiPipeline.addHandler(getDesignDebtsRoutes(db)));
  router.mount('/design/expenses',    apiPipeline.addHandler(getDesignExpensesRoutes(db)));

  // Embroidery routes
  router.mount('/embrodry/clients/',    apiPipeline.addHandler(getEmbrodryClientsRoutes(db)));
  router.mount('/embrodry/warehouse/',  apiPipeline.addHandler(getEmbrodryWarehouseRoutes(db)));
  router.mount('/embrodry/employees/',  apiPipeline.addHandler(getEmbrodryEmployeesRoutes(db)));
  router.mount('/embrodry/purchases/',  apiPipeline.addHandler(getEmbrodryPurchasesRoutes(db)));
  router.mount('/embrodry/models/',     apiPipeline.addHandler(getEmbrodryModelsRoutes(db)));
  router.mount('/embrodry/sales/',      apiPipeline.addHandler(getEmbroiderySalesRoutes(db)));
  router.mount('/embrodry/seasons/',    apiPipeline.addHandler(getEmbrodrySeasonRoutes(db)));
  router.mount('/embrodry/expenses/',   apiPipeline.addHandler(getEmbrodryExpensesRoutes(db)));
  router.mount('/embrodry/suppliers/',  apiPipeline.addHandler(getEmbrodrySuppliersRoutes(db)));
  router.mount('/embrodry/debts/',      apiPipeline.addHandler(getEmbrodryDebtsRoutes(db)));
  router.mount('/embrodry/returns/',    apiPipeline.addHandler(getEmbrodryReturnsRoutes(db)));
  router.mount('/embrodry/seasons',     apiPipeline.addHandler(getEmbrodrySeasonRoutes(db)));
  router.mount('/embrodry/expenses',    apiPipeline.addHandler(getEmbrodryExpensesRoutes(db)));
  router.mount('/embrodry/purchases',   apiPipeline.addHandler(getEmbrodryPurchasesRoutes(db)));
  router.mount('/embrodry/debts',       apiPipeline.addHandler(getEmbrodryDebtsRoutes(db)));
  router.mount('/embrodry/models',      apiPipeline.addHandler(getEmbrodryModelsRoutes(db)));
  router.mount('/embrodry/returns',     apiPipeline.addHandler(getEmbrodryReturnsRoutes(db)));
  router.mount('/embrodry/sales',       apiPipeline.addHandler(getEmbroiderySalesRoutes(db)));
  router.mount('/embroidery-employees', apiPipeline.addHandler(getEmbrodryEmployeesRoutes(db)));
  router.mount('/embrodry/warehouse',   apiPipeline.addHandler(getEmbrodryWarehouseRoutes(db)));
    ;

  final handler = Pipeline()
    .addMiddleware(logRequests())
    .addMiddleware(corsHeaders())
    .addMiddleware(securityHeaders())
    .addHandler(router);

  try {
    final server = await serve(handler, InternetAddress.anyIPv4, serverPort);
    print('✅ Server running successfully!');
    print('🌐 Server URL: http://\${await getLocalIPAddress()}:\${server.port}');

    // Start dynamic discovery broadcast
    await ServerDiscovery.startBroadcast(serverPort);

    // Graceful shutdown
    ProcessSignal.sigint.watch().listen((_) async {
      print('\n🛑 Shutting down server...');
      ServerDiscovery.stopBroadcast();
      await db.close();
      await server.close();
      print('✅ Server stopped gracefully');
      exit(0);
    });

  } catch (e) {
    print('❌ Failed to start server: \$e');
    await db.close();
    exit(1);
  }
}
