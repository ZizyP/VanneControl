package com.pistoncontrol.websocket

import com.pistoncontrol.mqtt.MqttManager
import com.pistoncontrol.mqtt.MessagePayload
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
                
                // FIX: Serialize payload properly
                val payloadJson = serializePayload(message.payload)
                
                val wsMessage = buildJsonObject {
                    put("type", "device_update")
                    put("device_id", message.deviceId)
                    put("topic", message.topic)
                    put("message_type", message.messageType.name)
                    put("payload", payloadJson)
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
    
    // FIX: This MUST be a class-level function, not local
    private fun serializePayload(payload: MessagePayload): JsonElement {
        return when (payload) {
            is MessagePayload.PistonState -> buildJsonObject {
                put("piston_number", payload.pistonNumber)
                put("is_active", payload.isActive)
                put("timestamp", payload.timestamp)
            }
            is MessagePayload.Status -> buildJsonObject {
                put("status", payload.status)
                payload.batteryLevel?.let { put("battery_level", it) }
                payload.signalStrength?.let { put("signal_strength", it) }
            }
            is MessagePayload.Telemetry -> buildJsonObject {
                put("sensor_type", payload.sensorType)
                put("value", payload.value)
                put("timestamp", payload.timestamp)
            }
            is MessagePayload.Error -> buildJsonObject {
                put("error_code", payload.errorCode)
                put("error_message", payload.errorMessage)
            }
            is MessagePayload.Raw -> {
                try {
                    Json.parseToJsonElement(payload.rawData)
                } catch (e: Exception) {
                    JsonPrimitive(payload.rawData)
                }
            }
        }
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
