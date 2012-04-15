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
  sessionStore = null
  logger = new Logger "app"

  # Public variables
  workers: []
  config: null
  options: null
  cluster:
    isMaster: false,
    isWorker: false

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
        http:
          port: 3000,
          host: ""
        paths:
          app: path.resolve process.cwd()
          static: path.resolve process.cwd() + "/public"
          views: path.resolve process.cwd() + "/views"
        socket:
          resource: "/socket"
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
          poweredBy: "moon.js"
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
      @cluster = require("cluster")

    # Create server
    if (!@options.cluster || @cluster.isWorker)

      @server = new Server @

      self = @
      # Create router
      @router = new director.http.Router()
        .configure(@options.router)

    # Instantiate template engine
    #@template = Template.init @

    @initialized = true
    # Return
    this

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
    this

  ###
    Shorthand to register scoped route
  ###
  path: (pattern, path) ->
    @init() unless @initialized
    if @router
      @router.path pattern, path
    this

  ###
    Add multiple routes
  ###
  routes: (routes) ->
    @init() unless @initialized
    if @router
      @router.mount(routes)
    this

  ###
    Restart application
  ###
  restart: () ->
    if @options.cluster
      for pid of @workers
        worker = @workers[pid]
        worker.refork = true
        worker.send { cmd: "stop" }
    else
      process.exit(0)

  ###
    Start application
  ###
  start: () ->
    @init() unless @initialized
    self = @

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

    if (!@options.cluster or @cluster.isMaster) and (@env is "development")
      @watcher = new Watcher (event, file, patch) ->
        switch event
          when "reload"
            logger.debug "Restarting to reflect changes"
            self.restart()

    # If this is the cluster master
    if @cluster.isMaster
      amount = @options.workers || require("os").cpus().length
      logger.info "Forking #{amount}", if amount > 1 then "workers" else "worker"
      amount++
      while amount -= 1
        worker =  @cluster.fork()
        @workers[worker.pid] = worker
        @cluster.on "death", (worker) ->
          message = "Worker ##{worker.pid} died"
          if (!worker.refork) and (worker.exitCode > 0)
            message += " with error: code " + worker.exitCode

          # Remove worker from master list
          delete self.workers[worker.pid]

          if worker.refork
            worker = self.cluster.fork()
            self.workers[worker.pid] = worker
          else
            logger.info message

          if self.workers.length is 0
            logger.error "All workers are dead. Exiting."
            process.exit 0

      process.on "message", (msg) ->
        return unless msg.cmd
        switch msg.cmd
          when "restart"
            for pid of @workers
              @workers[pid].send msg

    else
      # If this is a cluster worker
      if @cluster.isWorker
        process.on "message", (msg) ->
          switch msg.cmd
            when "stop" then process.exit()

      else
        process
          .on "restart", () ->
            self.restart()

          .on "exit", () ->
            logger.info "Process ##{process.pid} exiting"

          .on "SIGHUP", () ->
            logger.debug "Process ##{process.pid} got SIGHUP"

      process.on "uncaughtException", (err) ->
        logger.error "Uncaught exception:", err

      # Attach simple template engine
      errorTemplate = path.resolve @options.paths.views + "/error.jade"
      @router.attach () ->
        @render = (template, options) ->
          res = this.res
          unless template.match(/.jade/i)
            template = template + ".jade"
          file = path.resolve self.options.paths.views + "/" + template

          unless path.existsSync file
            res.writeHead 404
            res.end()
          else
            jade.renderFile file, options, (err, html) ->
              if err
                res.writeHead 500
                res.end err.stack
              else
                res.writeHead 200
                res.end html

      # Attach router
      @server.use (req, res, next) ->
        self.router.dispatch req, res, (err) ->
          if err
            stack = err.stack
            if self.router.routes[404]
              self.router.routes[404].on.apply @, [stack]
            else if self.env is "development"
              @res.end stack
            #tmplError @res, "Route Not Found", "The requested route does not exist: "+req.url, err
            return @
          next()
          return @
              
      @server.listen()

    this
 
module.exports = Application