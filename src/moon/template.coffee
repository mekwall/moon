###
  Moon.js
###

# Dependencies
path = require "path"
jade = require "jade"
nib = require "nib"

# Import classes
Logger = require "./logger"

class Template

  # Private variables
  logger = new Logger "template"

  ###
    Constructor
  ###
  constructor: (@app) ->
    @errorTemplate = path.resolve @app.options.paths.views + "/error.jade"
    this

  tmplError: (res, title, message, error, status = 500) ->
    if error
      error.title = title
      error.message = message
      error.status = status

    res.writeHead status
    jade.renderFile @errorTemplate, { error: error || {} }, (err, html) ->
      if err
        tmplError res, "Unknown error:", err
      else
        res.end html
    templateLogger.error message, error

  ###
    render
  ###
  render: (req, res, template, options) ->
    res = this.res
    self.template.render 

    unless template.match(/.jade/i)
      template = template + ".jade"
    file = path.resolve self.options.paths.views + "/" + template

    unless path.existsSync file
      e = new Error()
      tmplError res, "File Not Found", "Could not find template file: " + file, e, 404
    else
      jade.renderFile file, options, (err, html) ->
        if err
          tmplError res, "Template Rendering Error", "Failed to render template file: " + file, e
        else
          res.writeHead 200
          res.end html

module.exports =
  init: (app) ->
    template = new Template(app)
    # Let's set up a simple template renderer
    app.router.attach () ->
      @render = (template, options) ->
        template.render @req, @res, template, options