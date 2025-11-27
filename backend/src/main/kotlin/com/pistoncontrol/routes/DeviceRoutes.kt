package com.pistoncontrol.routes

import com.pistoncontrol.database.DatabaseFactory.dbQuery
import com.pistoncontrol.database.Devices
import com.pistoncontrol.database.Pistons
import com.pistoncontrol.mqtt.MqttManager
import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.auth.*
import io.ktor.server.auth.jwt.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import org.jetbrains.exposed.sql.*
import java.util.UUID

fun Route.deviceRoutes(mqttManager: MqttManager) {
    authenticate("auth-jwt") {
        route("/devices") {
            post {
                try {
                    val principal = call.principal<JWTPrincipal>()!!
                    val userId = UUID.fromString(principal.payload.getClaim("userId").asString())
                    val request = call.receive<CreateDeviceRequest>()
                    
                    val deviceId = dbQuery {
                        val existing = Devices.select { Devices.mqttClientId eq request.mqttClientId }.singleOrNull()
                        if (existing != null) {
                            return@dbQuery null
                        }
                        
                        Devices.insert {
                            it[ownerId] = userId
                            it[name] = request.name
                            it[mqttClientId] = request.mqttClientId
                            it[status] = "offline"
                        } get Devices.id
                    }
                    
                    if (deviceId == null) {
                        return@post call.respond(
                            HttpStatusCode.Conflict,
                            ErrorResponse("Device with this MQTT client ID already exists")
                        )
                    }
                    
                    call.respond(
                        HttpStatusCode.Created,
                        DeviceResponse(
                            id = deviceId.toString(),
                            name = request.name,
                            mqttClientId = request.mqttClientId,
                            status = "offline"
                        )
                    )
                } catch (e: Exception) {
                    call.respond(
                        HttpStatusCode.InternalServerError,
                        ErrorResponse("Failed to create device: ${e.message}")
                    )
                }
            }
            
            get {
                try {
                    val principal = call.principal<JWTPrincipal>()!!
                    val userId = UUID.fromString(principal.payload.getClaim("userId").asString())

                    val devicesWithPistons = dbQuery {
                        Devices.select { Devices.ownerId eq userId }.map { deviceRow ->
                            val deviceId = deviceRow[Devices.id]

                            // Fetch pistons for this device
                            val pistons = Pistons.select { Pistons.deviceId eq deviceId }.map {
                                PistonResponse(
                                    piston_number = it[Pistons.pistonNumber],
                                    state = it[Pistons.state],
                                    last_triggered = it[Pistons.lastTriggered]?.toString()
                                )
                            }

                            DeviceWithPistonsResponse(
                                id = deviceId.toString(),
                                name = deviceRow[Devices.name],
                                device_id = deviceRow[Devices.mqttClientId],  // Maps to mobile's device_id field
                                status = deviceRow[Devices.status],
                                last_seen = null,  // TODO: implement timestamp tracking
                                pistons = pistons
                            )
                        }
                    }

                    // Wrap in DevicesListResponse to match mobile expectations
                    call.respond(HttpStatusCode.OK, DevicesListResponse(devices = devicesWithPistons))
                } catch (e: Exception) {
                    call.respond(HttpStatusCode.InternalServerError, ErrorResponse(e.message ?: "Unknown error"))
                }
            }
            
            get("/{id}") {
                val deviceId = call.parameters["id"]
                if (deviceId == null) {
                    return@get call.respond(HttpStatusCode.BadRequest, ErrorResponse("Missing device ID"))
                }

                try {
                    val principal = call.principal<JWTPrincipal>()!!
                    val userId = UUID.fromString(principal.payload.getClaim("userId").asString())
                    val deviceUuid = try {
                        UUID.fromString(deviceId)
                    } catch (e: IllegalArgumentException) {
                        return@get call.respond(HttpStatusCode.BadRequest, ErrorResponse("Invalid device ID format"))
                    }

                    val deviceData = dbQuery {
                        // Check ownership
                        val device = Devices.select {
                            (Devices.id eq deviceUuid) and (Devices.ownerId eq userId)
                        }.singleOrNull()

                        if (device == null) {
                            return@dbQuery null
                        }

                        // Fetch pistons for this device
                        val pistons = Pistons.select { Pistons.deviceId eq deviceUuid }.map {
                            PistonResponse(
                                piston_number = it[Pistons.pistonNumber],
                                state = it[Pistons.state],
                                last_triggered = it[Pistons.lastTriggered]?.toString()
                            )
                        }

                        DeviceWithPistonsResponse(
                            id = device[Devices.id].toString(),
                            name = device[Devices.name],
                            device_id = device[Devices.mqttClientId],  // Maps to mobile's device_id field
                            status = device[Devices.status],
                            last_seen = null,  // TODO: implement timestamp tracking
                            pistons = pistons
                        )
                    }

                    if (deviceData == null) {
                        call.respond(HttpStatusCode.NotFound, ErrorResponse("Device not found"))
                    } else {
                        // Wrap in object matching mobile's DeviceResponse expectation
                        call.respond(HttpStatusCode.OK, mapOf("device" to deviceData))
                    }
                } catch (e: Exception) {
                    call.respond(HttpStatusCode.InternalServerError, ErrorResponse(e.message ?: "Unknown error"))
                }
            }
            
            post("/{deviceId}/pistons/{pistonNumber}") {
                val deviceId = call.parameters["deviceId"]
                val pistonNumberStr = call.parameters["pistonNumber"]

                if (deviceId == null) {
                    return@post call.respond(HttpStatusCode.BadRequest, ErrorResponse("Missing device ID"))
                }

                val pistonNumber = pistonNumberStr?.toIntOrNull()
                if (pistonNumber == null || pistonNumber !in 1..8) {
                    return@post call.respond(HttpStatusCode.BadRequest, ErrorResponse("Invalid piston number"))
                }

                try {
                    val principal = call.principal<JWTPrincipal>()!!
                    val userId = UUID.fromString(principal.payload.getClaim("userId").asString())
                    val request = call.receive<PistonCommand>()

                    val deviceUuid = UUID.fromString(deviceId)
                    val ownsDevice = dbQuery {
                        Devices.select {
                            (Devices.id eq deviceUuid) and (Devices.ownerId eq userId)
                        }.singleOrNull() != null
                    }

                    if (!ownsDevice) {
                        return@post call.respond(HttpStatusCode.Forbidden, ErrorResponse("Access denied"))
                    }

                    // Send MQTT command using binary protocol
                    mqttManager.publishCommand(deviceId, "${request.action}:$pistonNumber", useBinary = true)

                    // Update database with new state
                    val newState = if (request.action == "activate") "active" else "inactive"
                    val updatedPiston = dbQuery {
                        val now = java.time.Instant.now()

                        // Update or insert piston state
                        val existing = Pistons.select {
                            (Pistons.deviceId eq deviceUuid) and (Pistons.pistonNumber eq pistonNumber)
                        }.singleOrNull()

                        if (existing != null) {
                            Pistons.update({
                                (Pistons.deviceId eq deviceUuid) and (Pistons.pistonNumber eq pistonNumber)
                            }) {
                                it[state] = newState
                                it[lastTriggered] = now
                            }

                            val pistonId = existing[Pistons.id]
                            PistonWithIdResponse(
                                id = pistonId.toString(),
                                piston_number = pistonNumber,
                                state = newState,
                                last_triggered = now.toString()
                            )
                        } else {
                            // Create piston record if doesn't exist
                            val pistonId = Pistons.insert {
                                it[Pistons.deviceId] = deviceUuid
                                it[Pistons.pistonNumber] = pistonNumber
                                it[state] = newState
                                it[lastTriggered] = now
                            } get Pistons.id

                            PistonWithIdResponse(
                                id = pistonId.toString(),
                                piston_number = pistonNumber,
                                state = newState,
                                last_triggered = now.toString()
                            )
                        }
                    }

                    call.respond(
                        HttpStatusCode.OK,
                        PistonControlResponse(
                            message = "Piston ${if (newState == "active") "activated" else "deactivated"}",
                            piston = updatedPiston
                        )
                    )
                } catch (e: Exception) {
                    call.respond(HttpStatusCode.InternalServerError, ErrorResponse(e.message ?: "Unknown error"))
                }
            }
            
            get("/{deviceId}/pistons") {
                val deviceId = call.parameters["deviceId"]
                if (deviceId == null) {
                    return@get call.respond(HttpStatusCode.BadRequest, ErrorResponse("Missing device ID"))
                }
                
                try {
                    val principal = call.principal<JWTPrincipal>()!!
                    val userId = UUID.fromString(principal.payload.getClaim("userId").asString())
                    val deviceUuid = UUID.fromString(deviceId)
                    
                    val ownsDevice = dbQuery {
                        Devices.select { 
                            (Devices.id eq deviceUuid) and (Devices.ownerId eq userId) 
                        }.singleOrNull() != null
                    }
                    
                    if (!ownsDevice) {
                        return@get call.respond(HttpStatusCode.Forbidden, ErrorResponse("Access denied"))
                    }
                    
                    val pistons = dbQuery {
                        Pistons.select { Pistons.deviceId eq deviceUuid }.map {
                            PistonResponse(
                                piston_number = it[Pistons.pistonNumber],
                                state = it[Pistons.state],
                                last_triggered = it[Pistons.lastTriggered]?.toString()
                            )
                        }
                    }
                    
                    call.respond(HttpStatusCode.OK, pistons)
                } catch (e: Exception) {
                    call.respond(HttpStatusCode.InternalServerError, ErrorResponse(e.message ?: "Unknown error"))
                }
            }
        }
    }
}
