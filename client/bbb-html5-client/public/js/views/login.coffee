define [
  'jquery',
  'underscore',
  'backbone',
  'globals',
  'cs!models/authentication',
  'cs!collections/meetings',
  'text!templates/login.html',
  'text!templates/login_loading.html',
], ($, _, Backbone, globals, AuthenticationModel, MeetingsCollection, loginTemplate, loginLoadingTemplate) ->

  LoginView = Backbone.View.extend
    id: 'login-view'
    model: new AuthenticationModel()

    render: ->
      # At first we render a simple "loading" page while we check if the
      # user is authenticated or not
      compiledTemplate = _.template(loginLoadingTemplate, {})
      @$el.html compiledTemplate
      # Go check the authentication

      # TODO: check if the user's browser supports websockets
      # @_browserSupportsWebSockets()

      # Connect to the server and authenticate the user once the connection is stabilished
      globals.events.on "connected", (data) => @_authenticate()
      globals.connection.connect()

    # Fetch information from the server to check if the user is autheticated
    # already or not. If not, authenticates the user.
    _authenticate: ->
      # information that comes in the client URL, that will be used to validate the
      # client to join the session
      urlVars = getUrlVars()
      authToken = urlVars["auth_token"]
      userId = urlVars["user_id"]
      meetingId = urlVars["meeting_id"]

      console.log "Authenticating user with:", authToken, userId, meetingId

      if authToken? and userId? and meetingId?
        @model.authenticate authToken, userId, meetingId, (err, data) =>
          if not err? and data.payload?.valid
            console.log "User authenticated successfully"
            @_onLoginAccepted()
          else
            console.log "User not authorized:", data, err
            @_renderAuthenticationError()
      else
        console.log "Invalid parameters in the URL:", authToken, userId, meetingId
        @_renderAuthenticationError()

    _renderAuthenticationError: ->
      # TODO: render a page showing the authentication error

    # Actions to take when the login was authorized.
    _onLoginAccepted: ->
      globals.currentAuth = @model
      globals.router.showSession()

    # Checks if browser support websockets
    _browserSupportsWebSockets: ->
      if window.WebSocket?
        true
      else
        alert("Websockets is not supported by your current browser")
        false

  # Helper method to get the meeting_id, user_id and auth_token from the url
  getUrlVars = ->
    vars = {}
    parts = window.location.href.replace(/[?&]+([^=&]+)=([^&]*)/gi, (m,key,value) ->
      vars[key] = value
    )
    vars

  LoginView
