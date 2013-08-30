/**
* BigBlueButton open source conferencing system - http://www.bigbluebutton.org/
* 
* Copyright (c) 2012 BigBlueButton Inc. and by respective authors (see below).
*
* This program is free software; you can redistribute it and/or modify it under the
* terms of the GNU Lesser General Public License as published by the Free Software
* Foundation; either version 3.0 of the License, or (at your option) any later
* version.
* 
* BigBlueButton is distributed in the hope that it will be useful, but WITHOUT ANY
* WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
* PARTICULAR PURPOSE. See the GNU Lesser General Public License for more details.
*
* You should have received a copy of the GNU Lesser General Public License along
* with BigBlueButton; if not, see <http://www.gnu.org/licenses/>.
*
*/

package org.bigbluebutton.api.messaging;

import java.awt.image.BufferedImage;
import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.Executor;
import java.util.concurrent.Executors;

import javax.imageio.ImageIO;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import com.google.gson.Gson;
import com.google.gson.reflect.TypeToken;
import redis.clients.jedis.Jedis;
import redis.clients.jedis.JedisPool;
import redis.clients.jedis.JedisPubSub;

public class RedisMessagingService implements MessagingService {
	private static Logger log = LoggerFactory.getLogger(RedisMessagingService.class);
	
	private JedisPool redisPool;
	private final Set<MessageListener> listeners = new HashSet<MessageListener>();

	private final Executor exec = Executors.newSingleThreadExecutor();
	private Runnable pubsubListener;

	public RedisMessagingService(){
		
	}
	
 	@Override
	public void addListener(MessageListener listener) {
 		listeners.add(listener);
	}
 	
	public void removeListener(MessageListener listener) {
 		listeners.remove(listener);
 	}

	public void recordMeetingInfo(String meetingId, Map<String, String> info) {
		Jedis jedis = redisPool.getResource();
		try {
		    for (String key: info.keySet()) {
				    	log.debug("Storing metadata {} = {}", key, info.get(key));
				}   

		    log.debug("Saving metadata in {}", meetingId);
			jedis.hmset("meeting:info:" + meetingId, info);
		} catch (Exception e){
			log.warn("Cannot record the info meeting:"+meetingId,e);
		} finally {
			redisPool.returnResource(jedis);
		}		
	}

	public void endMeeting(String meetingId) {
		HashMap<String,String> map = new HashMap<String, String>();
		map.put("messageId", MessagingConstants.END_MEETING_REQUEST_EVENT);
		map.put("meetingId", meetingId);
		Gson gson = new Gson();
		send(MessagingConstants.SYSTEM_CHANNEL, gson.toJson(map));
	}

	public void send(String channel, String message) {
		Jedis jedis = redisPool.getResource();
		try {
			jedis.publish(channel, message);
		} catch(Exception e){
			log.warn("Cannot publish the message to redis",e);
		}finally{
			redisPool.returnResource(jedis);
		}
	}

	public void start() {
		log.debug("Starting redis pubsub...");		

		final Jedis jedis = redisPool.getResource();
		try {
			pubsubListener = new Runnable() {
			    public void run() {
			    	jedis.psubscribe(new PubSubListener(), MessagingConstants.BIGBLUEBUTTON_PATTERN);       			
			    }
			};
			exec.execute(pubsubListener);
		} catch (Exception e) {
			log.error("Error in subscribe: " + e.getMessage());
		}
	}

	public void stop() {
		try {
			redisPool.destroy();
		} catch (Exception e) {
			e.printStackTrace();
		}
	}
	
	public void setRedisPool(JedisPool redisPool){
		this.redisPool=redisPool;
	}
	
	private class PubSubListener extends JedisPubSub {
		
		public PubSubListener() {
			super();			
		}

		@Override
		public void onMessage(String channel, String message) {
			// Not used.
		}

		@Override
		public void onPMessage(String pattern, String channel, String message) {
			log.debug("Message Received in channel: " + channel);
			log.debug("Message: " + message);
			
			Gson gson = new Gson();
			HashMap<String,String> map = gson.fromJson(message, new TypeToken<Map<String, String>>() {}.getType());
			
//			for (String key: map.keySet()) {
//				log.debug("rx: {} = {}", key, map.get(key));
//			}
			
			if(channel.equalsIgnoreCase(MessagingConstants.SYSTEM_CHANNEL)){
				String meetingId = map.get("meetingId");
				String messageId = map.get("messageId");
				log.debug("*** Meeting {} Message {}", meetingId, messageId);
				
				for (MessageListener listener : listeners) {
					if(MessagingConstants.MEETING_STARTED_EVENT.equalsIgnoreCase(messageId)) {
						listener.meetingStarted(meetingId);
					} else if(MessagingConstants.MEETING_ENDED_EVENT.equalsIgnoreCase(messageId)) {
						listener.meetingEnded(meetingId);
					}
				}
			}
			else if(channel.equalsIgnoreCase(MessagingConstants.PARTICIPANTS_CHANNEL)){
				String meetingId = map.get("meetingId");
				String messageId = map.get("messageId");
				if(MessagingConstants.USER_JOINED_EVENT.equalsIgnoreCase(messageId)){
					String internalUserId = map.get("internalUserId");
					String externalUserId = map.get("externalUserId");
					String fullname = map.get("fullname");
					String role = map.get("role");
					
					for (MessageListener listener : listeners) {
						listener.userJoined(meetingId, internalUserId, externalUserId, fullname, role);
					}
				} else if(MessagingConstants.USER_STATUS_CHANGE_EVENT.equalsIgnoreCase(messageId)){
					String internalUserId = map.get("internalUserId");
					String status = map.get("status");
					String value = map.get("value");
					
					for (MessageListener listener : listeners) {
						listener.updatedStatus(meetingId, internalUserId, status, value);
					}
				} else if(MessagingConstants.USER_LEFT_EVENT.equalsIgnoreCase(messageId)){
					String internalUserId = map.get("internalUserId");
					
					for (MessageListener listener : listeners) {
						listener.userLeft(meetingId, internalUserId);
					}
				}
			}
		}

		@Override
		public void onPSubscribe(String pattern, int subscribedChannels) {
			log.debug("Subscribed to the pattern:"+pattern);
		}

		@Override
		public void onPUnsubscribe(String pattern, int subscribedChannels) {
			// Not used.
		}

		@Override
		public void onSubscribe(String channel, int subscribedChannels) {
			// Not used.
		}

		@Override
		public void onUnsubscribe(String channel, int subscribedChannels) {
			// Not used.
		}		
	}

	@Override
	public void recordMeeting(String meetingID, String externalID, String name) {
		Jedis jedis = redisPool.getResource();
		try {
			HashMap<String,String> map = new HashMap<String, String>();
			map.put("meetingID", meetingID);
			map.put("externalID", externalID);
			map.put("name", name);
			
			jedis.hmset("meeting-" + meetingID, map);
			jedis.sadd("meetings", meetingID);

		} finally {
			redisPool.returnResource(jedis);
		}
	}
	public void removeMeeting(String meetingId){
		Jedis jedis = redisPool.getResource();
		try {
			jedis.del("meeting-" + meetingId);
			//jedis.hmset("meeting"+ COLON +"info" + COLON + meetingId, metadata);
			jedis.srem("meetings", meetingId);

		} finally {
			redisPool.returnResource(jedis);
		}
	}

	@Override
	public void recordPresentation(String meetingID, String presentationName, int numberOfPages) {
		Jedis jedis = redisPool.getResource();
		try {
			
			jedis.sadd("meeting-" + meetingID + "-presentations", presentationName);
			for(int i=1;i<=numberOfPages;i++){
				jedis.rpush("meeting-"+meetingID+"-presentation-"+presentationName+"-pages", Integer.toString(i));
				jedis.set("meeting-"+meetingID+"-presentation-"+presentationName+"-page-"+i+"-image", "slide"+i+".png");
				
				/*default image size is 800x600.
				This will cause images in any other aspect ratio to be stretched out
				To fix this, we pass the image size through redis which is obtained from the png files in the 
				var/bigbluebutton directory*/
				int width = 800;
				int height = 600;
				try {
					BufferedImage bimg = ImageIO.read(new File("/var/bigbluebutton/"+meetingID+"/"+meetingID+"/"+presentationName+"/pngs/slide"+i+".png"));
					width = bimg.getWidth();
					height = bimg.getHeight();
				} catch (IOException e) {
					/*If there is an error in opening the files, the images will default back to 800x600
					This is not ideal*/
					width = 800;
					height = 600;
					log.error(e.toString());
				}
				
				jedis.set("meeting-"+meetingID+"-presentation-"+presentationName+"-page-"+i+"-width", Integer.toString(width));
				jedis.set("meeting-"+meetingID+"-presentation-"+presentationName+"-page-"+i+"-height", Integer.toString(height));
			}
			jedis.set("meeting-" + meetingID + "-currentpresentation", presentationName);
			//VIEWBOX
			ArrayList viewbox = new ArrayList();
			viewbox.add(0);
			viewbox.add(0);
			viewbox.add(1);
			viewbox.add(1);
			Gson gson = new Gson();
			jedis.set("meeting-" + meetingID + "-viewbox", gson.toJson(viewbox));
		} finally {
			redisPool.returnResource(jedis);
		}
	}

}
