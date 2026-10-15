# Middlewares

While Tokamak doesn't have Express-style middleware, it achieves the same functionality through nested routes and context handlers.

## Basic Middleware

Create middleware by wrapping routes:

```zig
fn logger(children: []const tk.Route) tk.Route {
    const H = struct {
        fn handleLogger(ctx: *tk.Context) anyerror!void {
            log.debug("{s} {s}", .{
                @tagName(ctx.req.method),
                ctx.req.url.path,
            });

            return ctx.next();
        }
    };

    return .{ .handler = &H.handleLogger, .children = children };
}

const routes: []const tk.Route = &.{
    logger(&.{
        .get("/", hello),
        .get("/users", getUsers),
    }),
};
```

## Context Handlers

Middleware handlers receive `*tk.Context` and must call `ctx.next()`:

```zig
fn timing(ctx: *tk.Context) anyerror!void {
    const io = try ctx.injector.get(std.Io);
    const start = std.Io.Clock.awake.now(io);

    try ctx.next();

    const duration = start.durationTo(std.Io.Clock.awake.now(io));
    log.info("Request took {d}ms", .{duration.toMilliseconds()});
}
```

## Request-Scoped Dependencies

Since Zig doesn't have closures, use `ctx.nextScoped()` to pass data to downstream handlers:

```zig
fn auth(ctx: *tk.Context) anyerror!void {
    const db = try ctx.injector.get(*Database);
    const token = ctx.req.header("Authorization") orelse
        return error.Unauthorized;

    const user = try jwt.parse(token);

    // Make user available to downstream handlers
    var inj = tk.Injector.init(&.{ .ref(&user) }, ctx.injector);
    return ctx.nextScoped(&inj);
}

// Downstream handler can now inject User
fn getProfile(user: User) !Profile {
    return Profile{ .id = user.id, .name = user.name };
}
```

> **Tip:** Middleware handlers must use `ctx.injector.get(T)` to access dependencies manually, as they don't support automatic DI syntax.

## Common Middleware Patterns

### Authentication

```zig
fn requireAuth(children: []const tk.Route) tk.Route {
    const H = struct {
        fn handle(ctx: *tk.Context) anyerror!void {
            const token = ctx.req.header("Authorization") orelse
                return error.Unauthorized;

            const user = try validateToken(token);
            var inj = tk.Injector.init(&.{ .ref(&user) }, ctx.injector);
            return ctx.nextScoped(&inj);
        }
    };

    return .{ .handler = &H.handle, .children = children };
}

const routes: []const tk.Route = &.{
    .get("/public", publicHandler),
    requireAuth(&.{
        .get("/private", privateHandler),
    }),
};
```

### CORS

```zig
fn cors(ctx: *tk.Context) anyerror!void {
    ctx.res.header("access-control-allow-origin", "*");
    ctx.res.header("access-control-allow-methods", "GET, POST, PUT, DELETE");

    if (ctx.req.method == .OPTIONS and ctx.req.header("access-control-request-method") != null) {
        return ctx.send({});
    }

    try ctx.next();
}
```

### Error Handling

```zig
fn errorHandler(ctx: *tk.Context) anyerror!void {
    ctx.next() catch |err| {
        log.err("Request failed: {}", .{err});

        ctx.res.status = switch (err) {
            error.Unauthorized => 401,
            error.NotFound => 404,
            error.ValidationError => 400,
            else => 500,
        };

        try ctx.send(.{ .@"error" = @errorName(err) });
    };
}
```

## Composing Middleware

Stack multiple middleware together:

```zig
const routes: []const tk.Route = &.{
    .{ .handler = errorHandler, .children = &.{
        logger(&.{
            .{ .handler = cors, .children = &.{
                requireAuth(&.{
                    .get("/api/users", getUsers),
                }),
            } },
        }),
    } },
};
```
