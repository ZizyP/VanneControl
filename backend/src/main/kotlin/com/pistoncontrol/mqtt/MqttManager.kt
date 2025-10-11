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
