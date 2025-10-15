package com.pistoncontrol.mqtt

import com.pistoncontrol.protocol.BinaryProtocolParser
import org.eclipse.paho.client.mqttv3.*
import org.eclipse.paho.client.mqttv3.persist.MemoryPersistence
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.launch
import mu.KotlinLogging
import java.util.UUID

private val logger = KotlinLogging.logger {}

/**
 * Enhanced MQTT Manager with Binary Protocol Support
 * 
 * This manager now supports BOTH JSON (for backward compatibility) 
 * and binary protocols (for efficiency). It automatically detects 
 * which format is being used.
 */

/**
 * Unified message structure for internal processing
 * This allows the rest of the application to work with a consistent
 * message format regardless of whether the source was JSON or binary
 */
data class DeviceMessage(
    val deviceId: String,
    val topic: String,
    val messageType: MessageType,
    val payload: MessagePayload
)

/**
 * Message types our system handles
 */
enum class MessageType {
    PISTON_STATE,
    STATUS_UPDATE,
    TELEMETRY,
    ERROR,
    UNKNOWN
}

/**
 * Sealed class for different payload types
 * This ensures type safety - you can't accidentally mix up payload types
 */
sealed class MessagePayload {
    data class PistonState(
        val pistonNumber: Int,
        val isActive: Boolean,
        val timestamp: Long
    ) : MessagePayload()
    
    data class Status(
        val status: String,
        val batteryLevel: Int?,
        val signalStrength: Int?
    ) : MessagePayload()
    
    data class Telemetry(
        val sensorType: String,
        val value: Float,
        val timestamp: Long
    ) : MessagePayload()
    
    data class Error(
        val errorCode: Int,
        val errorMessage: String
    ) : MessagePayload()
    
    data class Raw(
        val rawData: String
    ) : MessagePayload()
}

class MqttManager(
    private val broker: String,
    private val clientId: String
) {
    private lateinit var client: MqttClient
    private val parser = BinaryProtocolParser()
    
    // Flow for broadcasting messages to WebSocket clients
    private val _messageFlow = MutableSharedFlow<DeviceMessage>(replay = 0)
    val messageFlow: SharedFlow<DeviceMessage> = _messageFlow
    
    fun connect() {
        logger.info { "Connecting to MQTT broker: $broker" }
        
        client = MqttClient(broker, clientId, MemoryPersistence())
        
        val options = MqttConnectOptions().apply {
            isCleanSession = true
            isAutomaticReconnect = true
            connectionTimeout = 30
            keepAliveInterval = 60
        }
        
        client.setCallback(object : MqttCallback {
            override fun messageArrived(topic: String, message: MqttMessage) {
                try {
                    handleIncomingMessage(topic, message)
                } catch (e: Exception) {
                    logger.error(e) { "Error processing MQTT message from $topic" }
                }
            }
            
            override fun connectionLost(cause: Throwable?) {
                logger.warn { "MQTT connection lost: ${cause?.message}" }
            }
            
            override fun deliveryComplete(token: IMqttDeliveryToken?) {
                logger.debug { "MQTT delivery complete: ${token?.topics?.joinToString()}" }
            }
        })
        
        client.connect(options)
        
        // Subscribe to all device topics
        client.subscribe("devices/+/status", 1)
        client.subscribe("devices/+/telemetry", 1)
        client.subscribe("devices/+/binary", 1)  // New: dedicated binary topic
        
        logger.info { "MQTT client connected and subscribed to device topics" }
    }
    
    /**
     * Handle incoming MQTT message
     * This is where we detect whether it's binary or JSON
     */
    private fun handleIncomingMessage(topic: String, message: MqttMessage) {
        val data = message.payload
        
        // Step 1: Extract device ID from topic
        // Topic format: "devices/{deviceId}/status" or "devices/{deviceId}/telemetry"
        val topicParts = topic.split("/")
        if (topicParts.size < 2) {
            logger.warn { "Invalid topic format: $topic" }
            return
        }
        val deviceId = topicParts[1]
        
        // Step 2: Detect message format (binary vs JSON)
        val deviceMessage = if (isBinaryMessage(data, topic)) {
            parseBinaryMessage(deviceId, topic, data)
        } else {
            parseJsonMessage(deviceId, topic, data)
        }
        
        // Step 3: Broadcast to WebSocket clients
        if (deviceMessage != null) {
            GlobalScope.launch {
                _messageFlow.emit(deviceMessage)
            }
        }
    }
    
    /**
     * Detect if message is binary or JSON
     * 
     * Binary messages have these characteristics:
     * 1. First byte is a valid message type (0x01-0x04)
     * 2. Minimum size is 19 bytes
     * 3. Topic ends with "/binary"
     * 4. NOT starting with '{' or '[' (JSON markers)
     */
    private fun isBinaryMessage(data: ByteArray, topic: String): Boolean {
        if (data.isEmpty()) return false
        
        // Check if topic explicitly indicates binary
        if (topic.endsWith("/binary")) return true
        
        // Check message characteristics
        val firstByte = data[0]
        val isValidMessageType = firstByte in 0x01..0x04
        val hasMinimumSize = data.size >= BinaryProtocolParser.MIN_MESSAGE_SIZE
        val notJsonStart = data[0] != '{'.code.toByte() && data[0] != '['.code.toByte()
        
        return isValidMessageType && hasMinimumSize && notJsonStart
    }
    
    /**
     * Parse binary message using BinaryProtocolParser
     */
    private fun parseBinaryMessage(deviceId: String, topic: String, data: ByteArray): DeviceMessage? {
        logger.debug { "Parsing binary message from $deviceId (${data.size} bytes)" }
        
        val parsed = parser.parse(data) ?: return null
        
        // Convert parsed message to our internal format
        return when (parsed) {
            is BinaryProtocolParser.ParsedMessage.PistonStateChange -> {
                DeviceMessage(
                    deviceId = deviceId,
                    topic = topic,
                    messageType = MessageType.PISTON_STATE,
                    payload = MessagePayload.PistonState(
                        pistonNumber = parsed.pistonNumber,
                        isActive = parsed.isActive,
                        timestamp = parsed.timestamp
                    )
                )
            }
            
            is BinaryProtocolParser.ParsedMessage.StatusUpdate -> {
                DeviceMessage(
                    deviceId = deviceId,
                    topic = topic,
                    messageType = MessageType.STATUS_UPDATE,
                    payload = MessagePayload.Status(
                        status = parsed.status,
                        batteryLevel = parsed.batteryLevel,
                        signalStrength = parsed.signalStrength
                    )
                )
            }
            
            is BinaryProtocolParser.ParsedMessage.TelemetryData -> {
                DeviceMessage(
                    deviceId = deviceId,
                    topic = topic,
                    messageType = MessageType.TELEMETRY,
                    payload = MessagePayload.Telemetry(
                        sensorType = parsed.sensorType,
                        value = parsed.value,
                        timestamp = parsed.timestamp
                    )
                )
            }
            
            is BinaryProtocolParser.ParsedMessage.ErrorReport -> {
                DeviceMessage(
                    deviceId = deviceId,
                    topic = topic,
                    messageType = MessageType.ERROR,
                    payload = MessagePayload.Error(
                        errorCode = parsed.errorCode,
                        errorMessage = parsed.errorMessage
                    )
                )
            }
        }
    }
    
    /**
     * Parse JSON message (backward compatibility)
     * This maintains support for devices still using JSON
     */
    private fun parseJsonMessage(deviceId: String, topic: String, data: ByteArray): DeviceMessage? {
        logger.debug { "Parsing JSON message from $deviceId" }
        
        try {
            val jsonString = String(data)
            // You would use kotlinx.serialization here to parse JSON
            // For now, returning a raw payload
            return DeviceMessage(
                deviceId = deviceId,
                topic = topic,
                messageType = MessageType.UNKNOWN,
                payload = MessagePayload.Raw(rawData = jsonString)
            )
        } catch (e: Exception) {
            logger.error(e) { "Failed to parse JSON message" }
            return null
        }
    }
    
    /**
     * Publish command to device
     * Now supports both binary and JSON formats
     */
    fun publishCommand(deviceId: String, command: String, useBinary: Boolean = true) {
        try {
            if (useBinary) {
                publishBinaryCommand(deviceId, command)
            } else {
                publishJsonCommand(deviceId, command)
            }
        } catch (e: Exception) {
            logger.error(e) { "Failed to publish command to device $deviceId" }
            throw e
        }
    }
    
    /**
     * Publish binary command
     * This is much more efficient for simple commands
     */
    private fun publishBinaryCommand(deviceId: String, command: String) {
        // Parse command string (e.g., "activate:3" or "deactivate:5")
        val parts = command.split(":")
        if (parts.size != 2) {
            throw IllegalArgumentException("Invalid command format: $command")
        }
        
        val action = parts[0]
        val pistonNumber = parts[1].toIntOrNull() 
            ?: throw IllegalArgumentException("Invalid piston number: ${parts[1]}")
        
        val activate = action == "activate"
        
        // Use parser to create binary command
        val deviceUuid = UUID.fromString(deviceId)
        val binaryData = parser.createPistonCommand(deviceUuid, pistonNumber, activate)
        
        // Publish to binary topic
        val topic = "devices/$deviceId/commands/binary"
        val message = MqttMessage(binaryData).apply {
            qos = 1
            isRetained = false
        }
        client.publish(topic, message)
        
        logger.info { "Published binary command to $topic: $action piston $pistonNumber (${binaryData.size} bytes)" }
    }
    
    /**
     * Publish JSON command (backward compatibility)
     */
    private fun publishJsonCommand(deviceId: String, command: String) {
        val topic = "devices/$deviceId/commands"
        val message = MqttMessage(command.toByteArray()).apply {
            qos = 1
            isRetained = false
        }
        client.publish(topic, message)
        logger.info { "Published JSON command to $topic: $command" }
    }
    
    fun disconnect() {
        if (::client.isInitialized && client.isConnected) {
            client.disconnect()
            logger.info { "MQTT client disconnected" }
        }
    }
}
