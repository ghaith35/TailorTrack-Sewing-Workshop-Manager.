import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:postgres/postgres.dart';
import 'dart:convert';

Router getModelsRoutes(PostgreSQLConnection db) {
  final router = Router();

  // Helper function to safely convert database values to numbers
  double parseNum(dynamic v) =>
      v == null ? 0.0 : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0);

  int parseInt(dynamic v) =>
      v == null ? 0 : (v is num ? v.toInt() : int.tryParse(v.toString()) ?? 0);

  // =====================
  // SPECIFIC ROUTES FIRST (BEFORE GENERIC ONES)
  // =====================

  // Get available materials
  router.get('/materials/', (Request request) async {
    try {
      final results = await db.query('''
        SELECT m.id, m.code, mt.name as type_name,
       COALESCE(avg_prices.avg_price, 0) as price,
       m.stock_quantity
          FROM sewing.materials m
          JOIN sewing.material_types mt ON m.type_id = mt.id
          LEFT JOIN (
            SELECT material_id, AVG(unit_price) as avg_price
            FROM sewing.purchase_items
            GROUP BY material_id
          ) avg_prices ON m.id = avg_prices.material_id
          ORDER BY mt.name, m.code

      ''');

      List<Map<String, dynamic>> materials = results.map((row) => {
      'id': parseInt(row[0]),
      'code': row[1],
      'name': '${row[2]} - ${row[1]}',
      'type_name': row[2],
      'price': parseNum(row[3]),
      'stock_quantity': parseNum(row[4]),   // <-- add this line
    }).toList();


      return Response.ok(jsonEncode(materials), headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch available materials: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // Get models currently in production (from production_batches table)
  router.get('/in-production', (Request request) async {
    try {
      final results = await db.query("""
        SELECT pb.id, pb.model_id, m.name as model_name, pb.color, pb.size, pb.quantity, pb.production_date
        FROM sewing.production_batches pb
        JOIN sewing.models m ON pb.model_id = m.id
        WHERE pb.status = 'in_progress'
        ORDER BY pb.production_date DESC
      """);

      List<Map<String, dynamic>> inProductionModels = results.map((row) => {
        'id': parseInt(row[0]),
        'model_id': parseInt(row[1]),
        'model_name': row[2],
        'color': row[3],
        'size': row[4],
        'quantity': parseInt(row[5]),
        'production_date': row[6].toString(),
      }).toList();

      return Response.ok(jsonEncode(inProductionModels), headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch models in production: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // Endpoint to initiate production of a model
  // Endpoint to initiate production of a model (SIMPLE)
  router.post('/initiate-production', (Request request) async {
  try {
    final body = await request.readAsString();
    final data = jsonDecode(body) as Map<String, dynamic>;
    final modelId = parseInt(data['model_id']);
    final color   = data['color'] ?? '';
    final size    = data['size'] ?? '';
    final manualQty = parseInt(data['manual_quantity'] ?? 0);
    final autoQty   = parseInt(data['automatic_quantity'] ?? 0);

    // 1. Fetch manual/auto costs for this model (as per your /cost route)
    // Reuse your cost calculation logic:
    final costResult = await db.query('''
      -- This query matches your /<id>/cost endpoint
      SELECT 
        -- Material cost
        (SELECT COALESCE(SUM(mc.quantity_needed * COALESCE(pr.avg_price,0)),0)
           FROM sewing.model_components mc
           LEFT JOIN (SELECT material_id, AVG(unit_price) AS avg_price
                      FROM sewing.purchase_items GROUP BY material_id) pr
             ON mc.material_id = pr.material_id
           WHERE mc.model_id = m.id) AS material_cost,
        -- Manual cost
        m.cut_price + m.sewing_price + m.press_price AS manual_labor,
        COALESCE(m.washing,0)+COALESCE(m.embroidery,0)+COALESCE(m.laser,0)
          +COALESCE(m.printing,0)+COALESCE(m.crochet,0) AS additional_services,
        -- Auto labor parts
        m.cut_price + m.press_price AS auto_labor_base,
        m.assembly_price AS auto_assembly_price
      FROM sewing.models m
      WHERE m.id = @id
    ''', substitutionValues: {'id': modelId});

    if (costResult.isEmpty) {
      return Response.notFound(jsonEncode({'error': 'Model not found'}), headers: {'Content-Type': 'application/json'});
    }

    final c = costResult.first;
    final materialCost       = parseNum(c[0]);
    final manualLabor        = parseNum(c[1]);
    final additionalServices = parseNum(c[2]);
    final autoLaborBase      = parseNum(c[3]);
    final autoAssemblyPrice  = parseNum(c[4]);

    // Calculate per piece manual and automatic costs
    // For overhead, transport, etc, reuse your cost route if you need to be precise
    double overhead = 0, transport = 0; // For simplicity; you can fetch these as in /cost
    // Optionally, you can refactor cost breakdown into a function for DRY

    final manualCost = materialCost + manualLabor + additionalServices + overhead + transport;
    final autoLabor  = autoLaborBase + autoAssemblyPrice; // Add auto sewing/assembly costs here
    final automaticCost = materialCost + autoLabor + additionalServices + overhead + transport;

    final totalQty = manualQty + autoQty;
    final avgCost = (totalQty > 0)
        ? ((manualQty * manualCost) + (autoQty * automaticCost)) / totalQty
        : 0;

    // Check materials availability & deduct as before
    await db.transaction((ctx) async {
      final requiredMaterials = await ctx.query('''
        SELECT material_id, quantity_needed * @qty AS required_total
        FROM sewing.model_components
        WHERE model_id = @model_id
      ''', substitutionValues: {
        'model_id': modelId,
        'qty': totalQty,
      });

      for (var mat in requiredMaterials) {
        final materialId = parseInt(mat[0]);
        final requiredQuantity = parseNum(mat[1]);
        final stockRes = await ctx.query('SELECT stock_quantity FROM sewing.materials WHERE id = @mat_id', substitutionValues: {'mat_id': materialId});
        final available = stockRes.isEmpty ? 0.0 : parseNum(stockRes.first[0]);
        if (available < requiredQuantity) throw Exception('Insufficient stock for material ID: $materialId');
        await ctx.query('UPDATE sewing.materials SET stock_quantity = stock_quantity - @req WHERE id = @mat_id', substitutionValues: {'req': requiredQuantity, 'mat_id': materialId});
      }

      // Insert new batch (now includes manual/auto quantities/costs)
      await ctx.query('''
        INSERT INTO sewing.production_batches
          (model_id, production_date, color, size, manual_quantity, manual_cost, automatic_quantity, automatic_cost, average_cost, quantity, status)
        VALUES
          (@model_id, CURRENT_DATE, @color, @size, @manual_qty, @manual_cost, @auto_qty, @auto_cost, @avg_cost, @quantity, 'in_progress')
      ''', substitutionValues: {
        'model_id'   : modelId,
        'color'      : color,
        'size'       : size,
        'manual_qty' : manualQty,
        'manual_cost': manualCost,
        'auto_qty'   : autoQty,
        'auto_cost'  : automaticCost,
        'avg_cost'   : avgCost,
        'quantity'   : manualQty + autoQty,
      });


      // Insert into model_production for stats/history
      if (manualQty > 0) {
        await ctx.query('''
          INSERT INTO sewing.model_production
            (model_id, color, quantity, produced_at)
          VALUES
            (@model_id, @color, @quantity, CURRENT_DATE)
        ''', substitutionValues: {'model_id': modelId, 'color': color, 'quantity': manualQty});
      }
      if (autoQty > 0) {
        await ctx.query('''
          INSERT INTO sewing.model_production
            (model_id, color, quantity, produced_at)
          VALUES
            (@model_id, @color, @quantity, CURRENT_DATE)
        ''', substitutionValues: {'model_id': modelId, 'color': color, 'quantity': autoQty});
      }
    });

    return Response.ok(jsonEncode({
      'message': 'Production initiated with manual/auto quantities.',
      'model_id': modelId,
      'manual_quantity': manualQty,
      'manual_cost': manualCost,
      'automatic_quantity': autoQty,
      'automatic_cost': automaticCost,
      'average_cost': avgCost,
    }), headers: {'Content-Type': 'application/json'});
  } catch (e, st) {
    print('Error: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Failed to initiate production: $e'}),
      headers: {'Content-Type': 'application/json'},
    );
  }
});

  // Endpoint to mark a production batch as done and move to product_inventory
  // Endpoint to mark a production batch as done and move to product_inventory
router.post("/complete-production/<batchId>", (Request request, String batchId) async {
  try {
    await db.transaction((ctx) async {
      // Get batch details
      final batchResults = await ctx.query("""
        SELECT model_id, color, size, quantity
        FROM sewing.production_batches
        WHERE id = @batch_id AND status = 'in_progress'
        FOR UPDATE
      """, substitutionValues: {'batch_id': int.parse(batchId)});

      if (batchResults.isEmpty) {
        throw Exception('Production batch not found or not in progress.');
      }

      final batch = batchResults.first;
      final modelId = batch[0] as int;
      final color = batch[1] as String;
      final size = batch[2] as String;
      final quantity = batch[3] as int;

      // Insert a new row in product_inventory for this batch (never merge with other batches)
      await ctx.query("""
        INSERT INTO sewing.product_inventory
          (warehouse_id, model_id, color, size, quantity, last_updated, production_batch_id)
        VALUES (
          (SELECT id FROM sewing.warehouses WHERE type = 'ready' LIMIT 1),
          @model_id, @color, @size, @quantity, CURRENT_TIMESTAMP, @batch_id
        )
        ON CONFLICT (warehouse_id, model_id, color, size, production_batch_id) DO UPDATE SET
          quantity = sewing.product_inventory.quantity + @quantity,
          last_updated = CURRENT_TIMESTAMP
      """, substitutionValues: {
        'model_id': modelId,
        'color': color,
        'size': size,
        'quantity': quantity,
        'batch_id': int.parse(batchId),
      });

      // Update production batch status to 'completed'
      await ctx.query("""
        UPDATE sewing.production_batches
        SET status = 'completed'
        WHERE id = @batch_id
      """, substitutionValues: {'batch_id': int.parse(batchId)});
    });

    return Response.ok(
      jsonEncode({'message': 'Production batch completed and added to inventory.'}),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e) {
    return Response.internalServerError(
      body: jsonEncode({'error': 'Failed to complete production batch: $e'}),
      headers: {'Content-Type': 'application/json'},
    );
  }
});


  // =====================
  // BASIC MODEL CRUD (FOR ARCHIVE)
  // =====================

  // Get all models (archive)
  router.get('/', (Request request) async {
    try {
      final results = await db.query('''
      SELECT id, name, start_date, image_url, cut_price, sewing_price, press_price, 
            assembly_price, electricity, rent, maintenance, water, washing, embroidery, 
            laser, printing, crochet, sizes, nbr_of_sizes, created_at
      FROM sewing.models 
      ORDER BY created_at DESC
    ''');

    List<Map<String, dynamic>> models = results.map((row) => {
      'id': parseInt(row[0]),
      'name': row[1],
      'start_date': row[2].toString(),
      'image_url': row[3],
      'cut_price': parseNum(row[4]),
      'sewing_price': parseNum(row[5]),
      'press_price': parseNum(row[6]),
      'assembly_price': parseNum(row[7]),
      'electricity': parseNum(row[8]),
      'rent': parseNum(row[9]),
      'maintenance': parseNum(row[10]),
      'water': parseNum(row[11]),
      'washing': parseNum(row[12]),
      'embroidery': parseNum(row[13]),
      'laser': parseNum(row[14]),
      'printing': parseNum(row[15]),
      'crochet': parseNum(row[16]),
      'sizes': row[17],
      'nbr_of_sizes': row[18],
      'created_at': row[19].toString(),
    }).toList();

      return Response.ok(jsonEncode(models), headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch models: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // Create model
  router.post('/', (Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final results = await db.query('''
      INSERT INTO sewing.models (
        name, start_date, image_url, cut_price, sewing_price, press_price, 
        assembly_price, electricity, rent, maintenance, water, washing, 
        embroidery, laser, printing, crochet, sizes, nbr_of_sizes
      ) VALUES (
        @name, @start_date, @image_url, @cut_price, @sewing_price, @press_price,
        @assembly_price, @electricity, @rent, @maintenance, @water, @washing,
        @embroidery, @laser, @printing, @crochet, @sizes, @nbr_of_sizes
      ) RETURNING id
    ''', substitutionValues: {
      'name': data['name'],
      'start_date': DateTime.parse(data['start_date']),
      'image_url': data['image_url'] ?? '',
      'cut_price': parseNum(data['cut_price']),
      'sewing_price': parseNum(data['sewing_price']),
      'press_price': parseNum(data['press_price']),
      'assembly_price': parseNum(data['assembly_price']),
      'electricity': parseNum(data['electricity']),
      'rent': parseNum(data['rent']),
      'maintenance': parseNum(data['maintenance']),
      'water': parseNum(data['water']),
      'washing': parseNum(data['washing']),
      'embroidery': parseNum(data['embroidery']),
      'laser': parseNum(data['laser']),
      'printing': parseNum(data['printing']),
      'crochet': parseNum(data['crochet']),
      'sizes': data['sizes'],
      'nbr_of_sizes': parseInt(data['nbr_of_sizes']),
    });


      final newId = parseInt(results.first[0]);

      return Response(201,
        body: jsonEncode({'id': newId, 'message': 'Model created successfully'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to create model: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // =====================
  // GENERIC ROUTES WITH PARAMETERS (AFTER SPECIFIC ROUTES)
  // =====================

  // Get single model
  router.get('/<id>', (Request request, String id) async {
    try {
      final results = await db.query('''
      SELECT id, name, start_date, image_url, cut_price, sewing_price, press_price, 
            assembly_price, electricity, rent, maintenance, water, washing, embroidery, 
            laser, printing, crochet, sizes, nbr_of_sizes, created_at
      FROM sewing.models 
      WHERE id = @id
    ''', substitutionValues: {'id': int.parse(id)});

      if (results.isEmpty) {
        return Response.notFound(
          jsonEncode({'error': 'Model not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final row = results.first;
      final model = {
        'id': parseInt(row[0]),
        'name': row[1],
        'start_date': row[2].toString(),
        'image_url': row[3],
        'cut_price': parseNum(row[4]),
        'sewing_price': parseNum(row[5]),
        'press_price': parseNum(row[6]),
        'assembly_price': parseNum(row[7]),
        'electricity': parseNum(row[8]),
        'rent': parseNum(row[9]),
        'maintenance': parseNum(row[10]),
        'water': parseNum(row[11]),
        'washing': parseNum(row[12]),
        'embroidery': parseNum(row[13]),
        'laser': parseNum(row[14]),
        'printing': parseNum(row[15]),
        'crochet': parseNum(row[16]),
        'sizes': row[17],
        'nbr_of_sizes': row[18],
        'created_at': row[19].toString(),
      };


      return Response.ok(jsonEncode(model), headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch model: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // Update model
  router.put('/<id>', (Request request, String id) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      await db.query('''
      UPDATE sewing.models SET
        name = @name, start_date = @start_date, image_url = @image_url,
        cut_price = @cut_price, sewing_price = @sewing_price, press_price = @press_price,
        assembly_price = @assembly_price, electricity = @electricity, rent = @rent,
        maintenance = @maintenance, water = @water, washing = @washing,
        embroidery = @embroidery, laser = @laser, printing = @printing,
        crochet = @crochet,
        sizes = @sizes,
        nbr_of_sizes = @nbr_of_sizes
      WHERE id = @id
    ''', substitutionValues: {
      'id': int.parse(id),
      'name': data['name'],
      'start_date': DateTime.parse(data['start_date']),
      'image_url': data['image_url'] ?? '',
      'cut_price': parseNum(data['cut_price']),
      'sewing_price': parseNum(data['sewing_price']),
      'press_price': parseNum(data['press_price']),
      'assembly_price': parseNum(data['assembly_price']),
      'electricity': parseNum(data['electricity']),
      'rent': parseNum(data['rent']),
      'maintenance': parseNum(data['maintenance']),
      'water': parseNum(data['water']),
      'washing': parseNum(data['washing']),
      'embroidery': parseNum(data['embroidery']),
      'laser': parseNum(data['laser']),
      'printing': parseNum(data['printing']),
      'crochet': parseNum(data['crochet']),
      'sizes': data['sizes'],
      'nbr_of_sizes': parseInt(data['nbr_of_sizes']),
    });

      return Response.ok(
        jsonEncode({'message': 'Model updated successfully'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to update model: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // Delete model
  router.delete('/<id>', (Request request, String id) async {
    try {
      // Delete related data first due to foreign key constraints
      await db.query('DELETE FROM sewing.model_components WHERE model_id = @id',
          substitutionValues: {'id': int.parse(id)});
      
      final results = await db.query('DELETE FROM sewing.models WHERE id = @id RETURNING id',
          substitutionValues: {'id': int.parse(id)});
      
      if (results.isEmpty) {
        return Response.notFound(
          jsonEncode({'error': 'Model not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      return Response.ok(
        jsonEncode({'message': 'Model deleted successfully'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to delete model: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // Get model cost breakdown
  // ──────────────────────────────────────────────────────────────────────────────
// GET  /models/<id>/cost   – cost breakdown for a single model
// ──────────────────────────────────────────────────────────────────────────────
router.get('/<id>/cost', (Request request, String id) async {
  try {
    final modelId = int.parse(id);

    // Accept Query Parameters for division mode
    final params = request.url.queryParameters;
    final divisionMode = int.tryParse(params['division_mode'] ?? '0') ?? 0;
    final divisionPieces = int.tryParse(params['division_pieces'] ?? '0') ?? 0;

    // 1) Material cost
    final matRes = await db.query('''
      SELECT COALESCE(SUM(mc.quantity_needed * COALESCE(pr.avg_price,0)),0)
      FROM sewing.model_components mc
      LEFT JOIN (
        SELECT material_id, AVG(unit_price) AS avg_price
        FROM sewing.purchase_items GROUP BY material_id
      ) pr ON mc.material_id = pr.material_id
      WHERE mc.model_id = @id
    ''', substitutionValues: {'id': modelId});
    final materialCost = parseNum(matRes.first[0]);

    // 2) Static prices (cut, manual sewing, press, automatic assembly, additional services)
    final rowRes = await db.query('''
      SELECT cut_price,
             sewing_price,
             press_price,
             assembly_price,  -- used only for automatic assembly
             COALESCE(washing,0)+COALESCE(embroidery,0)+COALESCE(laser,0)
             +COALESCE(printing,0)+COALESCE(crochet,0) AS additional_services
      FROM sewing.models WHERE id = @id
    ''', substitutionValues: {'id': modelId});
    if (rowRes.isEmpty) {
      return Response.notFound(
        jsonEncode({'error': 'Model not found'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    final row                = rowRes.first;
    final cutPrice           = parseNum(row[0]);
    final manualSewPrice     = parseNum(row[1]);
    final pressPrice         = parseNum(row[2]);
    final autoAssemblyPrice  = parseNum(row[3]);
    final additionalServices = parseNum(row[4]);

    // 3) Modified How You Get pieces based on division mode
    int pieces;
    if (divisionMode == 1) {
      pieces = 2000; // Annual average (you can change 2000 as needed)
    } else if (divisionMode == 2 && divisionPieces > 0) {
      pieces = divisionPieces;
    } else {
      // Default: use actual month total
      final piecesRes = await db.query(r'''
        SELECT COALESCE(SUM(quantity), 0)
        FROM sewing.model_production
        WHERE date_trunc('month', produced_at)
              = date_trunc('month', CURRENT_DATE)
      ''');
      pieces = parseInt(piecesRes.first[0]);
    }
    if (pieces < 1) pieces = 1; // avoid division by zero!

    // 4) Automatic Sewing share (خياطة آلي)
    final sewSalRes = await db.query('''
      SELECT COALESCE(SUM(salary),0)
      FROM sewing.employees
      WHERE role = 'خياطة' AND seller_type = 'month' AND status = 'active'
    ''');
    final autoSewCost = parseNum(sewSalRes.first[0]) / pieces;

    // 5) Automatic Assembly share (فينيسيون)
    final asmSalRes = await db.query('''
      SELECT COALESCE(SUM(salary),0)
      FROM sewing.employees
      WHERE role = 'فينيسيون' AND seller_type = 'month' AND status = 'active'
    ''');
    final autoAsmCost = parseNum(asmSalRes.first[0]) / pieces;

    // 6) Overhead shares (electricity, rent, maintenance, water)
    Future<double> share(String type) async {
      final r = await db.query('''
        SELECT COALESCE(SUM(amount),0)
        FROM sewing.expenses
        WHERE expense_type = @type
          AND date_trunc('month', expense_date) = date_trunc('month', CURRENT_DATE)
      ''', substitutionValues: {'type': type});
      return parseNum(r.first[0]) / pieces;
    }
    final electricityShare = await share('electricity');
    final rentShare        = await share('rent');
    final maintenanceShare = await share('maintenance');
    final waterShare       = await share('water');
    final overheadShare    = electricityShare + rentShare + maintenanceShare + waterShare;

    // 7) Transport share
    final transportShare = await share('transport');

    // 8) Repair share  – REMOVED (machines feature dropped)
    const double repairShare = 0.0;

    // 9) Build manual vs. automatic totals
    final manualLabor = cutPrice + manualSewPrice + pressPrice;
    final manualTotal = materialCost
                      + manualLabor
                      + additionalServices
                      + overheadShare
                      + transportShare;

    final autoLabor  = cutPrice + pressPrice + autoSewCost + autoAsmCost;
    final autoTotal  = materialCost
                      + autoLabor
                      + additionalServices
                      + overheadShare
                      + transportShare;

    return Response.ok(
      jsonEncode({
        'pieces'               : pieces,
        'material_cost'        : materialCost,
        'manual_labor_cost'    : manualLabor,
        'automatic_labor_cost' : autoLabor,
        'additional_services'  : additionalServices,
        'electricity_share'    : electricityShare,
        'rent_share'           : rentShare,
        'maintenance_share'    : maintenanceShare,
        'water_share'          : waterShare,
        'overhead_share'       : overheadShare,
        'transport_share'      : transportShare,
        'repair_share'         : repairShare,     // kept for backward compatibility
        'manual_total_cost'    : manualTotal,
        'automatic_total_cost' : autoTotal,
        'emballage_cost': autoAsmCost,
        'sewing_cost': autoSewCost,
      }),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e) {
    return Response.internalServerError(
      body: jsonEncode({'error': 'Failed to calculate model cost: $e'}),
      headers: {'Content-Type': 'application/json'},
    );
  }
});

  // Get model materials
  router.get('/<id>/materials', (Request request, String id) async {
    try {
      final results = await db.query('''
        SELECT mc.material_id, mc.quantity_needed, m.code as material_code,
               COALESCE(avg_prices.avg_price, 0) as price,
               (mc.quantity_needed * COALESCE(avg_prices.avg_price, 0)) as total_cost
        FROM sewing.model_components mc
        JOIN sewing.materials m ON mc.material_id = m.id
        LEFT JOIN (
          SELECT material_id, AVG(unit_price) as avg_price
          FROM sewing.purchase_items
          GROUP BY material_id
        ) avg_prices ON mc.material_id = avg_prices.material_id
        WHERE mc.model_id = @id
      ''', substitutionValues: {'id': int.parse(id)});

      List<Map<String, dynamic>> materials = results.map((row) => {
        'material_id': parseInt(row[0]),
        'quantity_needed': parseNum(row[1]),
        'material_code': row[2],
        'price': parseNum(row[3]),
        'total_cost': parseNum(row[4]),
      }).toList();

      return Response.ok(jsonEncode(materials), headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch model materials: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // Add material to model
  router.post('/<id>/materials', (Request request, String id) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      await db.query('''
        INSERT INTO sewing.model_components (model_id, material_id, quantity_needed)
        VALUES (@model_id, @material_id, @quantity_needed)
        ON CONFLICT (model_id, material_id) 
        DO UPDATE SET quantity_needed = @quantity_needed
      ''', substitutionValues: {
        'model_id': int.parse(id),
        'material_id': parseInt(data['material_id']),
        'quantity_needed': parseNum(data['quantity_needed']),
      });

      return Response.ok(
        jsonEncode({'message': 'Material added to model successfully'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to add material to model: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });
  // Check material availability for production
  // -----------------------------------------
//  GET /check-availability/:modelId/:quantity
// -----------------------------------------
router.get('/check-availability/<modelId>/<quantity>', (Request request, String modelId, String quantity) async {
  try {
    final modelIdInt = int.parse(modelId);
    final qty        = int.parse(quantity);

    final results = await db.query('''
      SELECT
        mc.material_id,
        m.code                         AS material_code,
        mc.quantity_needed * @qty      AS required_quantity,
        m.stock_quantity               AS available_stock,
        (m.stock_quantity >= mc.quantity_needed * @qty) AS is_available
      FROM sewing.model_components mc
      JOIN sewing.materials m
        ON mc.material_id = m.id
      WHERE mc.model_id = @model_id
    ''', substitutionValues: {
      'model_id': modelIdInt,
      'qty'      : qty,
    });

    final materials = results.map((row) => {
      'material_id'      : parseInt(row[0]),
      'material_code'    : row[1],
      'required_quantity': parseNum(row[2]),
      'available_stock'  : parseNum(row[3]),
      'is_available'     : row[4] as bool,
    }).toList();

    final canProduce = materials.every((m) => m['is_available'] == true);

    return Response.ok(
      jsonEncode({
        'can_produce': canProduce,
        'materials'  : materials,
      }),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e) {
    return Response.internalServerError(
      body: jsonEncode({'error': 'Failed to check material availability: $e'}),
      headers: {'Content-Type': 'application/json'},
    );
  }
});


  // Delete material from model
  // Delete material from model
router.delete('/<id>/materials/<materialId>', (Request request, String id, String materialId) async {
  try {
    // First check if the material exists
    final checkResults = await db.query('''
      SELECT * FROM sewing.model_components 
      WHERE model_id = @model_id AND material_id = @material_id
    ''', substitutionValues: {
      'model_id': int.parse(id), 
      'material_id': int.parse(materialId)
    });

    if (checkResults.isEmpty) {
      return Response.notFound(
        jsonEncode({'error': 'Material not found in model'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // Now delete it
    await db.query('''
      DELETE FROM sewing.model_components 
      WHERE model_id = @model_id AND material_id = @material_id
    ''', substitutionValues: {
      'model_id': int.parse(id), 
      'material_id': int.parse(materialId)
    });

    return Response.ok(
      jsonEncode({'message': 'Material removed from model successfully'}),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e) {
    return Response.internalServerError(
      body: jsonEncode({'error': 'Failed to remove material from model: $e'}),
      headers: {'Content-Type': 'application/json'},
    );
  }
});


  // Delete all materials from model
  router.delete('/<id>/materials/all', (Request request, String id) async {
    try {
      await db.query('''
        DELETE FROM sewing.model_components WHERE model_id = @model_id
      ''', substitutionValues: {'model_id': int.parse(id)});

      return Response.ok(
        jsonEncode({'message': 'All materials removed from model successfully'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to remove all materials from model: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });
    // Update a production batch (color, size, quantity)
  router.put('/production-batch/<batchId>', (Request request, String batchId) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      // Only allow updating color, size, or quantity if status is 'in_progress'
      final results = await db.query("""
        UPDATE sewing.production_batches
        SET color = @color, 
            size = @size, 
            quantity = @quantity
        WHERE id = @batch_id AND status = 'in_progress'
        RETURNING id
      """, substitutionValues: {
        'batch_id': int.parse(batchId),
        'color': data['color'],
        'size': data['size'],
        'quantity': int.parse(data['quantity'].toString())
      });

      if (results.isEmpty) {
        return Response.notFound(
          jsonEncode({'error': 'Production batch not found or not editable'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      return Response.ok(
        jsonEncode({'message': 'Production batch updated successfully'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to update production batch: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // Delete a production batch (only if still in progress)
  router.delete('/production-batch/<batchId>', (Request request, String batchId) async {
    try {
      final results = await db.query('''
        DELETE FROM sewing.production_batches
        WHERE id = @batch_id AND status = 'in_progress'
        RETURNING id
      ''', substitutionValues: {'batch_id': int.parse(batchId)});

      if (results.isEmpty) {
        return Response.notFound(
          jsonEncode({'error': 'Production batch not found or not deletable'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      return Response.ok(
        jsonEncode({'message': 'Production batch deleted successfully'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to delete production batch: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });
router.get('/by_season/<seasonId|[0-9]+>', (Request req, String seasonId) async {
  final sid = int.parse(seasonId);
  
  try {
    final rows = await db.query(r'''
      SELECT 
        m.id, m.name, m.start_date, m.image_url, m.cut_price, m.sewing_price, 
        m.press_price, m.assembly_price, m.electricity, m.rent, m.maintenance, 
        m.water, m.washing, m.embroidery, m.laser, m.printing, m.crochet, 
        m.sizes, m.nbr_of_sizes, m.created_at
      FROM sewing.models m
      LEFT JOIN sewing.seasons se 
        ON m.start_date BETWEEN se.start_date AND se.end_date
      WHERE se.id = @sid OR @sid = 0
      ORDER BY m.created_at DESC
    ''', substitutionValues: {'sid': sid});

    List<Map<String, dynamic>> models = rows.map((row) => {
      'id': parseInt(row[0]),
      'name': row[1],
      'start_date': row[2].toString(),
      'image_url': row[3],
      'cut_price': parseNum(row[4]),
      'sewing_price': parseNum(row[5]),
      'press_price': parseNum(row[6]),
      'assembly_price': parseNum(row[7]),
      'electricity': parseNum(row[8]),
      'rent': parseNum(row[9]),
      'maintenance': parseNum(row[10]),
      'water': parseNum(row[11]),
      'washing': parseNum(row[12]),
      'embroidery': parseNum(row[13]),
      'laser': parseNum(row[14]),
      'printing': parseNum(row[15]),
      'crochet': parseNum(row[16]),
      'sizes': row[17],
      'nbr_of_sizes': row[18],
      'created_at': row[19].toString(),
    }).toList();

    return Response.ok(jsonEncode(models),
        headers: {'Content-Type': 'application/json'});
  } catch (e) {
    return Response.internalServerError(
      body: jsonEncode({'error': 'Failed to fetch models by season: $e'}),
      headers: {'Content-Type': 'application/json'},
    );
  }
});

// Add seasons endpoint (reuse from purchases or create new one)
router.get('/seasons', (Request req) async {
  try {
    final rows = await db.query(
      'SELECT id, name FROM sewing.seasons ORDER BY start_date DESC');
    final list = rows.map((r) => {
      'id': r[0],
      'name': r[1],
    }).toList();
    return Response.ok(jsonEncode(list),
        headers: {'Content-Type': 'application/json'});
  } catch (e) {
    return Response.internalServerError(
      body: jsonEncode({'error': 'Failed to fetch seasons: $e'}),
      headers: {'Content-Type': 'application/json'},
    );
  }
});

  return router;
}
