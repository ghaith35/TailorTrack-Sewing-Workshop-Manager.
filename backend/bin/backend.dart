import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:postgres/postgres.dart';

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

// NEW
import 'routes_design/clients_design_api.dart';
import 'routes_design/suppliers_design_api.dart';
import 'routes_design/warehouse_design_api.dart';
import 'routes_design/models_design_api.dart';
import 'routes_design/purchases_design_api.dart';
import 'routes_design/sales_design_api.dart';
import 'routes_design/season_design_api.dart';
import 'routes_design/expenses_design_api.dart';
import 'routes_design/debts_design_api.dart';
// import 'routes_design/returns_design_api.dart';

final db = PostgreSQLConnection(
  'localhost',
  5432,
  'osama',
  username: 'postgres',
  password: 'ghaith\$',
);

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
  'Access-Control-Allow-Headers': 'Origin, Content-Type, Accept',
};

Future<void> main() async {
  await db.open();
  print('✅ Database connected');

  final router = Router();

  // ── Existing sewing mounts ───────────────────────────────
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

  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(corsHeaders())
      .addHandler(router);

  final server = await serve(handler, InternetAddress.anyIPv4, 8888);
  print('✅ Server running on port ${server.port}');
}

// ===========================================================
// Below: Skeleton for each design route file
// Path: lib/routes_design/....dart
// Just CRUD examples; adapt SQL to your schema.
// ===========================================================
