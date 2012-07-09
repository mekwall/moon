###
  Moon.js
###

# Dependencies
_ = require "underscore"
_.mixin require "underscore.string"
fs = require "fs"
path = require "path"
coffee = require "iced-coffee-script"
styl = require "stylus"
nib = require "nib"
jade = require "jade"
sqwish = require "sqwish"
csso = require "csso"
uglifyjs = require "uglify-js"
mkdirp = require "mkdirp"
fileUtil = require "file"
glob = require "glob"
rimraf = require "rimraf"
mime = require "mime"
browserify = require "browserify"

# Include functions
{utils} = require "connect"
{exec} = require "child_process"
{parse} = require "url"
extname = path.extname
basename = path.basename
normalize = path.normalize

# Include classes
Logger = require "./logger"
{Buffer} = require "buffer"

###
  decodeURIComponent.

  Allows V8 to only deoptimize this fn instead of all of middleware.
  Borrowed from connect-static.

  @param {String} path
  @api private
###
decode = (path) ->
  try
    return decodeURIComponent path
  catch err
    return err

###
  Preprocessors
  An obj of default fileExtension: preprocessFunction pairs
  The preprocess function takes contents, [filename] and returns the preprocessed contents
###
module.exports.preprocessors = preprocessors = {}

# Coffee-script
try
  coffee = require "iced-coffee-script"
  preprocessors[".coffee"] = (contents) ->
    coffee.compile contents

# Stylus
try
  stylus = require "stylus"
  nib = require "nib"
  preprocessors[".styl"] = (contents, filename) ->
    styl(contents)
      .set("filename", filename)
      .use(nib())
      .render (err, out) ->
        throw err if err
        contents = out
    contents

###
  Template parsers
  An obj of default fileExtension: templateParserFunction pairs
  The templateParserFunction function takes contents, [filename] and returns the parsed contents
###
module.exports.templateParsers = templateParsers = {}

# Coffeekup
try
  ck = require "coffeekup"
  templateParsers[".coffee"] = (contents, filename) ->
    ck.compile contents, locals: no

# Jade
try
  templateParsers[".jade"] = (contents, filename) ->
    compiled = jade.compile contents, client: yes, compileDebug: no, filename: filename
    ###
    cmp = compiled.toString()
    replaced = cmp.replace(
      /(\' \+ escape\(\(interp = (.[^.\)]+)(?:.[^+]*)\+ \')/gm, # Will match
      '<a data-start="$2"></a>$1<a data-end="$2"></a>'
    )
    # /(\' \+ escape\(\(interp = (.[^\)]+)(?:.[^+]*)\+ \')/gm, # Matches all inputs
    # (\.(.[^)]+\))
    return replaced
    ###

# Add missing mime types
mime.define
  "text/css": [ "cgz" ]
  "application/javascript": [ "jgz" ]

###
  Assets
###
class Assets

  # Private variables
  jadeRuntime = fs.readFileSync(path.resolve __dirname, "../../vendor/jade.runtime.js").toString()
  logger = new Logger "assets"

  ###
    Constructor
    @param app
    @param bundles
  ###
  constructor: (@app, bundles) ->

    @options = @app.options.assets || {}
    @bundles =
      css: {}
      js: {} 
      jst: {}
    @appDir = @app.options.paths.app || process.cwd()
    @root = @app.options.paths.static
    @maxAge = 0
    @hidden = false
    @redirect = false
    @env = @app.env
    @cdnUrl = if @options.cdn? then @options.cdn.replace /\/$/, "" else undefined
    @embedImages = @options.embedImages ? true
    @embedFonts = @options.embed
    Fonts ? true
    @gzip = @options.gzip ? true
    @_tmplPrefix = coffee.compile (fs.readFileSync __dirname + "/template.client.coffee").toString()
    @_assetsDir = "/" + path.relative( process.cwd(), @app.options.paths.assets ) || "/assets"
    @_outputDir = normalize @root + "/" + @_assetsDir

    @preprocessors = preprocessors
    @templateParsers = templateParsers
    
    unless path.existsSync @root
      logger.error "The directory #{@root} doesn't exist"
      return
    
    # Clear out assets directory and start fresh
    try
      rimraf.sync @root + "/" + @_assetsDir
      unless @usingMiddleware
        fs.mkdirSync @_outputDir, "0755"
        fs.writeFileSync @_outputDir + "/.gitignore", "/*"

    # Add bundles
    if bundles
      @add bundles

    @

  ###
    Remove assets
    @param bundles
  ###
  remove: (bundles) ->
    unless bundles
      logger.error "Missing bundles object"
      return
    for type, obj of bundles
      for bundle in key bundles[type]
        @bundles[type][bundle]
    @

  ###
    Add bundles
    @param bundles
  ###
  add: (bundles) ->
    unless bundles
      logger.error "Missing bundles object"
      return
    for type, obj of bundles
      unless @bundles[type] then @bundles[type] = {}
      for bundle, patterns of bundles[type]
        matches = []
        # make sure patterns is an array
        patterns = [].concat(patterns)
        for pattern in patterns
          if fs.existsSync path.resolve pattern
            match = [path.resolve pattern]
          else
            match = glob.sync pattern.replace(/\\/g, "\/"), nosort: true
          matches = matches.concat match
          unless match.length
            logger.warn "Pattern #{pattern} did not match any assets"
        matches = _.uniq _.flatten matches
        if matches.length
          @bundles[type][bundle] = matches
          logger.debug "Added assets:", matches.map((file)-> basename(file)).join(", ")

    # Add any javascript necessary for templates (like the jade runtime)
    for filename in _.flatten @bundles.jst
      ext = extname(filename)
      switch ext
        when ".jade" then @_tmplPrefix = jadeRuntime + "\n" + @_tmplPrefix

    # Create static bundles of our assets
    if @env is "production"
      do @bundle

  ###
    Middleware
    Serves assets with given root path
    Some parts were borrowed from connect-static
    @param root
  ###
  middleware: (root) ->
    @usingMiddleware = true
    if root and path.exists root
      @root = root
    (req, res, next) =>
      # get request details
      ranges = req.headers.range
      head = true if req.method is "HEAD"
      get = true if req.method is "GET"
      # If method is not HEAD or GET, send to next
      return next() unless get and not head
      # parse url
      url = parse req.url
      urlpath = decode url.pathname
      return next( utils.error(400) ) if urlpath instanceof URIError
      # null byte(s)
      return next( utils.error(400) ) if ~urlpath.indexOf( "\u0000" )
      # when root is not given, consider .. malicious
      return next( utils.error(403) ) if not @root and ~urlpath.indexOf( ".." )
      # join / normalize from optional root dir
      urlpath = normalize( path.join( @root, urlpath ) )
      # malicious path
      return next( utils.error(403) ) if @root and 0 isnt urlpath.indexOf( @root )
      # "hidden" file
      next() if not @hidden and "." is basename(urlpath)[0]

      # in dev or testing, process-on-the-fly
      if @env in [ "development", "testing" ]
        switch extname urlpath
          when ".css"
            res.setHeader("Content-Type", "text/css")
            for bundle, filenames of @bundles.css
              for filename in filenames
                burl = basename urlpath, ".css"
                bname = basename filename, extname filename
                if burl is bname
                  contents = fs.readFileSync(filename).toString()
                  res.end @preprocess contents, filename
                  return
          when ".js"
            res.setHeader("Content-Type", "application/javascript")
            if req.url.match /\.jst\.js$/
              bundle = basename req.url, '.jst.js'
              res.end @generateJST bundle
              return

            if req.url.match /template-engine\.js$/
              res.end @_tmplPrefix
              return
          
            for bundle, filenames of @bundles.js
              for filename in filenames
                burl = basename(urlpath, extname urlpath)
                bname = basename(filename, extname filename)
                if burl is bname
                  contents = fs.readFileSync(filename).toString()
                  contents = @preprocess contents, filename
                  res.end contents
                  return

      # try and serve static file
      fs.stat urlpath, (err, stat) =>
        # ignore ENOENT
        if err
          return (if ("ENOENT" is err.code or "ENAMETOOLONG" is err.code) then next() else next(err))
        # redirect directory in case index.html is present
        else if stat.isDirectory()
          return next() unless @redirect
          res.statusCode = 301
          res.setHeader "Location", url.pathname + "/"
          res.end "Redirecting to " + url.pathname + "/"
          return

        # etag
        etag = '"' + stat.ino + '-' + stat.size + '-' + Date.parse(stat.mtime) + '"'
        if etag is req.headers["if-none-match"]
          req.emit "static"
          return utils.notModified(res)
        res.setHeader "Etag", etag

        # mimetype
        type = mime.lookup(urlpath)

        # header fields
        res.setHeader "Date", new Date().toUTCString() unless res.getHeader("Date")
        res.setHeader "Cache-Control", "public, max-age=" + (@maxAge / 1000) unless res.getHeader("Cache-Control")
        res.setHeader "Last-Modified", stat.mtime.toUTCString() unless res.getHeader("Last-Modified")
        unless res.getHeader("Content-Type")
          charset = mime.charsets.lookup(type)
          res.setHeader "Content-Type", type + (if charset then "; charset=" + charset else "")
        res.setHeader "Accept-Ranges", "bytes"

        # conditional GET support
        if utils.conditionalGET(req)
          unless utils.modified(req, res)
            return utils.notModified(res)
        opts = {}
        len = stat.size

        # accepted encoding
        acceptEncoding = req.headers["accept-encoding"] or "";
        if ~acceptEncoding.indexOf "gzip" and extname urlpath in [ ".gz", ".jgz", ".cgz" ]
          res.setHeader "Content-Encoding", "gzip"
          res.setHeader "Vary", "Accept-Encoding"

        # we have a Range request
        if ranges
          ranges = utils.parseRange(len, ranges)
          # valid
          if ranges
            opts.start = ranges[0].start
            opts.end = ranges[0].end
            # unsatisfiable range
            if opts.start > len - 1
              res.setHeader "Content-Range", "bytes */" + stat.size
              return next(utils.error(416))
            # limit last-byte-pos to current length
            opts.end = len - 1  if opts.end > len - 1
            # Content-Range
            len = opts.end - opts.start + 1
            res.statusCode = 206
            res.setHeader "Content-Range", "bytes " + opts.start + "-" + opts.end + "/" + stat.size

        res.setHeader "Content-Length", len
        # transfer
        return res.end() if head

        # stream
        stream = fs.createReadStream(urlpath, opts)
        req.emit "static", stream
        req.on "close", stream.destroy.bind(stream)
        stream.pipe res

  ###
    Run js pre-processors & output the packages in dev.
    @param {String} bundle The name of the package to output
    @return {String} Script tag(s) pointing to the ouput package(s)
  ###
  js: (bundle, gzip = @gzip) ->
    unless @bundles.js[bundle]?
      logger.error "JavaScript bundle not found:", bundle
      return
    
    if @env is "production"
      src = (@cdnUrl ? @_assetsDir) + "/" + bundle + ".js"
      src += ".jgz" if gzip
      return '<script src="' + src + '" type="text/javascript"></script>'
    
    output = []
    for filename, contents of @preprocessPkg bundle, "js"
      @writeFile filename, contents unless @usingMiddleware
      bname = basename filename
      output.push '<script src="' + @_assetsDir + "/" + bname + '" type="text/javascript"></script>'
    output.join ""
  
  ###
    Run css pre-processors & output the packages in dev.
    @param {String} bundle The name of the package to output
    @return {String} Link tag(s) pointing to the ouput package(s)
  ###
  css: (bundle, gzip = @gzip) ->
    unless @bundles.css[bundle]?
      logger.error "CSS bundle not found:", bundle
      return
    
    if @env is "production"
      src = (@cdnUrl ? @_assetsDir) + "/" + bundle + ".css"
      src += ".cgz" if gzip
      return '<link href="'+src+'" rel="stylesheet" type="text/css">'
    
    output = []
    for filename, contents of @preprocessPkg bundle, "css"
      @writeFile filename, @embedFiles filename, contents unless @usingMiddleware
      bname = path.basename filename
      output.push '<link href="' + @_assetsDir + "/" + bname + '" rel="stylesheet" type="text/css">'
    output.join ""
  
  ###
    Compile the templates into moon.jst['file/path'] : functionString pairs in dev
    @param {String} bundle The name of the package to output
    @return {String} Script tag(s) pointing to the ouput JST script file(s)
  ###
  jst: (bundle, gzip = @gzip) ->
    unless @bundles.jst[bundle]?
      logger.error "Template bundle not found:", bundle
      return
    
    if @env is "production"
      src = (@cdnUrl ? @_assetsDir) + '/' + bundle + '.jst.js'
      src += ".jgz" if gzip
      return "<script src=\"#{src}\" type=\"text/javascript\"></script>"
    
    unless @usingMiddleware
      fs.writeFileSync (@_outputDir + '/' + bundle + '.jst.js'), @generateJST bundle
      fs.writeFileSync (@_outputDir + '/template-engine.js'), @_tmplPrefix
    
    """
    <script src=\"#{@_assetsDir}/template-engine.js\" type=\"text/javascript\"></script>
    <script src=\"#{@_assetsDir}/#{bundle}.jst.js\" type=\"text/javascript\"></script>
    """

  ###
    Runs through all of the asset packages. Concatenates, minifies, and gzips them. Then outputs
    the final packages. (To be run once during the build step for production)
  ###
  bundle: (callback) ->
    total = _.reduce (_.values(bundles).length for key, bundles of @bundles), (memo, num) -> memo + num
    finishCallback = _.after total, -> callback() if callback?
    
    if @bundles.js?
      for bundle, files of @bundles.js
        logger.debug "Creating bundle:", bundle + ".js"
        contents = (contents for filename, contents of @preprocessPkg bundle, 'js').join('')
        contents = @uglify contents if @env is "production"
        filename = @_outputDir + "/" + bundle + ".js"
        @writeFile filename, contents
        if @gzip then @gzipBundle contents, filename, finishCallback else finishCallback()
        total++
        
    if @bundles.css?
      for bundle, files of @bundles.css 
        logger.debug "Creating bundle:", bundle + ".css"
        contents = (for filename, contents of @preprocessPkg bundle, 'css'
          @embedFiles filename, contents
        ).join('')
        contents = sqwish.minify contents if @env is "production"
        #contents = csso.justDoIt contents if @env is "production"
        filename = @_outputDir + "/" + bundle + ".css"
        @writeFile filename, contents
        if @gzip then @gzipBundle contents, filename, finishCallback else finishCallback()
        total++
        
    if @bundles.jst?
      for bundle, files of @bundles.jst
        logger.debug "Creating bundle:", bundle + ".jst.js"
        contents = @generateJST bundle
        contents = @_tmplPrefix + contents
        contents = @uglify contents if @env is "production"
        filename = @_outputDir + "/" + bundle + ".jst.js"
        @writeFile filename, contents
        if @gzip then @gzipBundle contents, filename, finishCallback else finishCallback()
        total++

  ###
    Generates javascript template functions packed into a JST namespace
     
    @param {String} bundle The package name to generate from
    @return {String} The new JST file contents
  ###
  generateJST: (bundle) ->
    tmplFileContents = ""
    for filename in @bundles.jst[bundle]
      # Read the file and compile it into a javascript function string
      contents = fs.readFileSync(filename).toString()
      ext = extname filename
      contents = if @templateParsers[ext]? then @templateParsers[ext](contents, filename) else contents
      namespace = basename filename, extname filename
      tmplFileContents += "window.moon.jst['#{namespace}'] = #{contents};\n"
    tmplFileContents


  ###
    Run a preprocessor or pass through the contents
    @param {String} filename The name of the file to preprocess
    @param {String} filename The contents of the file to preprocess
    @return {String} The new file contents 
  ###
  preprocess: (contents, filename) ->
    ext = extname filename
    if @preprocessors[ext]? then @preprocessors[ext](contents, filename) else contents

  ###
    Run any pre-processors on a package, and return an obj of { filename: compiledContents }
    @param {String} bundle The name of the package to preprocess
    @param {String} type Either 'js' or 'css'
    @return {Object} A { filename: compiledContents } obj
  ### 
  preprocessPkg: (bundle, type) ->
    obj = {}
    for filename in @bundles[type][bundle]
      contents = fs.readFileSync(filename).toString()
      contents = @preprocess contents, filename
      outputFilename = filename.replace /\.[^.]*$/, '' + '.' + type
      obj[outputFilename] = contents
    obj

  ###
    Given a filename creates the sub directories it's in, if it doesn't exist. And writes it to the
    @_outputDir.
    @param {String} filename Filename of the css/js/jst file to be output
    @param {String} contents Contents of the file to be output
    @return {String} The new full directory of the output file
  ###
  writeFile: (filename, contents) ->
    file = path.resolve filename
    dir = path.dirname file
    mkdirp.sync dir, "0755" unless path.existsSync dir
    fs.writeFileSync file, contents ? ""

  ###
    Runs uglify js on a string of javascript
    @param {String} str String of js to be uglified
    @return {String} str Minifed js string
  ###
  uglify: (str) ->
    jsp = uglifyjs.parser
    pro = uglifyjs.uglify
    ast = jsp.parse str
    ast = pro.ast_mangle(ast)
    ast = pro.ast_squeeze(ast)
    pro.gen_code(ast)

  ###
    Given the contents of a css file, replace references to url() with base64 embedded images & fonts.
    @param {String} str The filename to replace
    @param {String} str The CSS string to replace url()'s with
    @return {String} The CSS string with the url()'s replaced
  ###
  embedFiles: (filename, contents) ->
    
    endsWithEmbed = _.endsWith basename(filename).split('.')[0], '_embed'
    return contents if not contents? or contents is '' or not endsWithEmbed
    
    # Table of mime types depending on file extension
    mimes = {}
    if @embedImages
      mimes = _.extend {
        '.gif' : 'image/gif'
        '.png' : 'image/png'
        '.jpg' : 'image/jpeg'
        '.jpeg': 'image/jpeg'
        '.svg' : 'image/svg+xml'
      }, mimes
    
    if @embedFonts
      mimes = _.extend {
        '.ttf': 'font/truetype;charset=utf-8'
        '.woff': 'font/woff;charset=utf-8'
        '.svg' : 'image/svg+xml'
      }, mimes
    
    return contents if _.isEmpty mimes
    
    offset = 0
    offsetContents = contents.substring(offset, contents.length)
    
    return contents unless offsetContents.match(/url/g)?
    
    # While there are urls in the contents + offset replace it with base 64
    # If that url() doesn't point to an existing file then skip it by pointing the
    # offset ahead of it
    for i in [0..offsetContents.match(/url/g).length]

      start = offsetContents.indexOf('url(') + 4 + offset
      end = contents.substring(start, contents.length).indexOf(')') + start
      filename = _.trim _.trim(contents.substring(start, end), '"'), "'"
      filename = @root + '/' + filename.replace /^\//, ''
      mime = mimes[extname(filename)]
      
      if mime?    
        if path.existsSync filename
          base64Str = fs.readFileSync(path.resolve filename).toString('base64')
        
          newUrl = "data:#{mime};base64,#{base64Str}"
          contents = _.splice(contents, start, end - start, newUrl)
          end = start + newUrl.length + 4
        else
          throw new Error 'Tried to embed data-uri, but could not find file ' + filename
      else
        end += 4
      
      offset = end
      offsetContents = contents.substring(offset, contents.length)

    return contents

  ###
    Gzips a package.
    @param {String} contents The new file contents
    @param {String} filename The name of the new file
  ###
  gzipBundle: (contents, filename, callback) ->
    ext = if _.endsWith filename, '.js' then '.jgz' else '.cgz'
    gzip = require('gzip-js')
    options =
      level: 3,
      name: basename(filename),
      timestamp: parseInt(Date.now() / 1000, 10)
    zipped = gzip.zip contents, options
    fs.writeFile normalize(filename + ext), new Buffer(zipped), callback
    ###
    exec "gzip #{file}", (err, stdout, stderr) ->
      console.log stderr if stderr
      fs.renameSync file + '.gz', file + ext
      writeFile filename, contents
      callback()
    ###

module.exports = Assets