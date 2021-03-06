{spawn, exec} = require "child_process"
testutil = require "testutil"
growl = require "growl"
Logger = require "./src/moon/logger"
logger = new Logger "cli"

option "-p", "--prefix [DIR]", "set the installation prefix for `cake install`"
option "-w", "--watch", "continually build moon.js"

task "test", "test project", (options) ->
  process.env.NODE_ENV = "testing"
  testutil.fetchTestFiles "./test", (files) ->
    files.unshift "--colors"
    if options.grep?
      files.unshift options.grep
      files.unshift "--grep"
    
    mocha = spawn "node", ["./node_modules/mocha/bin/mocha"].concat(files)
    mocha.stdout.pipe(process.stdout, end: false);
    mocha.stderr.pipe(process.stderr, end: false);

task "build", "build moon.js", (options) ->
  if options.watch
    logger.info "Building and watching for changes..."
  else
    logger.info "Building..."
  coffee = spawn "node", ["./node_modules/iced-coffee-script/bin/coffee", (if options.watch then "-w" else ""), "-o", "./lib", "-c", "./src"]
  
  coffee.stderr.on "data", (e) -> 
    if e then logger.error e.toString().trim()
  coffee.on "exit", ->
    if options.watch
      logger.info "Exiting..."
    else
      logger.info "Done!"
  coffee.stdout.on "data", (data) -> 
    logger.info data.toString().trim() 
    return false

task "install", "install the `moon` command into /usr/local (or --prefix)", (options) ->
  base = options.prefix or "/usr/local"
  lib  = base + "/lib/moon"
  exec([
    "mkdir -p " + lib
    "cp -rf bin README resources vendor lib " + lib
    "ln -sf " + lib + "/bin/moon " + base + "/bin/moon"
  ].join(" && "), (err, stdout, stderr) ->
   if err then logger.error stderr
  )

task "doc", "rebuild the moon documentation", ->
  exec([
    "./node_modules/docco/bin/docco ./src/docco.coffee"
    "sed 's/docco.css/resources\\/docco.css/' < docs/docco.html > index.html"
    "rm -r docs"
  ].join(" && "), (err) ->
    throw err if err
  )