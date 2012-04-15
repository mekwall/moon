###
  moon.js
###

# Dependencies
require "colors"
_s = require "underscore.string"
utils = require "./utils"

###
Logger
@api public
###
module.exports = class Logger

  levels = [ "log", "error", "warn", "info", "debug" ]

  colors = [ "white", "red", "yellow".bold, "cyan", "yellow" ]

  level: 5

  constructor: (@name, @opts = {}) ->
    @env = @opts.env || (process.env.NODE_ENV || "development")
    unless @opts.level
      @level = 4 if @env is "production"
    else
      @level = @opts.level
    @enabled = true

  newLine: (num=1) ->
    console.log _s.repeat "\n", num-1

  log: (message..., type) ->
    index = levels.indexOf(type)
    return this if index > @level or not @enabled
    time = utils.timeString()
    if @env is "development"
      output = [ ("\ " + time + "").grey, "".grey + @name.grey + ".".grey + type[colors[index]] + " >".grey ].concat(message)
    else
      output = [ ("\ " + time + ""), "" + @name + "." + type + " >" ].concat(message)
    unless console[type]
      message = type
      type = "log"
    type = "log" if type is "debug"
    console[type].apply console, output

  error: (message, error) ->
    if error and error.stack
      error = error.stack
      if @env is "development"
        error.red.bold
      message += "\n"
    @log.apply this, [message, error || ""].concat([ "error" ])

  levels.forEach (name) ->
    return if name is "log"
    return if name is "error"
    Logger::[name] = ->
      @log.apply this, Array::slice.call(arguments).concat([ name ])
    return