define [
  'jquery',
  'underscore',
  'backbone',
  'globals',
  'text!templates/session_navbar.html'
], ($, _, Backbone, globals, sessionNavbarTemplate) ->

  # The navbar in a session
  # The contents are rendered by SessionView, this class is Used to
  # manage the events in the navbar.
  SessionNavbarView = Backbone.View.extend
    events:
      # TODO: temporary adaptation for iPads: chat always visible
      # "click #chat-btn": "_toggleChat"

      # TODO: temporary to test audio via WebRTC
      "click #webrtc-connect-btn": "_webrtcConnect"

      "click #users-btn": "_toggleUsers"
      "click #logout-btn": "_logout"
      "click #prev-slide-btn": "_previousSlide"
      "click #next-slide-btn": "_nextSlide"
      "click #tool-pan-btn": "_toolPan"
      "click #tool-line-btn": "_toolLine"
      "click #tool-rect-btn": "_toolRect"
      "click #tool-ellipse-btn": "_toolEllipse"

    # TODO: temporary to test audio via WebRTC
    _webrtcConnect: ->
      globals.connection.webrtcConnect globals.username, globals.presentationServer, globals.voiceBridge, (message) ->

    initialize: ->
      @$parentEl = null

    render: ->
      compiledTemplate = _.template(sessionNavbarTemplate)
      @$el.html compiledTemplate
      @_setToggleButtonsStatus()

    # Ensure the status of the toggle buttons is ok
    _setToggleButtonsStatus: ->
      $("#chat-btn", @$el).toggleClass "active", @$parentEl.hasClass("chat-enabled")
      $("#users-btn", @$el).toggleClass "active", @$parentEl.hasClass("users-enabled")

    # Toggle the visibility of the chat panel
    _toggleChat: ->
      clearTimeout @toggleChatTimeout if @toggleChatTimeout?
      @$parentEl.toggleClass "chat-enabled"
      @_setToggleButtonsStatus()
      # TODO: timeouting this is not the best solution, maybe the js
      #       should control the visibility of the panel, not the css
      @toggleChatTimeout = setTimeout(->
        $(window).resize()
      , 510)

    # Toggle the visibility of the users panel
    _toggleUsers: ->
      # clearTimeout @toggleUsersTimeout if @toggleUsersTimeout?
      @$parentEl.toggleClass "users-enabled"
      @_setToggleButtonsStatus()
      # TODO: timeouting this is not the best solution, maybe the js
      #       should control the visibility of the panel, not the css
      # @toggleChatTimeout = setTimeout(->
      #   $(window).resize()
      # , 510)

      # TODO: temporary adaptation for iPads
      $("#users").toggle()

    # Log out of the session
    _logout: ->
      globals.connection.emitLogout()
      globals.currentAuth = null

    # Go to the previous slide
    _previousSlide: ->
      globals.connection.emitPreviousSlide()

    # Go to the next slide
    _nextSlide: ->
      globals.connection.emitNextSlide()

    # "Pan" tool was clicked
    _toolPan: ->
      globals.connection.emitChangeTool("panzoom")

    # "Line" tool was clicked
    _toolLine: ->
      globals.connection.emitChangeTool("line")

    # "Rect" tool was clicked
    _toolRect: ->
      globals.connection.emitChangeTool("rect")

    # "Ellipse" tool was clicked
    _toolEllipse: ->
      globals.connection.emitChangeTool("ellipse")

  SessionNavbarView
