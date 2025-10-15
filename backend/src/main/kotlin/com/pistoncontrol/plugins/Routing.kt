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
import java.util.UUID

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
            call.respond(HttpStatusCode.OK, mapOf(
                "status" to "healthy",
                "timestamp" to System.currentTimeMillis()
            ))
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
                    mapOf("error" to "Missing device ID")
                )
                
                val stats = messageHandler.getDeviceStats(deviceId)
                
                if (stats == null) {
                    call.respond(HttpStatusCode.NotFound, mapOf("error" to "Device not found"))
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
