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
import java.util.*
import mu.KotlinLogging

private val logger = KotlinLogging.logger {}

@Serializable
data class PistonCommand(val action: String, val piston_number: Int)

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

fun Route.deviceRoutes(mqttManager: MqttManager) {
    authenticate("auth-jwt") {
        
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
            
            call.respond(HttpStatusCode.OK, mapOf(
                "success" to true,
                "message" to "Command sent",
                "action" to request.action,
                "piston" to pistonNumber
            ))
        }
        
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
                        mapOf(
                            "id" to row[Telemetry.id],
                            "device_id" to row[Telemetry.deviceId].toString(),
                            "piston_id" to row[Telemetry.pistonId]?.toString(),
                            "event_type" to row[Telemetry.eventType],
                            "payload" to row[Telemetry.payload],
                            "created_at" to row[Telemetry.createdAt].toString()
                        )
                    }
            }
            
            call.respond(HttpStatusCode.OK, telemetry)
        }
    }
}
