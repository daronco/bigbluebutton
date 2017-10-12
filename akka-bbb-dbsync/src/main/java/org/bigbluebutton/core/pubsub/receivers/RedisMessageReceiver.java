package org.bigbluebutton.core.pubsub.receivers;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.Executor;
import java.util.concurrent.Executors;
import java.util.concurrent.LinkedBlockingQueue;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import org.bigbluebutton.core.mongo.MongoConnector;

public class RedisMessageReceiver {
    private static final Logger log = LoggerFactory.getLogger(RedisMessageReceiver.class);

    private BlockingQueue<ReceivedMessage> receivedMessages = new LinkedBlockingQueue<ReceivedMessage>();

    private volatile boolean processMessage = false;

    private final Executor msgProcessorExec = Executors.newSingleThreadExecutor();

    private MongoConnector mongo = new MongoConnector();

    public RedisMessageReceiver() {
        start();
    }

    public void handleMessage(String pattern, String channel, String message) {
        ReceivedMessage rm = new ReceivedMessage(pattern, channel, message);
        receivedMessages.add(rm);
    }

    public void stop() {
        processMessage = false;
	  }

	  public void start() {
        try {
            processMessage = true;

            Runnable messageProcessor = new Runnable() {
                    public void run() {
                        while (processMessage) {
                            try {
                                ReceivedMessage msg = receivedMessages.take();
                                processMessage(msg);
                            } catch (InterruptedException e) {
                                log.warn("Error while taking received message from queue.");
                            }
                        }
                    }
                };
            msgProcessorExec.execute(messageProcessor);
        } catch (Exception e) {
            log.error("Error subscribing to channels: " + e.getMessage());
        }
	  }

	  private void processMessage(final ReceivedMessage msg) {
        // System.out.println("Processing the message: " + msg.toString());
        JsonParser parser = new JsonParser();
        JsonObject obj = (JsonObject) parser.parse(msg.getMessage());
        if (obj.has("envelope") && obj.has("core")) {
            JsonObject envelope = (JsonObject) obj.get("envelope");
            if (envelope.has("name")) {
                String name = envelope.get("name").getAsString();
                System.out.println("Message type: " + name);

                switch (name) {
                case "MeetingCreatedEvtMsg":
                    JsonObject core = (JsonObject) obj.get("core");
                    JsonObject body = (JsonObject) core.get("body");
                    String props = body.get("props").toString();
                    mongo.createMeeting(props);
                    break;
                }
            }
        }
	  }
}
