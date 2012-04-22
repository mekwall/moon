{spawn, exec} = require 'child_process'
testutil = require 'testutil'
growl = require 'growl'

option '-p', '--prefix [DIR]', 'set the installation prefix for `cake install`'
option '-w', '--watch', 'continually build moon.js'

task 'test', 'test project', (options) ->
  process.env.NODE_ENV = 'testing'
  testutil.fetchTestFiles './test', (files) ->
    files.unshift '--colors'
    if options.grep?
      files.unshift options.grep
      files.unshift '--grep'
    
    mocha = spawn 'mocha', files#, customFds: [0..2]
    mocha.stdout.pipe(process.stdout, end: false);
    mocha.stderr.pipe(process.stderr, end: false);

task 'build', 'build moon.js', (options) ->
  coffee = spawn 'coffee', ['-c' + (if options.watch then 'w' else ''), '-o', 'lib', 'src']
  coffee.stdout.on 'data', (data) -> console.log data.toString().trim()

task 'install', 'install the `moon` command into /usr/local (or --prefix)', (options) ->
  base = options.prefix or '/usr/local'
  lib  = base + '/lib/moon'
  exec([
    'mkdir -p ' + lib
    'cp -rf bin README resources vendor lib ' + lib
    'ln -sf ' + lib + '/bin/moon ' + base + '/bin/moon'
  ].join(' && '), (err, stdout, stderr) ->
   if err then console.error stderr
  )

task 'doc', 'rebuild the moon documentation', ->
  exec([
    'bin/docco src/docco.coffee'
    'sed "s/docco.css/resources\\/docco.css/" < docs/docco.html > index.html'
    'rm -r docs'
  ].join(' && '), (err) ->
    throw err if err
  )