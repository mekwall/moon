###
  Moon.js
###

# Dependencies
fs = require "fs"
path = require "path"
colors = require "colors"
utils = require "./moon/utils"
director = require "director"
jade = require "jade"

# Import classes
Config  = require "./moon/config"
Logger  = require "./moon/logger"
Watcher = require "./moon/watcher"
Assets  = require "./moon/assets"
Session = require "./moon/session"
Server  = require "./moon/server"
Template = require "./moon/template"

# Load and parse package.json
pkg = JSON.parse fs.readFileSync __dirname + "/../package.json"

###
  Application
###
class Application

  # Private variables
  logger = new Logger "app"

  # Public variables
  workers: []
  _workers: 0
  config: null
  options: null
  cluster:
    isMaster: false,
    isWorker: false
  currentHost: "*"

  ###
    Constructor
    @param options
    @param env defaults to development
  ###
  constructor: (options, @env = process.env.NODE_ENV || "development") ->

    # Create configurator
    @config = new Config()

    # Add defaults
    cwd = process.cwd()
    @config.defaults(
        cluster: false,
        workers: null,
        hosts:
          "*": {}
        http:
          enabled: true
          port: 3000
        https:
          enabled: false
          port: 443
        sockets:
          resource: "/sio"
        paths:
          app: path.resolve cwd
          static: path.resolve cwd + "/public"
          views: path.resolve cwd + "/views"
          favicon: path.resolve cwd + "/public/favicon.ico"
          assets: path.resolve cwd + "/assets"
        cookies:
          secret: "natural satellite"
        sessions:
          secret: "natural satellite"
        router:
          recurse: "backward",
          async: true
        redis:
          host: "127.0.0.1",
          port: 6379
        server:
          poweredBy: "Moon.js"
      )

    if options
      @config.set @env options

    this

  ###
    Init
  ###
  init: () ->
    # Only initialize once
    return this if @initialized
    unless @options
      @config.set @env, {}
      @options = @config.get()

    if @options.cluster
      @cluster = require "cluster"

    # Create server
    if (!@options.cluster || @cluster.isWorker)

      # Asset manager
      @assets = new Assets @

      # Session handler
      @session = new Session @

      # Server
      @server = new Server @

      # Router
      @router = new director.http.Router().configure @options.router

    # Instantiate template engine
    #@template = Template.init @

    @initialized = true
    # Return
    this

  ###
    Shortcut to server .use
    Registers a middleware
    @param fn
  ###
  use: (fn) ->
    if @server
      @server.use fn

  ###
    Configure
    @param env
    @param opts
  ###
  configure: (env, opts) ->
    unless env then return @options
    unless opts then return @config.get env
    @config.set env, opts
    unless @options then @options = @config.get env
    this

  ###
    Load config from file
    @param file
  ###
  loadConfig: (file) ->
    @config.loadFromFile file
    @options = @config.get()
    this

  ###
    Shorthand to register a get route
    @param pattern
    @param cb
  ###
  get: (pattern, cb) ->
    @init() unless @initialized
    if @router
      @router.get pattern, cb
    this

  ###
    Shorthand to register a post route
    @param pattern
    @param cb
  ###
  post: (pattern, cb) ->
    @init() unless @initialized
    if @router
      @router.post pattern, cb

  ###
    Shorthand to register scoped route
    @param pattern
    @param path
  ###
  path: (pattern, path) ->
    @init() unless @initialized
    if @router
      @router.path pattern, path

  ###
    vHost support
  ###
  host: (host) ->
    @currentHost = host

  ###
    Add multiple routes
    @param routes
  ###
  routes: (routes) ->
    @init() unless @initialized
    if @router
      if typeof routes is "string"
        try
          routes = require process.cwd() + "/" + routes
        catch e
          return logger.error "Could not load routes:", e
      @router.mount routes

  ###
    Add host
    @param host
  ###
  addHost: (host) ->

  ###
    Send command to workers
  ###
  sendCommandToWorkers: (cmd, data={}) ->
    if @options.cluster
      for pid,i of @workers
        if cmd is "restart"
          @workers[pid].refork = true
        @workers[pid].send cmd: cmd, data: data
    else
      process.exit 0

  ###
    Command application
    @param cmd
    @param args
  ###
  command: (cmd, args...) ->

  ###
    Restart application
  ###
  restart: () ->
    if @options.cluster
      @sendCommandToWorkers "restart"
    else
      process.exit 0

  ###
    Start application
    @param start
  ###
  start: () ->
    @init() unless @initialized

    unless @cluster.isWorker
      # Banner
      if @env is "development"
        logger.newLine 1
        banner = """
\                                      __        
\  .--------..-----..-----..-----.    |__|.-----.
\  |        ||  _  ||  _  ||     | __ |  ||__ --|
\  |__|__|__||_____||_____||__|__||__||  ||_____|
\ """.cyan.bold
        banner += "     real-time framework for node  ".grey+"|___| ".cyan.bold + ("v" + pkg.version).grey
        console.log banner
        logger.newLine 1
      else
        logger.newLine 1
        console.log " moon v"+pkg.version
        logger.newLine 1
      logger.info "Running on node", process.version
      logger.info "Environment:", @env

    # If master and is in development, init watcher for autoreload
    if (!@options.cluster or @cluster.isMaster) and (@env is "development")
      @watcher = new Watcher (event, data) =>
        switch event
          when "error"
            logger.debug "Pushing errors to sockets"
            data.error = error: data.error.toString(), stack: data.error.stack, file: data.file
            @sendCommandToWorkers "pushToSockets", event: event, data: data
          when "change"
            logger.debug "Pushing changes to sockets"
            @sendCommandToWorkers "pushToSockets", event: event, data: data
          when "reload"
            logger.debug "Reloading to reflect changes"
            @restart()

    # If this is the cluster master
    if @options.cluster && @cluster.isMaster
      amount = @options.workers || require("os").cpus().length
      logger.info "Forking #{amount}", if amount > 1 then "workers" else "worker"
      amount++
      while amount -= 1
        worker =  @cluster.fork()
        # uniqueID is not set in pre v0.8
        if not worker.uniqueID then worker.uniqueID = worker.pid
        @_workers++ 
        @workers[worker.uniqueID] = worker

      # On worker exit
      @cluster.on "exit", (worker) =>
        message = "Worker ##{worker.uniqueID} died"
        if (!worker.refork) and (worker.exitCode > 0)
          message += " with error: code #{worker.exitCode}"

        # Remove worker from master list
        delete @workers[worker.uniqueID]

        if worker.refork or @env is "development"
          worker = @cluster.fork()
          @workers[worker.uniqueID] = worker
        else
          @_workers--
          logger.info message

        if @_workers is 0
          logger.error "All workers are dead. Exiting."
          process.exit 0

      @cluster.on "online", (worker) =>
        logger.debug "Worker ##{worker.uniqueID} came online"

      @cluster.on "listening", (worker, listen) =>
        logger.debug "Worker ##{worker.uniqueID}  is now listening on #{listen.address}:#{listen.port}"

      process.on "message", (msg) =>
        return unless msg.cmd
        switch msg.cmd
          when "restart"
            for pid,i of @workers
              @workers[pid].send msg

    else

      if @options.cluster is true
        # If this is a cluster worker
        if @cluster.isWorker
          process.on "message", (msg) =>
            switch msg.cmd
              when "pushToSockets"
                @server.pushToSockets msg.data
              when "stop", "restart"
                process.exit(0)
        else
          process
            .on "restart", () =>
              @restart()

            .on "exit", () =>
              logger.info "Process ##{process.pid} exiting"

            .on "SIGHUP", () =>
              logger.debug "Process ##{process.pid} got SIGHUP"

          unless process.platform is "win32" and @cluster.isMaster
            process.on "SIGINT", () =>
              logger.debug "Process ##{process.pid} got SIGINT"

      #process.on "uncaughtException", (e) ->
      #  logger.error "Uncaught Exception:", require("util").inspect e

      # Attach simple template engine
      errorTemplate = path.resolve @options.paths.views + "/error.jade"
      
      self = @
      renderTemplate = (template, options = {}) ->
        unless template.match(/.jade/i)
          template = template + ".jade"
        file = path.resolve self.options.paths.views + "/" + template
        unless path.existsSync file
          @error new Error("Template does not exist")
        else
          options.css = (pkg) -> self.assets.css pkg
          options.js = (pkg) -> self.assets.js pkg
          options.jst = (pkg) -> self.assets.jst pkg
          jade.renderFile file, options, (err, html) =>
            if err
              logger.error "Error occured: ", err
              @error err 
            else
              @send html

      # Attach methods to router
      @router.attach ->

        @error = (error, status=500) ->
          @res.writeHead status
          data =
            title: "Internal Server Error"
            error: error
            css: (pkg) -> self.assets.css pkg
            js: (pkg) -> self.assets.js pkg
            jst: (pkg) -> self.assets.jst pkg
          jade.renderFile self.options.paths.views + "/error.jade", data, (err, html) =>
              if err then console.log err
              if err then @res.end err.stack else @res.end html

        @send = (data, status=200) ->
          if typeof data is "object"
            @json(data)
          else
            if self.env is "development"
              @res.setHeader("Expires", "-1");
              @res.setHeader("Cache-Control", "private, max-age=0")
            @res.setHeader("Content-Type", "text/html; charset=UTF-8")
            @res.writeHead status
            @res.end data

        @json = (data, status=200) ->
          @res.writeHead status
          @res.setHeader("Content-Type", "application/json; charset=UTF-8")
          @res.end JSON.stringify(data)
        @render = renderTemplate

      # Dispatch router on request
      @server.use (req, res, next) =>
        @router.dispatch req, res, (err) ->
          return do next unless err
          res.statusCode = 404
          next req.url+" not found"

      do @server.listen


utils.addChaining(
    Application.prototype, "properties", attr
  ) for attr of Application.prototype.properties

module.exports = Application