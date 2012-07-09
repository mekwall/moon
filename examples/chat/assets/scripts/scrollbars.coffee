((window, $) ->
  defaults = 
    startAtBottom: true
    mouseWheelDelta: 40
  Scrollbar = (elm, options) ->
    @options = $.extend({}, defaults, options)
    @content = elm.addClass("scrollbar-content")
    if @content.parent().hasClass("scrollbar-container")
      @container = @content.wrap("<div class=\"scrollbar-container\"></div>").parent()
    else
      @container = @content.parent()
    if @content.children(".scrollbar-vertical").length
      @scrollBar = @content.children(".scrollbar-vertical").hide()
    else
      @scrollBar = $("<div class=\"scrollbar-vertical\"></div>").hide().appendTo(@container)
    if @scrollBar.children(".scrollbar-handle").length
      @handle = @scrollBar.children(".scrollbar-handle")
    else
      @handle = $("<div class=\"scrollbar-handle\"></div>").appendTo(@scrollBar)
    
    @atBottom = false

    self = this
    @handle.draggable
      axis: "y"
      containment: @scrollBar
      drag: (e, ui) ->
        self.content.scrollTop self._multiplier() * ui.position.top
        self.atBottom = (self.content[0].scrollHeight - self.content[0].scrollTop is self.content.height())
        return @

    @content.scroll ->
      diff = -(self.content.height() - self.content[0].scrollHeight)
      self.handle.css "top", self.content[0].scrollTop / self._multiplier()
      return @

    $(window).resize(->
      self.update()
    ).trigger "resize"
    if $.event.special.mousewheel
      @container.bind "mousewheel", (e, delta) ->
        self.content.scrollTop self.content[0].scrollTop - (delta*self.options.mouseWheelDelta)

  $.extend Scrollbar::,
    update: ->
      diff = -(@content.height() - @content[0].scrollHeight)
      if diff
        @handle.height @_handleHeight()
        @atBottom = true  if @scrollBar.is(":hidden") and @options.startAtBottom
        #@content.css "right", @scrollBar.show().width()
        do @scrollBar.show
        if @atBottom
          @content.scrollTop diff
          @handle.css "top", @scrollBar.height() - (@handle.height() + 4)
        else
          @handle.css "top", @content[0].scrollTop / @_multiplier()
      else
        @scrollBar.hide()

    _multiplier: ->
      sh = @content[0].scrollHeight
      ch = @content.height()
      (sh - ch) / (@scrollBar.height() - (@handle.height() + 4))

    _handleHeight: ->
      multiplier = @_multiplier()
      height = @scrollBar.height() / 1.5 - multiplier
      (if (height < 10) then 10 else height)

  $.fn.scrollBars = ->
    args = $(arguments).toArray()
    @each ->
      $this = $(this)
      unless $this.data("scrollbar")
        $this.data "scrollbar", new Scrollbar($this, args[0])
      else
        sc = $this.data("scrollbar")
        sc[args[0]].apply sc, [].concat(args.splice(1))

  do $(window).resize

)(window, jQuery)