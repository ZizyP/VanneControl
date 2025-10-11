package com.pistoncontrol.websocket

import com.pistoncontrol.mqtt.MqttManager
import io.ktor.websocket.*
import kotlinx.coroutines.*
import kotlinx.serialization.json.*
import java.util.concurrent.ConcurrentHashMap
import mu.KotlinLogging

private val logger = KotlinLogging.logger {}

class WebSocketManager(private val mqttManager: MqttManager) {
    private val sessions = ConcurrentHashMap<String, DefaultWebSocketSession>()
    private val deviceSubscriptions = ConcurrentHashMap<String, MutableSet<String>>()
    
    suspend fun handleConnection(sessionId: String, session: DefaultWebSocketSession) {
        sessions[sessionId] = session
        logger.info { "WebSocket session connected: $sessionId" }
        
        try {
            session.send(Frame.Text("""{"type":"connected","session_id":"$sessionId"}"""))
            
            for (frame in session.incoming) {
                if (frame is Frame.Text) {
                    handleMessage(sessionId, frame.readText())
                }
            }
        } catch (e: Exception) {
            logger.error(e) { "WebSocket error for session $sessionId" }
        } finally {
            cleanup(sessionId)
        }
    }
    
    private suspend fun handleMessage(sessionId: String, message: String) {
        try {
            val json = Json.parseToJsonElement(message).jsonObject
            val type = json["type"]?.jsonPrimitive?.content
            
            when (type) {
                "subscribe" -> {
                    val deviceId = json["device_id"]?.jsonPrimitive?.content
                    if (deviceId != null) {
                        deviceSubscriptions.getOrPut(deviceId) { mutableSetOf() }.add(sessionId)
                        sessions[sessionId]?.send(
                            Frame.Text("""{"type":"subscribed","device_id":"$deviceId"}""")
                        )
                        logger.info { "Session $sessionId subscribed to device $deviceId" }
                    }
                }
                "unsubscribe" -> {
                    val deviceId = json["device_id"]?.jsonPrimitive?.content
                    if (deviceId != null) {
                        deviceSubscriptions[deviceId]?.remove(sessionId)
                        logger.info { "Session $sessionId unsubscribed from device $deviceId" }
                    }
                }
                "ping" -> {
                    sessions[sessionId]?.send(Frame.Text("""{"type":"pong"}"""))
                }
            }
        } catch (e: Exception) {
            logger.error(e) { "Error handling WebSocket message from session $sessionId" }
        }
    }
    
    private fun cleanup(sessionId: String) {
        sessions.remove(sessionId)
        deviceSubscriptions.values.forEach { it.remove(sessionId) }
        logger.info { "WebSocket session cleaned up: $sessionId" }
    }
    
    fun startMqttForwarding() {
        GlobalScope.launch {
            mqttManager.messageFlow.collect { message ->
                val subscribedSessions = deviceSubscriptions[message.deviceId] ?: emptySet()
                
                val wsMessage = buildJsonObject {
                    put("type", "device_update")
                    put("device_id", message.deviceId)
                    put("topic", message.topic)
                    put("payload", Json.parseToJsonElement(message.payload))
                    put("timestamp", System.currentTimeMillis())
                }.toString()
                
                subscribedSessions.forEach { sessionId ->
                    sessions[sessionId]?.let { session ->
                        try {
                            session.send(Frame.Text(wsMessage))
                        } catch (e: Exception) {
                            logger.error(e) { "Failed to send to WebSocket session $sessionId" }
                        }
                    }
                }
            }
        }
        logger.info { "MQTT to WebSocket forwarding started" }
    }
    
    suspend fun broadcast(message: String) {
        sessions.values.forEach { session ->
            try {
                session.send(Frame.Text(message))
            } catch (e: Exception) {
                logger.error(e) { "Failed to broadcast message" }
            }
        }
    }
}
