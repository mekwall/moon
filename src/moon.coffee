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
  ###
  constructor: (options, @env = process.env.NODE_ENV || "development") ->

    # Create configurator
    @config = new Config()

    # Add defaults
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
          app: path.resolve process.cwd()
          static: path.resolve process.cwd() + "/public"
          views: path.resolve process.cwd() + "/views"
          favicon: path.resolve process.cwd() + "/public/favicon.ico"
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

      @server = new Server @

      # Create router
      @router = new director.http.Router().configure @options.router

    # Instantiate template engine
    #@template = Template.init @

    @initialized = true
    # Return
    this

  ###
    Shortcut to server .use
    Registers a middleware
  ###
  use: (fn) ->
    if @server
      @server.use fn

  ###
    Configure
  ###
  configure: (env, opts) ->
    unless env then return @options
    unless opts then return @config.get env
    @config.set env, opts
    unless @options then @options = @config.get env
    this

  ###
    Load config from file
  ###
  loadConfig: (file) ->
    @config.loadFromFile file
    @options = @config.get()
    this

  ###
    Shorthand to register a get route
  ###
  get: (pattern, cb) ->
    @init() unless @initialized
    if @router
      @router.get pattern, cb
    this

  ###
    Shorthand to register a post route
  ###
  post: (pattern, cb) ->
    @init() unless @initialized
    if @router
      @router.post pattern, cb

  ###
    Shorthand to register scoped route
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
  ###
  routes: (routes) ->
    @init() unless @initialized
    if @router
      @router.mount routes

  ###
    Add host
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
        @_workers++
        @workers[worker.pid] = worker

        # On worker death
        @cluster.on "death", (worker) =>
          message = "Worker ##{worker.pid} died"
          if (!worker.refork) and (worker.exitCode > 0)
            message += " with error: code " + worker.exitCode

          # Remove worker from master list
          delete @workers[worker.pid]

          if worker.refork or @env is "development"
            worker = @cluster.fork()
            @workers[worker.pid] = worker
          else
            @_workers--
            logger.info message

          if @_workers is 0
            logger.error "All workers are dead. Exiting."
            process.exit 0

      process.on "message", (msg) =>
        return unless msg.cmd
        switch msg.cmd
          when "restart"
            for pid,i of @workers
              @workers[pid].send msg

    else

      # If this is a cluster worker
      if @cluster.isWorker
        process.on "message", (msg) =>
          switch msg.cmd
            when "pushToSockets" then @server.pushToSockets msg.data
            when "stop", "restart" then process.exit(0)
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
        res = this.res
        unless template.match(/.jade/i)
          template = template + ".jade"
        file = path.resolve self.options.paths.views + "/" + template
        unless path.existsSync file
          res.writeHead 500
          res.end "Template does not exist"
        else
          jade.renderFile file, options, (err, html) ->
            if err
              res.writeHead 500
              res.end err.stack
            else
              res.writeHead 200
              res.end html

      @router.attach () ->
        @render = renderTemplate

      # Dispatch router on request
      @server.use (req, res, next) =>
        @router.dispatch req, res, (err) ->
          return next() unless err
          res.statusCode = 404
          next req.url+" not found"

      @server.listen()


utils.addChaining(
    Application.prototype, "properties", attr
  ) for attr of Application.prototype.properties

module.exports = Application