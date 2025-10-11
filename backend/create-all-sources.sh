#!/bin/bash
set -e

echo "📝 Creating all backend source files..."

BASE="src/main/kotlin/com/pistoncontrol"
RESOURCES="src/main/resources"

# Create directories
mkdir -p $BASE/{plugins,routes,database,mqtt,websocket,models}
mkdir -p $RESOURCES

# ============= Models =============
cat > $BASE/models/Models.kt << 'EOFMODELS'
package com.pistoncontrol.models

import kotlinx.serialization.Serializable
import java.util.UUID

@Serializable
data class User(
    val id: String,
    val email: String,
    val role: String
)

@Serializable
data class Device(
    val id: String,
    val name: String,
    val ownerId: String,
    val mqttClientId: String,
    val status: String,
    val createdAt: String
)

@Serializable
data class Piston(
    val id: String,
    val deviceId: String,
    val pistonNumber: Int,
    val state: String,
    val lastTriggered: String?
)

@Serializable
data class TelemetryEvent(
    val id: Long,
    val deviceId: String,
    val pistonId: String?,
    val eventType: String,
    val payload: String?,
    val createdAt: String
)
EOFMODELS

# ============= Database Factory =============
cat > $BASE/database/DatabaseFactory.kt << 'EOFDB'
package com.pistoncontrol.database

import com.zaxxer.hikari.HikariConfig
import com.zaxxer.hikari.HikariDataSource
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.jetbrains.exposed.sql.Database
import org.jetbrains.exposed.sql.transactions.transaction
import mu.KotlinLogging

private val logger = KotlinLogging.logger {}

object DatabaseFactory {
    fun init() {
        val driverClassName = "org.postgresql.Driver"
        val jdbcURL = System.getenv("DATABASE_URL") 
            ?: throw IllegalStateException("DATABASE_URL not set")
        val user = System.getenv("DATABASE_USER") 
            ?: throw IllegalStateException("DATABASE_USER not set")
        val password = System.getenv("DATABASE_PASSWORD") 
            ?: throw IllegalStateException("DATABASE_PASSWORD not set")
        
        logger.info { "Initializing database connection to $jdbcURL" }
        
        Database.connect(createHikariDataSource(jdbcURL, driverClassName, user, password))
    }
    
    private fun createHikariDataSource(
        url: String,
        driver: String,
        user: String,
        password: String
    ) = HikariDataSource(HikariConfig().apply {
        driverClassName = driver
        jdbcUrl = url
        username = user
        this.password = password
        maximumPoolSize = 10
        minimumIdle = 2
        idleTimeout = 600000
        connectionTimeout = 30000
        maxLifetime = 1800000
        isAutoCommit = false
        transactionIsolation = "TRANSACTION_REPEATABLE_READ"
        
        validate()
    })
    
    suspend fun <T> dbQuery(block: () -> T): T =
        withContext(Dispatchers.IO) {
            transaction { block() }
        }
}
EOFDB

# ============= Database Tables =============
cat > $BASE/database/Tables.kt << 'EOFTABLES'
package com.pistoncontrol.database

import org.jetbrains.exposed.sql.Table
import org.jetbrains.exposed.sql.javatime.timestamp

object Users : Table("users") {
    val id = uuid("id")
    val email = text("email")
    val passwordHash = text("password_hash")
    val role = text("role")
    val createdAt = timestamp("created_at")
    val updatedAt = timestamp("updated_at")
    
    override val primaryKey = PrimaryKey(id)
}

object Devices : Table("devices") {
    val id = uuid("id")
    val name = text("name")
    val ownerId = uuid("owner_id")
    val mqttClientId = text("mqtt_client_id")
    val status = text("status")
    val createdAt = timestamp("created_at")
    val updatedAt = timestamp("updated_at")
    
    override val primaryKey = PrimaryKey(id)
}

object Pistons : Table("pistons") {
    val id = uuid("id")
    val deviceId = uuid("device_id")
    val pistonNumber = integer("piston_number")
    val state = text("state")
    val lastTriggered = timestamp("last_triggered").nullable()
    
    override val primaryKey = PrimaryKey(id)
}

object Telemetry : Table("telemetry") {
    val id = long("id")
    val deviceId = uuid("device_id")
    val pistonId = uuid("piston_id").nullable()
    val eventType = text("event_type")
    val payload = text("payload").nullable()
    val createdAt = timestamp("created_at")
    
    override val primaryKey = PrimaryKey(id)
}

object AuthTokens : Table("auth_tokens") {
    val id = uuid("id")
    val userId = uuid("user_id")
    val refreshToken = text("refresh_token")
    val expiresAt = timestamp("expires_at")
    val createdAt = timestamp("created_at")
    
    override val primaryKey = PrimaryKey(id)
}
EOFTABLES

# ============= MQTT Manager =============
cat > $BASE/mqtt/MqttManager.kt << 'EOFMQTT'
package com.pistoncontrol.mqtt

import org.eclipse.paho.client.mqttv3.*
import org.eclipse.paho.client.mqttv3.persist.MemoryPersistence
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.launch
import mu.KotlinLogging

private val logger = KotlinLogging.logger {}

data class DeviceMessage(
    val deviceId: String,
    val topic: String,
    val payload: String
)

class MqttManager(
    private val broker: String,
    private val clientId: String
) {
    private lateinit var client: MqttClient
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
                    val parts = topic.split("/")
                    if (parts.size >= 2) {
                        val deviceId = parts[1]
                        val payload = String(message.payload)
                        
                        logger.debug { "MQTT message received: $topic -> $payload" }
                        
                        GlobalScope.launch {
                            _messageFlow.emit(
                                DeviceMessage(deviceId, topic, payload)
                            )
                        }
                    }
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
        
        logger.info { "MQTT client connected and subscribed to device topics" }
    }
    
    fun publishCommand(deviceId: String, command: String) {
        try {
            val topic = "devices/$deviceId/commands"
            val message = MqttMessage(command.toByteArray()).apply {
                qos = 1
                isRetained = false
            }
            client.publish(topic, message)
            logger.info { "Published command to $topic: $command" }
        } catch (e: Exception) {
            logger.error(e) { "Failed to publish command to device $deviceId" }
            throw e
        }
    }
    
    fun disconnect() {
        if (::client.isInitialized && client.isConnected) {
            client.disconnect()
            logger.info { "MQTT client disconnected" }
        }
    }
}
EOFMQTT

# ============= WebSocket Manager =============
cat > $BASE/websocket/WebSocketManager.kt << 'EOFWS'
package com.pistoncontrol.websocket

import com.pistoncontrol.mqtt.MqttManager
import io.ktor.websocket.*
import kotlinx.coroutines.*
import kotlinx.serialization.json.*
import java.util.concurrent.ConcurrentHashMap
import mu.KotlinLogging

private val logger = KotlinLogging.logger {}

class WebSocketManager(private val mqttManager: MqttManager) {
    private val sessions = ConcurrentHashMap<String, DefaultWebSocketSession>()
    private val deviceSubscriptions = ConcurrentHashMap<String, MutableSet<String>>()
    
    suspend fun handleConnection(sessionId: String, session: DefaultWebSocketSession) {
        sessions[sessionId] = session
        logger.info { "WebSocket session connected: $sessionId" }
        
        try {
            session.send(Frame.Text("""{"type":"connected","session_id":"$sessionId"}"""))
            
            for (frame in session.incoming) {
                if (frame is Frame.Text) {
                    handleMessage(sessionId, frame.readText())
                }
            }
        } catch (e: Exception) {
            logger.error(e) { "WebSocket error for session $sessionId" }
        } finally {
            cleanup(sessionId)
        }
    }
    
    private suspend fun handleMessage(sessionId: String, message: String) {
        try {
            val json = Json.parseToJsonElement(message).jsonObject
            val type = json["type"]?.jsonPrimitive?.content
            
            when (type) {
                "subscribe" -> {
                    val deviceId = json["device_id"]?.jsonPrimitive?.content
                    if (deviceId != null) {
                        deviceSubscriptions.getOrPut(deviceId) { mutableSetOf() }.add(sessionId)
                        sessions[sessionId]?.send(
                            Frame.Text("""{"type":"subscribed","device_id":"$deviceId"}""")
                        )
                        logger.info { "Session $sessionId subscribed to device $deviceId" }
                    }
                }
                "unsubscribe" -> {
                    val deviceId = json["device_id"]?.jsonPrimitive?.content
                    if (deviceId != null) {
                        deviceSubscriptions[deviceId]?.remove(sessionId)
                        logger.info { "Session $sessionId unsubscribed from device $deviceId" }
                    }
                }
                "ping" -> {
                    sessions[sessionId]?.send(Frame.Text("""{"type":"pong"}"""))
                }
            }
        } catch (e: Exception) {
            logger.error(e) { "Error handling WebSocket message from session $sessionId" }
        }
    }
    
    private fun cleanup(sessionId: String) {
        sessions.remove(sessionId)
        deviceSubscriptions.values.forEach { it.remove(sessionId) }
        logger.info { "WebSocket session cleaned up: $sessionId" }
    }
    
    fun startMqttForwarding() {
        GlobalScope.launch {
            mqttManager.messageFlow.collect { message ->
                val subscribedSessions = deviceSubscriptions[message.deviceId] ?: emptySet()
                
                val wsMessage = buildJsonObject {
                    put("type", "device_update")
                    put("device_id", message.deviceId)
                    put("topic", message.topic)
                    put("payload", Json.parseToJsonElement(message.payload))
                    put("timestamp", System.currentTimeMillis())
                }.toString()
                
                subscribedSessions.forEach { sessionId ->
                    sessions[sessionId]?.let { session ->
                        try {
                            session.send(Frame.Text(wsMessage))
                        } catch (e: Exception) {
                            logger.error(e) { "Failed to send to WebSocket session $sessionId" }
                        }
                    }
                }
            }
        }
        logger.info { "MQTT to WebSocket forwarding started" }
    }
    
    suspend fun broadcast(message: String) {
        sessions.values.forEach { session ->
            try {
                session.send(Frame.Text(message))
            } catch (e: Exception) {
                logger.error(e) { "Failed to broadcast message" }
            }
        }
    }
}
EOFWS

# ============= Auth Routes =============
cat > $BASE/routes/AuthRoutes.kt << 'EOFAUTH'
package com.pistoncontrol.routes

import com.pistoncontrol.database.DatabaseFactory.dbQuery
import com.pistoncontrol.database.Users
import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import kotlinx.serialization.Serializable
import org.jetbrains.exposed.sql.*
import org.mindrot.jbcrypt.BCrypt
import com.auth0.jwt.JWT
import com.auth0.jwt.algorithms.Algorithm
import java.util.*
import mu.KotlinLogging

private val logger = KotlinLogging.logger {}

@Serializable
data class LoginRequest(val email: String, val password: String)

@Serializable
data class RegisterRequest(val email: String, val password: String)

@Serializable
data class AuthResponse(val token: String, val user: UserInfo)

@Serializable
data class UserInfo(val id: String, val email: String, val role: String)

fun Route.authRoutes(jwtSecret: String, jwtIssuer: String, jwtAudience: String) {
    
    post("/auth/register") {
        val request = call.receive<RegisterRequest>()
        
        if (!request.email.contains("@") || request.email.length < 5) {
            return@post call.respond(HttpStatusCode.BadRequest, mapOf("error" to "Invalid email"))
        }
        
        if (request.password.length < 8) {
            return@post call.respond(HttpStatusCode.BadRequest, 
                mapOf("error" to "Password must be at least 8 characters"))
        }
        
        val existing = dbQuery {
            Users.select { Users.email eq request.email }.singleOrNull()
        }
        
        if (existing != null) {
            return@post call.respond(HttpStatusCode.Conflict, 
                mapOf("error" to "Email already registered"))
        }
        
        val userId = dbQuery {
            Users.insert {
                it[email] = request.email
                it[passwordHash] = BCrypt.hashpw(request.password, BCrypt.gensalt())
                it[role] = "user"
                it[createdAt] = java.time.Instant.now()
                it[updatedAt] = java.time.Instant.now()
            }[Users.id]
        }
        
        val token = JWT.create()
            .withAudience(jwtAudience)
            .withIssuer(jwtIssuer)
            .withClaim("userId", userId.toString())
            .withClaim("email", request.email)
            .withClaim("role", "user")
            .withExpiresAt(Date(System.currentTimeMillis() + 86400000))
            .sign(Algorithm.HMAC256(jwtSecret))
        
        logger.info { "User registered: ${request.email}" }
        
        call.respond(HttpStatusCode.Created, AuthResponse(
            token = token,
            user = UserInfo(userId.toString(), request.email, "user")
        ))
    }
    
    post("/auth/login") {
        val request = call.receive<LoginRequest>()
        
        val user = dbQuery {
            Users.select { Users.email eq request.email }.singleOrNull()
        }
        
        if (user == null || !BCrypt.checkpw(request.password, user[Users.passwordHash])) {
            return@post call.respond(HttpStatusCode.Unauthorized, 
                mapOf("error" to "Invalid credentials"))
        }
        
        val token = JWT.create()
            .withAudience(jwtAudience)
            .withIssuer(jwtIssuer)
            .withClaim("userId", user[Users.id].toString())
            .withClaim("email", user[Users.email])
            .withClaim("role", user[Users.role])
            .withExpiresAt(Date(System.currentTimeMillis() + 86400000))
            .sign(Algorithm.HMAC256(jwtSecret))
        
        logger.info { "User logged in: ${request.email}" }
        
        call.respond(HttpStatusCode.OK, AuthResponse(
            token = token,
            user = UserInfo(user[Users.id].toString(), user[Users.email], user[Users.role])
        ))
    }
}
EOFAUTH

# ============= Device Routes =============
cat > $BASE/routes/DeviceRoutes.kt << 'EOFDEV'
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
EOFDEV

# ============= Plugins =============
cat > $BASE/plugins/Security.kt << 'EOFSEC'
package com.pistoncontrol.plugins

import com.auth0.jwt.JWT
import com.auth0.jwt.algorithms.Algorithm
import io.ktor.server.application.*
import io.ktor.server.auth.*
import io.ktor.server.auth.jwt.*

fun Application.configureSecurity() {
    val jwtSecret = environment.config.property("jwt.secret").getString()
    val jwtIssuer = environment.config.property("jwt.issuer").getString()
    val jwtAudience = environment.config.property("jwt.audience").getString()
    val jwtRealm = "Piston Control"
    
    install(Authentication) {
        jwt("auth-jwt") {
            realm = jwtRealm
            verifier(
                JWT.require(Algorithm.HMAC256(jwtSecret))
                    .withAudience(jwtAudience)
                    .withIssuer(jwtIssuer)
                    .build()
            )
            validate { credential ->
                if (credential.payload.getClaim("userId").asString() != null) {
                    JWTPrincipal(credential.payload)
                } else null
            }
        }
    }
}
EOFSEC

cat > $BASE/plugins/Serialization.kt << 'EOFSER'
package com.pistoncontrol.plugins

import io.ktor.serialization.kotlinx.json.*
import io.ktor.server.application.*
import io.ktor.server.plugins.contentnegotiation.*
import kotlinx.serialization.json.Json

fun Application.configureSerialization() {
    install(ContentNegotiation) {
        json(Json {
            prettyPrint = true
            isLenient = true
            ignoreUnknownKeys = true
        })
    }
}
EOFSER

cat > $BASE/plugins/Sockets.kt << 'EOFSOCK'
package com.pistoncontrol.plugins

import io.ktor.server.application.*
import io.ktor.server.websocket.*
import java.time.Duration

fun Application.configureWebSockets() {
    install(WebSockets) {
        pingPeriod = Duration.ofSeconds(30)
        timeout = Duration.ofSeconds(15)
        maxFrameSize = Long.MAX_VALUE
        masking = false
    }
}
EOFSOCK

cat > $BASE/plugins/Monitoring.kt << 'EOFMON'
package com.pistoncontrol.plugins

import io.ktor.server.application.*
import io.ktor.server.plugins.callloging.*
import io.ktor.server.request.*
import org.slf4j.event.Level

fun Application.configureMonitoring() {
    install(CallLogging) {
        level = Level.INFO
        filter { call -> call.request.path().startsWith("/") }
        format { call ->
            val status = call.response.status()
            val httpMethod = call.request.httpMethod.value
            val path = call.request.path()
            "$httpMethod $path - $status"
        }
    }
}
EOFMON

cat > $BASE/plugins/Routing.kt << 'EOFROUTE'
package com.pistoncontrol.plugins

import com.pistoncontrol.mqtt.MqttManager
import com.pistoncontrol.routes.*
import com.pistoncontrol.websocket.WebSocketManager
import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import io.ktor.server.websocket.*
import java.util.UUID

fun Application.configureRouting(mqttManager: MqttManager) {
    val jwtSecret = environment.config.property("jwt.secret").getString()
    val jwtIssuer = environment.config.property("jwt.issuer").getString()
    val jwtAudience = environment.config.property("jwt.audience").getString()
    
    val wsManager = WebSocketManager(mqttManager)
    wsManager.startMqttForwarding()
    
    routing {
        get("/health") {
            call.respond(HttpStatusCode.OK, mapOf(
                "status"


cat backend/create-all-source.sh
