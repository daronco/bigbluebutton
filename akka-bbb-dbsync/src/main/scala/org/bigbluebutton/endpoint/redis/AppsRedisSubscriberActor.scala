package org.bigbluebutton.endpoint.redis

import java.io.PrintWriter
import java.io.StringWriter
import java.net.InetSocketAddress

import scala.concurrent.duration.DurationInt

import akka.actor.ActorSystem
import akka.actor.OneForOneStrategy
import akka.actor.Props
import akka.actor.SupervisorStrategy.Resume

import redis.actors.RedisSubscriberActor
import redis.api.pubsub.Message
import redis.api.pubsub.PMessage
import redis.api.servers.ClientSetname

import org.bigbluebutton.SystemConfiguration
import org.bigbluebutton.core.pubsub.receivers.RedisMessageReceiver

object AppsRedisSubscriberActor extends SystemConfiguration {

  val channels = Seq(fromAkkaAppsRedisChannel)
  val patterns = Seq("bigbluebutton:*")

  def props(system: ActorSystem, msgReceiver: RedisMessageReceiver): Props =
    Props(classOf[AppsRedisSubscriberActor], system, msgReceiver,
      redisHost, redisPort,
      channels, patterns).withDispatcher("akka.rediscala-subscriber-worker-dispatcher")
}

class AppsRedisSubscriberActor(val system: ActorSystem,
  msgReceiver: RedisMessageReceiver, redisHost: String,
  redisPort: Int,
  channels: Seq[String] = Nil, patterns: Seq[String] = Nil)
    extends RedisSubscriberActor(new InetSocketAddress(redisHost, redisPort),
      channels, patterns, onConnectStatus = connected => { println(s"connected: $connected") }) with SystemConfiguration {

  override val supervisorStrategy = OneForOneStrategy(maxNrOfRetries = 10, withinTimeRange = 1 minute) {
    case e: Exception => {
      val sw: StringWriter = new StringWriter()
      sw.write("An exception has been thrown on AppsRedisSubscriberActor, exception message [" + e.getMessage() + "] (full stacktrace below)\n")
      e.printStackTrace(new PrintWriter(sw))
      log.error(sw.toString())
      Resume
    }
  }

  write(ClientSetname("BbbTrDBSyncAkkaSub").encodedRequest)

  def onMessage(message: Message) {
    System.out.println(s"onMessage for:\n${message.channel}\n${message.data.utf8String}\n")
    msgReceiver.handleMessage("", message.channel, message.data.utf8String)
  }

  def onPMessage(message: PMessage) {
    System.out.println(s"onPMessage for:\n${message.channel}\n${message.patternMatched}\n${message.data.utf8String}\n")
    msgReceiver.handleMessage(message.patternMatched, message.channel, message.data.utf8String)
  }

  def handleMessage(message: String) {
    System.out.println(s"handleMessage for:\n${message}\n")
  }
}
