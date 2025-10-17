package com.pistoncontrol.protocol

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.UUID
import mu.KotlinLogging

private val logger = KotlinLogging.logger {}

/**
 * Binary Protocol Parser for IoT Device Communication
 * 
 * This parser handles binary messages from Raspberry Pi devices, which is more
 * efficient than JSON for IoT applications (50-70% smaller payloads).
 * 
 * Protocol Structure:
 * - Header (1 byte): Message type identifier
 * - Device ID (16 bytes): UUID of the device
 * - Payload (variable): Message-specific data
 * - Checksum (2 bytes): CRC16 for data integrity
 * 
 * Message Types:
 * 0x01 = Piston State Change
 * 0x02 = Status Update
 * 0x03 = Telemetry Data
 * 0x04 = Error Report
 */
class BinaryProtocolParser {
    
    companion object {
        // Message type constants
        const val MSG_PISTON_STATE: Byte = 0x01
        const val MSG_STATUS_UPDATE: Byte = 0x02
        const val MSG_TELEMETRY: Byte = 0x03
        const val MSG_ERROR: Byte = 0x04
        
        // Protocol constants
        const val HEADER_SIZE = 1
        const val DEVICE_ID_SIZE = 16
        const val CHECKSUM_SIZE = 2
        const val MIN_MESSAGE_SIZE = HEADER_SIZE + DEVICE_ID_SIZE + CHECKSUM_SIZE
    }
    
    /**
     * Sealed class representing parsed messages
     * This uses Kotlin's type-safe approach to handle different message types
     */
    sealed class ParsedMessage {
        abstract val deviceId: UUID
        
        /**
         * Piston state changed (activated/deactivated)
         */
        data class PistonStateChange(
            override val deviceId: UUID,
            val pistonNumber: Int,
            val isActive: Boolean,
            val timestamp: Long
        ) : ParsedMessage()
        
        /**
         * Device status update (online/offline, battery, etc.)
         */
        data class StatusUpdate(
            override val deviceId: UUID,
            val status: String,
            val batteryLevel: Int?,
            val signalStrength: Int?
        ) : ParsedMessage()
        
        /**
         * Telemetry data (temperature, pressure, etc.)
         */
        data class TelemetryData(
            override val deviceId: UUID,
            val sensorType: String,
            val value: Float,
            val timestamp: Long
        ) : ParsedMessage()
        
        /**
         * Error report from device
         */
        data class ErrorReport(
            override val deviceId: UUID,
            val errorCode: Int,
            val errorMessage: String
        ) : ParsedMessage()
    }
    
    /**
     * Parse binary data received from MQTT
     * 
     * This is the main entry point for parsing. It:
     * 1. Validates message size
     * 2. Verifies checksum
     * 3. Extracts device ID
     * 4. Delegates to specific parser based on message type
     * 
     * @param data Raw bytes from MQTT message
     * @return ParsedMessage or null if parsing fails
     */
    fun parse(data: ByteArray): ParsedMessage? {
        try {
            // Step 1: Validate minimum message size
            if (data.size < MIN_MESSAGE_SIZE) {
                logger.warn { "Message too short: ${data.size} bytes (minimum: $MIN_MESSAGE_SIZE)" }
                return null
            }
            
            // Step 2: Create ByteBuffer for efficient reading
            // LITTLE_ENDIAN matches most embedded systems (ARM, ESP32)
            val buffer = ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN)
            
            // Step 3: Read header (message type)
            val messageType = buffer.get()
            
            // Step 4: Read device ID (16 bytes = 128-bit UUID)
            val deviceIdBytes = ByteArray(DEVICE_ID_SIZE)
            buffer.get(deviceIdBytes)
            val deviceId = bytesToUUID(deviceIdBytes)
            
            // Step 5: Extract payload (everything except header, device ID, and checksum)
            val payloadSize = data.size - MIN_MESSAGE_SIZE
            val payload = ByteArray(payloadSize)
            buffer.get(payload)
            
            // Step 6: Verify checksum for data integrity
            val receivedChecksum = buffer.short
            val calculatedChecksum = calculateChecksum(data, data.size - CHECKSUM_SIZE)
            
            if (receivedChecksum != calculatedChecksum) {
                logger.error { 
                    "Checksum mismatch! Received: $receivedChecksum, Calculated: $calculatedChecksum" 
                }
                return null
            }
            
            // Step 7: Parse payload based on message type
            return when (messageType) {
                MSG_PISTON_STATE -> parsePistonState(deviceId, payload)
                MSG_STATUS_UPDATE -> parseStatusUpdate(deviceId, payload)
                MSG_TELEMETRY -> parseTelemetry(deviceId, payload)
                MSG_ERROR -> parseError(deviceId, payload)
                else -> {
                    logger.warn { "Unknown message type: 0x${messageType.toString(16)}" }
                    null
                }
            }
            
        } catch (e: Exception) {
            logger.error(e) { "Error parsing binary message" }
            return null
        }
    }
    
    /**
     * Parse piston state change message
     * 
     * Payload format:
     * - Byte 0: Piston number (1-8)
     * - Byte 1: State (0=inactive, 1=active)
     * - Bytes 2-9: Timestamp (8 bytes, long)
     */
    private fun parsePistonState(deviceId: UUID, payload: ByteArray): ParsedMessage.PistonStateChange? {
        if (payload.size < 10) {
            logger.warn { "Invalid piston state payload size: ${payload.size}" }
            return null
        }
        
        val buffer = ByteBuffer.wrap(payload).order(ByteOrder.LITTLE_ENDIAN)
        val pistonNumber = buffer.get().toInt()
        val isActive = buffer.get() == 1.toByte()
        val timestamp = buffer.long
        
        return ParsedMessage.PistonStateChange(
            deviceId = deviceId,
            pistonNumber = pistonNumber,
            isActive = isActive,
            timestamp = timestamp
        )
    }
    
    /**
     * Parse status update message
     * 
     * Payload format:
     * - Byte 0: Status code (0=offline, 1=online, 2=error)
     * - Byte 1: Battery level (0-100, or 255 if not applicable)
     * - Byte 2: Signal strength (0-100, or 255 if not applicable)
     */
    private fun parseStatusUpdate(deviceId: UUID, payload: ByteArray): ParsedMessage.StatusUpdate? {
        if (payload.size < 3) {
            logger.warn { "Invalid status update payload size: ${payload.size}" }
            return null
        }
        
        val buffer = ByteBuffer.wrap(payload).order(ByteOrder.LITTLE_ENDIAN)
        val statusCode = buffer.get().toInt()
        val batteryLevel = buffer.get().toInt().let { if (it == 255) null else it }
        val signalStrength = buffer.get().toInt().let { if (it == 255) null else it }
        
        val status = when (statusCode) {
            0 -> "offline"
            1 -> "online"
            2 -> "error"
            else -> "unknown"
        }
        
        return ParsedMessage.StatusUpdate(
            deviceId = deviceId,
            status = status,
            batteryLevel = batteryLevel,
            signalStrength = signalStrength
        )
    }
    
    /**
     * Parse telemetry data message
     * 
     * Payload format:
     * - Byte 0: Sensor type (0=temp, 1=pressure, 2=humidity, etc.)
     * - Bytes 1-4: Float value
     * - Bytes 5-12: Timestamp (8 bytes, long)
     */
    private fun parseTelemetry(deviceId: UUID, payload: ByteArray): ParsedMessage.TelemetryData? {
        if (payload.size < 13) {
            logger.warn { "Invalid telemetry payload size: ${payload.size}" }
            return null
        }
        
        val buffer = ByteBuffer.wrap(payload).order(ByteOrder.LITTLE_ENDIAN)
        val sensorTypeCode = buffer.get().toInt()
        val value = buffer.float
        val timestamp = buffer.long
        
        val sensorType = when (sensorTypeCode) {
            0 -> "temperature"
            1 -> "pressure"
            2 -> "humidity"
            3 -> "voltage"
            else -> "unknown"
        }
        
        return ParsedMessage.TelemetryData(
            deviceId = deviceId,
            sensorType = sensorType,
            value = value,
            timestamp = timestamp
        )
    }
    
    /**
     * Parse error report message
     * 
     * Payload format:
     * - Bytes 0-3: Error code (4 bytes, int)
     * - Remaining bytes: Error message (UTF-8 string)
     */
    private fun parseError(deviceId: UUID, payload: ByteArray): ParsedMessage.ErrorReport? {
        if (payload.size < 4) {
            logger.warn { "Invalid error payload size: ${payload.size}" }
            return null
        }
        
        val buffer = ByteBuffer.wrap(payload).order(ByteOrder.LITTLE_ENDIAN)
        val errorCode = buffer.int
        
        val messageBytes = ByteArray(payload.size - 4)
        buffer.get(messageBytes)
        val errorMessage = String(messageBytes, Charsets.UTF_8)
        
        return ParsedMessage.ErrorReport(
            deviceId = deviceId,
            errorCode = errorCode,
            errorMessage = errorMessage
        )
    }
    
    /**
     * Convert 16 bytes to UUID
     * UUID is stored as two longs (most significant bits, least significant bits)
     */
    private fun bytesToUUID(bytes: ByteArray): UUID {
        val buffer = ByteBuffer.wrap(bytes)
        val mostSigBits = buffer.long
        val leastSigBits = buffer.long
        return UUID(mostSigBits, leastSigBits)
    }
    
    /**
     * Calculate CRC16 checksum for data integrity
     * This is a simple but effective error detection algorithm
     * 
     * CRC (Cyclic Redundancy Check) works by:
     * 1. Treating data as a large binary number
     * 2. Dividing by a polynomial (0x8005 in this case)
     * 3. Using the remainder as the checksum
     */
    private fun calculateChecksum(data: ByteArray, length: Int): Short {
        var crc = 0xFFFF
        
        for (i in 0 until length) {
            crc = crc xor (data[i].toInt() and 0xFF)
            
            for (j in 0 until 8) {
                if ((crc and 0x0001) != 0) {
                    crc = (crc shr 1) xor 0x8005
                } else {
                    crc = crc shr 1
                }
            }
        }
        
        return crc.toShort()
    }
    
    /**
     * Create binary command to send to device
     * This is the reverse operation - encoding commands to binary
     * 
     * @param deviceId Target device UUID
     * @param pistonNumber Which piston (1-8)
     * @param activate True to activate, false to deactivate
     * @return Binary data ready to send via MQTT
     */
    fun createPistonCommand(deviceId: UUID, pistonNumber: Int, activate: Boolean): ByteArray {
        // Calculate total size
        val totalSize = MIN_MESSAGE_SIZE + 2 // header + deviceId + payload(2 bytes) + checksum
        val buffer = ByteBuffer.allocate(totalSize).order(ByteOrder.LITTLE_ENDIAN)
        
        // Write header
        buffer.put(MSG_PISTON_STATE)
        
        // Write device ID
        val deviceIdBytes = uuidToBytes(deviceId)
        buffer.put(deviceIdBytes)
        
        // Write payload
        buffer.put(pistonNumber.toByte())
        buffer.put(if (activate) 1.toByte() else 0.toByte())
        
        // Calculate and write checksum
        val dataForChecksum = buffer.array()
        val checksum = calculateChecksum(dataForChecksum, totalSize - CHECKSUM_SIZE)
        buffer.putShort(checksum)
        
        return buffer.array()
    }
    
    /**
     * Convert UUID to 16 bytes
     */
    private fun uuidToBytes(uuid: UUID): ByteArray {
        val buffer = ByteBuffer.allocate(16)
        buffer.putLong(uuid.mostSignificantBits)
        buffer.putLong(uuid.leastSignificantBits)
        return buffer.array()
    }
}
