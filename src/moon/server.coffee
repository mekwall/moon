###
  Moon.js
###

# Dependencies
http = require 'http'
connect = require 'connect'
connectRedis = require 'connect-redis'
io = require 'socket.io'

# Import classes
RedisStore = connectRedis connect
Session = connect.middleware.session.Session
Logger = require './logger'

# Import functions
parseCookie = connect.utils.parseCookie
parseSignedCookies = connect.utils.parseSignedCookies

director = require 'director'

###
  Server
###
class Server

  # Private variables
  logger = new Logger "server"
  socketLogger = new Logger "socket"
  redisLogger = new Logger "redis"

  # Public varialbes
  app: null
  http: null
  socket: null
  initialized: false

  ###
    Constructor
  ###
  constructor: (@app) ->
    @init()

  ###
    Initialize
  ###
  init: () ->
    return if @initialized
    self = @

    if (!@app.options.cluster || @app.cluster.isWorker)

      @http = connect()
        .use( connect.favicon @app.options.paths.static + "/favicon.ico" )
        .use( connect.bodyParser() )
        .use( connect.compress() )
        .use( connect.cookieParser( @app.options.cookies.secret ) )

      # Create redis clients
      sessionRedisClient = require('redis').createClient @app.options.redis.port, @app.options.redis.host, @app.options.redis
      socketRedisClient = require('redis').createClient @app.options.redis.port, @app.options.redis.host, @app.options.redis

      if @app.options.redis.pass

        sessionRedisClient.auth @app.options.redis.pass, (err) ->
          if err then redisLogger.error("SessionClient:", err)

        socketRedisClient.auth @app.options.redis.pass, (err) ->
          if err then redisLogger.error("SocketClient:", err)

      sessionRedisClient.on "error", (err) ->
        redisLogger.error "SessionClient:", err

      socketRedisClient.on "error", (err) ->
        redisLogger.error "SocketClient:", err

      sessionRedisClient.on "end", (err) ->
        redisLogger.debug "SessionClient: Connection closed"

      socketRedisClient.on "end", (err) ->
        redisLogger.debug "SessionClient: Connection closed"

      # Create stores
      sessionRedisClient.on "ready", () ->
        redisLogger.info "SessionClient: Ready to recieve commands"
        self.sessionStore = new RedisStore client: sessionRedisClient
        self.http.use(
          connect.session(
            cookie:
              httpOnly: false
              maxAge: self.app.options.sessions.maxAge || null
            store: @sessionStore
            key: "moon.sid"
          )
        )

      socketRedisClient.on "ready", () ->
        redisLogger.info "SocketClient: Ready to recieve commands"
        self.socketStore = new io.RedisStore(
          redisPub: socketRedisClient,
          redisSub: socketRedisClient,
          redisClient: socketRedisClient
        )

        self.socket = io.listen(
          self.http,
          store: self.socketStore,
          resource: self.app.options.socket.resource || "/sio",
          authorization: true,
          "log level": 0
        )

        self.socket.configure "production", () ->
          self.socket.enable('browser client etag');
          transports = [
            "websocket", 
            #"flashsocket",
            #"htmlfile",
            "xhr-polling",
            "jsonp-polling"
          ]
          self.socket.set "transports", transports;
          socketLogger.info "Transports enabled:", transports.join ","
          #self.socket.set "error", logger

        self.socket.configure "development", () ->
          transports = [ "websocket" ]
          self.socket.set "transports", transports
          socketLogger.info "Transports enabled:", transports.join ","
          #self.socket.set "error", logger

        self.socket.on "authorization", (data, response) ->
          if data.headers.cookie
            data.cookie = parseCookie data.headers.cookie
            data.cookie = parseSignedCookies data.cookie, self.app.options.cookies.secret
            data.sessionID = data.cookie["moon.sid"]
            socketLogger.debug "Handshake:", data.sessionID
            try
              sessionStore.get data.sessionID, (err, session) ->
                if err or !session
                  logger.debug('Socket handshake failed: ID:' + data.sessionID);
                  response "AUTH_ERROR", false
                else
                  # create a session object, passing data as request and our
                  # just acquired session data
                  data.session = new Session data, session
                  logger.debug "Authenticated:", data.sessionID
                  response null, true
            catch e
              logger.error "SessionStore:", e
              response "AUTH_ERROR", false
          else
            return response "MISSING_COOKIE", false

        self.socket.on "connection", (socket) ->
          self.socketConnection socket

      @http.use (req, res, next) ->
        unless req.session then req.session = {}
        logger.debug "HTTP request:", req.method, req.url.bold
        if self.app.options.server and self.app.options.server.poweredBy
          res.setHeader "X-Powered-By", self.app.options.server.poweredBy
        next()

    @initialized = true
    this

  ###
    Socket connection
  ###
  socketConnection: (socket) ->
    self = @
    hs = socket.handshake
    socket.join hs.sessionID
    @sockets[hs.sessionID] = socket
    socketLogger.debug "Connected:", hs.sessionID
    # setup an inteval that will keep our session fresh
    intervalID = setInterval () ->
        # reload the session (just in case something changed,
        # we don't want to override anything, but the age)
        # reloading will also ensure we keep an up2date copy
        # of the session with our connection.
        try
          hs.session.reload () ->
            # "touch" it (resetting maxAge and lastAccess)
            # and save it back again.
            hs.session.touch().save()
        catch e
          socketLogger.error "Failed to reload session: ", hs.sessionID, e
      , 60 * 1000

    socket.on "disconnect", () ->
      delete self.sockets[hs.sessionID];
      socketLogger.debug "Socket disconnected:", hs.sessionID
      # clear the socket interval to stop refreshing the session
      clearInterval intervalID

  ###
    Shorthand for use
  ###
  use: (fn) ->
    @http.use fn
    this

  ###
    Listen
  ###
  listen: (cb) ->
    @init() unless @initialized

    @http
      .use( connect.static @app.options.paths.static )

    unless cb
      cb = () ->
        unless process.isMaster
          logger.info("Process ##{process.pid} is listening")
        else unless cluster.restarted
          logger.info("Worker ##{process.pid} is listening")

    # Attach server
    http.createServer(@http)

    @http.listen(
      @app.options.http.port || null, 
      @app.options.http.host || null, 
      cb || null
    )

    this

module.exports = Server