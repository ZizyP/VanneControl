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
                    
                    val devices = dbQuery {
                        Devices.select { Devices.ownerId eq userId }.map {
                            DeviceResponse(
                                id = it[Devices.id].toString(),
                                name = it[Devices.name],
                                mqttClientId = it[Devices.mqttClientId],
                                status = it[Devices.status]
                            )
                        }
                    }
                    
                    call.respond(HttpStatusCode.OK, devices)
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
                    val device = dbQuery {
                        Devices.select { Devices.id eq UUID.fromString(deviceId) }.singleOrNull()
                    }
                    
                    if (device == null) {
                        call.respond(HttpStatusCode.NotFound, ErrorResponse("Device not found"))
                    } else {
                        call.respond(
                            HttpStatusCode.OK,
                            DeviceResponse(
                                id = device[Devices.id].toString(),
                                name = device[Devices.name],
                                mqttClientId = device[Devices.mqttClientId],
                                status = device[Devices.status]
                            )
                        )
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
                    
                    mqttManager.publishCommand(deviceId, "${request.action}:$pistonNumber", useBinary = true)
                    
                    call.respond(
                        HttpStatusCode.OK,
                        CommandResponse(
                            success = true,
                            message = "Command sent",
                            deviceId = deviceId,
                            pistonNumber = pistonNumber,
                            action = request.action
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
