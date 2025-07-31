// File: routes/auth_api.dart

import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:postgres/postgres.dart';
import 'package:bcrypt/bcrypt.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

/// Call this in your main.dart, passing in your db connection,
/// a fixed super-PIN (for emergency restore), and a JWT secret.
Router getLoginRoutes(
  PostgreSQLConnection db, {
  required String superPin,
  required String jwtSecret,
}) {
  final router = Router();

  // --- 1) LOGIN ---
  router.post('/login', (Request req) async {
    final body = jsonDecode(await req.readAsString());
    final username = body['username'] as String;
    final password = body['password'] as String;

    final result = await db.query(
      'SELECT id, password_hash, role, is_active FROM public.users WHERE username = @u',
      substitutionValues: {'u': username},
    );
    if (result.isEmpty) {
      return Response.forbidden(jsonEncode({'error': 'Invalid credentials'}));
    }

    final row = result.first;
    if (!(row[3] as bool)) {
      return Response.forbidden(jsonEncode({'error': 'User inactive'}));
    }
    final hash = row[1] as String;
    if (!BCrypt.checkpw(password, hash)) {
      return Response.forbidden(jsonEncode({'error': 'Invalid credentials'}));
    }

    // issue JWT
    final jwt = JWT(
      {'id': row[0], 'role': row[2]},
      issuer: 'workshop-app',
    );
    final token = jwt.sign(SecretKey(jwtSecret), expiresIn: const Duration(hours: 8));

    return Response.ok(jsonEncode({
      'token': token,
      'role': row[2],
    }), headers: {'Content-Type': 'application/json'});
  });

  // --- 2) SUPER-PIN RESTORE ---
  router.post('/restore', (Request req) async {
    final body = jsonDecode(await req.readAsString());
    if (body['superPin'] != superPin) {
      return Response.forbidden(jsonEncode({'error': 'Invalid superPin'}));
    }
    // issue a super-admin JWT
    final jwt = JWT({'role': 'SuperAdmin'}, issuer: 'workshop-app');
    final token = jwt.sign(SecretKey(jwtSecret), expiresIn: const Duration(minutes: 30));
    return Response.ok(jsonEncode({'token': token, 'role': 'SuperAdmin'}),
        headers: {'Content-Type': 'application/json'});
  });

  // --- Middleware: verify JWT & extract claims ---
  Middleware checkJwt = createMiddleware(
    requestHandler: (Request request) {
      final authHeader = request.headers['Authorization'];
      if (authHeader == null || !authHeader.startsWith('Bearer ')) {
        return Response.forbidden(jsonEncode({'error': 'Missing token'}));
      }
      try {
        final token = authHeader.split(' ').last;
        final jwt = JWT.verify(token, SecretKey(jwtSecret));
        return request.change(context: {
          'userId': jwt.payload['id'],
          'role': jwt.payload['role'],
        });
      } on JWTExpiredError {
        return Response.forbidden(jsonEncode({'error': 'Token expired'}));
      } catch (_) {
        return Response.forbidden(jsonEncode({'error': 'Invalid token'}));
      }
    },
  );

  // --- Middleware: only Admin or SuperAdmin ---
  Middleware onlyAdmin = createMiddleware(
    requestHandler: (Request request) {
      final role = request.context['role'] as String?;
      if (role != 'Admin' && role != 'SuperAdmin') {
        return Response.forbidden(jsonEncode({'error': 'Admin only'}));
      }
      return null;
    },
  );

  // --- 3) ADMIN USER MANAGEMENT ---
  final admin = Router();

  // list users (optionally filter by role)
  admin.get('/users', (Request req) async {
    final rolesParam = req.url.queryParametersAll['roles'];
    final where = (rolesParam != null && rolesParam.isNotEmpty)
        ? 'WHERE role = ANY(@r)'
        : '';
    final users = await db.mappedResultsQuery(
      'SELECT id, username, role, is_active, created_at, updated_at '
      'FROM public.users $where',
      substitutionValues: {'r': rolesParam},
    );
    return Response.ok(jsonEncode(users), headers: {'Content-Type': 'application/json'});
  });

  // create user
  admin.post('/users', (Request req) async {
    final body = jsonDecode(await req.readAsString());
    final uname = body['username'] as String;
    final role  = body['role'] as String;
    final pwd   = body['initialPassword'] as String;
    final hash  = BCrypt.hashpw(pwd, BCrypt.gensalt());

    await db.transaction((tx) async {
      final insert = await tx.query(
        'INSERT INTO public.users (username, password_hash, role) VALUES (@u,@h,@r) RETURNING id',
        substitutionValues: {'u': uname, 'h': hash, 'r': role},
      );
      final newId = insert.first[0] as int;
      await tx.query(
        'INSERT INTO public.admin_audit (admin_id, action, target_user_id, details) '
        'VALUES (@a,"create_user",@t, NULL)',
        substitutionValues: {'a': req.context['userId'], 't': newId},
      );
    });
    return Response.ok(jsonEncode({'status': 'created'}));
  });

  // update user fields
  admin.put('/users/<id>', (Request req, String id) async {
    final body = jsonDecode(await req.readAsString());
    final updates = <String>[];
    final subs = <String, dynamic>{ 'id': int.parse(id) };

    if (body.containsKey('username')) {
      updates.add('username = @u');
      subs['u'] = body['username'];
    }
    if (body.containsKey('role')) {
      updates.add('role = @r');
      subs['r'] = body['role'];
    }
    if (body.containsKey('isActive')) {
      updates.add('is_active = @ia');
      subs['ia'] = body['isActive'];
    }
    if (updates.isEmpty) return Response.badRequest(body: 'nothing to update');

    final sql = 'UPDATE public.users SET '
        '${updates.join(', ')}, updated_at = NOW() WHERE id = @id';
    await db.query(sql, substitutionValues: subs);
    await db.query(
      'INSERT INTO public.admin_audit (admin_id, action, target_user_id) '
      'VALUES (@a, "update_user", @t)',
      substitutionValues: {'a': req.context['userId'], 't': int.parse(id)},
    );
    return Response.ok(jsonEncode({'status': 'updated'}));
  });

  // reset password
  admin.post('/users/<id>/reset-password', (Request req, String id) async {
    final body = jsonDecode(await req.readAsString());
    final newPwd = body['newPassword'] as String;
    final hash   = BCrypt.hashpw(newPwd, BCrypt.gensalt());

    await db.transaction((tx) async {
      await tx.query(
        'UPDATE public.users SET password_hash = @h, updated_at = NOW() WHERE id = @id',
        substitutionValues: {'h': hash, 'id': int.parse(id)},
      );
      await tx.query(
        'INSERT INTO public.admin_audit (admin_id, action, target_user_id) '
        'VALUES (@a, "reset_password", @t)',
        substitutionValues: {'a': req.context['userId'], 't': int.parse(id)},
      );
    });
    return Response.ok(jsonEncode({'status': 'password reset'}));
  });

  // soft-delete user
  admin.delete('/users/<id>', (Request req, String id) async {
    await db.transaction((tx) async {
      await tx.query(
        'UPDATE public.users SET is_active = FALSE, updated_at = NOW() WHERE id = @id',
        substitutionValues: {'id': int.parse(id)},
      );
      await tx.query(
        'INSERT INTO public.admin_audit (admin_id, action, target_user_id) '
        'VALUES (@a, "soft_delete", @t)',
        substitutionValues: {'a': req.context['userId'], 't': int.parse(id)},
      );
    });
    return Response.ok(jsonEncode({'status': 'soft-deleted'}));
  });

  // hard-delete (destroy) user – requires superPin in body
  admin.delete('/users/<id>/destroy', (Request req, String id) async {
    final body = jsonDecode(await req.readAsString());
    if (body['superPin'] != superPin) {
      return Response.forbidden(jsonEncode({'error': 'Invalid superPin'}));
    }
    await db.transaction((tx) async {
      await tx.query('DELETE FROM public.users WHERE id = @id',
          substitutionValues: {'id': int.parse(id)});
      await tx.query(
        'INSERT INTO public.admin_audit (admin_id, action, target_user_id) '
        'VALUES (@a, "hard_delete", @t)',
        substitutionValues: {'a': req.context['userId'], 't': int.parse(id)},
      );
    });
    return Response.ok(jsonEncode({'status': 'hard-deleted'}));
  });

  // mount the admin router under /admin, protected by JWT & role check
  router.mount(
    '/admin/',
    Pipeline()
      .addMiddleware(checkJwt)
      .addMiddleware(onlyAdmin)
      .addHandler(admin),
  );

  return router;
}
