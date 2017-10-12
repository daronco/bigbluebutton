package org.bigbluebutton

import com.typesafe.config.ConfigFactory
import scala.util.Try

trait SystemConfiguration {

  val config = ConfigFactory.load()

  lazy val redisHost = Try(config.getString("redis.host")).getOrElse("127.0.0.1")
  lazy val redisPort = Try(config.getInt("redis.port")).getOrElse(6379)
  lazy val redisPassword = Try(config.getString("redis.password")).getOrElse("")

  lazy val fromAkkaAppsRedisChannel = Try(config.getString("redis.fromAkkaAppsRedisChannel")).getOrElse("from-akka-apps-redis-channel")

  // lazy val toAkkaTranscodeRedisChannel = Try(config.getString("redis.toAkkaTranscodeRedisChannel")).getOrElse("bigbluebutton:to-bbb-transcode:system")
  // lazy val fromAkkaTranscodeRedisChannel = Try(config.getString("redis.fromAkkaTranscodeRedisChannel")).getOrElse("bigbluebutton:from-bbb-transcode:system")
}
