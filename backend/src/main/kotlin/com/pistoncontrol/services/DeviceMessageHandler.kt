package com.pistoncontrol.services

import com.pistoncontrol.database.DatabaseFactory.dbQuery
import com.pistoncontrol.database.*
import com.pistoncontrol.mqtt.*
import org.jetbrains.exposed.sql.*
import java.time.Instant
import java.util.UUID
import mu.KotlinLogging

private val logger = KotlinLogging.logger {}

class DeviceMessageHandler {
    
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
    
    private suspend fun handlePistonState(message: DeviceMessage) {
        val payload = message.payload as? MessagePayload.PistonState ?: return
        
        dbQuery {
            val deviceUuid = UUID.fromString(message.deviceId)
            
            Pistons.update({
                (Pistons.deviceId eq deviceUuid) and 
                (Pistons.pistonNumber eq payload.pistonNumber)
            }) {
                it[state] = if (payload.isActive) "active" else "inactive"
                it[lastTriggered] = Instant.now()
            }
            
            Telemetry.insert {
                it[deviceId] = deviceUuid
                it[Telemetry.pistonId] = null
                it[eventType] = if (payload.isActive) "activated" else "deactivated"
                it[Telemetry.payload] = """{"piston_number":${payload.pistonNumber},"timestamp":${payload.timestamp}}"""
                it[createdAt] = Instant.ofEpochMilli(payload.timestamp)
            }
            
            logger.info { "Piston ${payload.pistonNumber} on device ${message.deviceId}: ${if (payload.isActive) "active" else "inactive"}" }
        }
    }
    
    private suspend fun handleStatusUpdate(message: DeviceMessage) {
        val payload = message.payload as? MessagePayload.Status ?: return
        
        dbQuery {
            val deviceUuid = UUID.fromString(message.deviceId)
            
            Devices.update({ Devices.id eq deviceUuid }) {
                it[status] = payload.status
                it[updatedAt] = Instant.now()
            }
            
            Telemetry.insert {
                it[deviceId] = deviceUuid
                it[Telemetry.pistonId] = null
                it[eventType] = "status_update"
                it[Telemetry.payload] = buildString {
                    append("""{"status":"${payload.status}"""")
                    if (payload.batteryLevel != null) {
                        append(""","battery_level":${payload.batteryLevel}""")
                    }
                    if (payload.signalStrength != null) {
                        append(""","signal_strength":${payload.signalStrength}""")
                    }
                    append("}")
                }
                it[createdAt] = Instant.now()
            }
            
            logger.info { "Device ${message.deviceId} status: ${payload.status}" }
        }
    }
    
    private suspend fun handleTelemetry(message: DeviceMessage) {
        val payload = message.payload as? MessagePayload.Telemetry ?: return
        
        dbQuery {
            val deviceUuid = UUID.fromString(message.deviceId)
            
            Telemetry.insert {
                it[deviceId] = deviceUuid
                it[Telemetry.pistonId] = null
                it[eventType] = "sensor_reading"
                it[Telemetry.payload] = """{"sensor":"${payload.sensorType}","value":${payload.value},"timestamp":${payload.timestamp}}"""
                it[createdAt] = Instant.ofEpochMilli(payload.timestamp)
            }
            
            logger.debug { "Telemetry: ${payload.sensorType} = ${payload.value}" }
        }
    }
    
    private suspend fun handleError(message: DeviceMessage) {
        val payload = message.payload as? MessagePayload.Error ?: return
        
        dbQuery {
            val deviceUuid = UUID.fromString(message.deviceId)
            
            Devices.update({ Devices.id eq deviceUuid }) {
                it[status] = "error"
                it[updatedAt] = Instant.now()
            }
            
            Telemetry.insert {
                it[deviceId] = deviceUuid
                it[Telemetry.pistonId] = null
                it[eventType] = "error"
                it[Telemetry.payload] = """{"error_code":${payload.errorCode},"message":"${payload.errorMessage}"}"""
                it[createdAt] = Instant.now()
            }
            
            logger.error { "Device ${message.deviceId} error ${payload.errorCode}: ${payload.errorMessage}" }
        }
    }
    
    private suspend fun handleUnknown(message: DeviceMessage) {
        val payload = message.payload as? MessagePayload.Raw ?: return
        
        dbQuery {
            val deviceUuid = UUID.fromString(message.deviceId)
            
            Telemetry.insert {
                it[deviceId] = deviceUuid
                it[Telemetry.pistonId] = null
                it[eventType] = "unknown"
                it[Telemetry.payload] = payload.rawData
                it[createdAt] = Instant.now()
            }
        }
    }
    
    suspend fun getDeviceStats(deviceId: String): DeviceStats? {
        return dbQuery {
            val deviceUuid = UUID.fromString(deviceId)
            
            val device = Devices.select { Devices.id eq deviceUuid }.singleOrNull() ?: return@dbQuery null
            
            val pistonStates = Pistons.select { Pistons.deviceId eq deviceUuid }
                .associate { it[Pistons.pistonNumber] to it[Pistons.state] }
            
            val telemetryCount = Telemetry.select { Telemetry.deviceId eq deviceUuid }.count()
            
            val lastActivity = Telemetry.select { Telemetry.deviceId eq deviceUuid }
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

data class DeviceStats(
    val deviceId: String,
    val status: String,
    val activePistons: Int,
    val totalPistons: Int,
    val totalEvents: Long,
    val lastActivity: Instant?
)
