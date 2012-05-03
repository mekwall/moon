###
  Moon.js
###

# Dependencies
_ = require "underscore"
http = require "http"
connect = require "connect"
httpProxy = require "http-proxy"
io = require "socket.io"
redis = require "redis"
director = require "director"

# Import classes
Logger = require "./logger"

# Import functions
parseCookie = connect.utils.parseCookie
parseSignedCookies = connect.utils.parseSignedCookies

# apply some patches to response object
# based on the connect patch
res = http.ServerResponse.prototype
do ->
  setHeader = res.setHeader
  _renderHeaders = res._renderHeaders
  writeHead = res.writeHead

  unless res._hasMoonPatch
    res.__defineGetter__ "protocol", () ->
      if req.isHttps
        return "HTTPS"
      else if req.isSpdy
        return "SPDY"
      else
        return "HTTP"

    res._hasMoonPatch = true
  
  unless res._hasConnectPatch
    res.__defineGetter__ "headerSent", () ->
      @_header || false

    res.setHeader = (field, val) ->
      key = field.toLowerCase()

      # special-case Set-Cookie
      if @_headers and key is "set-cookie"
        rev = @getHeader field
        if rev
          val = prev.concat(val) if Array.isArray(prev) else [prev, val]

      # charset
      else if @.charset and key is "content-type"
        val += '; charset=' + @charset
      setHeader.call @, field, val

    res._renderHeaders = () ->
      @emit "header" unless @_emittedHeader
      @_emittedHeader = true
      _renderHeaders.call @

    res.writeHead = () ->
      @emit "header" unless @_emittedHeader
      @_emittedHeader = true
      writeHead.apply @, arguments

    res._hasConnectPatch = true

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
  sockets: null
  initialized: false
  middleware: []
  _sockets: {}

  ###
    Constructor
  ###
  constructor: (@app) ->
    @init()
    @

  ###
    Initialize
  ###
  init: () ->
    return if @initialized

    if (!@app.options.cluster || @app.cluster.isWorker)

      @proxy = new httpProxy.HttpProxy
        target:
          host:  @app.options.http.host || "localhost"
          port: @app.options.http.port || 3000

      # HTTP
      @http = http.createServer (req, res) =>
        if @app.env is "development"
          logger.debug "#{req.protocol} request: #{req.method} #{req.url.bold}"

        if req.url is "/favicon.ico"
          res.end require("fs").readFileSync @app.options.paths.static + "/favicon.ico"
          return

        if @app.options.server and @app.options.server.poweredBy
          res.setHeader "X-Powered-By", @app.options.server.poweredBy
        @handle req, res

      # HTTPS
      if @app.options.https and @app.options.https.enabled

        https = require "https"
        fs = require "fs"

        options =
          key: fs.readFileSync @app.options.https.key
          cert: fs.readFileSync @app.options.https.cert

        @https = https.createServer options, (req, res) =>
          req.isHttps = true
          @proxy.proxyRequest req, res

      # SPDY
      if @app.options.spdy and @app.options.spdy.enabled

        spdy = require "spdy"
        fs = require "fs"

        options =
          key: fs.readFileSync @app.options.spdy.key
          cert: fs.readFileSync @app.options.spdy.cert
          ca: fs.readFileSync @app.options.spdy.ca
          ciphers: '!aNULL:!ADH:!eNull:!LOW:!EXP:RC4+RSA:MEDIUM:HIGH'
          maxStreams: 15

        @spdy = spdy.createServer options, (req, res) =>
          # push js init script
          #@spdy.push "/js/moon.js", "content-type": "application/javascript"
          logger.debug "SPDY request: #{req.method} #{req.url.bold}"
          @proxy.proxyRequest req, res

      @use connect.bodyParser()
      @use @app.assets.middleware()
      @use connect.cookieParser @app.options.cookies.secret
      @use @app.session.middleware()

    @initialized = true
    this

  ###
    Push data to sockets
  ###
  pushToSockets: (data) ->
    for id,socket of @_sockets
      socket.emit "_moon", data

  ###
    Socket connection
  ###
  socketConnection: (socket) ->
    hs = socket.handshake
    socket.join hs.sessionID
    @_sockets[hs.sessionID] = socket
    socketLogger.debug "Connected:", hs.sessionID
    # setup an inteval that will keep our session fresh
    intervalID = setInterval () ->
        # reload the session (just in case something changed,
        # we don"t want to override anything, but the age)
        # reloading will also ensure we keep an up2date copy
        # of the session with our connection.
        try
          hs.session.reload () ->
            # "touch" it (resetting maxAge and lastAccess)
            # and save it back again.
            hs.session.touch().save()
        catch e
          #socketLogger.error "Failed to reload session:", hs.sessionID, e
      , 60 * 1000

    socket.on "disconnect", () =>
      delete @_sockets[hs.sessionID]
      socketLogger.debug "Disconnected:", hs.sessionID
      # clear the socket interval to stop refreshing the session
      clearInterval intervalID

  ###
    Attach middlewares
  ###
  use: (fn) ->
    unless fn
      logger.debug "Nothing was passed to use()"
      @

    # wrap sub-apps
    if typeof fn.handle is "function"
      server = fn
      fn = (req, res, next) ->
        server.handle req, res, next

    # wrap vanilla http.Servers
    if fn instanceof http.Server
      fn = fn.listeners('request')[0]

    if typeof fn is "function"
      logger.debug "Attached middleware:", fn.name || fn.constructor.name
      @middleware.push fn
    @

  ###
    Handle request
  ###
  handle: (req, res, out) ->

    env = @app.env
    stack = @middleware
    idx = 0

    next = (err=null) ->
      # get next in stack
      mw = stack[idx++]

      # no more in stack or headers sent
      if !mw or res.headerSent

        # delegate to parent
        return out err if out

        if res.headerSent
          # destroy socket if headers already sent
          return req.socket.destroy() 

        # unhandled error
        if err
          # default to 500
          res.statusCode = 500 if res.statusCode < 400
          # log error
          logger.error "HTTP error:", err
          # set correct error status
          res.statusCode = err.status if err.status
          # production gets a basic error message
          if env is "production" 
            msg = http.STATUS_CODES[res.statusCode.toString()]
          else
            msg = err.stack || err.toString()
        else
          logger.debug "HTTP error: File Not Found"
          res.statusCode = 404
          msg = "Cannot " + req.method + " " + _.escape req.originalUrl
        # set necessary headers
        res.setHeader "Content-Type", "text/plain"
        res.setHeader "Content-Length", Buffer.byteLength(msg)
        # respond without content if method is HEAD
        return res.end() if req.method is "HEAD"
        # otherwise respond with message
        res.end msg
        return

      # no more in stack or headers sent
      next err if err
      # send to middleware
      logger.debug "Sending "+req.url+" to " + (mw.name || mw.constructor.name)
      mw req, res, next
      return

    next()


  ###
    Listen
  ###
  listen: (cb) ->
    @init() unless @initialized

    unless cb
      cb = () ->
        unless process.isMaster
          logger.info("Process ##{process.pid} is listening")
        else unless cluster.restarted
          logger.info("Worker ##{process.pid} is listening")

    @http.listen @app.options.http.port or null, @app.options.http.host or null, cb or null

    if @https
      @https.listen @app.options.https.port or 3443, @app.options.https.host or null
    else if @spdy
      @spdy.listen @app.options.spdy.port or 3443, @app.options.spdy.host or null
    
    # Create redis clients
    subClient = redis.createClient @app.options.redis.port, @app.options.redis.host, @app.options.redis
    redisClient = redis.createClient @app.options.redis.port, @app.options.redis.host, @app.options.redis

    # Bind some events
    subClient
      .on "error", (err) ->
        if err.toString().match "ECONNREFUSED"
          socketLogger.error "redis: Connection refused. Server down?"
        else
          socketLogger.error "redis: Unknown error", err

      .on "end", ->
        socketLogger.debug "redis: Connection closed"

      .on "ready", ->
        socketLogger.info "redis: Ready to recieve commands"

    redisClient
      .on "error", (err) ->
        if err.toString().match "ECONNREFUSED"
          socketLogger.error "redis: Connection refused. Server down?"
        else
          socketLogger.error "redis: Unknown error", err

      .on "end", ->
        socketLogger.debug "redis: Connection closed"

      .on "ready", ->
        socketLogger.info "redis: Ready to recieve commands"

    if @app.options.redis.pass
      subClient.auth @app.options.redis.pass, (err) =>
        if err then socketLogger.error "redis:", err
      redisClient.auth @app.options.redis.pass, (err) =>
        if err then socketLogger.error "redis:", err

    @socketStore = new io.RedisStore(
      redisPub: redisClient,
      redisSub: subClient,
      redisClient: redisClient
    )

    @sockets = io.listen @http,
      store: @socketStore
      resource: @app.options.sockets.resource || "/sio"
      logger: logger
      error: logger
      "log level": 1

    secret = @app.options.cookies.secret
    @sockets.set "authorization", (data, response) =>
      if data.headers.cookie
        data.cookie = parseCookie data.headers.cookie
        data.cookie = parseSignedCookies data.cookie, secret
        data.sessionID = data.cookie["moon.sid"]
        socketLogger.debug "Handshake: ID:" + data.sessionID
        try
          @app.session.get data.sessionID, data, (session) ->
            unless session
              socketLogger.debug "Handshake failed: ID:" + data.sessionID
              response "AUTH_ERROR", false
            else
              data.session = session
              socketLogger.debug "Authenticated: ID:" + data.sessionID
              response null, true
        catch e
          socketLogger.error "redis:", e
          response "AUTH_ERROR", false

      else
        return response "MISSING_COOKIE", false

    # default transport
    transports = [ "websocket" ]

    unless @app.env in [ "development", "testing" ]
      # enable etag, minification and gzip for production
      @sockets
        .enable( "browser client etag" )
        .enable( "browser client minification" )
        .enable( "broswer client gzip" )
      # add additional transports
      transports.concat [ "websocket", "xhr-polling", "jsonp-polling" ]

    @sockets.set "transports", transports
    socketLogger.info "Transports enabled:", transports.join ", "

    if @https
      @sockets.on "upgrade", (req, socket, head) ->
        @proxy.proxyWebSocketRequest req, socket, head

    @sockets.on "connection", (socket) =>
      @socketConnection socket

    @

module.exports = Server