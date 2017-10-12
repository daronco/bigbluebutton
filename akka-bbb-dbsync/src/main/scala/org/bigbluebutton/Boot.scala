package org.bigbluebutton

import akka.actor.ActorSystem

import org.bigbluebutton.endpoint.redis.AppsRedisSubscriberActor
import org.bigbluebutton.core.pubsub.receivers.RedisMessageReceiver

object Boot extends App with SystemConfiguration {

  implicit val system = ActorSystem("bigbluebutton-dbsync-system")

  val redisMsgReceiver = new RedisMessageReceiver()
  val redisSubscriberActor = system.actorOf(AppsRedisSubscriberActor.props(system, redisMsgReceiver), "redis-subscriber")

}
