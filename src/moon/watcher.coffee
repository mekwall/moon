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
diff      = require "./diff"

stylus    = require "stylus"
jade      = require "jade"

#prettydiff  = require "./prettydiff"

# Import classes
Logger = require "./logger"

# node < 0.7 compatibility
unless fs.existsSync
  fs.exists = path.exists
  fs.existsSync = path.existsSync

###
  Watcher
###
class Watcher

  # Private variables
  logger = new Logger "watcher"
  defaults =
    ext: "js,json,css,jade,styl,coffee,png,jpg,gif",
    include: "**/",
    exclude: "node_modules/**,test/**,package.json"

  # Temporary directory
  tempPath = temp.path()
  unless fs.existsSync tempPath
    fs.mkdirSync tempPath

  # Remove temporary directory
  unless process.platform is "win32"
    process.on "SIGINT", ()->
      logger.debug "Cleaning up..."
      fs.unlinkSync tempPath + "/*"
      fs.rmdirSync tempPath
  else
    # Fallback for Windows
    # Bug in node.js prevents us to do this
    # Ref: https://groups.google.com/group/nodejs/browse_thread/thread/9a6b9214722e526f
    ###
    try
      tty = require "tty"
      process.stdin.resume()
      tty.setRawMode true
      process.stdin.on "keypress", (char, key) ->
        if key and key.ctrl and key.name is "c"
          logger.debug "Cleaning up..."
          fs.unlinkSync tempPath + "/*"
          fs.rmdirSync tempPath
          process.exit 0###

  # Public variables
  files: []
  tempFiles: {}

  constructor: (cb, opts) ->
    self = @
    dir = process.cwd()
    unless fs.existsSync dir
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
    await glob pattern, nonegate: true, defer err,files
    include = files

    for dir of self.opts.exclude
      exclude.push "**/#{self.opts.exclude[dir]}"

    pattern = "{" + exclude.join(',') + "}"
    await glob pattern, nonegate: true, defer err, files
    for file of files
      idx = include.indexOf(files[file])
      if idx > 0
        include.splice idx, 1
    self.files = include
    if typeof cb is "function" then cb()

  tempCopy: (file) ->
    unless @tempFiles[file]
      @tempFiles[file] = path.normalize "#{tempPath}/" + crypto.createHash("md5").update(file).digest("hex")
    require('fs-extra').copy file, @tempFiles[file], (err) -> {}
    this

  watch: (cb) ->
    self = @
    logger.debug "Watching for changes in files"
    @files.forEach (file) ->
      fs.stat file, (e, prevStats) ->
        throw e if e
        ext = path.extname(file).replace ".", ""

        # Create copies of the original for diff patch
        self.tempCopy file

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

              oldStr = ( fs.readFileSync self.tempFiles[file] ).toString()
              newStr = ( fs.readFileSync file .toString() ).toString()

              self.tempCopy file

              switch ext

                when "jpg", "png", "gif"
                  cb "change", 
                    action: "reloadSingle",
                    file: file

                when "jade"
                  ###
                  oldStr = do jade.compile oldStr, pretty: true 
                  newStr = do jade.compile newStr, pretty: true

                  #prettydiff.api( source: oldStr, diff: newStr, mode: "diff",  );

                  patch = diff.diffWords oldStr, newStr

                  for i, change of patch
                    if change.added or change.removed
                      console.log change
                  ###
                  cb "change", 
                    action: "reload",
                    file: file

                when "styl"

                  try

                    await
                      stylus.render oldStr, pretty: true, defer err, oldStr
                      stylus.render newStr, pretty: true, defer err, newStr

                    patch = diff.diffCss oldStr, newStr

                    changes = []
                    for change,i in patch
                      if !change.added and !change.removed
                        patch.slice(i,0)
                        continue
                      val = change.value = change.value.replace(/\n/g,"").trim()
                      change.selector = val.match(/^(.[^{]+)/)[0].trim()
                      change.rules = _.compact(val.split("{").slice(1).join("").trim().split(";"))
                      changes.push change

                    cb "change", 
                      action: "reloadSingle",
                      file: file, 
                      changes: changes

                  catch err
                    logger.error "Something went wrong:", err
                    cb "error",
                      file: file,
                      error: err

                when "css"

                  patch = diff.diffCss oldStr, newStr
                  changes = []
                  for change,i in patch
                    if !change.added and !change.removed
                      patch.slice(i,0)
                      continue
                    val = change.value = change.value.replace(/\n/g,"").trim()
                    change.selector = val.match(/^(.[^{]+)/)[0].trim()
                    change.rules = _.compact(val.split("{").slice(1).join("").trim().split(";"))
                    changes.push change

                  cb "change", 
                    action: "reloadSingle",
                    file: file, 
                    changes: changes

                when "js", "coffee"
                  cb "reload",
                    file: file

module.exports = Watcher