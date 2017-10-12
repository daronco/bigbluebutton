package org.bigbluebutton

import akka.actor.ActorSystem

import org.bigbluebutton.endpoint.redis.AppsRedisSubscriberActor
import org.bigbluebutton.core.pubsub.receivers.RedisMessageReceiver

object Boot extends App with SystemConfiguration {

  implicit val system = ActorSystem("bigbluebutton-dbsync-system")

  // val redisPublisher = new RedisPublisher(system)

  // val inJsonMsgBus = new InJsonMsgBus
  // val redisMessageHandlerActor = system.actorOf(JsonMsgHdlrActor.props(inGW))
  // inJsonMsgBus.subscribe(redisMessageHandlerActor, toAkkaTranscodeJsonChannel)

  // val redisSubscriberActor = system.actorOf(AppsRedisSubscriberActor.props(system, inJsonMsgBus), "redis-subscriber")

  //val bbbInGW = new BigBlueButtonInGW(system, eventBus, bbbMsgBus, outGW)
  val redisMsgReceiver = new RedisMessageReceiver()
  val redisSubscriberActor = system.actorOf(AppsRedisSubscriberActor.props(system, redisMsgReceiver), "redis-subscriber")

}
