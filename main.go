package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"time"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/streadway/amqp"
)

type FileInfo struct {
	Bucket      string    `json:"bucket"`
	Key         string    `json:"key"`
	Size        int64     `json:"size"`
	EventTime   string    `json:"eventTime"`
	ProcessedAt string    `json:"processedAt"`
}

func HandleRequest(ctx context.Context, s3Event events.S3Event) error {
	// Connect to RabbitMQ
	url := fmt.Sprintf("amqp://%s:%s@%s:%s/",
		os.Getenv("RABBITMQ_USERNAME"),
		os.Getenv("RABBITMQ_PASSWORD"),
		os.Getenv("RABBITMQ_HOST"),
		os.Getenv("RABBITMQ_PORT"),
	)

	conn, err := amqp.Dial(url)
	if err != nil {
		return fmt.Errorf("failed to connect to RabbitMQ: %v", err)
	}
	defer conn.Close()

	ch, err := conn.Channel()
	if err != nil {
		return fmt.Errorf("failed to open channel: %v", err)
	}
	defer ch.Close()

	q, err := ch.QueueDeclare(
		"s3_uploads", // name
		true,         // durable
		false,        // delete when unused
		false,        // exclusive
		false,        // no-wait
		nil,          // arguments
	)
	if err != nil {
		return fmt.Errorf("failed to declare queue: %v", err)
	}

	for _, record := range s3Event.Records {
		s3 := record.S3
		
		fileInfo := FileInfo{
			Bucket:      s3.Bucket.Name,
			Key:         s3.Object.Key,
			Size:        s3.Object.Size,
			EventTime:   record.EventTime.String(),
			ProcessedAt: time.Now().UTC().Format(time.RFC3339),
		}

		body, err := json.Marshal(fileInfo)
		if err != nil {
			return fmt.Errorf("error marshaling message: %v", err)
		}

		err = ch.Publish(
			"",     // exchange
			q.Name, // routing key
			false,  // mandatory
			false,  // immediate
			amqp.Publishing{
				ContentType: "application/json",
				Body:        body,
			})
		if err != nil {
			return fmt.Errorf("failed to publish message: %v", err)
		}

		log.Printf("Published message for file: %s", s3.Object.Key)
	}

	return nil
}

func main() {
	lambda.Start(HandleRequest)
}