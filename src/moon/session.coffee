###
  Moon.js
###

# Dependencies
redis = require "redis"
connect = require "connect"
connectRedis = require "connect-redis"

# Import classes
Logger = require "./logger"
RedisStore = connectRedis connect
ConnectSession = connect.middleware.session.Session

class Session

  # Public variables
  sessionStore: null
  logger: new Logger "session"

  constructor: (@app) ->
    @server = @app.server
    @init()
    this

  init: () ->
    # Create redis client
    redisClient = redis.createClient @app.options.redis.port, @app.options.redis.host, @app.options.redis

    # If there's a password, use it
    if @app.options.redis.pass
      redisClient.auth @app.options.redis.pass, (err) =>
        if err then logger.error("redis:", err)

    redisClient.on "error", (err) =>
      if err.toString().match "ECONNREFUSED"
        @logger.error "redis: Connection refused. Server down?"
      else
        @logger.error "redis: Unknown error", err

    redisClient.on "end", () =>
      @logger.debug "redis: Connection closed"

    redisClient.on "ready", () =>
      @logger.info "redis: Ready to recieve commands"
      
    # Create session store
    @sessionStore = new RedisStore client: redisClient

    # Add session to connect
    @server.use(
      connect.session(
        cookie:
          httpOnly: false
          maxAge: @app.options.sessions.maxAge || null
        store: @sessionStore
        key: @app.options.sessions.key || "moon.sid"
      )
    )

module.exports = Session