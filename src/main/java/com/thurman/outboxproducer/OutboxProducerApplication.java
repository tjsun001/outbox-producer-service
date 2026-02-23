package com.thurman.outboxproducer;

import java.time.Instant;
import java.util.UUID;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.ApplicationContext;
import org.springframework.core.env.Environment;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Component;

@SpringBootApplication
public class OutboxProducerApplication {
    public static void main(String[] args) {
        SpringApplication.run(OutboxProducerApplication.class, args);
    }
}

/**
 * Startup smoke producer (ONE message).
 *
 * Disabled by default.
 *
 * Enable it only when you want to validate MSK connectivity:
 *   app.kafka.startup.producer.enabled=true
 *
 * Optional:
 *   app.kafka.startup.producer.wait-for-ack=true     (default false)
 *   app.exit-after-send=true                        (default false)
 *
 * Note: Spring Boot relaxed binding lets you use env vars like:
 *   APP_KAFKA_STARTUP_PRODUCER_ENABLED=true
 *   APP_KAFKA_STARTUP_PRODUCER_WAIT_FOR_ACK=true
 *   APP_EXIT_AFTER_SEND=true
 */
@Component
@ConditionalOnProperty(
        prefix = "app.kafka.startup.producer",
        name = "enabled",
        havingValue = "true"
)
class ProducerOnStart implements CommandLineRunner {

    private static final Logger log = LoggerFactory.getLogger(ProducerOnStart.class);

    private final KafkaTemplate<String, String> kafkaTemplate;
    private final String topic;
    private final ApplicationContext ctx;
    private final Environment env;

    ProducerOnStart(
            KafkaTemplate<String, String> kafkaTemplate,
            @Value("${APP_TOPIC:outbox.events.test}") String topic,
            ApplicationContext ctx,
            Environment env
    ) {
        this.kafkaTemplate = kafkaTemplate;
        this.topic = topic;
        this.ctx = ctx;
        this.env = env;
    }

    @Override
    public void run(String... args) throws Exception {
        if (topic == null || topic.isBlank()) {
            throw new IllegalStateException("APP_TOPIC is required (env var or property).");
        }

        boolean waitForAck = env.getProperty("app.kafka.startup.producer.wait-for-ack", Boolean.class, false);
        boolean exitAfterSend = env.getProperty("app.exit-after-send", Boolean.class, false);

        String key = UUID.randomUUID().toString();
        String msg = "startup-smoke-" + Instant.now();

        log.info("Startup smoke producer enabled. Sending 1 message to topic='{}' key='{}' (waitForAck={})",
                topic, key, waitForAck);

        if (waitForAck) {
            kafkaTemplate.send(topic, key, msg).get(); // waits for broker ack
            log.info("Message sent successfully (ack received).");
        } else {
            kafkaTemplate.send(topic, key, msg);
            log.info("Message send initiated (not waiting for ack).");
        }

        if (exitAfterSend) {
            log.info("Exit-after-send is true. Shutting down cleanly with exit code 0.");
            SpringApplication.exit(ctx, () -> 0);
        } else {
            log.info("Exit-after-send is false. App will keep running (if anything else keeps it alive).");
        }
    }
}