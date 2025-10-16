package com.pistoncontrol.services

import com.pistoncontrol.database.DatabaseFactory.dbQuery
import com.pistoncontrol.database.*
import com.pistoncontrol.mqtt.*
import org.jetbrains.exposed.sql.*
import java.time.Instant
import java.util.UUID
import mu.KotlinLogging
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

private val logger = KotlinLogging.logger {}

/**
 * Device Message Handler
 * 
 * Processes MQTT messages and persists them to PostgreSQL.
 * Uses kotlinx.serialization for JSON handling.
 */
class DeviceMessageHandler {
    
    // JSON serializer instance
    private val json = Json { 
        prettyPrint = false
        ignoreUnknownKeys = true
    }
    
    suspend fun handleMessage(message: DeviceMessage) {
        logger.debug { "Processing ${message.messageType} from device ${message.deviceId}" }
        
        try {
            when (message.messageType) {
                MessageType.PISTON_STATE -> handlePistonState(message)
                MessageType.STATUS_UPDATE -> handleStatusUpdate(message)
                MessageType.TELEMETRY -> handleTelemetry(message)
                MessageType.ERROR -> handleError(message)
                MessageType.UNKNOWN -> handleUnknown(message)
            }
        } catch (e: Exception) {
            logger.error(e) { "Failed to handle message from ${message.deviceId}" }
        }
    }
    
    /**
     * Handle piston state changes
     * 
     * LEARNING NOTE: We build a JSON string using kotlinx.serialization's buildJsonObject,
     * which ensures proper escaping and valid JSON format.
     */
    private suspend fun handlePistonState(message: DeviceMessage) {
        val payload = message.payload as? MessagePayload.PistonState ?: return
        
        dbQuery {
            val deviceUuid = UUID.fromString(message.deviceId)
            
            // Find existing piston
            val pistonRecord = Pistons.select {
                (Pistons.deviceId eq deviceUuid) and
                (Pistons.pistonNumber eq payload.pistonNumber)
            }.singleOrNull()
            
            if (pistonRecord == null) {
                // Create new piston
                Pistons.insert {
                    it[deviceId] = deviceUuid
                    it[pistonNumber] = payload.pistonNumber
                    it[state] = if (payload.isActive) "active" else "inactive"
                    it[lastTriggered] = Instant.ofEpochMilli(payload.timestamp)
                }
                logger.info { "Created piston ${payload.pistonNumber} for device ${message.deviceId}" }
            } else {
                // Update existing piston
                val pistonUuid = pistonRecord[Pistons.id]
                
                Pistons.update({ Pistons.id eq pistonUuid }) {
                    it[state] = if (payload.isActive) "active" else "inactive"
                    it[lastTriggered] = Instant.ofEpochMilli(payload.timestamp)
                }
                
                logger.info { 
                    "Updated piston ${payload.pistonNumber}: ${if (payload.isActive) "ACTIVE" else "INACTIVE"}" 
                }
                
                // ✅ FIX: Build proper JSON string using kotlinx.serialization
                val jsonPayload = buildJsonObject {
                    put("piston_number", payload.pistonNumber)
                    put("timestamp", payload.timestamp)
                }.toString()
                
                // Log telemetry event
                Telemetry.insert {
                    it[deviceId] = deviceUuid
                    it[Telemetry.pistonId] = pistonUuid
                    it[eventType] = if (payload.isActive) "activated" else "deactivated"
                    it[Telemetry.payload] = jsonPayload  // PostgreSQL will auto-cast to JSONB
                    it[createdAt] = Instant.ofEpochMilli(payload.timestamp)
                }
            }
        }
    }
    
    /**
     * Handle device status updates
     * 
     * LEARNING NOTE: We use buildJsonObject to conditionally add fields.
     * Only non-null values are included in the JSON.
     */
    private suspend fun handleStatusUpdate(message: DeviceMessage) {
        val payload = message.payload as? MessagePayload.Status ?: return
        
        dbQuery {
            val deviceUuid = UUID.fromString(message.deviceId)
            
            // Update device status
            Devices.update({ Devices.id eq deviceUuid }) {
                it[status] = payload.status
                it[updatedAt] = Instant.now()
            }
            
            // ✅ FIX: Build JSON with conditional fields
            val jsonPayload = buildJsonObject {
                put("status", payload.status)
                payload.batteryLevel?.let { put("battery_level", it) }
                payload.signalStrength?.let { put("signal_strength", it) }
            }.toString()
            
            // Log status update to telemetry
            Telemetry.insert {
                it[deviceId] = deviceUuid
                it[Telemetry.pistonId] = null
                it[eventType] = "status_update"
                it[Telemetry.payload] = jsonPayload
                it[createdAt] = Instant.now()
            }
            
            logger.info { "Device ${message.deviceId} status: ${payload.status}" }
        }
    }
    
    /**
     * Handle telemetry sensor readings
     */
    private suspend fun handleTelemetry(message: DeviceMessage) {
        val payload = message.payload as? MessagePayload.Telemetry ?: return
        
        dbQuery {
            val deviceUuid = UUID.fromString(message.deviceId)
            
            // ✅ FIX: Build JSON for sensor data
            val jsonPayload = buildJsonObject {
                put("sensor", payload.sensorType)
                put("value", payload.value.toDouble())  // Ensure it's stored as number
                put("timestamp", payload.timestamp)
            }.toString()
            
            Telemetry.insert {
                it[deviceId] = deviceUuid
                it[Telemetry.pistonId] = null
                it[eventType] = "sensor_reading"
                it[Telemetry.payload] = jsonPayload
                it[createdAt] = Instant.ofEpochMilli(payload.timestamp)
            }
            
            logger.debug { "Telemetry: ${payload.sensorType} = ${payload.value}" }
        }
    }
    
    /**
     * Handle error reports from devices
     */
    private suspend fun handleError(message: DeviceMessage) {
        val payload = message.payload as? MessagePayload.Error ?: return
        
        dbQuery {
            val deviceUuid = UUID.fromString(message.deviceId)
            
            // Mark device as in error state
            Devices.update({ Devices.id eq deviceUuid }) {
                it[status] = "error"
                it[updatedAt] = Instant.now()
            }
            
            // ✅ FIX: Build JSON for error details
            val jsonPayload = buildJsonObject {
                put("error_code", payload.errorCode)
                put("message", payload.errorMessage)
            }.toString()
            
            Telemetry.insert {
                it[deviceId] = deviceUuid
                it[Telemetry.pistonId] = null
                it[eventType] = "error"
                it[Telemetry.payload] = jsonPayload
                it[createdAt] = Instant.now()
            }
            
            logger.error { 
                "Device ${message.deviceId} error ${payload.errorCode}: ${payload.errorMessage}" 
            }
        }
    }
    
    /**
     * Handle unknown message types (fallback)
     * 
     * LEARNING NOTE: For unknown messages, we store the raw JSON data as-is.
     */
    private suspend fun handleUnknown(message: DeviceMessage) {
        val payload = message.payload as? MessagePayload.Raw ?: return
        
        dbQuery {
            val deviceUuid = UUID.fromString(message.deviceId)
            
            Telemetry.insert {
                it[deviceId] = deviceUuid
                it[Telemetry.pistonId] = null
                it[eventType] = "unknown"
                it[Telemetry.payload] = payload.rawData  // Already a JSON string
                it[createdAt] = Instant.now()
            }
            
            logger.warn { "Unknown message type from ${message.deviceId}" }
        }
    }
    
    /**
     * Get device statistics for monitoring
     */
    suspend fun getDeviceStats(deviceId: String): DeviceStats? {
        return dbQuery {
            val deviceUuid = UUID.fromString(deviceId)
            
            val device = Devices.select { Devices.id eq deviceUuid }
                .singleOrNull() ?: return@dbQuery null
            
            val pistonStates = Pistons.select { Pistons.deviceId eq deviceUuid }
                .associate { it[Pistons.pistonNumber] to it[Pistons.state] }
            
            val telemetryCount = Telemetry.select { 
                Telemetry.deviceId eq deviceUuid 
            }.count()
            
            val lastActivity = Telemetry.select { 
                Telemetry.deviceId eq deviceUuid 
            }
                .orderBy(Telemetry.createdAt to SortOrder.DESC)
                .limit(1)
                .singleOrNull()
                ?.get(Telemetry.createdAt)
            
            DeviceStats(
                deviceId = deviceId,
                status = device[Devices.status],
                activePistons = pistonStates.count { it.value == "active" },
                totalPistons = pistonStates.size,
                totalEvents = telemetryCount,
                lastActivity = lastActivity
            )
        }
    }
}

/**
 * Data class for device statistics
 */
data class DeviceStats(
    val deviceId: String,
    val status: String,
    val activePistons: Int,
    val totalPistons: Int,
    val totalEvents: Long,
    val lastActivity: Instant?
)
