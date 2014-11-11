EventEmitter = require('events').EventEmitter
request = require("request")

# Class that emits a callback. Will try several times until the callback is
# properly emitted and stop when successful (or after a given number of tries).
# Emits "success" on success and "error" when gave up trying to emit the callback.
module.exports = class CallbackEmitter extends EventEmitter

  constructor: (@url, @message) ->

  start: ->
    @_scheduleNext 0

  _scheduleNext: (timeout) ->
    setTimeout( =>
      @_emitMessage (error, result) =>
        # TODO: treat error
        if result
          @emit "success"
        else
          # TODO: increase the timeout periodically and stop at some point, emitting "error"
          @_scheduleNext 1000
    , timeout)

  _emitMessage: (callback) ->
    # TODO: the external meeting ID is not on redis yet
    # message.meetingID = rep.externalMeetingID

    requestOptions =
      uri: @url
      method: "POST"
      json: @message

    request requestOptions, (error, response, body) ->
      if error?
        console.log "Error calling url:",requestOptions.uri
        console.log "Error:", error
        console.log "Response:", response
        callback error, false
      else
        console.log "Successful callback call to:", requestOptions.uri
        callback null, true