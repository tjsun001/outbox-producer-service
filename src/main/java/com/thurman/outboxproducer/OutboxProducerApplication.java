package com.thurman.outboxproducer;

import java.time.Instant;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Component;

@SpringBootApplication
public class OutboxProducerApplication {
    public static void main(String[] args) {
        SpringApplication.run(OutboxProducerApplication.class, args);
    }
}

@Component
class ProducerOnStart implements CommandLineRunner {

    private final KafkaTemplate<String, String> kafkaTemplate;
    private final String topic;

    ProducerOnStart(KafkaTemplate<String, String> kafkaTemplate,
                    @Value("${APP_TOPIC:outbox.events.test}") String topic) {
        this.kafkaTemplate = kafkaTemplate;
        this.topic = topic;
    }

    @Override
    public void run(String... args) {
        String msg = "producer-service-" + Instant.now();
        kafkaTemplate.send(topic, "key1", msg);
        System.out.println("Produced message to topic=" + topic + " value=" + msg);
    }
}

