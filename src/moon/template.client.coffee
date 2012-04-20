window.moon = window.moon or {}
(($, window) ->
  moon.jst = {}
  moon.data = {}
  moon.render = (template, data) ->
    throw new Error("Template '" + template + "'' could not be found")  unless moon.jst[template]
    moon.data[template] = []  unless moon.data[template]
    moon.data[template].push
      template: template
      data: data

    moon.jst[template] data

  $.fn.render = (data, template) ->
    @map ->
      self = $(this)
      template = self.data("template")  unless template
      throw Error("Element is not bound to a template")  unless template
      elem = $(moon.render(template, data))
      if events = self.data("events")
        $.each events, (eventType, data) ->
          method = data[0].handler
          methodData = data[0].data
          elem.on eventType, methodData, method
      elem.attr "data-id", data.id  if data.id
      elem.attr "data-template", template
      self.replaceWith elem
      elem

  moon.renderExisting = (parent, template, data) ->
    xe = parent.find("[data-id='" + data.id + "']")
    return xe.render(data, template)  if xe.length
    false

  $.fn.renderList = (data, ret) ->
    @map ->
      self = $(this)
      template = self.data("template-list")
      throw Error("Element is not bound to a template")  unless template
      data = [].concat(data)
      elems = []
      len = data.len
      $.each data, (i, data) ->
        ne = undefined
        ne = moon.renderExisting(self, template, data)  if data.id
        unless ne
          ne = $(moon.render(template, data))
          ne.attr "data-id", data.id  if data.id
          self.append ne
        elems.push ne

      elems
) jQuery, window