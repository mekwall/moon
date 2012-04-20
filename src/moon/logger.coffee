###
  Moon.js
###

# Dependencies
_s = require "underscore.string"
utils = require "./utils"

try
  winston = require "winston"
  winston.addColors
      log: "white"
      info: "cyan"
      warn: "yellow"
      error: "red"
      debug: "yellow"

  ###
  transport = new (winston.transports.Console)(
    colorize: true,
    prettyPrint: true,
    handleExceptions: false
    timestamp: () -> return utils.timeString() 
  )

  @logger = new winston.Logger
    exitOnError: false,
    transports: [
      transport
    ]

  @logger.setLevels winston.config.npm.levels
  ###

###
  Logger
###
module.exports = class Logger

  # Private variables
  levels = [ "log", "error", "warn", "info", "debug" ]

  # Public variables
  colors: [ "white", "red", "yellow", "green", "cyan" ]
  level: 6

  ###
    Constructor
  ###
  constructor: (@name, @opts = {}) ->
    @env = @opts.env || (process.env.NODE_ENV || "development")
    unless @opts.level
      @level = 3 if @env is "production"
      @level = 6 if @env is "development"
      @level = 6 if @env is "test"
    else
      @level = @opts.level
    @enabled = true
    @

  ###
    New line
  ###
  newLine: (num=1) ->
    console.log _s.repeat "\n", num-1

  ###
    Log message
  ###
  log: (message..., type) ->
    index = levels.indexOf(type)
    return this if index > @level or not @enabled
    time = utils.timeString()
    if @env is "development"
      sp1 = "         ".split(" ").slice(@name.length).join(" ")
      sp2 = "      ".split(" ").slice(type.length).join(" ")
      output = [ ("\ " + time + "").grey, "".grey + @name.white + sp1 + type[@colors[index]] + sp2 + ">".grey ].concat(message)
    else
      output = [ ("\ " + time + ""), "" + @name + "." + type + " >" ].concat(message)
    unless console[type]
      message = type
      type = "log"
    type = "log" if type is "debug"
    console[type].apply console, output

  ###
    Error handler
  ###
  error: (message, error) ->
    if error and error.stack
      error = error.stack
      if @env is "development"
        error.red.bold
      message += "\n"
    @log.apply this, [message, error || ""].concat([ "error" ])


  ###
    Create methods for each level
  ###
  levels.forEach (name) ->
    return if name is "log"
    return if name is "error"
    Logger::[name] = ->
      @log.apply this, Array::slice.call(arguments).concat([ name ])
    return