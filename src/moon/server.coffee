###
  Moon.js
###

# Dependencies
fs = require "fs"
temp = require "temp"
_ = require "underscore"
http = require "http"
connect = require "connect"
httpProxy = require "http-proxy"
io = require "socket.io"
cookie = require "cookie"

# Import classes
Logger = require "./logger"

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

  # Public variables
  app: null
  http: null
  sockets: null
  initialized: false
  stack: []
  _sockets: {}

  ###
    Constructor
  ###
  constructor: (@app) ->
    @init()
    return @

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

        unless @procotol
          if req.https
            req.protocol = "HTTPS"
          else
            req.protocol = "HTTP" 

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
  use: (route, fn) ->
    # default route to "/"
    unless typeof route is "string"
      fn = route
      route = "/"

    # wrap sub-apps
    if typeof fn.handle is "function"
      server = fn
      fn.route = route
      fn.name = server.name || server.handle.name
      fn = (req, res, next) ->
        server.handle req, res, next

    # wrap vanilla http.Servers
    if fn instanceof http.Server
      fn = fn.listeners("request")[0]

    # strip trailing slash
    if route[route.length - 1] is "/"
      route = route.slice 0, -1

    logger.debug "Attached middleware:", fn.name || fn.constructor.name
    @stack.push { route: route, handle: fn }
    return @

  ###
    Handle request
  ###
  handle: (req, res, out) ->

    env = @app.env
    fqdn = ~req.url.indexOf "://"
    stack = @stack
    removed = ''
    slashAdded = false
    idx = 0

    # set original url
    req.originalUrl = req.originalUrl or req.url

    next = (err) ->
      if slashAdded
        req.url = req.url.substr(1)
        slashAdded = false

      # put the prefix back on if it was removed
      req.url = removed + req.url
      req.originalUrl = req.originalUrl or req.url
      removed = ''

      # next callback
      layer = stack[idx++]

      # no more in stack or headers sent
      if !layer or res.headerSent

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
          logger.debug "HTTP error:", err
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

      try
        path = connect.utils.parseUrl(req).pathname
        path = "/" if path is undefined

        # skip this layer if the route doesn't match.
        if path.indexOf(layer.route) is not 0 then return next err

        c = path[layer.route.length]
        if c and c is not "/" and c is not '.' then return next err

        # call the layer handler
        # trim off the part of the url that matches the route
        removed = layer.route
        req.url = req.url.substr removed.length

        # ensure leading slash
        if not fqdn and req.url[0] is not "/"
          req.url = "/" + req.url
          slashAdded = true

        # send to middleware
        logger.debug "Sending " + req.url + " to " + (layer.handle.name || layer.handle.constructor.name || 'anonymous')
        arity = layer.handle.length

        # no more in stack or headers sent
        if err
          if arity == 4
            layer.handle err, req, res, next
          else
            next err
        else if arity < 4
          layer.handle req, res, next
        else
          do next
      catch e
        next e

      return

    do next


  ###
    Listen
  ###
  listen: (cb) ->
    @init() unless @initialized

    unless cb
      cb = () ->
        unless process.isMaster
          logger.info "Process ##{process.pid} is listening"
        else unless cluster.restarted
          logger.info "Worker ##{process.pid} is listening"

    @http.listen @app.options.http.port or null, @app.options.http.host or null, cb or null

    if @https
      @https.listen @app.options.https.port or 3443, @app.options.https.host or null
    else if @spdy
      @spdy.listen @app.options.spdy.port or 3443, @app.options.spdy.host or null

    if @app.options.redis.enabled
      redis = require "redis"

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
        error: logger
        "log level": 1

    else if @app.cluster
      logger.warn "MemoryStore and clustering does not work together! Please enable Redis to share sessions."

    if not @sockets
      @sockets = io.listen @http,
        resource: @app.options.sockets.resource || "/sio"
        error: logger
        "log level": 1

    secret = @app.options.cookies.secret
    @sockets.set "authorization", (data, response) =>
      if data.headers.cookie
        data.cookie = (cookie.parse data.headers.cookie)["moon.sid"]
        data.sessionID = connect.utils.parseSignedCookie data.cookie, secret
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

    # Build socket.io.js and add to built-in assets
    filename = @app.options.paths.assets + "/scripts/socket.io.js"
    file = @sockets.static.has "/socket.io.js"
    file.callback "/socket.io.js", (e, content) =>
      temp.open "moon-socket.io-", (e, info) =>
        fs.write info.fd, content.toString()
        fs.close info.fd, (e) =>
          @app.assets.add js: moon: [
            # Socket.io client
            info.path
          ]
    @

module.exports = Server