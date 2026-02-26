package com.thurman.outboxproducer;

import java.time.Instant;
import java.util.UUID;

import org.apache.kafka.clients.producer.RecordMetadata;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.ConfigurableApplicationContext;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.core.env.Environment;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Component;

/**
 * Startup smoke producer (ONE message).
 *
 * Disabled by default.
 *
 * Enable only when validating MSK connectivity:
 *   app.kafka.startup.producer.enabled=true
 *
 * Optional:
 *   app.kafka.startup.producer.wait-for-ack=true   (default true)
 *   app.exit-after-send=true                      (default true)
 *
 * Env-var equivalents via Spring relaxed binding:
 *   APP_KAFKA_STARTUP_PRODUCER_ENABLED=true
 *   APP_KAFKA_STARTUP_PRODUCER_WAIT_FOR_ACK=true
 *   APP_EXIT_AFTER_SEND=true
 *
 * Topic (canonical):
 *   app.topic=outbox.events.test
 *
 * Also supported:
 *   APP_TOPIC=outbox.events.test
 */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
@ConditionalOnProperty(
        prefix = "app.kafka.startup.producer",
        name = "enabled",
        havingValue = "true",
        matchIfMissing = false
)
public class ProducerOnStart implements CommandLineRunner {

    private static final Logger log = LoggerFactory.getLogger(ProducerOnStart.class);

    private final KafkaTemplate<String, String> kafkaTemplate;
    private final ConfigurableApplicationContext ctx;
    private final Environment env;

    // Prefer canonical property, but allow APP_TOPIC as a fallback.
    @Value("${app.topic:${APP_TOPIC:outbox.events.test}}")
    private String topic;

    public ProducerOnStart(
            KafkaTemplate<String, String> kafkaTemplate,
            ConfigurableApplicationContext ctx,
            Environment env
    ) {
        this.kafkaTemplate = kafkaTemplate;
        this.ctx = ctx;
        this.env = env;
    }

    @Override
    public void run(String... args) {
        if (topic == null || topic.isBlank()) {
            failFast("APP_TOPIC/app.topic is required (env var or property).", null);
            return;
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
                log.warn("waitForAck=false requested, but we will still wait for ack for run-once reliability.");
            }

            // Always wait for broker ack to make success deterministic
            var sendResult = kafkaTemplate.send(topic, key, msg).get();
            RecordMetadata md = sendResult.getRecordMetadata();

            log.info("SENT ack=true topic={} partition={} offset={} key={} value={}",
                    topic, md.partition(), md.offset(), key, msg);

            log.info("DONE produced=1 exitCode=0");

            if (exitAfterSend) {
                shutdown(0);
            } else {
                log.info("Exit-after-send is false. App will keep running.");
            }

        } catch (Exception e) {
            failFast("DONE produced=0 exitCode=1", e);
        }
    }

    private void shutdown(int exitCode) {
        int code = SpringApplication.exit(ctx, () -> exitCode);
        System.exit(code);
    }

    private void failFast(String message, Exception e) {
        if (e == null) {
            log.error(message);
        } else {
            log.error(message, e);
        }
        shutdown(1);
    }
}