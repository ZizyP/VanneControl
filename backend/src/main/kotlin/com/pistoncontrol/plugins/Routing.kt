package com.pistoncontrol.plugins

import com.pistoncontrol.mqtt.MqttManager
import com.pistoncontrol.services.DeviceMessageHandler
import com.pistoncontrol.routes.*
import com.pistoncontrol.websocket.WebSocketManager
import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.auth.*
import io.ktor.server.auth.jwt.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import io.ktor.server.websocket.*
import kotlinx.serialization.Serializable
import java.util.UUID

@Serializable
data class HealthResponse(
    val status: String,
    val timestamp: Long
)

@Serializable
data class ErrorResponse(
    val error: String
)

fun Application.configureRouting(
    mqttManager: MqttManager,
    messageHandler: DeviceMessageHandler
) {
    val jwtSecret = environment.config.property("jwt.secret").getString()
    val jwtIssuer = environment.config.property("jwt.issuer").getString()
    val jwtAudience = environment.config.property("jwt.audience").getString()
    
    val wsManager = WebSocketManager(mqttManager)
    wsManager.startMqttForwarding()
    
    routing {
        get("/health") {
            call.respond(
                HttpStatusCode.OK, 
                HealthResponse(
                    status = "healthy",
                    timestamp = System.currentTimeMillis()
                )
            )
        }
        
        head("/health") {
            call.respond(HttpStatusCode.OK)
        }
        
        authRoutes(jwtSecret, jwtIssuer, jwtAudience)
        deviceRoutes(mqttManager)
        
        authenticate("auth-jwt") {
            get("/devices/{id}/stats") {
                val deviceId = call.parameters["id"] ?: return@get call.respond(
                    HttpStatusCode.BadRequest, 
                    ErrorResponse(error = "Missing device ID")
                )
                
                val stats = messageHandler.getDeviceStats(deviceId)
                
                if (stats == null) {
                    call.respond(
                        HttpStatusCode.NotFound, 
                        ErrorResponse(error = "Device not found")
                    )
                } else {
                    call.respond(HttpStatusCode.OK, stats)
                }
            }
        }
        
        webSocket("/ws") {
            val sessionId = UUID.randomUUID().toString()
            wsManager.handleConnection(sessionId, this)
        }
    }
}
