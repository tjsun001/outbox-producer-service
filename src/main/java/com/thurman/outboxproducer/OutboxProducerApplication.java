package com.thurman.outboxproducer;

import java.time.Instant;
import java.util.UUID;

import org.apache.kafka.clients.producer.RecordMetadata;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.ConfigurableApplicationContext;
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
 *   app.kafka.startup.producer.wait-for-ack=true   (default true)
 *   app.exit-after-send=true                      (default true)
 *
 * Spring Boot relaxed binding lets you use env vars like:
 *   APP_KAFKA_STARTUP_PRODUCER_ENABLED=true
 *   APP_KAFKA_STARTUP_PRODUCER_WAIT_FOR_ACK=true
 *   APP_EXIT_AFTER_SEND=true
 *
 * Topic can be provided either as:
 *   APP_TOPIC=outbox.events.test
 * or as:
 *   app.topic=outbox.events.test
 */
@Component
@ConditionalOnProperty(
        prefix = "app.kafka.startup.producer",
        name = "enabled",
        havingValue = "true",
        matchIfMissing = false
)
class ProducerOnStart implements CommandLineRunner {

    private static final Logger log = LoggerFactory.getLogger(ProducerOnStart.class);

    private final KafkaTemplate<String, String> kafkaTemplate;
    private final ConfigurableApplicationContext ctx;
    private final Environment env;
    private final String topic;

    ProducerOnStart(
            KafkaTemplate<String, String> kafkaTemplate,
            ConfigurableApplicationContext ctx,
            Environment env,
            @Value("${APP_TOPIC:outbox.events.test}") String topic
    ) {
        this.kafkaTemplate = kafkaTemplate;
        this.ctx = ctx;
        this.env = env;
        this.topic = topic;
    }

    @Override
    public void run(String... args) throws Exception {
        if (topic == null || topic.isBlank()) {
            throw new IllegalStateException("APP_TOPIC is required (env var or property).");
        }

        // Defaults chosen for ECS "run once" determinism
        boolean waitForAck = env.getProperty("app.kafka.startup.producer.wait-for-ack", Boolean.class, true);
        boolean exitAfterSend = env.getProperty("app.exit-after-send", Boolean.class, true);

        String bootstrap = env.getProperty("spring.kafka.bootstrap-servers", "<missing>");
        log.info("MODE=startup-smoke enabled=true topic={} waitForAck={} exitAfterSend={} bootstrap={}",
                topic, waitForAck, exitAfterSend, bootstrap);

        String key = UUID.randomUUID().toString();
        String msg = "startup-smoke-" + Instant.now();

        try {
            if (!waitForAck) {
                log.warn("waitForAck=false requested, but Option A forces ack waiting for run-once reliability. Proceeding with ack wait.");
            }

            var sendResult = kafkaTemplate.send(topic, key, msg).get(); // waits for broker ack
            RecordMetadata md = sendResult.getRecordMetadata();

            log.info("SENT ack=true topic={} partition={} offset={} key={} value={}",
                    topic, md.partition(), md.offset(), key, msg);

            log.info("DONE produced=1 exitCode=0");

            if (exitAfterSend) {
                int code = SpringApplication.exit(ctx, () -> 0);
                System.exit(code); // make ECS run-once behavior deterministic
            } else {
                log.info("Exit-after-send is false. App will keep running (if anything else keeps it alive).");
            }

        } catch (Exception e) {
            log.error("DONE produced=0 exitCode=1", e);
            int code = SpringApplication.exit(ctx, () -> 1);
            System.exit(code);
        }
    }
}