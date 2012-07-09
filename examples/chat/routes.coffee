module.exports = (app) ->
  404: ->
    @render "error",
      error:
        title: "File Not Found"
        message: "Did you lose it?"

  500: ->
    @render "error",
      error:
        title: "Internal Server Error"
        message: "Oh my..."

  "/":
    get: ->
      @render "index"