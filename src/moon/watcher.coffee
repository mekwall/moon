###
  Moon.js
###

# Dependencies
_         = require "underscore"
fs        = require "fs"
fs-extra  = require "fs-extra"
crypto    = require "crypto"
temp      = require "temp"
path      = require "path"
glob      = require "glob"
jade      = require "jade"
stylus    = require "stylus"
diff      = require './diff'

# Import classes
Logger = require "./logger"

###
  Watcher
###
class Watcher

  # Private variables
  logger = new Logger "watcher"
  defaults =
    ext: "js,json,css,jade,stylus,coffee",
    include: "**/",
    exclude: "node_modules/**,test/**,package.json"

  # Temporary directory
  tempPath = temp.path()
  unless path.existsSync tempPath
    fs.mkdirSync tempPath

  # Remove temporary directory
  try
    process.on "SIGINT", ()->
      logger.debug "Cleaning up..."
      fs.unlinkSync tempPath + "/*"
      fs.rmdirSync tempPath

  catch e
    # Fallback for Windows
    # Bug in node.js prevents us to do this
    # Ref: https://groups.google.com/group/nodejs/browse_thread/thread/9a6b9214722e526f
    ###
    tty = require "tty"
    process.stdin.resume()
    tty.setRawMode true
    process.stdin.on "keypress", (char, key) ->
      if key and key.ctrl and key.name is "c"
        logger.debug "Cleaning up..."
        fs.unlinkSync tempPath + "/*"
        fs.rmdirSync tempPath
        process.exit 0
    ###

  # Public variables
  files: []

  constructor: (cb, opts) ->
    self = @
    dir = process.cwd()
    unless path.existsSync dir
      logger.error "Path does not exist"
      return
    @dir = dir
    @opts = _.extend {}, defaults, opts || {}

    if typeof @opts.ext is "string"
      @opts.ext = @opts.ext.split ","

    if typeof @opts.include is "string"
      @opts.include = @opts.include.split ","

    if typeof @opts.exclude is "string"
      @opts.exclude = @opts.exclude.split ","

    @scan () ->
      self.watch(cb)
    this

  scan: (cb) ->
    include = []
    exclude = []
    self = @

    for dir of @opts.include
      for ext of @opts.ext
        include.push "#{@opts.include[dir]}*.#{@opts.ext[ext]}"

    pattern = "{" + include.join(',') + "}"
    glob pattern, nonegate: true, (err, files) ->
      include = files

      for dir of self.opts.exclude
        exclude.push "**/#{self.opts.exclude[dir]}"

      pattern = "{" + exclude.join(',') + "}"
      glob pattern, nonegate: true, (err, files) ->
        for file of files
          idx = include.indexOf(files[file])
          if idx > 0
            include.splice idx, 1
        self.files = include
        if typeof cb is "function" then cb()

  tempCopy: (file) ->
    tempFile = "#{tempPath}/" + crypto.createHash("md5").update(file).digest("hex")
    require('fs-extra').copyFile file, tempFile, (err) -> {}
    return path.normalize tempFile

  watch: (cb) ->
    self = @
    logger.debug "Watching for changes in files"
    @files.forEach (file) ->
      fs.stat file, (e, prevStats) ->
        throw e if e
        ext = path.extname(file).replace ".", ""
        # Create copies of the original for diff patch
        switch ext
          when "jade", "css", "stylus"
            tempFile = self.tempCopy file

        watcher = fs.watch file, callback = (e, filename) ->
          if e is "rename"
            watcher.close()
            return watcher = fs.watch file, callback

          if e is "change"
            return fs.stat file, (err, stats) ->
              throw err if err
              return if stats.size is prevStats.size and stats.mtime.getTime() is prevStats.mtime.getTime()

              logger.debug "Detected change in", file
              prevStats = stats
              switch ext
                when "jade", "css", "stylus"
                  oldStr = fs.readFileSync(tempFile).toString()
                  newStr = fs.readFileSync(file).toString()
                  patch = diff.diffLines oldStr, newStr
                  cb("push", file, patch)

                when "js", "coffee"
                  cb("reload", file)

module.exports = Watcher