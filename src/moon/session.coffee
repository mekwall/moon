###
  Moon.js
###

# Dependencies
redis = require "redis"
connect = require "connect"
connectRedis = require "connect-redis"

# Import classes
Logger = require "./logger"
RedisStore = connectRedis(connect)
ConnectSession = connect.middleware.session

###
  Session
###
class Session

  # Private variables
  sessionStore = null
  logger = new Logger "session"

  ###
    Constructor
  ###
  constructor: (@app) ->
    @init()
    this

  ###
    Init
  ###
  init: ->
    # Create redis client
    redisClient = redis.createClient @app.options.redis.port, @app.options.redis.host, @app.options.redis

    # If there's a password, use it
    if @app.options.redis.pass
      redisClient.auth @app.options.redis.pass, (err) ->
        if err then logger.error("redis:", err)

    # bind some events
    redisClient
      .on "error", (err) ->
        if err.toString().match "ECONNREFUSED"
          logger.error "redis: Connection refused. Server down?"
        else
          logger.error "redis: Unknown error", err

      .on "end", () ->
        logger.debug "redis: Connection closed"

      .on "ready", () ->
        logger.info "redis: Ready to recieve commands"
      
    # Create session store
    sessionStore = new RedisStore client: redisClient

  ###
    Middleware
  ###
  middleware: ->    
    return connect.session(
      cookie:
        httpOnly: false
        #maxAge: @app.options.sessions.maxAge || 0
      store: sessionStore
      key: @app.options.sessions.key || "moon.sid"
    )


  ###
    Get session
    @param id session id
    @param req requeat
    @param cb callback
  ###
  get: (id, req, cb) ->
    sessionStore.load id, (err, session) =>
      unless session
        logger.error "Could not find session: " + id
        return cb(false)

      session.save = (cb) ->
        sessionStore.set(id, session, cb)

      # create a session object, passing data as request and our
      # just acquired session data
      if req then session = new ConnectSession req, session
      cb session

module.exports = Session