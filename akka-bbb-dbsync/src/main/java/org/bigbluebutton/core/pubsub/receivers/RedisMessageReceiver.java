package org.bigbluebutton.core.pubsub.receivers;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.Executor;
import java.util.concurrent.Executors;
import java.util.concurrent.LinkedBlockingQueue;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class RedisMessageReceiver {
    private static final Logger log = LoggerFactory.getLogger(RedisMessageReceiver.class);

    private BlockingQueue<ReceivedMessage> receivedMessages = new LinkedBlockingQueue<ReceivedMessage>();

    private volatile boolean processMessage = false;

    private final Executor msgProcessorExec = Executors.newSingleThreadExecutor();

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
        System.out.println("Processing the message: " + msg.toString());
	  }
}
