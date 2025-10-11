package com.pistoncontrol

import com.pistoncontrol.database.DatabaseFactory
import com.pistoncontrol.mqtt.MqttManager
import com.pistoncontrol.plugins.*
import io.ktor.server.application.*
import io.ktor.server.netty.*
import mu.KotlinLogging

private val logger = KotlinLogging.logger {}

fun main(args: Array<String>): Unit = EngineMain.main(args)

fun Application.module() {
    logger.info { "Starting Piston Control Backend..." }
    
    // Initialize Database
    try {
        DatabaseFactory.init()
        logger.info { "Database initialized successfully" }
    } catch (e: Exception) {
        logger.error(e) { "Failed to initialize database" }
        throw e
    }
    
    // Initialize MQTT Manager
    val mqttBroker = System.getenv("MQTT_BROKER") ?: throw IllegalStateException("MQTT_BROKER not set")
    val mqttManager = MqttManager(
        broker = mqttBroker,
        clientId = "ktor-backend-${System.currentTimeMillis()}"
    )
    
    try {
        mqttManager.connect()
        logger.info { "MQTT Manager connected to $mqttBroker" }
    } catch (e: Exception) {
        logger.error(e) { "Failed to connect to MQTT broker" }
        throw e
    }
    
    // Configure plugins
    configureSerialization()
    configureSecurity()
    configureWebSockets()
    configureMonitoring()
    configureRouting(mqttManager)
    
    logger.info { "Piston Control Backend started successfully" }
}
