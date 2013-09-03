define(['SIPml'], function (SIPml) {

// Create a SIP Stack
var sipStack;
var connected;
var voicebridge;
var connectingTS, connectedTS;

function createSipStack(caller, server, callback) {
    console.log("...Creating sip stack..");
    var eventsListener = function(e){
        console.log("... SIPml.Stack event listener: " + e.type + "...");
        if(e.type == 'started') {
            // there's no need to login, call directly!
            //login();
            connected = true;
            makeCall(callback);
        } else if(e.type == 'i_new_message') { // incoming new SIP MESSAGE (SMS-like)
            console.log("To accept the message, uncomment");
            //   acceptMessage(e);
        } else if(e.type == 'i_new_call') { // incoming audio/video call
            console.log("To accept call, uncomment.");
            //acceptCall(e);
        } else if (e.type == 'm_permission_requested') {
            console.log("Waiting for user authorization to access the microphone");
        } else if (e.type == 'm_permission_refused') {
            callback("The user denied the access to the microphone");
        } else if (e.type == 'm_permission_accepted') {
            console.log("Permission accepted");
            connectingTS = new Date().getTime();
        } else if (e.type == 'stopped') {
        }
    };

    sipStack = new SIPml.Stack({
        realm: server, // mandatory: domain name
        impi: 'bbbuser', // mandatory: authorization name (IMS Private Identity)
        impu: [ 'sip:bbbuser@', server ].join(""), // mandatory: valid SIP Uri (IMS Public Identity)
        password: 'secret', // optional
        display_name: caller, // optional
        websocket_proxy_url: [ 'ws://', server, ':5066' ].join(""), // optional
        outbound_proxy_url: [ 'udp://', server, ':5060' ].join(""), // optional
        //enable_rtcweb_breaker: true, // optional
        events_listener: { events: '*', listener: eventsListener }, // optional: '*' means all events
        sip_headers: [ // optional
            { name: 'User-Agent', value: 'IM-client/OMA1.0 sipML5-v1.0.0.0', session: true },
            { name: 'Organization', value: 'BigBlueButton', session: true }
        ],
        sip_caps: [
            { name: '+g.oma.sip-im' },
            { name: '+sip.ice' },
            { name: 'language', value: '\"en,fr\"' },
            { name: 'bbbcap', value: 'HelloBBB' }
        ]
    });
}

// Making a call
var callSession;
var makeCall = function(callback) {
    var eventsListener = function(e) {
        console.log("... call session event listener: " + e.type + "...");
        if (e.type == 'connecting') {

        } else if (e.type == 'connected') {
            connectedTS = new Date().getTime();
            callback();
            console.info("This call was established in " + (connectedTS-connectingTS) + "ms");
        } else if (e.type == 'terminated') {

        }
    };
    console.log("... Making a call...");
    //callSession = sipStack.newSession('call-audiovideo', {
    callSession = sipStack.newSession('call-audio', {
        //video_local: document.getElementById('video-local'),
        //video_remote: document.getElementById('video-remote'),
        audio_remote: document.getElementById('audio-remote'),
        events_listener: { events: '*', listener: eventsListener } // optional: '*' means all events
    });
    //callSession.call(voicebridge + "-12345-Richard", {display_name: 'Guga'});
    //callSession.call(voicebridge, {display_name: 'Guga'});

    callSession.call(voicebridge);
};

// Hang Up
function webrtc_hangup(callback) {
    if (sipStack) {
        var onStoppedCallback = function(e) {
//            if (connected) {
//                connected = false;
                callback();
                sipStack.removeEventListener('stopped', onStoppedCallback);
//            }
        };
        sipStack.addEventListener('stopped', onStoppedCallback);
        sipStack.stop(); // shutdown all sessions
    }
}

WebRTC = function() {};

// Call
WebRTC.connect = function(username, voiceBridge, server, callback) {
    var sayswho = navigator.sayswho,
        browser = sayswho[0],
        version = +(sayswho[1].split('.')[0]);

    console.log("Browser: " + browser + ", version: " + version);
    if (browser != "Chrome" || version < 26) {
        callback("Browser version not supported");
        return;
    }

    voicebridge = voiceBridge;
    server = server || window.document.location.host;
    console.log("user " + username + " calling to " +  voicebridge);
    // Initialize the engine.
    console.log("... Initializing the engine ...")
    var readyCallback = function(e){
        createSipStack(username, server, callback);
    };
    var errorCallback = function(e){
        console.error('Failed to initialize the engine: ' + e.message);
        callback('Failed to initialize the engine: ' + e.message);
    };
    // You must call this function before any other.
    SIPml.init(readyCallback, errorCallback);
    sipStack.start();
    //makeCall(voicebridge);
};

// http://stackoverflow.com/questions/5916900/detect-version-of-browser
navigator.sayswho= (function(){
    var ua= navigator.userAgent,
        N= navigator.appName,
        tem,
        M= ua.match(/(opera|chrome|safari|firefox|msie|trident)\/?\s*([\d\.]+)/i) || [];
    M= M[2]? [M[1], M[2]]:[N, navigator.appVersion, '-?'];
    if(M && (tem= ua.match(/version\/([\.\d]+)/i))!= null) M[2]= tem[1];
    return M;
})();

  return WebRTC;

});
