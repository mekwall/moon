###
  Moon.js
###

# Dependencies
_ = require "underscore"
fs = require "fs"
path = require "path"
Logger = require "./logger"

###
  Config
###
module.exports = class Config

  logger = new Logger "config"

  ###
    Config Constructor

    Optional: provide config object and environment
  ###
  constructor: (config, env = (process.env.NODE_ENV || "development")) ->
    @env = env
    @[env] = {};
    if typeof config is "Object"
      for env of config
        @[env] config[env]

  # Container for default options
  default: {}

  ###
    Load configuration from file

    JSON and YAML is supported
  ###
  loadFromFile: (file) ->
    ext = file.split(".").pop()
    unless ext
      ext = "json"
      file = file+".json"
    accepted = "js,json,yml,yaml".split(",")

    unless accepted.indexOf ext
      logger.error "Unknown config file type"
      process.exit 0

    try
      config = fs.readFileSync file
      switch ext
        when "js", "json"
          config = JSON.parse config
        when "yml", "yaml"
          yaml = require "js-yaml"
          await yaml.loadAll config, defer config
    catch e
      logger.error "Could not read/parse config file"
      process.exit 0

    for env, cfg of config
      @set env, config[env]

  ###
    Set configuration
  ###
  set: (env, config) ->
    if @[env]
      @[env] = _.extend @[env], config
    else
      @[env] = _.extend {}, @default, config
    this

  ###
    Add defaults
  ###
  defaults: (config) ->
    @default = _.extend {}, @default, config
    @[@env] = _.extend {}, config, @[@env]
    this

  ###
    Get configuration

    Omit both env and key to get config for current environment
    Omit env to return key for current environment
  ###
  get: (env, key) ->
    if env is undefined and key is undefined then return @[@env]
    if key then @[env][key] else @[@env][env]