define [
  'jquery',
  'underscore',
  'backbone',
  'globals',
], ($, _, Backbone, globals) ->

  AuthenticationModel = Backbone.Model.extend
    defaults:
      username: null
      meetingId: null
      externalMeetingId: null
      userId: null
      loginAccepted: false

    # Sends a message to the server to authenticate this client.
    authenticate: (authToken, userId, meetingId, callback) ->
      message = {
        "payload": {
            "auth_token": @authToken
            "userid": @userId
            "meeting_id": @meetingId
        },
        "header": {
            "timestamp": new Date().getTime()
            "name": "validate_auth_token"
        }
      }
      @_waitAuthenticationReply(callback)
      console.log "Sending authentication message", message
      globals.connection.emit(message)

    # Waits for a reply to an authentication message and calls `callback(err, message)`
    # when received, where `message` is the reply received.
    # Will also set internal variables with the information received in the reply.
    _waitAuthenticationReply: (callback) ->
      globals.events.on "message", (received) =>
        if received?.header?.name is "validate_auth_token_reply"
          console.log "Authentication response", received
          @set("username", received.payload.fullname)
          @set("meetingId", received.payload.meeting_id)
          @set("externalMeetingId", received.payload.external_meeting_id)
          @set("userId", received.payload.user_id)
          callback?(null, received)

  # getURLParameter = (name) ->
  #   name = name.replace(/[\[]/,"\\\[").replace(/[\]]/,"\\\]")
  #   regexS = "[\\?&]"+name+"=([^&#]*)"
  #   regex = new RegExp(regexS)
  #   results = regex.exec(location.search)
  #   unless results?
  #     ""
  #   else
  #     decodeURIComponent(results[1].replace(/\+/g, " "))

  AuthenticationModel
