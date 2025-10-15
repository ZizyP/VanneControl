package com.pistoncontrol.routes

import com.pistoncontrol.database.DatabaseFactory.dbQuery
import com.pistoncontrol.database.*
import com.pistoncontrol.mqtt.MqttManager
import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.auth.*
import io.ktor.server.auth.jwt.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.jetbrains.exposed.sql.*
import java.time.Instant
import java.util.*
import mu.KotlinLogging

private val logger = KotlinLogging.logger {}

@Serializable
data class CreateDeviceRequest(
    val name: String,
    val mqtt_client_id: String
)

@Serializable
data class PistonCommand(val action: String, val piston_number: Int)

@Serializable
data class PistonCommandResponse(
    val success: Boolean,
    val message: String,
    val action: String,
    val piston: Int
)

@Serializable
data class DeviceResponse(
    val id: String,
    val name: String,
    val status: String,
    val pistons: List<PistonResponse>
)

@Serializable
data class PistonResponse(
    val id: String,
    val piston_number: Int,
    val state: String,
    val last_triggered: String?
)

@Serializable
data class TelemetryResponse(
    val id: Long,
    val device_id: String,
    val piston_id: String?,
    val event_type: String,
    val payload: String?,
    val created_at: String
)

fun Route.deviceRoutes(mqttManager: MqttManager) {
    authenticate("auth-jwt") {
        
        // Create device
        post("/devices") {
            try {
                val request = call.receive<CreateDeviceRequest>()
                val principal = call.principal<JWTPrincipal>()!!
                val userId = UUID.fromString(principal.payload.getClaim("userId").asString())
                
                // Check if device with this MQTT client ID already exists
                val existing = dbQuery {
                    Devices.select { Devices.mqttClientId eq request.mqtt_client_id }
                        .singleOrNull()
                }
                
                if (existing != null) {
                    return@post call.respond(
                        HttpStatusCode.Conflict,
                        mapOf("error" to "Device with this MQTT client ID already exists")
                    )
                }
                
                val deviceId = UUID.randomUUID()
                
                // Create device and pistons
                dbQuery {
                    Devices.insert {
                        it[id] = deviceId
                        it[name] = request.name
                        it[ownerId] = userId
                        it[mqttClientId] = request.mqtt_client_id
                        it[status] = "offline"
                        it[createdAt] = Instant.now()
                        it[updatedAt] = Instant.now()
                    }
                    
                    // Create 8 pistons for this device
                    for (pistonNum in 1..8) {
                        Pistons.insert {
                            it[id] = UUID.randomUUID()
                            it[Pistons.deviceId] = deviceId
                            it[pistonNumber] = pistonNum
                            it[state] = "inactive"
                            it[lastTriggered] = null
                        }
                    }
                }
                
                logger.info { "Device created: $deviceId by user $userId" }
                
                // Return the created device with pistons
                val pistons = dbQuery {
                    Pistons.select { Pistons.deviceId eq deviceId }
                        .map { row ->
                            PistonResponse(
                                id = row[Pistons.id].toString(),
                                piston_number = row[Pistons.pistonNumber],
                                state = row[Pistons.state],
                                last_triggered = row[Pistons.lastTriggered]?.toString()
                            )
                        }
                }
                
                call.respond(HttpStatusCode.Created, DeviceResponse(
                    id = deviceId.toString(),
                    name = request.name,
                    status = "offline",
                    pistons = pistons
                ))
                
            } catch (e: Exception) {
                logger.error(e) { "Failed to create device" }
                call.respond(
                    HttpStatusCode.InternalServerError,
                    mapOf("error" to "Failed to create device: ${e.message}")
                )
            }
        }
        
        // Get all devices
        get("/devices") {
            val principal = call.principal<JWTPrincipal>()!!
            val userId = UUID.fromString(principal.payload.getClaim("userId").asString())
            
            val devices = dbQuery {
                Devices.select { Devices.ownerId eq userId }
                    .map { deviceRow ->
                        val deviceId = deviceRow[Devices.id]
                        val pistons = Pistons.select { Pistons.deviceId eq deviceId }
                            .map { pistonRow ->
                                PistonResponse(
                                    id = pistonRow[Pistons.id].toString(),
                                    piston_number = pistonRow[Pistons.pistonNumber],
                                    state = pistonRow[Pistons.state],
                                    last_triggered = pistonRow[Pistons.lastTriggered]?.toString()
                                )
                            }
                        
                        DeviceResponse(
                            id = deviceId.toString(),
                            name = deviceRow[Devices.name],
                            status = deviceRow[Devices.status],
                            pistons = pistons
                        )
                    }
            }
            
            call.respond(HttpStatusCode.OK, devices)
        }
        
        // Get specific device
        get("/devices/{id}") {
            val deviceId = call.parameters["id"] ?: return@get call.respond(
                HttpStatusCode.BadRequest, mapOf("error" to "Missing device ID")
            )
            val principal = call.principal<JWTPrincipal>()!!
            val userId = UUID.fromString(principal.payload.getClaim("userId").asString())
            
            val device = dbQuery {
                Devices.select {
                    (Devices.id eq UUID.fromString(deviceId)) and
                    (Devices.ownerId eq userId)
                }.singleOrNull()?.let { deviceRow ->
                    val pistons = Pistons.select { Pistons.deviceId eq deviceRow[Devices.id] }
                        .map { pistonRow ->
                            PistonResponse(
                                id = pistonRow[Pistons.id].toString(),
                                piston_number = pistonRow[Pistons.pistonNumber],
                                state = pistonRow[Pistons.state],
                                last_triggered = pistonRow[Pistons.lastTriggered]?.toString()
                            )
                        }
                    
                    DeviceResponse(
                        id = deviceRow[Devices.id].toString(),
                        name = deviceRow[Devices.name],
                        status = deviceRow[Devices.status],
                        pistons = pistons
                    )
                }
            }
            
            if (device == null) {
                call.respond(HttpStatusCode.NotFound, mapOf("error" to "Device not found"))
            } else {
                call.respond(HttpStatusCode.OK, device)
            }
        }
        
        // Control piston - THIS IS THE FIX!
        post("/devices/{deviceId}/pistons/{pistonNumber}") {
            val deviceId = call.parameters["deviceId"] ?: return@post call.respond(
                HttpStatusCode.BadRequest, mapOf("error" to "Missing device ID")
            )
            val pistonNumber = call.parameters["pistonNumber"]?.toIntOrNull() ?: return@post call.respond(
                HttpStatusCode.BadRequest, mapOf("error" to "Invalid piston number")
            )
            
            val request = call.receive<PistonCommand>()
            val principal = call.principal<JWTPrincipal>()!!
            val userId = UUID.fromString(principal.payload.getClaim("userId").asString())
            
            val hasAccess = dbQuery {
                Devices.select {
                    (Devices.id eq UUID.fromString(deviceId)) and
                    (Devices.ownerId eq userId)
                }.count() > 0
            }
            
            if (!hasAccess) {
                return@post call.respond(HttpStatusCode.Forbidden, mapOf("error" to "Access denied"))
            }
            
            val command = Json.encodeToString(
                PistonCommand.serializer(),
                PistonCommand(request.action, pistonNumber)
            )
            
            mqttManager.publishCommand(deviceId, command)
            logger.info { "Command sent to device $deviceId: ${request.action} piston $pistonNumber" }
            
            // FIX: Use @Serializable data class instead of mapOf
            call.respond(HttpStatusCode.OK, PistonCommandResponse(
                success = true,
                message = "Command sent",
                action = request.action,
                piston = pistonNumber
            ))
        }
        
        // Get telemetry
        get("/devices/{deviceId}/telemetry") {
            val deviceId = call.parameters["deviceId"] ?: return@get call.respond(
                HttpStatusCode.BadRequest, mapOf("error" to "Missing device ID")
            )
            val limit = call.request.queryParameters["limit"]?.toIntOrNull() ?: 100
            val principal = call.principal<JWTPrincipal>()!!
            val userId = UUID.fromString(principal.payload.getClaim("userId").asString())
            
            val hasAccess = dbQuery {
                Devices.select {
                    (Devices.id eq UUID.fromString(deviceId)) and
                    (Devices.ownerId eq userId)
                }.count() > 0
            }
            
            if (!hasAccess) {
                return@get call.respond(HttpStatusCode.Forbidden, mapOf("error" to "Access denied"))
            }
            
            val telemetry = dbQuery {
                Telemetry.select { Telemetry.deviceId eq UUID.fromString(deviceId) }
                    .orderBy(Telemetry.createdAt to SortOrder.DESC)
                    .limit(limit)
                    .map { row ->
                        TelemetryResponse(
                            id = row[Telemetry.id],
                            device_id = row[Telemetry.deviceId].toString(),
                            piston_id = row[Telemetry.pistonId]?.toString(),
                            event_type = row[Telemetry.eventType],
                            payload = row[Telemetry.payload],
                            created_at = row[Telemetry.createdAt].toString()
                        )
                    }
            }
            
            call.respond(HttpStatusCode.OK, telemetry)
        }
    }
}
